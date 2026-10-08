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
    def test_ship_catalog_and_rotation(self):
        equipment = pilots.starter_equipment()
        for model, info in pilots.SHIP_MODELS.items():
            equipment["ships"][model] = model
            equipment["items"][model + "-laser"] = {
                "model": "laser", "ship": model, "slot": f'laser{info["lasers"]}'}
            equipment["items"][model + "-engine"] = {
                "model": "engine", "ship": model, "slot": f'generator{info["generators"]}'}
        equipment["active_ship"] = "goliath"
        cargo = {ship: {"prometium": pilots.ship_info(model)["cargo"]}
                 for ship, model in equipment["ships"].items()}
        self.assertTrue(pilots.valid_equipment(equipment))
        self.assertTrue(pilots.valid_cargo(cargo, equipment))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            record = {"verifier": "a" * 64, "credits": 2345, "equipment": equipment, "cargo": cargo}
            path = root / "pilots.json"
            path.write_text(json.dumps({"version": 3, "pilots": {"test": record}}))
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential.json"), "--rotate"], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            saved = json.loads(path.read_text())["pilots"]["test"]
            self.assertEqual(saved["equipment"], equipment)
            self.assertEqual(saved["cargo"], cargo)
        for model, info in pilots.SHIP_MODELS.items():
            candidate = json.loads(json.dumps(equipment))
            candidate["items"][model + "-laser"]["slot"] = f'laser{info["lasers"] + 1}'
            self.assertFalse(pilots.valid_equipment(candidate))
            candidate = json.loads(json.dumps(cargo))
            candidate[model]["prometium"] += 1
            self.assertFalse(pilots.valid_cargo(candidate, equipment))

    def test_reference_models(self):
        for model in pilots.LASER_MODELS | pilots.GENERATOR_MODELS:
            with self.subTest(model=model):
                equipment = pilots.starter_equipment()
                equipment["items"]["reference"] = {"model": model, "ship": "", "slot": ""}
                self.assertTrue(pilots.valid_equipment(equipment))
                item = equipment["items"]["reference"]
                item.update(ship="starter", slot="laser2" if model in pilots.LASER_MODELS else "generator3")
                self.assertTrue(pilots.valid_equipment(equipment))
                item["slot"] = "generator3" if model in pilots.LASER_MODELS else "laser2"
                self.assertFalse(pilots.valid_equipment(equipment))

    def test_expanded_slots(self):
        equipment = pilots.starter_equipment()
        equipment["items"]["starter-laser"]["slot"] = "laser4"
        equipment["items"]["starter-shield"]["slot"] = "generator6"
        self.assertTrue(pilots.valid_equipment(equipment))
        for model, slot in [("laser", "laser5"), ("shield", "generator7"), ("engine", "extra1")]:
            with self.subTest(slot=slot):
                candidate = pilots.starter_equipment()
                candidate["items"][f"starter-{model}"]["slot"] = slot
                self.assertFalse(pilots.valid_equipment(candidate))

    def test_rotation_and_migration(self):
        for version in (1, 2, 3, 4):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                record = {"verifier": "a" * 64, "credits": 2345,
                          "contract": {"id": "test", "progress": 2}}
                if version >= 2:
                    record["equipment"] = pilots.starter_equipment()
                    record["equipment"]["items"]["starter-laser"].update(ship="", slot="")
                    for model in pilots.LASER_MODELS | pilots.GENERATOR_MODELS:
                        record["equipment"]["items"][model] = {"model": model, "ship": "", "slot": ""}
                if version >= 3:
                    record["cargo"] = {"starter": {"seprom": 2}}
                if version == 4:
                    record["ammo"] = {"x1": 4321, "x2": 45, "x3": 123, "x4": 7}
                path = root / "pilots.json"
                path.write_text(json.dumps({"version": version, "pilots": {"test": record}}))
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                saved = json.loads(path.read_text())
                self.assertEqual(saved["version"], 4)
                expected = record | {"equipment": record.get("equipment", pilots.starter_equipment()),
                                     "cargo": record.get("cargo", {"starter": {}}),
                                     "ammo": record.get("ammo", pilots.starter_ammo())}
                expected["verifier"] = saved["pilots"]["test"]["verifier"]
                self.assertEqual(saved["pilots"]["test"], expected)

    def test_invalid_ammo_preserved(self):
        for ammo in ({}, pilots.starter_ammo() | {"x1": -1}, pilots.starter_ammo() | {"x2": 1.5},
                     pilots.starter_ammo() | {"x4": True}, pilots.starter_ammo() | {"x3": 2_000_000_001},
                     pilots.starter_ammo() | {"unknown": 1}):
            with self.subTest(ammo=ammo), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / "pilots.json"
                original = json.dumps({"version": 4, "pilots": {"test": {
                    "verifier": "a" * 64, "credits": 1, "equipment": pilots.starter_equipment(),
                    "cargo": {"starter": {}}, "ammo": ammo}}})
                path.write_text(original)
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_text(), original)
                self.assertFalse((root / "credential.json").exists())

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

    def test_invalid_cargo_preserved(self):
        for cargo in ({}, {"starter": {"seprom": -1}}, {"starter": {"seprom": 1.5}},
                      {"starter": {"unknown": 1}}, {"starter": {"prometium": 400, "seprom": 1}}):
            with self.subTest(cargo=cargo), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / "pilots.json"
                original = json.dumps({"version": 3, "pilots": {"test": {
                    "verifier": "a" * 64, "credits": 1, "equipment": pilots.starter_equipment(), "cargo": cargo}}})
                path.write_text(original)
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_text(), original)
                self.assertFalse((root / "credential.json").exists())


if __name__ == "__main__":
    unittest.main()
