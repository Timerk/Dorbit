#!/usr/bin/env python3
"""Compare cold/warm ship imports in disposable projects; never edit game assets."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def profile(engine: Path, ship: str, mode: int) -> dict:
    with tempfile.TemporaryDirectory(prefix="dorbit-import-profile-") as directory, \
            tempfile.TemporaryDirectory(prefix="dorbit-import-restored-") as restored_directory:
        root = Path(directory)
        (root / "assets/ships").mkdir(parents=True)
        (root / "tools").mkdir()
        shutil.copyfile(ROOT / "assets/ships" / f"{ship}.glb", root / "assets/ships" / f"{ship}.glb")
        settings = (ROOT / "assets/ships" / f"{ship}.glb.import").read_text()
        settings = re.sub(r"gltf/embedded_image_handling=\d+", f"gltf/embedded_image_handling={mode}", settings)
        (root / "assets/ships" / f"{ship}.glb.import").write_text(settings)
        shutil.copyfile(ROOT / "tools/import_ship_materials.gd", root / "tools/import_ship_materials.gd")
        (root / "project.godot").write_text('''config_version=5
[application]
config/features=PackedStringArray("4.7", "GL Compatibility")
[editor]
import/use_multiple_threads=false
[rendering]
renderer/rendering_method="gl_compatibility"
''')
        timings = {}
        for phase in ("cold", "warm", "restored"):
            target = root
            if phase == "restored":
                target = Path(restored_directory)
                shutil.copytree(root, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".godot"))
                # Match a clean checkout, not importer-rewritten source metadata.
                (target / "assets/ships" / f"{ship}.glb.import").write_text(settings)
                shutil.copytree(root / ".godot/imported", target / ".godot/imported")
            start = time.perf_counter()
            result = subprocess.run([str(engine), "--headless", "--path", str(target), "--editor", "--import"],
                                    capture_output=True, text=True, timeout=900)
            timings[f"{phase}_seconds"] = round(time.perf_counter() - start, 3)
            if result.returncode or re.search(r"SCRIPT ERROR:|Parse Error:|ERROR:", result.stdout + result.stderr):
                raise RuntimeError(result.stdout + result.stderr)
        timings["imported_bytes"] = sum(path.stat().st_size for path in (root / ".godot/imported").rglob("*") if path.is_file())
        return {"ship": ship, "mode": "basis" if mode == 2 else "uncompressed", **timings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("--ship", choices=[p.stem for p in (ROOT / "assets/ships").glob("*.glb")], default="liberator")
    parser.add_argument("--output", type=Path, default=ROOT / "build/validation/import-profile-results.json")
    args = parser.parse_args()
    results = []
    for mode in (2, 3):
        result = profile(args.engine.resolve(), args.ship, mode)
        results.append(result)
        print(json.dumps(result), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
