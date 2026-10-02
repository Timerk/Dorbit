#!/usr/bin/env python3
"""Provision or rotate private-group credentials with the game server stopped."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets


def starter_equipment() -> dict:
    return {"revision": 0, "active_ship": "starter", "ships": {"starter": "pathfinder"},
            "items": {f"starter-{model}": {"model": model, "ship": "starter", "slot": slot}
                      for model, slot in [("laser", "laser1"), ("shield", "generator1"), ("engine", "generator2")]}}


def valid_equipment(data: object) -> bool:
    if (not isinstance(data, dict) or type(data.get("revision")) is not int
            or not 0 <= data["revision"] <= 2_000_000_000
            or not isinstance(data.get("ships"), dict) or not data["ships"]
            or not isinstance(data.get("items"), dict)
            or not isinstance(data.get("active_ship"), str) or data["active_ship"] not in data["ships"]):
        return False
    for ship, model in data["ships"].items():
        if not re.fullmatch(r"[a-z0-9_-]{1,32}", ship) or model != "pathfinder":
            return False
    occupied = set()
    for identifier, item in data["items"].items():
        if (not re.fullmatch(r"[a-z0-9_-]{1,32}", identifier) or not isinstance(item, dict)
                or item.get("model") not in ("laser", "shield", "engine")
                or not isinstance(item.get("ship"), str) or not isinstance(item.get("slot"), str)):
            return False
        location = item["ship"], item["slot"]
        if location == ("", ""):
            continue
        slots = ("laser1", "laser2") if item["model"] == "laser" else ("generator1", "generator2")
        if item["ship"] not in data["ships"] or item["slot"] not in slots or location in occupied:
            return False
        occupied.add(location)
    return True


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
            data = {"version": 2, "pilots": {}}
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("version") not in (1, 2) or not isinstance(data.get("pilots"), dict) or not data["pilots"]:
                parser.error("Invalid ledger; preserve it and recover from backup")
            for pilot, record in data["pilots"].items():
                if (not re.fullmatch(r"[a-z0-9_-]{1,32}", pilot)
                        or not isinstance(record, dict)
                        or not isinstance(record.get("verifier"), str)
                        or not re.fullmatch(r"[0-9a-f]{64}", record["verifier"])
                        or type(record.get("credits")) is not int
                        or not 0 <= record["credits"] <= 2_000_000_000):
                    parser.error("Invalid pilot record; preserve it and recover from backup")
                if data["version"] == 1:
                    if "equipment" in record:
                        parser.error("Unexpected equipment in legacy ledger; preserve it and recover")
                    record["equipment"] = starter_equipment()
                elif not valid_equipment(record.get("equipment")):
                    parser.error("Invalid equipment; preserve it and recover from backup")
            data["version"] = 2
        exists = args.pilot in data["pilots"]
        if exists != args.rotate:
            parser.error("Use --rotate for an existing pilot; omit it for a new pilot")
        token = secrets.token_hex(32)
        credits = data["pilots"].get(args.pilot, {}).get("credits", 0)
        record = data["pilots"].setdefault(args.pilot, {"credits": credits, "equipment": starter_equipment()})
        record["verifier"] = hashlib.sha256(token.encode()).hexdigest()
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
