#!/usr/bin/env python3
"""Provision or rotate private-group credentials with the game server stopped."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import time

# Use the runtime catalog to keep hull slots and cargo validation identical.
SHIP_MODELS = json.loads((Path(__file__).resolve().parents[1] / "assets/ships/catalog.json").read_text(encoding="utf-8"))
SKYLAB_BALANCE = json.loads((Path(__file__).resolve().parents[1] / "assets/skylab/balance-v1.json").read_text(encoding="utf-8"))


def ship_info(model: str) -> dict:
    return SHIP_MODELS["liberator" if model == "pathfinder" else model]

LASER_MODELS = {"laser", "mp-1", "lf-2", "lf-3", "lf-4"}
LAUNCHER_MODELS = {"hst-1", "hst-2"}
GENERATOR_MODELS = {"shield", "sg3n-a02", "fs-01", "sg3n-a03", "sg3n-b00", "sg3n-b01", "sg3n-b02",
                    "engine", "g3n-1010", "g3n-2010", "g3n-3210", "g3n-3310", "g3n-6900", "g3n-7900"}


def starter_equipment() -> dict:
    return {"revision": 0, "active_ship": "starter", "ships": {"starter": "pathfinder"},
            "items": {f"starter-{model}": {"model": model, "ship": "starter", "slot": slot}
                      for model, slot in [("laser", "laser1"), ("shield", "generator1"), ("engine", "generator2")]}}


def starter_ammo() -> dict:
    return {"x1": 10000, "x2": 0, "x3": 0, "x4": 0, "r-310": 100, "plt-2026": 0, "plt-2021": 0, "plt-3030": 0, "eco-10": 0, "hstrm-01": 0}


def valid_ammo(data: object, legacy: bool = False) -> bool:
    return (isinstance(data, dict) and data.keys() == ({"x1", "x2", "x3", "x4"} if legacy else starter_ammo().keys())
            and all(type(amount) is int and 0 <= amount <= 2_000_000_000 for amount in data.values()))


def valid_equipment(data: object) -> bool:
    if (not isinstance(data, dict) or type(data.get("revision")) is not int
            or not 0 <= data["revision"] <= 2_000_000_000
            or not isinstance(data.get("ships"), dict) or not data["ships"]
            or not isinstance(data.get("items"), dict)
            or not isinstance(data.get("active_ship"), str) or data["active_ship"] not in data["ships"]):
        return False
    for ship, model in data["ships"].items():
        if (not isinstance(ship, str) or not re.fullmatch(r"[a-z0-9_-]{1,32}", ship)
                or not isinstance(model, str) or model not in (*SHIP_MODELS, "pathfinder")):
            return False
    occupied = set()
    for identifier, item in data["items"].items():
        if (not re.fullmatch(r"[a-z0-9_-]{1,32}", identifier) or not isinstance(item, dict)
                or not isinstance(item.get("model"), str)
                or item["model"] not in LASER_MODELS | GENERATOR_MODELS | LAUNCHER_MODELS
                or not isinstance(item.get("ship"), str) or not isinstance(item.get("slot"), str)):
            return False
        location = item["ship"], item["slot"]
        if location == ("", ""):
            continue
        if item["ship"] not in data["ships"]:
            return False
        hull = ship_info(data["ships"][item["ship"]])
        kind, count = ("launcher", 1) if item["model"] in LAUNCHER_MODELS else (("laser", hull["lasers"]) if item["model"] in LASER_MODELS else ("generator", hull["generators"]))
        slots = tuple(f"{kind}{index}" for index in range(1, count + 1))
        if item["ship"] not in data["ships"] or item["slot"] not in slots or location in occupied:
            return False
        occupied.add(location)
    return True

def valid_cargo(data: object, equipment: dict) -> bool:
    prices = {"prometium", "endurium", "terbium", "prometid", "duranium", "xenomit", "promerium", "seprom"}
    if not isinstance(data, dict) or data.keys() != equipment["ships"].keys():
        return False
    for ship, hold in data.items():
        if not isinstance(hold, dict):
            return False
        capacity = ship_info(equipment["ships"][ship])["cargo"]
        if any(resource not in prices or type(amount) is not int or not 1 <= amount <= 2 * capacity
               for resource, amount in hold.items()) or sum(hold.values()) > 2 * capacity:
            return False
    return True


def starter_skylab(at: int) -> dict:
    names = SKYLAB_BALANCE["modules"].keys()
    resources = list(SKYLAB_BALANCE["modules"]["storage"][0]["capacities"])
    return {"version": 1, "balance_version": 1, "lastSimulatedAt": at,
            "inventory": {r: SKYLAB_BALANCE["bootstrap"]["raw_stock"] if r in ("prometium", "endurium", "terbium") else 0 for r in resources},
            "modules": {n: {"level": SKYLAB_BALANCE["bootstrap"]["levels"][n], "enabled": True, "upgrade": None} for n in names},
            "carry": {n: 0.0 for n in names}, "robots": {n: {"active": [], "credit": 0, "advanced": 0} for n in names if n.endswith("Collector")},
            "shipment": None, "fair_turn": 0, "last_outputs": {n: 0 for n in names}, "last_net": {r: 0 for r in resources}}


def valid_skylab(lab: object, equipment: dict) -> bool:
    balance = SKYLAB_BALANCE
    modules = balance["modules"]
    resources = {"prometium", "endurium", "terbium", "prometid", "duranium", "xenomit", "promerium", "seprom"}
    collectors = {name for name in modules if name.endswith("Collector")}
    def integer(value, low=0, high=2_000_000_000):
        return type(value) is int and low <= value <= high
    if (not isinstance(lab, dict) or lab.get("version") != 1 or lab.get("balance_version") != 1
            or not integer(lab.get("lastSimulatedAt"), high=10_000_000_000)
            or not integer(lab.get("fair_turn"), high=1)):
        return False
    for field, keys in [("inventory", resources), ("modules", set(modules)), ("carry", set(modules)),
                        ("robots", collectors), ("last_outputs", set(modules)), ("last_net", resources)]:
        if not isinstance(lab.get(field), dict) or lab[field].keys() != keys:
            return False
    if any(not integer(x) for x in lab["inventory"].values()) or any(not integer(x, -2_000_000_000) for x in lab["last_net"].values()):
        return False
    if any(not integer(x) for x in lab["last_outputs"].values()):
        return False
    for name, module in lab["modules"].items():
        if (not isinstance(module, dict) or not integer(module.get("level"), high=len(modules[name]))
                or type(module.get("enabled")) is not bool):
            return False
        carry = lab["carry"][name]
        rate = modules[name][module["level"]-1]["rate_per_hour"] if module["level"] else 0
        if type(carry) not in (int, float) or not math.isfinite(carry) or not 0 <= carry <= (2 if name == "xeno" else 1) + rate * 1.48 / 60:
            return False
        job = module.get("upgrade")
        if job is not None:
            if (name == "transport" or not isinstance(job, dict) or not integer(job.get("targetLevel"), 1, 20)
                    or job["targetLevel"] != module["level"] + 1
                    or not integer(job.get("startedAt"), high=10_000_000_000)
                    or not integer(job.get("finishesAt"), high=10_000_000_000)
                    or job["finishesAt"] <= job["startedAt"]):
                return False
            if name != "basic" and job["targetLevel"] > lab["modules"]["basic"]["level"]:
                return False
    if not lab["modules"]["basic"]["enabled"] or lab["modules"]["basic"]["level"] < 1:
        return False
    for robots in lab["robots"].values():
        if (not isinstance(robots, dict) or not isinstance(robots.get("active"), list)
                or len(robots["active"]) > 12 or not integer(robots.get("credit")) or not integer(robots.get("advanced"))):
            return False
        for robot in robots["active"]:
            if (not isinstance(robot, dict) or robot.get("kind") not in ("credit", "advanced")
                    or not integer(robot.get("startedAt"), high=10_000_000_000)
                    or not integer(robot.get("expiresAt"), high=10_000_000_000)
                    or robot["expiresAt"] - robot["startedAt"] != 172800):
                return False
    shipment = lab.get("shipment")
    if shipment is not None:
        if (not isinstance(shipment, dict) or not isinstance(shipment.get("id"), str)
                or shipment.get("recipientId") not in equipment["ships"]
                or not isinstance(shipment.get("manifest"), dict) or not shipment["manifest"]
                or any(r not in resources or not integer(a, 1) for r, a in shipment["manifest"].items())
                or sum(shipment["manifest"].values()) > ship_info(equipment["ships"][shipment["recipientId"]])["cargo"]
                or not integer(shipment.get("dispatchedAt"), high=10_000_000_000)
                or not integer(shipment.get("arrivesAt"), high=10_000_000_000)
                or shipment["arrivesAt"] < shipment["dispatchedAt"] or shipment.get("delivered") is not False):
            return False
    return True


def valid_boosts(data: object, equipment: dict) -> bool:
    groups = {"prometid": {"lasers", "rockets"}, "duranium": {"shields", "engines"},
              "promerium": {"lasers", "rockets", "shields", "engines"},
              "seprom": {"lasers", "rockets", "shields"}}
    if not isinstance(data, dict) or data.keys() != equipment["ships"].keys():
        return False
    for boost in data.values():
        if not isinstance(boost, dict):
            return False
        for group, entry in boost.items():
            if (not isinstance(entry, dict) or entry.keys() != {"resource", "remaining"}
                    or not isinstance(entry["resource"], str)
                    or group not in groups.get(entry["resource"], set())):
                return False
            remaining = entry["remaining"]
            maximum = 2_000_000_000
            if (type(remaining) not in (int, float) or not math.isfinite(remaining)
                    or not 0 < remaining <= maximum
                    or group in ("lasers", "rockets") and remaining != int(remaining)):
                return False
    return True


def migrate_skylab_credits(record: dict) -> bool:
    import copy
    old = record.get("uridium")
    if type(old) is not int or not 0 <= old <= 2_000_000_000 or record["credits"] + old * 100 > 2_000_000_000:
        return False
    lab = copy.deepcopy(record.get("skylab"))
    if not isinstance(lab, dict) or not isinstance(lab.get("robots"), dict):
        return False
    for robots in lab["robots"].values():
        if (not isinstance(robots, dict) or type(robots.get("uridium")) is not int
                or "advanced" in robots or not isinstance(robots.get("active"), list)):
            return False
        robots["advanced"] = robots.pop("uridium")
        for robot in robots["active"]:
            if not isinstance(robot, dict) or robot.get("kind") not in ("credit", "uridium"):
                return False
            if robot["kind"] == "uridium": robot["kind"] = "advanced"
    if not valid_skylab(lab, record["equipment"]):
        return False
    record["skylab"] = lab
    record["credits"] += record.pop("uridium") * 100
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
    parser.add_argument("--premium", choices=("on", "off"), help="Operator-set transport-duration flag for an existing schema-6 pilot")
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
            data = {"version": 6, "pilots": {}}
        else:
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("version") not in (1, 2, 3, 4, 5, 6, 7) or not isinstance(data.get("pilots"), dict) or not data["pilots"]:
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
                if data["version"] < 3:
                    if "cargo" in record:
                        parser.error("Unexpected cargo in legacy ledger; preserve it and recover")
                    record["cargo"] = {ship: {} for ship in record["equipment"]["ships"]}
                elif not valid_cargo(record.get("cargo"), record["equipment"]):
                    parser.error("Invalid cargo; preserve it and recover from backup")
                if data["version"] == 4 and "ammo" not in record and "boosts" not in record:
                    parser.error("Missing schema-4 progression; preserve it and recover")
                if data["version"] < 4 and "ammo" in record:
                    parser.error("Unexpected ammunition in legacy ledger; preserve it and recover")
                if "ammo" not in record and data["version"] < 5:
                    record["ammo"] = starter_ammo()
                elif not valid_ammo(record.get("ammo")) and not (data["version"] < 7 and valid_ammo(record.get("ammo"), legacy=True)):
                    parser.error("Invalid ammunition; preserve it and recover from backup")
                if data["version"] < 7 and set(record["ammo"]) == {"x1", "x2", "x3", "x4"}:
                    record["ammo"].update({kind: amount for kind, amount in starter_ammo().items() if kind not in record["ammo"]})
                if "boosts" not in record and data["version"] < 6:
                    record["boosts"] = {ship: {} for ship in record["equipment"]["ships"]}
                elif not valid_boosts(record.get("boosts"), record["equipment"]):
                    parser.error("Invalid resource boosts; preserve it and recover from backup")
                if data["version"] < 5 and any(field in record for field in ("skylab", "uridium", "premium")):
                    parser.error("Unexpected Skylab fields in legacy ledger; preserve it and recover")
                if "skylab" in record and data["version"] < 6:
                    if not migrate_skylab_credits(record):
                        parser.error("Invalid legacy industry or credit conversion overflow; original preserved")
                if (data["version"] == 7 or "skylab" in record) and ("uridium" in record
                        or type(record.get("premium")) is not bool or not valid_skylab(record.get("skylab"), record["equipment"])):
                    parser.error("Invalid Skylab state; preserve it and recover from backup")
            data["version"] = 7 if any("skylab" in r for r in data["pilots"].values()) else 6
        exists = args.pilot in data["pilots"]
        if exists != args.rotate:
            parser.error("Use --rotate for an existing pilot; omit it for a new pilot")
        token = secrets.token_hex(32)
        credits = data["pilots"].get(args.pilot, {}).get("credits", 0)
        record = data["pilots"].setdefault(args.pilot, {"credits": credits, "equipment": starter_equipment(), "cargo": {"starter": {}}, "ammo": starter_ammo(), "boosts": {"starter": {}}})
        if data["version"] == 7 and not exists:
            # Keep the authoritative bootstrap in Godot. Adding pilots to v6 requires it here too.
            record.update(premium=False, skylab=starter_skylab(int(time.time())))
        if args.premium is not None:
            if data["version"] != 7 or not exists:
                parser.error("Start the updated server once to initialize Skylab before setting transport benefits")
            record["premium"] = args.premium == "on"
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
