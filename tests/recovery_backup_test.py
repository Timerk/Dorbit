"""Disposable recovery rehearsal; never connects to SSH or real systemd."""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import pilots_test

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Linux-only dependencies are not exercised by the simulated systemd fixture on Windows.
if os.name == "nt":
    with patch.dict(sys.modules, {"fcntl": SimpleNamespace(), "pwd": SimpleNamespace()}):
        deploy = load("recovery_deploy", "tools/vps-deploy.py")
else:
    deploy = load("recovery_deploy", "tools/vps-deploy.py")
backup = load("recovery_pull", "tools/recovery-backup.py")
pilots = load("recovery_pilots", "tools/pilots.py")


class PullTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.root.chmod(0o700)
        self.payload = b"age-encryption.org/v1\ndisposable ciphertext"
        self.wire = hashlib.sha256(self.payload).hexdigest().encode() + b"\n" + self.payload

    def receive(self, *args, **kwargs):
        self.assertEqual(args[0][-2:], ["fixture-host", "snapshot"])
        self.assertIn("-oStrictHostKeyChecking=yes", args[0])
        kwargs["stdout"].write(self.wire)

    def collect(self, keep=2):
        with patch.object(backup.subprocess, "run", side_effect=self.receive):
            backup.collect(self.root, "fixture-host", keep)

    def copies(self):
        return list(self.root.glob("recovery-*.tar.age"))

    def test_retention_and_unrelated_files(self):
        unrelated = self.root / "operator-copy.age"
        unrelated.write_bytes(b"retain")
        for _ in range(4):
            self.collect()
        self.assertEqual(len(self.copies()), 2)
        self.assertTrue(all(p.read_bytes() == self.payload for p in self.copies()))
        self.assertEqual(unrelated.read_bytes(), b"retain")
        self.assertFalse((self.root / ".lock").exists())

    def test_corruption_keeps_old_copy(self):
        self.collect()
        old = self.copies()[0]
        self.wire += b"corrupt"
        with self.assertRaises(ValueError):
            self.collect(1)
        self.assertTrue(old.exists())
        self.assertEqual(list(self.root.glob(".incoming-*")), [])

    def test_transfer_failure_keeps_old_copy(self):
        self.collect()
        with patch.object(backup.subprocess, "run", side_effect=subprocess.TimeoutExpired("ssh", 1)):
            with self.assertRaises(subprocess.TimeoutExpired):
                backup.collect(self.root, "fixture-host", 1)
        self.assertEqual(len(self.copies()), 1)

    def test_overlap_and_bad_config(self):
        for host, keep in [("-unsafe", 2), ("fixture-host", 0), ("fixture-host", 366)]:
            with self.assertRaises(ValueError):
                backup.collect(self.root, host, keep)
        (self.root / ".lock").mkdir()
        with self.assertRaises(FileExistsError):
            self.collect()


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, relative in {"STATE": "state", "DATA": "data", "UNIT": "dorbit.service",
                               "ENV": "server.env", "RECIPIENT": "recipient"}.items():
            patcher = patch.object(deploy, name, self.root / relative)
            patcher.start()
            self.addCleanup(patcher.stop)
        deploy.STATE.mkdir()
        deploy.DATA.mkdir()
        (self.root / "credentials").mkdir()
        self.path, self.journal, self.ammo, self.boosts = pilots_test.ProvisioningTest.journal_fixture(deploy.DATA)
        self.token = "disposable-test-token"
        data = json.loads(self.path.read_text())
        data["pilots"]["test"]["verifier"] = hashlib.sha256(self.token.encode()).hexdigest()
        self.path.write_text(json.dumps(data))
        (self.root / "credentials/test.json").write_text(json.dumps({"id": "test", "token": self.token}))
        deploy.UNIT.write_text("fixture service")
        deploy.ENV.write_text("DORBIT_PORT=24991\n")
        deploy.RECIPIENT.write_text("age1fixture")
        self.calls = []
        self.real_age = False
        for name, kwargs in {"run": {"side_effect": self.command}, "stopped": {}, "ready": {},
                             "active_commit": {"return_value": "b" * 40}}.items():
            patcher = patch.object(deploy, name, **kwargs)
            value = patcher.start()
            setattr(self, name, value)
            self.addCleanup(patcher.stop)
        patcher = patch.object(deploy.shutil, "disk_usage", return_value=SimpleNamespace(free=10 * 1024**3))
        patcher.start()
        self.addCleanup(patcher.stop)

    def command(self, *args):
        self.calls.append(args)
        if args[:2] == ("systemctl", "is-active"):
            return "active"
        if "--property=FragmentPath" in args:
            return str(deploy.UNIT)
        if args[0] == "age":
            if self.real_age:
                return subprocess.run(args, capture_output=True, check=True, text=True).stdout
            if "-o" in args:
                Path(args[args.index("-o") + 1]).write_bytes(b"ciphertext")
        return ""

    def snapshot(self):
        output = io.BytesIO()
        deploy.recovery_snapshot(output)
        return output.getvalue()

    def test_separate_forced_entrypoint_and_command_allowlist(self):
        with patch.dict(os.environ), patch.object(deploy.os, "geteuid", return_value=0, create=True), \
             patch.object(deploy.os, "umask"), patch.object(deploy.fcntl, "flock", create=True), \
             patch.object(deploy.fcntl, "LOCK_EX", 2, create=True), \
             patch.object(deploy.fcntl, "LOCK_NB", 4, create=True), \
             patch.object(deploy, "recovery_snapshot") as snapshot, \
             patch.object(deploy.sys, "argv", ["/usr/local/sbin/dorbit-recovery"]):
            deploy.main("snapshot")
            snapshot.assert_called_once()
            for command in ("stop", "prepare " + "a" * 40, "snapshot extra"):
                with self.assertRaises(RuntimeError):
                    deploy.main(command)
            with patch.object(deploy.sys, "argv", ["/usr/local/sbin/dorbit-deploy"]):
                with self.assertRaises(RuntimeError):
                    deploy.main("snapshot")

    def test_order_restart_before_receipt_and_cleanup(self):
        wire = self.snapshot()
        self.assertEqual(wire[:64], hashlib.sha256(wire[65:]).hexdigest().encode())
        self.assertLess(self.calls.index(("systemctl", "stop", deploy.SERVICE)),
                        self.calls.index(("systemctl", "start", deploy.SERVICE)))
        self.ready.assert_called_once()
        self.assertEqual(list(deploy.STATE.iterdir()), [])

    def test_dirty_stop_stays_stopped(self):
        (deploy.DATA / "pilots.json.lock").mkdir()
        with self.assertRaises(RuntimeError):
            self.snapshot()
        self.assertNotIn(("systemctl", "start", deploy.SERVICE), self.calls)

    def test_pending_deploy_never_stops(self):
        (deploy.STATE / "pending.json").write_text("{}")
        with self.assertRaises(RuntimeError):
            self.snapshot()
        self.assertEqual(self.calls, [])

    def test_missing_journal_stays_stopped(self):
        self.journal.unlink()
        with self.assertRaises(RuntimeError):
            self.snapshot()
        self.assertNotIn(("systemctl", "start", deploy.SERVICE), self.calls)

    def test_archive_failure_restarts_and_cleans_up(self):
        (self.root / "credentials/test.json").unlink()
        (self.root / "credentials").rmdir()
        with self.assertRaises(RuntimeError):
            self.snapshot()
        self.assertIn(("systemctl", "start", deploy.SERVICE), self.calls)
        self.assertEqual(list(deploy.STATE.iterdir()), [])

    def test_encryption_failure_restarts_clean_service_without_receipt(self):
        original = self.command
        def fail(*args):
            if args[0] == "age" and "-o" in args:
                raise RuntimeError("fixture encryption failure")
            return original(*args)
        self.run.side_effect = fail
        with self.assertRaises(RuntimeError):
            self.snapshot()
        self.assertIn(("systemctl", "start", deploy.SERVICE), self.calls)
        self.assertEqual(list(deploy.STATE.iterdir()), [])

    def test_readiness_failure_has_no_receipt(self):
        self.ready.side_effect = RuntimeError("fixture not ready")
        output = io.BytesIO()
        with self.assertRaises(RuntimeError):
            deploy.recovery_snapshot(output)
        self.assertEqual(output.getvalue(), b"")

    @unittest.skipUnless(shutil.which("age") and shutil.which("age-keygen"), "age tools required")
    def test_real_encrypted_restore_rehearsal(self):
        key = self.root / "identity"
        subprocess.run(["age-keygen", "-o", str(key)], check=True, capture_output=True)
        recipient = subprocess.run(["age-keygen", "-y", str(key)], check=True,
                                   capture_output=True, text=True).stdout.strip()
        deploy.RECIPIENT.write_text(recipient)
        self.real_age = True
        wire = self.snapshot()
        receiver = self.root / "receiver"
        receiver.mkdir(mode=0o700)
        def transfer(*args, **kwargs):
            kwargs["stdout"].write(wire)
        with patch.object(backup.subprocess, "run", side_effect=transfer):
            backup.collect(receiver, "fixture-host", 2)
        encrypted, = receiver.glob("recovery-*.tar.age")
        archive = self.root / "restored.tar"
        subprocess.run(["age", "-d", "-i", str(key), "-o", str(archive), str(encrypted)],
                       check=True, capture_output=True)
        restored = self.root / "restored"
        restored.mkdir()
        with tarfile.open(archive) as source:
            source.extractall(restored, filter="data")
        for path in deploy.DATA.iterdir():
            self.assertEqual(path.read_bytes(), (restored / "data" / path.name).read_bytes())
        data = json.loads((restored / "data/pilots.json").read_text())
        pilots.replay_combat_journal(data, restored / "data/pilots.json.combat")
        record = data["pilots"]["test"]
        self.assertEqual(record["credits"], 2345)
        self.assertEqual(record["ammo"], self.ammo)
        self.assertEqual(record["boosts"], self.boosts)
        self.assertEqual(record["cargo"]["starter"]["seprom"], 3)
        credential = json.loads((restored / "credentials/test.json").read_text())
        self.assertEqual(hashlib.sha256(credential["token"].encode()).hexdigest(), record["verifier"])
        self.assertEqual((restored / "server.env").read_bytes(), deploy.ENV.read_bytes())
        self.assertEqual(json.loads((restored / "recovery.json").read_text())["commit"], "b" * 40)


if __name__ == "__main__":
    unittest.main()
