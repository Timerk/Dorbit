#!/usr/bin/env python3
"""Run a Linux dedicated server and ten headless ENet clients. Standard library only."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / ".tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64"


def distribution(values):
    ordered = sorted(values)
    return {
        "count": len(values), "mean": sum(values) / len(values),
        **{f"p{p}": ordered[math.ceil(len(values) * p / 100) - 1] for p in (50, 95, 99)},
        "max": ordered[-1],
    }


def process_sample(pid):
    # Fields after comm begin with field 3. utime/stime are fields 14/15.
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    status = dict(line.split(":", 1) for line in Path(f"/proc/{pid}/status").read_text().splitlines())
    return {
        "monotonic_seconds": time.monotonic(),
        "monotonic_raw_seconds": time.clock_gettime(time.CLOCK_MONOTONIC_RAW),
        "cpu_seconds": (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK"),
        "rss_mib": int(status["VmRSS"].split()[0]) / 1024,
        "hwm_mib": int(status["VmHWM"].split()[0]) / 1024,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--warmup", type=int, default=15)
    parser.add_argument("--git", default="git", help="Use git.exe for a Windows-owned worktree in WSL")
    parser.add_argument("--output", type=Path, required=True, help="New directory for logs and JSON")
    args = parser.parse_args()
    if platform.system() != "Linux" or args.seconds < 30 or args.warmup < 1:
        parser.error("Requires Linux, seconds >= 30, warmup >= 1")
    output = args.output.resolve()
    revision = subprocess.check_output([args.git, "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    git_status = subprocess.check_output([args.git, "status", "--short"], cwd=ROOT, text=True)
    source_hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
        "tests/server_workload.gd", "tests/network_test.gd", "tools/benchmark_server.py")}
    started_utc = datetime.now(timezone.utc).isoformat()
    output.mkdir(parents=True, exist_ok=False)
    command = [str(ENGINE), "--headless", "--max-fps", "60", "--path", str(ROOT)]
    imported = subprocess.run(command + ["--editor", "--import"], capture_output=True, text=True, timeout=120)
    (output / "import.log").write_text(imported.stdout + imported.stderr)
    if imported.returncode or "ERROR:" in imported.stdout + imported.stderr:
        raise RuntimeError(f"Import failed; see {output / 'import.log'}")
    processes = []
    logs = []
    samples = []

    def launch(role, index=0):
        log = (output / f"{role}-{index}.log").open("w")
        logs.append(log)
        child = subprocess.Popen(command + ["--script", "res://tests/server_workload.gd", "--",
            f"--role={role}", f"--index={index}", f"--seconds={args.seconds}",
            f"--warmup={args.warmup}", f"--output={output}"], stdout=log, stderr=subprocess.STDOUT)
        processes.append(child)
        return child

    def healthy():
        for child in processes:
            if child.poll() is not None:
                raise RuntimeError(f"Process {child.pid} exited early with {child.returncode}; see logs in {output}")

    try:
        server = launch("server")
        deadline = time.monotonic() + 30
        while "BENCHMARK_READY" not in (output / "server-0.log").read_text():
            healthy()
            if time.monotonic() > deadline:
                raise TimeoutError("Server did not start")
            time.sleep(0.1)
        for index in range(10):
            launch("client", index)
        deadline = time.monotonic() + 30 + args.warmup + args.seconds + 30
        while not (output / "server.json").exists():
            healthy()
            if time.monotonic() > deadline:
                raise TimeoutError("Workload did not finish")
            if (output / "start.json").exists():
                samples.append(process_sample(server.pid))
            time.sleep(1 if samples else 0.1)
        samples.append(process_sample(server.pid))
        healthy()
        server_result = json.loads((output / "server.json").read_text())
        cpu = [100 * (b["cpu_seconds"] - a["cpu_seconds"]) /
               (b["monotonic_seconds"] - a["monotonic_seconds"]) for a, b in zip(samples, samples[1:])]
        environment = {
            "platform": platform.platform(), "cpu": platform.processor(),
            "lscpu": subprocess.check_output(["lscpu"], text=True),
            "memory": Path("/proc/meminfo").read_text(),
            "os_release": Path("/etc/os-release").read_text(),
            "engine": subprocess.check_output([str(ENGINE), "--headless", "--version"], text=True).strip(),
            "git_commit": revision, "git_status": git_status,
            "source_sha256": source_hashes, "started_utc": started_utc,
            "command": command, "clients": 10, "transport": "ENet UDP IPv4 loopback port 24683",
            "seconds": args.seconds, "warmup": args.warmup,
        }
        result = {"environment": environment, "server": server_result, "process": {
            "sample_window_seconds": samples[-1]["monotonic_seconds"] - samples[0]["monotonic_seconds"],
            "sample_window_raw_seconds": samples[-1]["monotonic_raw_seconds"] - samples[0]["monotonic_raw_seconds"],
            "cpu_percent_one_core": distribution(cpu),
            "rss_mib": distribution([sample["rss_mib"] for sample in samples]),
            "lifetime_hwm_mib": samples[-1]["hwm_mib"], "samples": samples,
        }}
        (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"server": server_result, "process": {k: v for k, v in result["process"].items() if k != "samples"}}, indent=2))
        if not server_result["passed"]:
            raise RuntimeError("Workload activity checks failed")
    finally:
        for child in reversed(processes):
            if child.poll() is None:
                child.terminate()
        for child in processes:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        for log in logs:
            log.close()
    for log in output.glob("*.log"):
        if "ERROR:" in log.read_text():
            raise RuntimeError(f"Godot reported errors in {log}")


if __name__ == "__main__":
    main()
