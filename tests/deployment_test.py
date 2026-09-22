"""Deployment transactions against disposable files and simulated systemd only."""

import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("deploy", ROOT / "tools/vps-deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
OLD = "a" * 40
NEW = "b" * 40


class DeploymentTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        for name, value in {
            "STATE": root / "state", "RELEASES": root / "releases", "CURRENT": root / "current",
            "DATA": root / "data", "UNIT": root / "dorbit.service", "ENV": root / "server.env",
            "RECIPIENT": root / "recipient",
        }.items():
            patcher = patch.object(deploy, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        deploy.STATE.mkdir()
        deploy.RELEASES.mkdir()
        (deploy.RELEASES / OLD).mkdir()
        deploy.CURRENT.symlink_to(deploy.RELEASES / OLD)
        deploy.DATA.mkdir()
        (deploy.DATA / "pilots.json").write_text("private disposable pilot ledger")
        deploy.UNIT.write_text("fixed unit")
        deploy.ENV.write_text("DORBIT_PORT=24567\n")
        deploy.RECIPIENT.write_text("age1test")
        self.calls = []
        self.stopped = False
        self.start_patch("run", side_effect=self.command)
        self.start_patch("stopped")
        patcher = patch.object(deploy.shutil, "disk_usage", return_value=SimpleNamespace(free=10 * 1024**3))
        patcher.start()
        self.addCleanup(patcher.stop)

    def start_patch(self, name, **kwargs):
        patcher = patch.object(deploy, name, **kwargs)
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def command(self, *args):
        self.calls.append(args)
        if args[:2] == ("systemctl", "is-active"):
            return "active"
        if "--property=FragmentPath" in args:
            return str(deploy.UNIT)
        if args[:2] == ("systemctl", "stop"):
            self.stopped = True
        if args[0] == "age" and "-o" in args:
            self.assertTrue(self.stopped, "Backup must follow service stop")
            if getattr(self, "real_age", False):
                return subprocess.run(args, check=True, capture_output=True, text=True).stdout
            # This suite checks transaction ordering, not cryptography.
            Path(args[args.index("-o") + 1]).write_bytes(b"simulated ciphertext")
        return ""

    def archive(self, extra=None, unit=b"fixed unit"):
        path = Path(self.temp.name) / "input.tar.gz"
        with tarfile.open(path, "w:gz") as output:
            for name, data in [("REVISION", NEW.encode()), ("deploy/dorbit.service", unit),
                               ("tools/server.sh", b"#!/bin/bash\n")]:
                member = tarfile.TarInfo(name)
                member.size = len(data)
                output.addfile(member, io.BytesIO(data))
            if extra:
                output.addfile(extra)
        return path

    def prepare(self, archive=None, previous=OLD):
        archive = archive or self.archive()
        with patch.object(deploy.sys, "stdin", SimpleNamespace(buffer=io.BytesIO(archive.read_bytes()))), \
             patch("builtins.print"):
            deploy.prepare(NEW, previous, deploy.digest(archive))
        return json.loads((deploy.STATE / "pending.json").read_text())

    def test_rejects_wrong_current_without_stopping(self):
        with self.assertRaisesRegex(RuntimeError, "expected_current"):
            self.prepare(previous="c" * 40)
        self.assertFalse(self.stopped)

    def test_rejects_unit_changes_without_stopping(self):
        with self.assertRaisesRegex(RuntimeError, "Unit changed"):
            self.prepare(self.archive(unit=b"User=root"))
        self.assertFalse(self.stopped)

    def test_rejects_unsafe_archives(self):
        for name, kind in [("../escape", tarfile.REGTYPE), ("/escape", tarfile.REGTYPE),
                           ("link", tarfile.SYMTYPE), ("hardlink", tarfile.LNKTYPE),
                           ("device", tarfile.CHRTYPE), ("REVISION", tarfile.REGTYPE)]:
            with self.subTest(name=name):
                member = tarfile.TarInfo(name)
                member.type = kind
                with self.assertRaises(RuntimeError):
                    deploy.unpack(self.archive(extra=member), Path(self.temp.name) / "unpack")
        self.assertFalse(self.stopped)

    def test_lock_is_preserved_and_backed_up_before_refusal(self):
        (deploy.DATA / "pilots.json.lock").mkdir()
        state = self.prepare()
        with self.assertRaisesRegex(RuntimeError, "operator recovery"):
            deploy.activate(state, state["backup_sha256"])
        self.assertEqual(state["phase"], "backed-up")
        self.assertTrue((deploy.STATE / state["id"] / "backup.tar.age").exists())
        self.assertTrue((deploy.DATA / "pilots.json.lock").is_dir())
        self.assertEqual(deploy.active_commit(), OLD)

    def test_backup_receipt_and_pending_transaction_gate_activation(self):
        state = self.prepare()
        with self.assertRaisesRegex(RuntimeError, "receipt"):
            deploy.activate(state, "wrong")
        with self.assertRaisesRegex(RuntimeError, "Pending"):
            self.prepare()
        self.assertEqual(deploy.active_commit(), OLD)
        self.assertFalse((deploy.RELEASES / NEW).exists())
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "private disposable pilot ledger")

    def activate(self, state, failure=False):
        self.start_patch("ready", side_effect=RuntimeError("unready") if failure else None)
        with patch.object(deploy.pwd, "getpwnam", return_value=SimpleNamespace(pw_uid=1000, pw_gid=1000)), \
             patch.object(deploy.os, "chown"), patch("builtins.print"):
            deploy.activate(state, state["backup_sha256"])

    def test_success_keeps_previous_release_and_data(self):
        state = self.prepare()
        self.activate(state)
        self.assertEqual(deploy.active_commit(), NEW)
        self.assertTrue((deploy.RELEASES / OLD).is_dir())
        self.assertFalse((deploy.STATE / "pending.json").exists())
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "private disposable pilot ledger")

    def test_failed_readiness_stops_without_restoring_saves(self):
        state = self.prepare()
        with self.assertRaisesRegex(RuntimeError, "unready"):
            self.activate(state, failure=True)
        self.assertEqual(self.calls[-1], ("systemctl", "stop", "dorbit.service"))
        self.assertEqual(deploy.active_commit(), NEW)
        self.assertTrue((deploy.STATE / "pending.json").exists())
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "private disposable pilot ledger")

    def test_active_service_without_game_readiness_fails(self):
        def no_game(*args):
            if "--property=InvocationID" in args:
                return "new-invocation"
            if args[:2] == ("systemctl", "is-active"):
                return "active"
            return ""
        with patch.object(deploy, "run", side_effect=no_game), \
             patch.object(deploy.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "timed out"):
                deploy.ready(timeout=0.01)

    @unittest.skipUnless(shutil.which("age") and shutil.which("age-keygen"), "age not installed")
    def test_encrypted_recovery_round_trip(self):
        key = Path(self.temp.name) / "recovery.key"
        subprocess.run(["age-keygen", "-o", str(key)], check=True, capture_output=True)
        recipient = subprocess.check_output(["age-keygen", "-y", str(key)], text=True).strip()
        deploy.RECIPIENT.write_text(recipient)
        self.real_age = True
        state = self.prepare()
        transaction = deploy.STATE / state["id"]
        self.assertFalse((transaction / "backup.tar").exists())
        plaintext = subprocess.check_output(["age", "-d", "-i", str(key), str(transaction / "backup.tar.age")])
        with tarfile.open(fileobj=io.BytesIO(plaintext)) as backup:
            self.assertEqual(backup.extractfile("data/pilots.json").read(), b"private disposable pilot ledger")
            self.assertEqual(backup.extractfile("dorbit.service").read(), b"fixed unit")
            self.assertEqual(backup.extractfile("server.env").read(), b"DORBIT_PORT=24567\n")
            self.assertEqual(json.load(backup.extractfile("transaction.json"))["previous"], OLD)


if __name__ == "__main__":
    unittest.main()
