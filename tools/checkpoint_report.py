#!/usr/bin/env python3
"""Summarize a checked ten-client benchmark; never promote diagnostics to capacity evidence."""
import argparse
import json
import math
from pathlib import Path


STAGES = ("write", "flush", "readback", "close", "rename")


def distribution(values):
    values = sorted(values)
    return {"count": len(values), **{
        name: values[math.ceil(len(values) * rank) - 1] if values else None
        for name, rank in (("p95", .95), ("p99", .99), ("max", 1))}}


def summarize(result):
    server = result["server"]
    reasons = []
    if not server["passed"]: reasons.append("workload activity failed")
    if not result["shutdown"]["passed"]: reasons.append("shutdown failed")
    if result["network"]["socket_dropped_frames"]: reasons.append("capture dropped frames")
    if server["minimum_roster"] != 10: reasons.append("ten-client roster missing")
    if server["elapsed_seconds"] < 60: reasons.append("window shorter than 60 seconds")
    if not any(event.get("checkpoints", 0) > 1 for event in server.get("simultaneous_extras", [])):
        reasons.append("simultaneous resupply evidence missing")
    labs = server["skylab"]
    if len(labs) != 10 or any(lab["after_at"] <= lab["before_at"] or
                             lab["after_inventory"] == lab["before_inventory"] for lab in labs.values()):
        reasons.append("minute-boundary industry evidence missing")
    events = [event for event in server["persistence_events"] if "stages_us" in event]
    timings = {}
    for kind in ("replace_backup", "replace_primary", "replace_journal"):
        selected = [event for event in events if event["kind"] == kind]
        if not selected: reasons.append(f"{kind} substep evidence missing")
        if any(not event["succeeded"] or not all(stage in event["stages_us"] for stage in STAGES)
               for event in selected): reasons.append(f"{kind} replacement failed or incomplete")
        timings[kind] = {stage: distribution([event["stages_us"][stage] for event in selected
                                            if stage in event["stages_us"]]) for stage in STAGES}
    return {"activity_and_capture_checks_passed": not reasons, "limitations": reasons,
            "runtime_scope": "source workload using editor executable; not exported/VPS capacity evidence",
            "environment": result["environment"],
            "clock_comparison": {key: server[key] for key in ("elapsed_seconds", "system_elapsed_seconds")},
            "external_clock_comparison": {key: result["process"][key] for key in
                                          ("sample_window_seconds", "sample_window_raw_seconds")},
            "session_tick_us": server["session_tick_us"],
            "checkpoint_us": {key: value for key, value in server["persistence_us"].items()
                              if key.startswith("checkpoint")},
            "replacement_substeps_us": timings,
            "simultaneous_extras": server.get("simultaneous_extras", []),
            "skylab": labs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    result = summarize(json.loads(args.results.read_text()))
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["activity_and_capture_checks_passed"] else 1)


if __name__ == "__main__":
    main()
