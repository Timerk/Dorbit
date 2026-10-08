"""Portable preview artifact selection and reporting regressions."""

import hashlib
import gzip
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import tarfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ci", ROOT / "tools/ci-deploy.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
SHA = "b" * 40


def package_bytes(filename, sha=SHA):
    output = io.BytesIO()
    if filename == "windows.zip":
        with zipfile.ZipFile(output, "w") as client:
            client.writestr("REVISION", sha)
    else:
        with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as server:
                revision = tarfile.TarInfo("./REVISION")
                revision.size = len(sha)
                server.addfile(revision, io.BytesIO(sha.encode()))
    return output.getvalue()


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
            archive.writestr(filename, package_bytes(filename))

    def builds(self, listing=None):
        with patch.dict(os.environ, self.env), \
             patch.object(ci, "api", side_effect=listing or self.listing), \
             patch.object(ci, "run", side_effect=self.download):
            ci.download_builds(preview=True)

    def test_partial_rerun_uses_each_successful_build_attempt(self):
        self.builds()
        self.assertEqual(self.names, [f"Preview-Linux-{SHA}-1", f"Preview-Windows-{SHA}-2"])
        for filename in ("server.tar.gz", "windows.zip"):
            self.assertEqual((Path("dist") / filename).read_bytes(), package_bytes(filename))

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


class PreviewReuseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(os.chdir, Path.cwd())
        os.chdir(self.temp.name)
        self.env = {"GITHUB_REPOSITORY": "test/dorbit", "GITHUB_RUN_ID": "123",
                    "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "c" * 40,
                    "GITHUB_OUTPUT": "outputs", "GITHUB_STEP_SUMMARY": "summary"}
        self.source = {"id": 100, "workflow_id": 1, "status": "completed", "conclusion": "success",
                       "head_repository": {"full_name": "test/dorbit"}, "event": "workflow_dispatch",
                       "head_branch": "main", "head_sha": "c" * 40, "run_attempt": 3}
        self.artifacts = [{"id": 1, "name": f"Preview-Linux-{SHA}-1", "expired": False},
                          {"id": 2, "name": f"Preview-Windows-{SHA}-2", "expired": False}]
        self.job_conclusion = "success"

    def api(self, path):
        if path.endswith("/workflows/preview.yml"):
            return {"id": 1}
        if path.endswith("/workflows/validate.yml"):
            return {"id": 2}
        if "/workflows/1/runs?" in path:
            return {"workflow_runs": [self.source]}
        if "/workflows/2/runs?" in path:
            return {"workflow_runs": []}
        if path.endswith("/artifacts?per_page=100"):
            return {"total_count": len(self.artifacts), "artifacts": self.artifacts}
        if "/attempts/" in path:
            names = ("linux", "windows") if self.source["workflow_id"] == 1 else ("linux-server", "windows")
            return {"total_count": 2, "jobs": [{"name": name, "conclusion": self.job_conclusion} for name in names]}
        self.fail(f"Unexpected API path: {path}")

    def reuse(self):
        with patch.dict(os.environ, self.env), patch.object(ci, "api", side_effect=self.api):
            return ci.reusable_preview(SHA)

    def test_reuses_exact_pair_from_successful_partial_rerun(self):
        self.assertEqual(self.reuse(), {"run": "100", "attempt": "3", "prefix": "Preview", "linux": "1", "windows": "2"})

    def test_rejects_wrong_workflow_revision_repo_event_and_run_state(self):
        for replacement in ({"head_sha": "d" * 40}, {"head_branch": "feature"}, {"event": "pull_request"},
                            {"head_repository": {"full_name": "fork/dorbit"}}, {"status": "in_progress"},
                            {"conclusion": "failure"}, {"workflow_id": 9}, {"id": 123}):
            original = self.source.copy()
            with self.subTest(replacement=replacement):
                self.source.update(replacement)
                self.assertEqual(self.reuse()["run"], "")
            self.source = original

    def test_rejects_missing_expired_ambiguous_and_wrong_revision_packages(self):
        original = self.artifacts
        for artifacts in (original[:1], [original[0] | {"expired": True}, original[1]],
                          original + [original[0]], [original[0] | {"name": f"Preview-Linux-{'a' * 40}-1"}, original[1]],
                          [original[0] | {"name": f"Preview-Linux-{SHA}-4"}, original[1]]):
            with self.subTest(artifacts=artifacts):
                self.artifacts = artifacts
                self.assertEqual(self.reuse()["run"], "")

    def test_rejects_artifact_uploaded_by_a_failed_job(self):
        self.job_conclusion = "failure"
        self.assertEqual(self.reuse()["run"], "")

    def test_validation_merge_commit_is_not_reused_for_head_commit(self):
        self.source.update(workflow_id=2, event="pull_request", head_sha=SHA)
        self.artifacts = [artifact | {"name": artifact["name"].replace("Preview-", "Dorbit-").replace(SHA, "a" * 40)}
                          for artifact in self.artifacts]
        original = self.api
        def api(path):
            if "/workflows/1/runs?" in path:
                return {"workflow_runs": []}
            if "/workflows/2/runs?" in path:
                return {"workflow_runs": [self.source]}
            return original(path)
        with patch.dict(os.environ, self.env), patch.object(ci, "api", side_effect=api):
            self.assertEqual(ci.reusable_preview(SHA)["run"], "")
            self.artifacts = [artifact | {"name": artifact["name"].replace("a" * 40, SHA)} for artifact in self.artifacts]
            self.assertEqual(ci.reusable_preview(SHA)["prefix"], "Dorbit")

    def test_selection_freezes_head_and_emits_reuse_outputs(self):
        original = self.api
        def api(path):
            if path.endswith("/pulls/52"):
                return {"state": "open", "head": {"sha": SHA, "repo": {"full_name": "test/dorbit"}}}
            return original(path)
        with patch.dict(os.environ, self.env | {"PR_NUMBER": "52"}), patch.object(ci, "api", side_effect=api):
            ci.preview_select()
        self.assertIn(f"sha={SHA}\n", Path("outputs").read_text())
        self.assertIn("reuse_run=100\n", Path("outputs").read_text())
        self.assertIn("run 100", Path("summary").read_text())

    def test_reused_download_uses_source_attempt_not_current_attempt(self):
        env = self.env | {"PREVIEW_SHA": SHA, "PREVIEW_SOURCE_RUN": "100", "PREVIEW_SOURCE_ATTEMPT": "3",
                          "PREVIEW_SOURCE_PREFIX": "Dorbit", "LINUX_BUILD_ATTEMPT": "1", "WINDOWS_BUILD_ATTEMPT": "2"}
        names = []
        def listing(path):
            prefix = "repos/test/dorbit/actions/runs/100/artifacts?name="
            self.assertTrue(path.startswith(prefix))
            name = path.removeprefix(prefix)
            names.append(name)
            return {"total_count": 1, "artifacts": [{"id": len(names), "name": name, "expired": False}]}
        def download(*args, stdout):
            filename = "server.tar.gz" if len(names) == 1 else "windows.zip"
            with zipfile.ZipFile(stdout, "w") as archive:
                archive.writestr(filename, package_bytes(filename))
        with patch.dict(os.environ, env), patch.object(ci, "api", side_effect=listing), patch.object(ci, "run", side_effect=download):
            ci.download_builds(preview=True)
        self.assertEqual(names, [f"Dorbit-Linux-{SHA}-1", f"Dorbit-Windows-{SHA}-2"])

    def test_embedded_revisions_must_match_for_both_platforms(self):
        Path("dist").mkdir()
        for wrong in ("server.tar.gz", "windows.zip"):
            with self.subTest(wrong=wrong):
                for filename in ("server.tar.gz", "windows.zip"):
                    (Path("dist") / filename).write_bytes(package_bytes(filename, "a" * 40 if filename == wrong else SHA))
                with self.assertRaisesRegex(ValueError, "revision mismatch"):
                    ci.verify_preview_packages(SHA)

    def test_newer_preview_or_stop_request_prevents_activation(self):
        for filename in ("preview.yml", "stop-preview.yml", None):
            with self.subTest(filename=filename):
                Path("outputs").unlink(missing_ok=True)
                def api(path):
                    if path.endswith("/runs/123"):
                        return {"id": 123, "created_at": "2026-10-08T17:00:00Z"}
                    requests = [{"id": 125, "created_at": "2026-10-08T17:00:00Z"}] if filename and f"/{filename}/" in path else []
                    return {"workflow_runs": requests}
                with patch.dict(os.environ, self.env), patch.object(ci, "api", side_effect=api):
                    ci.preview_current()
                self.assertEqual(Path("outputs").read_text().strip(), f"current={str(filename is None).lower()}")


if __name__ == "__main__":
    unittest.main()
