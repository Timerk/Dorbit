"""Operator provisioning must preserve progression and reject corrupt equipment."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import pilots


class ProvisioningTest(unittest.TestCase):
    def test_rotation_and_migration(self):
        for version in (1, 2):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                record = {"verifier": "a" * 64, "credits": 2345,
                          "contract": {"id": "test", "progress": 2}}
                if version == 2:
                    record["equipment"] = pilots.starter_equipment()
                    record["equipment"]["items"]["starter-laser"].update(ship="", slot="")
                path = root / "pilots.json"
                path.write_text(json.dumps({"version": version, "pilots": {"test": record}}))
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                saved = json.loads(path.read_text())
                self.assertEqual(saved["version"], 2)
                expected = record | {"equipment": record.get("equipment", pilots.starter_equipment())}
                expected["verifier"] = saved["pilots"]["test"]["verifier"]
                self.assertEqual(saved["pilots"]["test"], expected)

    def test_invalid_equipment_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            equipment = pilots.starter_equipment()
            equipment["items"]["starter-engine"]["slot"] = "generator1"
            path = root / "pilots.json"
            original = json.dumps({"version": 2, "pilots": {"test": {
                "verifier": "a" * 64, "credits": 1, "equipment": equipment}}})
            path.write_text(original)
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential.json"), "--rotate"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_text(), original)
            self.assertFalse((root / "credential.json").exists())


if __name__ == "__main__":
    unittest.main()
