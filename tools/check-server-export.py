#!/usr/bin/env python3
"""Check the exported server in a clean directory, with disposable saves only."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

import pilots


ROOT = Path(__file__).resolve().parents[1]
ERRORS = ("SCRIPT ERROR:", "Parse Error:", "ERROR:")


def port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def probe(command, environment, cwd=None):
    try:
        result = subprocess.run(command, env=environment, cwd=cwd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired as error:
        def decoded(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
        raise RuntimeError("Server export probe timed out: " + decoded(error.output) + decoded(error.stderr)) from error
    output = result.stdout + result.stderr
    if result.returncode or any(error in output for error in ERRORS):
        raise RuntimeError(output)
    lines = [line.removeprefix("DORBIT_SERVER_EXPORT=") for line in output.splitlines()
             if line.startswith("DORBIT_SERVER_EXPORT=")]
    if len(lines) != 1:
        raise RuntimeError("Missing server export manifest: " + output)
    return json.loads(lines[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("editor", type=Path)
    parser.add_argument("pack", type=Path)
    parser.add_argument("--runtime", type=Path, help="Use the Linux export template instead of the editor")
    args = parser.parse_args()
    editor, pack = args.editor.resolve(), args.pack.resolve()
    runtime = args.runtime.resolve() if args.runtime else editor
    with tempfile.TemporaryDirectory(prefix="dorbit-export-check-") as directory:
        clean = Path(directory)
        runtime_directory = clean / "runtime"
        runtime_directory.mkdir()
        shipped = runtime_directory / pack.name
        shutil.copyfile(pack, shipped)
        if args.runtime:
            executable = runtime_directory / (pack.stem + (".exe" if os.name == "nt" else ".x86_64"))
            shutil.copy2(runtime, executable)
            packed_command = [str(executable), "--headless"]
        else:
            packed_command = [str(editor), "--headless", "--path", str(clean), "--main-pack", str(shipped)]
        data = clean / "data"
        data.mkdir()
        token = "disposable-export-check-token"
        ledger = data / "pilots.json"
        # Use the current save schema so migration is not mistaken for data loss.
        # A nonempty laser boost must survive both restarts without firing.
        original = json.dumps({"version": 5, "pilots": {
            "export_test": {"verifier": hashlib.sha256(token.encode()).hexdigest(), "credits": 137,
                            "equipment": pilots.starter_equipment(), "cargo": {"starter": {"seprom": 5}},
                            "ammo": pilots.starter_ammo(), "contracts": {},
                            "boosts": {"starter": {"lasers": {"resource": "seprom", "remaining": 7}}}}}})
        ledger.write_text(original)
        environment = dict(os.environ, DORBIT_DATA_DIR=str(data), APPDATA=str(clean / "appdata"),
                           HOME=str(clean), XDG_DATA_HOME=str(clean / "userdata"))
        environment.pop("DORBIT_PILOT_FILE", None)
        script = str(ROOT / "tests/server_export_test.gd")
        source = probe([str(editor), "--headless", "--path", str(ROOT), "--script", script,
                        "--", f"--port={port()}"], environment)
        # Inspect pack resources with the editor: release templates deliberately
        # disallow external script/path overrides. Boot/network checks below use
        # the real release template and its adjacent PCK with no overrides.
        exported = probe([str(editor), "--headless", "--path", str(clean), "--main-pack", str(shipped),
                          "--script", script, "--", "--expect-export", f"--port={port()}"], environment, clean)
        if source != exported:
            raise RuntimeError("Exported protocol, collision geometry or ship catalog differs from source")
        # Boot the actual exported main scene twice without the checkout or import cache.
        for attempt in range(2):
            request = clean / f"stop-{attempt}"
            log = clean / f"startup-{attempt}.log"
            started = time.monotonic()
            server_port = port()
            with log.open("w") as output:
                process = subprocess.Popen([*packed_command, "--", f"--port={server_port}"], cwd=clean,
                    env=dict(environment, DORBIT_SHUTDOWN_FILE=str(request)), stdout=output, stderr=subprocess.STDOUT)
                try:
                    deadline = started + 15
                    while time.monotonic() < deadline:
                        if "Server listening on UDP" in log.read_text():
                            break
                        if process.poll() is not None:
                            raise RuntimeError(log.read_text())
                        time.sleep(0.05)
                    else:
                        raise RuntimeError("Exported server did not start within 15 seconds: " + log.read_text())
                    print(f"TIMING: exported server ready (attempt {attempt + 1}): {time.monotonic() - started:.2f}s")
                    client = subprocess.run([str(editor), "--headless", "--path", str(ROOT), "--script",
                        "res://tests/server_export_client_test.gd", "--", str(server_port)], env=environment,
                        capture_output=True, text=True, timeout=30)
                    client_output = client.stdout + client.stderr
                    if client.returncode or any(error in client_output for error in ERRORS):
                        raise RuntimeError(client_output)
                    print(client_output.strip())
                    request.touch()
                    process.wait(timeout=10)
                    text = log.read_text()
                    if process.returncode or any(error in text for error in ERRORS):
                        raise RuntimeError(text)
                    if "Server shutdown requested" not in text or json.loads(ledger.read_text()) != json.loads(original):
                        raise RuntimeError("Shutdown did not preserve disposable pilot data")
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
        if (clean / ".godot/imported").exists() or (runtime_directory / ".godot/imported").exists():
            raise RuntimeError("Exported server unexpectedly created an import cache")
        print("Exported server matches source protocol, hull catalog and 30 colliders; clean startup/restart and saves passed.")


if __name__ == "__main__":
    main()
