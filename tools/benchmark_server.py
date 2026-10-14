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
import socket
import struct
import subprocess
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / ".tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64"


def distribution(values):
    if not values:
        return {}
    ordered = sorted(values)
    return {
        "count": len(values), "mean": sum(values) / len(values),
        **{f"p{p}": ordered[math.ceil(len(values) * p / 100) - 1] for p in (50, 95, 99)},
        "max": ordered[-1],
    }


def decode_datagram(frame, packet_type, server_port):
    """Count each loopback IPv4 UDP datagram once, including IP/UDP headers."""
    if packet_type != socket.PACKET_OUTGOING or len(frame) < 42 or frame[12:14] != b"\x08\x00":
        return None
    ip = frame[14:]
    header = (ip[0] & 15) * 4
    if ip[0] >> 4 != 4 or ip[9] != 17 or len(ip) < header + 8:
        return None
    source, destination, udp_length = struct.unpack_from("!HHH", ip, header)
    if source != server_port or ip[12:20] != b"\x7f\x00\x00\x01" * 2:
        return None
    return destination, struct.unpack_from("!H", ip, 2)[0], udp_length - 8


class TrafficCapture:
    """AF_PACKET on loopback requires root or CAP_NET_RAW. No game sockets changed."""

    def __init__(self, port):
        self.port = port
        self.socket = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
        self.socket.bind(("lo", 0))
        try:
            # Root can raise this socket's buffer without changing host sysctls.
            self.socket.setsockopt(socket.SOL_SOCKET, 33, 16 * 1024 * 1024)  # SO_RCVBUFFORCE
        except PermissionError:
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.socket.settimeout(0.1)
        self.lock = threading.Lock()
        self.counts = {}
        self.running = True
        self.thread = threading.Thread(target=self.receive, daemon=True)
        self.thread.start()

    def receive(self):
        while self.running:
            try:
                frame, address = self.socket.recvfrom(65535)
            except socket.timeout:
                continue
            decoded = decode_datagram(frame, address[2], self.port)
            if decoded is not None:
                port, ip_bytes, payload_bytes = decoded
                with self.lock:
                    counter = self.counts.setdefault(port, [0, 0, 0])
                    for index, value in enumerate((1, ip_bytes, payload_bytes)):
                        counter[index] += value

    def snapshot(self):
        with self.lock:
            return time.clock_gettime(time.CLOCK_MONOTONIC_RAW), {p: c.copy() for p, c in self.counts.items()}

    def close(self):
        self.running = False
        self.thread.join(timeout=2)
        # PACKET_STATISTICS returns received and kernel-dropped frames since last read.
        received, dropped = struct.unpack("II", self.socket.getsockopt(263, 6, 8))
        self.socket.close()
        return {"socket_received_frames": received, "socket_dropped_frames": dropped}


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
    parser.add_argument("--engine", type=Path, default=ENGINE, help="Godot Linux executable")
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--warmup", type=int, default=15)
    parser.add_argument("--scenario", choices=("spread", "single-map"), required=True)
    parser.add_argument("--git", default="git", help="Use git.exe for a Windows-owned worktree in WSL")
    parser.add_argument("--output", type=Path, required=True, help="New directory for logs and JSON")
    args = parser.parse_args()
    if platform.system() != "Linux" or args.seconds < 30 or args.warmup < 1:
        parser.error("Requires Linux, seconds >= 30, warmup >= 1")
    output = args.output.resolve()
    revision = subprocess.check_output([args.git, "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    git_status = subprocess.check_output([args.git, "status", "--short"], cwd=ROOT, text=True)
    source_files = list((ROOT / "scripts").glob("*.gd")) + list((ROOT / "assets").rglob("*.json")) + [
        ROOT / name for name in ("tests/server_workload.gd", "tests/network_test.gd",
                                "tests/benchmark_store.gd", "tools/benchmark_server.py", "project.godot")]
    source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}
    started_utc = datetime.now(timezone.utc).isoformat()
    output.mkdir(parents=True, exist_ok=False)
    command = [str(args.engine), "--headless", "--max-fps", "60", "--path", str(ROOT)]
    imported = subprocess.run(command + ["--editor", "--import"], capture_output=True, text=True, timeout=600)
    (output / "import.log").write_text(imported.stdout + imported.stderr)
    if imported.returncode or "ERROR:" in imported.stdout + imported.stderr:
        raise RuntimeError(f"Import failed; see {output / 'import.log'}")
    processes = []
    logs = []
    samples = []
    capture = TrafficCapture(24683 + int(os.environ.get("DORBIT_TEST_PORT_OFFSET", "0")))
    traffic_start = None

    def launch(role, index=0):
        log = (output / f"{role}-{index}.log").open("w")
        logs.append(log)
        environment = os.environ.copy()
        # Keep all test credentials, saves and client settings inside the owned run directory.
        environment["XDG_DATA_HOME"] = str(output / f"user-{role}-{index}")
        environment.pop("DORBIT_TEST_CLOCK", None)
        child = subprocess.Popen(command + ["--script", "res://tests/server_workload.gd", "--",
            f"--role={role}", f"--index={index}", f"--seconds={args.seconds}",
            f"--warmup={args.warmup}", f"--scenario={args.scenario}", f"--output={output}"],
            env=environment, stdout=log, stderr=subprocess.STDOUT)
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
                if traffic_start is None:
                    traffic_start = capture.snapshot()
                if not samples or time.monotonic() - samples[-1]["monotonic_seconds"] >= 1:
                    samples.append(process_sample(server.pid))
            time.sleep(0.1)
        traffic_end = capture.snapshot()
        samples.append(process_sample(server.pid))
        healthy()
        server_result = json.loads((output / "server.json").read_text())
        cpu = [100 * (b["cpu_seconds"] - a["cpu_seconds"]) /
               (b["monotonic_raw_seconds"] - a["monotonic_raw_seconds"]) for a, b in zip(samples, samples[1:])]
        traffic_seconds = traffic_end[0] - traffic_start[0]
        client_traffic = {}
        for pilot, port in server_result["peer_ports"].items():
            totals = [b - a for a, b in zip(traffic_start[1].get(port, [0, 0, 0]), traffic_end[1].get(port, [0, 0, 0]))]
            client_traffic[pilot] = {"port": port, "map": server_result["pilot_maps"][pilot],
                "udp_datagrams": totals[0], "ip_bytes": totals[1], "udp_payload_bytes": totals[2],
                "packets_per_second": totals[0] / traffic_seconds, "ip_bytes_per_second": totals[1] / traffic_seconds,
                "udp_payload_bytes_per_second": totals[2] / traffic_seconds}
        capture_stats = capture.close()
        capture = None
        (output / "stop").touch()
        server.wait(timeout=15)
        shutdown = json.loads((output / "shutdown.json").read_text())
        environment = {
            "platform": platform.platform(), "cpu": platform.processor(),
            "lscpu": subprocess.check_output(["lscpu"], text=True),
            "memory": Path("/proc/meminfo").read_text(),
            "os_release": Path("/etc/os-release").read_text(),
            "engine": subprocess.check_output([str(args.engine), "--headless", "--version"], text=True).strip(),
            "git_commit": revision, "git_status": git_status,
            "source_sha256": source_hashes, "started_utc": started_utc,
            "command": command, "clients": 10, "transport": "ENet UDP IPv4 loopback port 24683",
            "seconds": args.seconds, "warmup": args.warmup, "scenario": args.scenario,
            "save_filesystem": subprocess.check_output(["findmnt", "-T", str(output), "-o", "TARGET,SOURCE,FSTYPE"], text=True),
            "invocation": __import__("sys").argv,
        }
        result = {"environment": environment, "server": server_result, "shutdown": shutdown,
            "network": {"window_raw_seconds": traffic_seconds, "per_client": client_traffic,
                "total_packets_per_second": sum(c["packets_per_second"] for c in client_traffic.values()),
                "total_ip_bytes_per_second": sum(c["ip_bytes_per_second"] for c in client_traffic.values()),
                **capture_stats}, "process": {
            "sample_window_seconds": samples[-1]["monotonic_seconds"] - samples[0]["monotonic_seconds"],
            "sample_window_raw_seconds": samples[-1]["monotonic_raw_seconds"] - samples[0]["monotonic_raw_seconds"],
            "cpu_percent_one_core": distribution(cpu),
            "rss_mib": distribution([sample["rss_mib"] for sample in samples]),
            "lifetime_hwm_mib": samples[-1]["hwm_mib"], "samples": samples,
        }}
        (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({"passed": server_result["passed"], "tick_us": server_result["session_tick_us"],
            "persistence_us": server_result["persistence_us"], "network": result["network"],
            "process": {k: v for k, v in result["process"].items() if k != "samples"}}, indent=2))
        if not server_result["passed"]:
            raise RuntimeError("Workload activity checks failed")
        if capture_stats["socket_dropped_frames"]:
            raise RuntimeError("Packet capture dropped frames; network result is incomplete")
        if not shutdown["passed"] or server.returncode:
            raise RuntimeError("Clean server shutdown failed")
    finally:
        if capture is not None:
            capture.close()
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
