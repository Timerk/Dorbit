#!/usr/bin/env python3
"""Provision or rotate private-group credentials with the game server stopped."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets


def write_new(path: Path, data: dict) -> None:
    # Exclusive creation preserves interrupted files and existing credentials.
    with path.open("x", encoding="utf-8") as file:
        os.chmod(path, 0o600)
        json.dump(data, file, indent=2)
        file.write("\n")
        file.flush()
        os.fsync(file.fileno())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("pilot", help="Stable lowercase ID, 1..32 letters, digits, _ or -")
    parser.add_argument("credential", type=Path, help="New private client credential file")
    parser.add_argument("--init", action="store_true", help="Explicitly initialize a new ledger")
    parser.add_argument("--rotate", action="store_true", help="Replace an existing pilot token, preserving credits")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9_-]{1,32}", args.pilot):
        parser.error("Invalid pilot ID")
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = args.directory / "pilots.json"
    lock = args.directory / "pilots.json.lock"
    lock.mkdir()  # Same exclusive lock as the game server.
    try:
        if args.init:
            if path.exists() or args.rotate:
                parser.error("--init requires a new ledger and cannot be combined with --rotate")
            data = {"version": 1, "pilots": {}}
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("version") != 1 or not isinstance(data.get("pilots"), dict) or not data["pilots"]:
                parser.error("Invalid ledger; preserve it and recover from backup")
            for pilot, record in data["pilots"].items():
                if (not re.fullmatch(r"[a-z0-9_-]{1,32}", pilot)
                        or not isinstance(record, dict)
                        or not isinstance(record.get("verifier"), str)
                        or not re.fullmatch(r"[0-9a-f]{64}", record["verifier"])
                        or type(record.get("credits")) is not int
                        or not 0 <= record["credits"] <= 2_000_000_000):
                    parser.error("Invalid pilot record; preserve it and recover from backup")
        exists = args.pilot in data["pilots"]
        if exists != args.rotate:
            parser.error("Use --rotate for an existing pilot; omit it for a new pilot")
        token = secrets.token_hex(32)
        credits = data["pilots"].get(args.pilot, {}).get("credits", 0)
        data["pilots"][args.pilot] = {"verifier": hashlib.sha256(token.encode()).hexdigest(), "credits": credits}
        temporary = path.with_name("pilots.json.tmp")
        if temporary.exists():
            parser.error("Interrupted pilots.json.tmp exists; preserve it and recover first")
        # Deliver the credential before activating it, so a write failure cannot strand a pilot.
        write_new(args.credential, {"id": args.pilot, "token": token})
        write_new(temporary, data)
        if path.exists():
            backup = path.with_name("pilots.json.bak.tmp")
            write_new(backup, json.loads(path.read_text(encoding="utf-8")))
            os.replace(backup, path.with_name("pilots.json.bak"))
        os.replace(temporary, path)
        if os.name == "posix":
            descriptor = os.open(args.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        print(f"Provisioned {args.pilot}. Keep {args.credential} private; credits: {credits}.")
    finally:
        lock.rmdir()


if __name__ == "__main__":
    main()
