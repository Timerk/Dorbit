#!/usr/bin/env python3
"""Translate Linux service/terminal stop signals into a graceful Godot shutdown."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def main() -> int:
    if len(sys.argv) < 2:
        sys.exit("Usage: python3 tools/run_server.py GODOT [ARGUMENTS...]")
    stopping = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    # A private, per-launch path cannot contain a previous server's stop request.
    with tempfile.TemporaryDirectory(prefix="dorbit-stop-") as directory:
        request = Path(directory) / "stop"
        environment = dict(os.environ, DORBIT_SHUTDOWN_FILE=str(request))
        # Ctrl+C must reach this launcher, not terminate Godot before _exit_tree.
        child = subprocess.Popen(sys.argv[1:], env=environment, start_new_session=True)
        deadline = None
        while child.poll() is None:
            if stopping and deadline is None:
                request.touch(mode=0o600)
                deadline = time.monotonic() + 20
            if deadline is not None and time.monotonic() >= deadline:
                print("Graceful shutdown timed out; forcing exit. Preserve saves and inspect the lock before restart.", file=sys.stderr)
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
                return 1
            time.sleep(0.05)
        return child.returncode if child.returncode >= 0 else 128 - child.returncode


if __name__ == "__main__":
    sys.exit(main())
