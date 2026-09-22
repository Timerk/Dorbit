"""Deployment transactions against disposable files and simulated systemd only."""

import importlib.util
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("deploy", ROOT / "tools/vps-deploy.py")
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
ci_spec = importlib.util.spec_from_file_location("ci", ROOT / "tools/ci-deploy.py")
ci = importlib.util.module_from_spec(ci_spec)
ci_spec.loader.exec_module(ci)
OLD = "a" * 40
NEW = "b" * 40


class DeploymentFixture:
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

    def activate(self, state, failure=False):
        self.start_patch("ready", side_effect=RuntimeError("unready") if failure else None)
        with patch.object(deploy.pwd, "getpwnam", return_value=SimpleNamespace(pw_uid=1000, pw_gid=1000)), \
             patch.object(deploy.os, "chown"), patch("builtins.print"):
            deploy.activate(state, state["backup_sha256"])


class DeploymentTest(DeploymentFixture, unittest.TestCase):
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


class PreviewDeploymentTest(DeploymentFixture, unittest.TestCase):
    def setUp(self):
        super().setUp()
        for name, value in (("PREVIEW", True), ("USER", "dorbit-preview"),
                            ("SERVICE", "dorbit-preview.service"), ("SEED", Path(self.temp.name) / "seed")):
            patcher = patch.object(deploy, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        deploy.CURRENT.unlink()
        (deploy.DATA / "pilots.json").unlink()
        deploy.DATA.rmdir()
        (deploy.DATA.parent / "saves").mkdir()
        deploy.SEED.mkdir()
        (deploy.SEED / "pilots.json").write_text("private fresh preview seed")
        self.production = Path(self.temp.name) / "production"
        self.production.mkdir()
        (self.production / "pilots.json").write_text("production must stay untouched")

    def command(self, *args):
        if "--property=User" in args:
            return "dorbit-preview"
        if "--property=UnitFileState" in args:
            return "static"
        return super().command(*args)

    def prepare(self, pr=15, fresh=False):
        archive = self.archive()
        with patch.object(deploy.sys, "stdin", SimpleNamespace(buffer=io.BytesIO(archive.read_bytes()))), patch("builtins.print"):
            deploy.prepare(NEW, deploy.active_commit(), deploy.digest(archive),
                           {"pr": pr, "fresh": fresh, "build_run": 123, "attempt": 1})
        return json.loads((deploy.STATE / "pending.json").read_text())

    def test_first_start_stop_and_redeploy_same_commit(self):
        self.activate(self.prepare())
        first_release = deploy.CURRENT.resolve()
        (deploy.DATA / "pilots.json").write_text("earned preview progress")
        with patch("builtins.print"):
            deploy.stop_preview()
        self.activate(self.prepare())
        self.assertNotEqual(deploy.CURRENT.resolve(), first_release)
        self.assertTrue(first_release.exists())
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "earned preview progress")
        self.assertEqual((self.production / "pilots.json").read_text(), "production must stay untouched")
        self.assertTrue(all("dorbit.service" not in args for args in self.calls))

    def test_pr_switch_and_return_preserve_independent_saves(self):
        self.activate(self.prepare(pr=15))
        (deploy.DATA / "pilots.json").write_text("PR 15 progress")
        self.activate(self.prepare(pr=17))
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "private fresh preview seed")
        (deploy.DATA / "pilots.json").write_text("PR 17 progress")
        self.activate(self.prepare(pr=15))
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "PR 15 progress")
        self.assertEqual((deploy.DATA.parent / "saves/pr-17/pilots.json").read_text(), "PR 17 progress")

    def test_fresh_saves_archive_old_directory_after_backup_receipt(self):
        self.activate(self.prepare())
        (deploy.DATA / "pilots.json").write_text("old preview progress")
        state = self.prepare(fresh=True)
        with self.assertRaisesRegex(RuntimeError, "receipt"):
            deploy.activate(state, "wrong")
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "old preview progress")
        self.activate(state)
        self.assertEqual((deploy.STATE / state["id"] / "archived-data/pilots.json").read_text(), "old preview progress")
        self.assertEqual((deploy.DATA / "pilots.json").read_text(), "private fresh preview seed")

    def test_failed_start_and_stop_preserve_pending_recovery(self):
        state = self.prepare()
        with self.assertRaisesRegex(RuntimeError, "unready"):
            self.activate(state, failure=True)
        with patch("builtins.print"):
            deploy.stop_preview()
        self.assertTrue((deploy.STATE / "pending.json").exists())
        self.assertEqual(self.calls[-1], ("systemctl", "stop", "dorbit-preview.service"))
        self.assertEqual((self.production / "pilots.json").read_text(), "production must stay untouched")

    def test_symlink_cannot_select_production_saves(self):
        (deploy.DATA.parent / "saves/pr-15").symlink_to(self.production)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            self.prepare()
        self.assertEqual((self.production / "pilots.json").read_text(), "production must stay untouched")


class ReleaseSelectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(os.chdir, Path.cwd())
        os.chdir(self.temp.name)
        self.build = {"head_sha": NEW, "head_repository": {"full_name": "test/dorbit"},
                      "workflow_id": 42, "event": "push", "head_branch": "main",
                      "status": "completed", "conclusion": "success"}
        self.client = io.BytesIO()
        with zipfile.ZipFile(self.client, "w") as client:
            client.writestr("REVISION", NEW)
        self.files = {"server.tar.gz": b"disposable server artifact", "windows.zip": self.client.getvalue()}
        self.signed_files = dict(self.files)

    def manifest(self, files):
        return json.dumps({"commit": NEW, "run_id": 123, "run_attempt": 1,
            "files": {key: hashlib.sha256(value).hexdigest() for key, value in files.items()}}).encode()

    def provenance(self, path, sha):
        self.assertEqual(sha, NEW)
        expected = (self.manifest(self.signed_files) if Path(path).name == "manifest.json"
                    else self.signed_files[Path(path).name])
        if Path(path).read_bytes() != expected:
            raise subprocess.CalledProcessError(1, "gh attestation verify")

    def download(self, tag, name, directory):
        target = Path(directory) / name
        if tag == f"build-{OLD}":
            with zipfile.ZipFile(target, "w") as client:
                client.writestr("REVISION", OLD)
        elif name == "manifest.json":
            target.write_bytes(self.manifest(self.files))
        else:
            target.write_bytes(self.files[name])

    def select(self):
        with patch.dict(os.environ, RELEASE=f"build-{NEW}", EXPECTED_CURRENT=OLD,
                        GITHUB_REPOSITORY="test/dorbit"), \
             patch.object(ci, "api", side_effect=[{"draft": False, "prerelease": False}, self.build, {"id": 42}]), \
             patch.object(ci, "verify_provenance", side_effect=self.provenance), \
             patch.object(ci, "verify_rollback_client") as rollback, \
             patch.object(ci, "download", side_effect=self.download), patch("builtins.print"):
            ci.select()
        rollback.assert_called_once_with("recovery/windows.zip", OLD)

    def test_selects_tested_pair_and_preserves_old_client(self):
        self.select()
        self.assertEqual(json.loads(Path("selection.json").read_text())["commit"], NEW)
        with zipfile.ZipFile("recovery/windows.zip") as previous:
            self.assertEqual(previous.read("REVISION"), OLD.encode())

    def test_rejects_unqualified_validation_runs(self):
        for index, (field, value) in enumerate([
            ("head_sha", OLD), ("head_repository", {"full_name": "fork/dorbit"}),
            ("workflow_id", 99), ("event", "pull_request"), ("head_branch", "feature"),
            ("status", "in_progress"), ("conclusion", "failure"),
        ]):
            with self.subTest(field=field), patch.dict(self.build, {field: value}):
                workspace = Path(self.temp.name) / str(index)
                workspace.mkdir()
                os.chdir(workspace)
                with self.assertRaisesRegex(ValueError, "successful main push"):
                    self.select()
                self.assertFalse(Path("selection.json").exists())

    def test_replaced_release_and_matching_manifest_cannot_borrow_successful_run(self):
        self.files["server.tar.gz"] = b"attacker replacement with matching mutable checksum"
        with self.assertRaises(subprocess.CalledProcessError):
            self.select()
        self.assertFalse(Path("selection.json").exists())
        self.assertFalse(Path("dist/server.tar.gz").exists())

    def test_missing_package_attestation_refuses_deployment(self):
        original = self.provenance
        def missing(path, sha):
            if Path(path).name == "windows.zip":
                raise subprocess.CalledProcessError(1, "gh attestation verify")
            original(path, sha)
        with patch.object(self, "provenance", side_effect=missing):
            with self.assertRaises(subprocess.CalledProcessError):
                self.select()
        self.assertFalse(Path("selection.json").exists())

    def test_preview_pins_open_same_repository_pr_head(self):
        with patch.dict(os.environ, PR_NUMBER="15", GITHUB_REPOSITORY="test/dorbit",
                        GITHUB_OUTPUT="output", GITHUB_STEP_SUMMARY="summary"), \
             patch.object(ci, "api", return_value={"state": "open", "head": {
                 "repo": {"full_name": "test/dorbit"}, "sha": NEW}}):
            ci.preview_select()
        self.assertEqual(Path("output").read_text(), f"sha={NEW}\npr=15\n")

    def test_preview_rejects_closed_fork_and_deleted_branches(self):
        for state, repository in (("closed", {"full_name": "test/dorbit"}),
                                  ("open", {"full_name": "fork/dorbit"}), ("open", None)):
            with self.subTest(state=state, repository=repository), \
                 patch.dict(os.environ, PR_NUMBER="15", GITHUB_REPOSITORY="test/dorbit"), \
                 patch.object(ci, "api", return_value={"state": state, "head": {"repo": repository, "sha": NEW}}):
                with self.assertRaisesRegex(ValueError, "open PRs"):
                    ci.preview_select()


class ArtifactBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "dist").mkdir()
        (self.root / "tools").mkdir()
        self.trusted = self.root / "tools/ci-deploy.py"
        self.trusted.write_bytes(b"trusted deployment code")
        self.target = self.root / "dist/server.tar.gz"

    def archive(self, members):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as archive:
            for name in members:
                archive.writestr(name, b"untrusted artifact bytes")
        output.seek(0)
        return output

    def test_copies_only_expected_file_without_extracting_nested_content(self):
        ci.artifact_file(self.archive(["server.tar.gz"]), "server.tar.gz", self.target)
        self.assertEqual(self.target.read_bytes(), b"untrusted artifact bytes")
        self.assertEqual(self.trusted.read_bytes(), b"trusted deployment code")

    def test_rejects_traversal_absolute_paths_extra_members_and_links(self):
        link = zipfile.ZipInfo("server.tar.gz")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for names in (["../tools/ci-deploy.py"], ["../../tools/ci-deploy.py"],
                      [str(self.trusted)], ["..\\tools\\ci-deploy.py"],
                      ["C:/tools/ci-deploy.py"], ["server.tar.gz", "../tools/ci-deploy.py"],
                      ["server.tar.gz/"], [link]):
            with self.subTest(names=names), self.assertRaises(ValueError):
                ci.artifact_file(self.archive(names), "server.tar.gz", self.target)
            self.assertFalse(self.target.exists())
            self.assertEqual(self.trusted.read_bytes(), b"trusted deployment code")

    def test_refuses_preexisting_symlink_target(self):
        self.target.symlink_to(self.trusted)
        with self.assertRaises(FileExistsError):
            ci.artifact_file(self.archive(["server.tar.gz"]), "server.tar.gz", self.target)
        self.assertEqual(self.trusted.read_bytes(), b"trusted deployment code")

    def test_downloads_raw_artifacts_from_exact_run_attempt(self):
        self.addCleanup(os.chdir, Path.cwd())
        (self.root / "dist").rmdir()
        os.chdir(self.root)
        def listing(path):
            self.assertIn("/actions/runs/123/artifacts?name=Preview-", path)
            self.assertTrue(path.endswith(f"-{NEW}-2"))
            name = path.split("?name=")[1]
            return {"total_count": 1, "artifacts": [{"id": 456, "name": name, "expired": False}]}
        def raw_download(*args, stdout):
            self.assertEqual(args, ("gh", "api", "repos/test/dorbit/actions/artifacts/456/zip"))
            filename = "windows.zip" if Path("dist/server.tar.gz").exists() else "server.tar.gz"
            stdout.write(self.archive([filename]).getvalue())
        with patch.dict(os.environ, PREVIEW_SHA=NEW, GITHUB_REPOSITORY="test/dorbit",
                        GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="2"), \
             patch.object(ci, "api", side_effect=listing), patch.object(ci, "run", side_effect=raw_download):
            ci.download_builds(preview=True)
        self.assertTrue(Path("dist/server.tar.gz").is_file())
        self.assertTrue(Path("dist/windows.zip").is_file())

    def test_provenance_verifier_pins_workflow_ref_source_and_signer(self):
        with patch.dict(os.environ, GITHUB_REPOSITORY="test/dorbit"), patch.object(ci, "run") as run:
            ci.verify_provenance("dist/manifest.json", NEW)
        run.assert_called_once_with("gh", "attestation", "verify", "dist/manifest.json",
            "--repo", "test/dorbit", "--cert-identity",
            "https://github.com/test/dorbit/.github/workflows/validate.yml@refs/heads/main",
            "--source-ref", "refs/heads/main", "--source-digest", NEW,
            "--signer-digest", NEW, "--deny-self-hosted-runners")

    def test_rollback_requires_attestation_or_exact_legacy_checksum(self):
        self.target.write_bytes(b"independently archived pre-CI client")
        legacy = "90650412c9027500f2e2e82d800a62e8af63b45c"
        with patch.object(ci, "verify_provenance") as verify:
            ci.verify_rollback_client(self.target, OLD)
        verify.assert_called_once_with(self.target, OLD)
        for value in ("", "0" * 64):
            with patch.dict(os.environ, LEGACY_CLIENT_SHA256=value), self.assertRaisesRegex(ValueError, "trusted environment"):
                ci.verify_rollback_client(self.target, legacy)
        with patch.dict(os.environ, LEGACY_CLIENT_SHA256=ci.digest(self.target)):
            ci.verify_rollback_client(self.target, legacy)


if __name__ == "__main__":
    unittest.main()
