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
    def test_legacy_industry_currency_rotation_preserves_jobs_and_robots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lab = pilots.starter_skylab(100)
            for robots in lab["robots"].values():
                robots["uridium"] = robots.pop("advanced")
            lab["robots"]["prometiumCollector"]["uridium"] = 7
            lab["robots"]["prometiumCollector"]["active"] = [
                {"kind": "uridium", "startedAt": 100, "expiresAt": 172900}]
            record = {"verifier": "a" * 64, "credits": 2345, "uridium": 70,
                      "equipment": pilots.starter_equipment(), "ammo": {"x1": 12, "x2": 23, "x3": 34, "x4": 4},
                      "cargo": {"starter": {"xenomit": 3}}, "contracts": {}, "premium": False, "skylab": lab}
            original = {"version": 5, "pilots": {"test": record}}
            path = root / "pilots.json"
            path.write_text(json.dumps(original))
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential.json"), "--rotate"], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            saved = json.loads(path.read_text())
            self.assertEqual(saved["version"], 6)
            self.assertEqual(saved["pilots"]["test"]["credits"], 9345)
            self.assertNotIn("uridium", saved["pilots"]["test"])
            self.assertEqual(saved["pilots"]["test"]["ammo"], record["ammo"])
            robots = saved["pilots"]["test"]["skylab"]["robots"]["prometiumCollector"]
            self.assertEqual(robots["advanced"], 7)
            self.assertEqual(robots["active"], [{"kind": "advanced", "startedAt": 100, "expiresAt": 172900}])
            self.assertEqual(json.loads(path.with_name("pilots.json.bak").read_text()), original)
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential-2.json"), "--rotate"], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(path.read_text())["pilots"]["test"]["credits"], 9345)

    def test_legacy_currency_conversion_overflow_preserves_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lab = pilots.starter_skylab(100)
            for robots in lab["robots"].values():
                robots["uridium"] = robots.pop("advanced")
            record = {"verifier": "a" * 64, "credits": 1_999_999_950, "uridium": 1,
                      "equipment": pilots.starter_equipment(), "ammo": pilots.starter_ammo(),
                      "cargo": {"starter": {}}, "contracts": {}, "premium": False, "skylab": lab}
            original = json.dumps({"version": 5, "pilots": {"test": record}})
            path = root / "pilots.json"
            path.write_text(original)
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential.json"), "--rotate"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(path.read_text(), original)
            self.assertFalse((root / "credential.json").exists())

    def test_skylab_rotation_benefits_and_new_pilot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lab = pilots.starter_skylab(100)
            lab["carry"]["xeno"] = 1.75
            lab["shipment"] = {"id": "shipment-1", "recipientId": "starter",
                               "manifest": {"promerium": 3}, "dispatchedAt": 100,
                               "arrivesAt": 160, "delivered": False}
            lab["robots"]["prometiumCollector"]["active"] = [
                {"kind": "credit", "startedAt": 100, "expiresAt": 172900}]
            record = {"verifier": "a" * 64, "credits": 2345,
                      "equipment": pilots.starter_equipment(),
                      "cargo": {"starter": {"xenomit": 500}},
                      "ammo": {"x1": 4321, "x2": 45, "x3": 123, "x4": 7}, "premium": False, "skylab": lab,
                      "contracts": {}, "boosts": {"starter": {}}}
            path = root / "pilots.json"
            original = {"version": 6, "pilots": {"test": record}}
            path.write_text(json.dumps(original))
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                     str(root / "credential.json"), "--rotate",
                                     "--premium", "on"], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            saved = json.loads(path.read_text())
            expected = record | {"premium": True,
                                 "verifier": saved["pilots"]["test"]["verifier"]}
            self.assertEqual(saved["pilots"]["test"], expected)
            self.assertEqual(json.loads(path.with_name("pilots.json.bak").read_text()), original)
            result = subprocess.run([sys.executable, pilots.__file__, str(root), "new",
                                     str(root / "new.json")], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            added = json.loads(path.read_text())
            self.assertEqual(added["pilots"]["test"], expected)
            self.assertTrue(pilots.valid_skylab(added["pilots"]["new"]["skylab"], added["pilots"]["new"]["equipment"]))
            self.assertNotIn("uridium", added["pilots"]["new"])

    def test_corrupt_skylab_preserved(self):
        for field, value in [("carry", {"xeno": float("nan")}), ("modules", {}),
                             ("shipment", {"manifest": {"xenomit": -1}})]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                lab = pilots.starter_skylab(100)
                lab[field] = value
                path = root / "pilots.json"
                original = json.dumps({"version": 6, "pilots": {"test": {
                    "verifier": "a" * 64, "credits": 1, "equipment": pilots.starter_equipment(),
                    "ammo": pilots.starter_ammo(), "cargo": {"starter": {}}, "premium": False, "skylab": lab}}})
                path.write_text(original)
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_text(), original)
                self.assertFalse((root / "credential.json").exists())

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
            candidate[model]["prometium"] = 2 * info["cargo"] + 1
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
        for version, layout in ((1, "legacy"), (2, "legacy"), (3, "legacy"), (4, "ammo"), (4, "boosts"), (4, "both"), (5, "both")):
            with self.subTest(version=version, layout=layout), tempfile.TemporaryDirectory() as directory:
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
                if layout in ("ammo", "both"):
                    record["ammo"] = {"x1": 4321, "x2": 45, "x3": 123, "x4": 7}
                if layout in ("boosts", "both"):
                    record["boosts"] = {"starter": {"lasers": {"resource": "seprom", "remaining": 7},
                                                      "shields": {"resource": "duranium", "remaining": 600.25}}}
                path = root / "pilots.json"
                path.write_text(json.dumps({"version": version, "pilots": {"test": record}}))
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                saved = json.loads(path.read_text())
                self.assertEqual(saved["version"], 5)
                expected = record | {"equipment": record.get("equipment", pilots.starter_equipment()),
                                     "cargo": record.get("cargo", {"starter": {}}),
                                     "ammo": record.get("ammo", pilots.starter_ammo()),
                                     "boosts": record.get("boosts", {"starter": {}})}
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
                      {"starter": {"unknown": 1}}, {"starter": {"prometium": 800, "seprom": 1}}):
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

    def test_invalid_boosts_preserved(self):
        for boosts in ({}, {"starter": {"engines": {"resource": "seprom", "remaining": 1}}},
                       {"starter": {"lasers": {"resource": "promerium", "remaining": 1.5}}},
                       {"starter": {"shields": {"resource": "duranium", "remaining": -1}}}):
            with self.subTest(boosts=boosts), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / "pilots.json"
                original = json.dumps({"version": 4, "pilots": {"test": {
                    "verifier": "a" * 64, "credits": 1, "equipment": pilots.starter_equipment(),
                    "cargo": {"starter": {}}, "boosts": boosts}}})
                path.write_text(original)
                result = subprocess.run([sys.executable, pilots.__file__, str(root), "test",
                                         str(root / "credential.json"), "--rotate"], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(path.read_text(), original)
                self.assertFalse((root / "credential.json").exists())


if __name__ == "__main__":
    unittest.main()
