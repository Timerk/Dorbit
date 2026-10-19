"""Measure fresh-process scenery startup using isolated device profiles and ledgers."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--mode", choices=("both", "client", "server"), default="both")
    args = parser.parse_args()
    results = []
    modes = (False, True) if args.mode == "both" else (args.mode == "server",)
    for dedicated in modes:
        for run in range(args.runs):
            with tempfile.TemporaryDirectory(prefix="dorbit-scenery-") as directory:
                profile = Path(directory)
                ledger = profile / "ledger"
                ledger.mkdir()
                (ledger / "pilots.json").write_text(json.dumps({"version": 1, "pilots": {
                    "benchmark": {"verifier": "0" * 64, "credits": 0}}}))
                env = dict(os.environ, APPDATA=directory, XDG_DATA_HOME=directory,
                           XDG_CONFIG_HOME=directory, DORBIT_DATA_DIR=str(ledger))
                env.pop("DORBIT_PILOT_FILE", None)
                command = [str(args.engine.resolve()), "--path", str(args.project.resolve()), "--max-fps", "60"]
                if dedicated:
                    command.append("--headless")
                command += ["--script", "res://tests/scenery_startup_benchmark.gd", "--", "--port=25993"]
                if dedicated:
                    command.append("--server")
                started = time.perf_counter()
                process = subprocess.run(command, env=env, capture_output=True, text=True,
                                         encoding="utf-8", errors="replace", timeout=120)
                output = process.stdout + process.stderr
                if process.returncode or any(error in output for error in ("ERROR:", "SCRIPT ERROR:", "Parse Error:")):
                    raise RuntimeError(output)
                line = next(line for line in output.splitlines() if line.startswith("SCENERY_BENCHMARK="))
                result = json.loads(line.split("=", 1)[1])
                result.update(run=run + 1, process_seconds=round(time.perf_counter() - started, 3))
                results.append(result)
                print(json.dumps(result), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
