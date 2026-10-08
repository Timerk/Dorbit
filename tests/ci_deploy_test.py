"""Portable preview artifact selection and reporting regressions."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ci", ROOT / "tools/ci-deploy.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
SHA = "b" * 40


class PreviewArtifactsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(os.chdir, Path.cwd())
        os.chdir(self.temp.name)
        self.env = {
            "PREVIEW_SHA": SHA, "GITHUB_REPOSITORY": "test/dorbit",
            "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "3",
            "LINUX_BUILD_ATTEMPT": "1", "WINDOWS_BUILD_ATTEMPT": "2",
            "GITHUB_STEP_SUMMARY": "summary",
        }
        self.names = []

    def listing(self, path):
        prefix = "repos/test/dorbit/actions/runs/123/artifacts?name="
        self.assertTrue(path.startswith(prefix))
        name = path.removeprefix(prefix)
        self.names.append(name)
        return {"total_count": 1, "artifacts": [{"id": len(self.names), "name": name, "expired": False}]}

    def download(self, *args, stdout):
        self.assertEqual(args, ("gh", "api", f"repos/test/dorbit/actions/artifacts/{len(self.names)}/zip"))
        filename = "server.tar.gz" if len(self.names) == 1 else "windows.zip"
        with zipfile.ZipFile(stdout, "w") as archive:
            archive.writestr(filename, b"checked package")

    def builds(self, listing=None):
        with patch.dict(os.environ, self.env), \
             patch.object(ci, "api", side_effect=listing or self.listing), \
             patch.object(ci, "run", side_effect=self.download):
            ci.download_builds(preview=True)

    def test_partial_rerun_uses_each_successful_build_attempt(self):
        self.builds()
        self.assertEqual(self.names, [f"Preview-Linux-{SHA}-1", f"Preview-Windows-{SHA}-2"])
        for filename in ("server.tar.gz", "windows.zip"):
            self.assertEqual((Path("dist") / filename).read_bytes(), b"checked package")

    def test_full_run_uses_current_builds(self):
        self.env.update(LINUX_BUILD_ATTEMPT="3", WINDOWS_BUILD_ATTEMPT="3")
        self.builds()
        self.assertEqual(self.names, [f"Preview-Linux-{SHA}-3", f"Preview-Windows-{SHA}-3"])

    def test_deploy_only_rerun_reuses_both_original_builds(self):
        self.env["WINDOWS_BUILD_ATTEMPT"] = "1"
        self.builds()
        self.assertEqual(self.names, [f"Preview-Linux-{SHA}-1", f"Preview-Windows-{SHA}-1"])

    def test_rejects_invalid_or_future_build_attempt_before_api(self):
        for value in ("", "0", "-1", "4", "1/../../", "1\n"):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                os.chdir(directory)
                self.env["LINUX_BUILD_ATTEMPT"] = value
                with self.assertRaisesRegex(ValueError, "Invalid build attempt"):
                    self.builds(lambda path: self.fail("Invalid attempt must be rejected before querying artifacts"))
                os.chdir(self.temp.name)

    def test_missing_artifact_does_not_fall_back_to_another_attempt(self):
        with self.assertRaisesRegex(ValueError, "successful build job's attempt"):
            self.builds(lambda path: {"total_count": 0, "artifacts": []})
        self.assertFalse(Path("dist/server.tar.gz").exists())

    def test_rejects_expired_mismatched_or_ambiguous_artifacts(self):
        name = f"Preview-Linux-{SHA}-1"
        for artifacts in ([{"id": 1, "name": name, "expired": True}],
                          [{"id": 1, "name": f"Preview-Linux-{SHA}-2", "expired": False}],
                          [{"id": 1, "name": name, "expired": False}] * 2):
            with self.subTest(artifacts=artifacts), tempfile.TemporaryDirectory() as directory:
                os.chdir(directory)
                with self.assertRaises(ValueError):
                    self.builds(lambda path: {"total_count": len(artifacts), "artifacts": artifacts})
                self.assertFalse(Path("dist/server.tar.gz").exists())
                os.chdir(self.temp.name)

    def test_summary_links_retained_windows_build_and_current_recovery_run(self):
        Path("activated").touch()
        with patch.dict(os.environ, self.env):
            ci.preview_report()
        summary = Path("summary").read_text()
        self.assertIn("Preview ready", summary)
        self.assertIn(f"Preview-Windows-{SHA}-2", summary)
        self.assertNotIn(f"Preview-Windows-{SHA}-3", summary)
        self.assertIn("https://github.com/test/dorbit/actions/runs/123#artifacts", summary)

    def test_recovery_reference_records_windows_build_attempt(self):
        Path("dist").mkdir()
        Path("dist/server.tar.gz").write_bytes(b"checked server package")
        with zipfile.ZipFile("dist/windows.zip", "w") as client:
            client.writestr("REVISION", SHA)
        backup = b"simulated encrypted recovery copy"
        state = {"id": "transaction", "backup_sha256": hashlib.sha256(backup).hexdigest()}

        def ssh(command, **kwargs):
            if command.startswith("prepare-preview "):
                self.assertEqual(command, f"prepare-preview {SHA} 52 keep {ci.digest('dist/server.tar.gz')} 123 2")
                return SimpleNamespace(stdout=json.dumps(state).encode())
            self.assertEqual(command, "backup transaction")
            kwargs["stdout"].write(backup)

        with patch.dict(os.environ, self.env | {"PR_NUMBER": "52", "FRESH_SAVES": "false"}), \
             patch.object(ci, "ssh", side_effect=ssh) as calls:
            ci.preview_prepare()
        self.assertEqual(calls.call_count, 2)
        self.assertEqual(json.loads(Path("recovery/transaction.json").read_text()), state)
        self.assertEqual(Path("recovery/backup.tar.age").read_bytes(), backup)


if __name__ == "__main__":
    unittest.main()
