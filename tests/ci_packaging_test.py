"""Exercise the real packaging helper against a disposable Git repository."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash") or ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else None)


@unittest.skipUnless(BASH, "Bash is required to exercise Linux packaging")
class PackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        shutil.copyfile(ROOT / "tools/deploy-server.sh", self.root / "tools/deploy-server.sh")
        # The fake checker proves which files and cache the real helper provides.
        (self.root / "tools/server.sh").write_text('''#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
if [[ "$1" == setup ]]; then
  test -f .tools/godot-linux/pinned.zip
elif [[ "$1" == build ]]; then
  echo built >> "$CHECK_CALLS"
  [[ "${FAIL_BUILD:-0}" == 0 ]] || exit 8
  mkdir -p build/linux
  echo executable > build/linux/DorbitServer.x86_64
  echo exported > build/linux/DorbitServer.pck
  echo notices > build/linux/THIRD_PARTY_NOTICES.txt
  echo template > .tools/godot-linux/linux_release.x86_64
else
  test "$(cat source.txt)" = committed
  echo checked >> "$CHECK_CALLS"
  [[ "${FAIL_CHECK:-0}" == 0 ]] || exit 9
  mkdir -p .godot/imported
  if [[ "${EXPECT_CACHE:-0}" == 1 ]]; then test -f .godot/imported/seed; fi
  echo imported > .godot/imported/result
fi
''', encoding="utf-8", newline="\n")
        for name in ("tools/run_server.py", "tools/pilots.py", "tools/check-server-export.py", "deploy/dorbit.service",
                     "assets/ships/catalog.json", "assets/ui/fonts/OFL.txt"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture")
        (self.root / "source.txt").write_text("committed")
        self.git("init", "-q")
        self.git("config", "core.autocrlf", "false")
        self.git("add", "tools", "source.txt", "assets", "deploy")
        self.git("-c", "user.name=CI", "-c", "user.email=ci@example.test", "commit", "-qm", "fixture")
        self.sha = self.git("rev-parse", "HEAD").strip()
        (self.root / "source.txt").write_text("dirty checkout must not enter release")
        tools = self.root / ".tools/godot-linux"
        tools.mkdir(parents=True)
        (tools / "pinned.zip").write_bytes(b"fixture archive")
        self.calls = self.root / "calls"
        self.cache = self.root / "cache"
        self.env = dict(os.environ, CHECK_CALLS=self.calls.as_posix(),
                        DORBIT_IMPORT_CACHE=self.cache.as_posix())

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True)

    def package(self):
        return subprocess.run([BASH, "tools/deploy-server.sh", self.sha], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_checks_committed_release_once_and_publishes_cold_cache(self):
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        release = self.root / "build/server-releases" / self.sha
        self.assertFalse((release / "source.txt").exists(), "Raw source must not enter the deployed release")
        self.assertFalse((release / ".godot").exists())
        self.assertFalse((release / ".tools").exists())
        self.assertEqual((release / "runtime/DorbitServer.pck").read_text().strip(), "exported")
        self.assertTrue((release / "tools/run_server.py").is_file())
        self.assertTrue((release / "deploy/dorbit.service").is_file())
        self.assertEqual((release / "REVISION").read_text().strip(), self.sha)
        self.assertEqual(self.calls.read_text().splitlines(), ["checked", "built"])
        self.assertEqual((self.cache / "result").read_text().strip(), "imported")
        self.assertNotEqual(self.package().returncode, 0, "Existing releases must not be overwritten")

    def test_seeds_imports_and_refreshes_cache_after_success(self):
        self.cache.mkdir()
        (self.cache / "seed").write_text("cached")
        self.env["EXPECT_CACHE"] = "1"
        result = self.package()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.cache / "result").is_file())

    def test_failed_check_publishes_neither_release_nor_cache(self):
        self.env["FAIL_CHECK"] = "1"
        self.assertNotEqual(self.package().returncode, 0)
        self.assertFalse((self.root / "build/server-releases" / self.sha).exists())
        self.assertFalse(self.cache.exists())
        self.assertEqual(list((self.root / "build/server-releases").glob(".prepare.*")), [])

    def test_failed_export_publishes_neither_release_nor_cache(self):
        self.env["FAIL_BUILD"] = "1"
        self.assertNotEqual(self.package().returncode, 0)
        self.assertFalse((self.root / "build/server-releases" / self.sha).exists())
        self.assertFalse(self.cache.exists())


@unittest.skipUnless(BASH, "Bash is required to exercise Linux checks")
class TimingTest(unittest.TestCase):
    def test_zero_exit_godot_error_still_fails_and_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            shutil.copyfile(ROOT / "tools/server.sh", root / "tools/server.sh")
            engine = root / ".tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64"
            engine.parent.mkdir(parents=True)
            engine.write_text('#!/usr/bin/env bash\necho "SCRIPT ERROR: fixture"\nexit 0\n', newline="\n")
            engine.chmod(0o755)
            summary = root / "summary.md"
            result = subprocess.run([BASH, "tools/server.sh", "check"], cwd=root,
                                    env=dict(os.environ, GITHUB_STEP_SUMMARY=summary.as_posix()),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("TIMING:", result.stdout)
            self.assertIn("(exit 1)", result.stdout)
            self.assertIn("--editor --import", summary.read_text())
            self.assertIn("| 1 |", summary.read_text())


@unittest.skipUnless(BASH, "Bash is required to exercise the packaged service entry point")
class ExportedLauncherTest(unittest.TestCase):
    def test_packaged_runtime_skips_import_and_incomplete_release_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="dorbit package ") as directory:
            root = Path(directory)
            (root / "tools").mkdir()
            (root / "runtime").mkdir()
            shutil.copyfile(ROOT / "tools/server.sh", root / "tools/server.sh")
            (root / "tools/run_server.py").write_text("import json, sys; print(json.dumps(sys.argv[1:]))")
            binary = root / "runtime/DorbitServer.x86_64"
            binary.write_text("#!/usr/bin/env bash\nexit 0\n", newline="\n")
            binary.chmod(0o755)
            pack = root / "runtime/DorbitServer.pck"
            pack.write_text("fixture")
            result = subprocess.run([BASH, "tools/server.sh", "run", "--port=24568"], cwd=root,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            args = json.loads(result.stdout)
            self.assertTrue(args[0].endswith("runtime/DorbitServer.x86_64"))
            self.assertNotIn("--path", args)
            self.assertNotIn("--import", args)
            self.assertEqual(args[-3:], ["--", "--server", "--port=24568"])
            pack.unlink()
            (root / "project.godot").write_text("fallback must not run")
            failed = subprocess.run([BASH, "tools/server.sh", "run"], cwd=root,
                                    capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("Incomplete exported server", failed.stderr)


if __name__ == "__main__":
    unittest.main()
