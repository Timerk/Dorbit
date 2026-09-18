#!/usr/bin/env python3
"""Exercise real Linux stop signals and restart against disposable pilot data."""

import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(sys.argv.pop(1)).resolve()


class ServerShutdownTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="dorbit-shutdown-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.data = self.directory / "data"
        self.data.mkdir()
        self.ledger = self.data / "pilots.json"
        self.lock = self.data / "pilots.json.lock"
        self.original = json.dumps({"version": 1, "pilots": {
            "restart_test": {"verifier": hashlib.sha256(b"disposable test token").hexdigest(), "credits": 137}
        }})
        self.ledger.write_text(self.original)
        self.processes: list[subprocess.Popen] = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self) -> None:
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=25)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    def start(self) -> tuple[subprocess.Popen, Path]:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        log = self.directory / f"server-{len(self.processes)}.log"
        with log.open("w") as output:
            process = subprocess.Popen(
                [sys.executable, str(ROOT / "tools/run_server.py"), str(ENGINE),
                 "--headless", "--max-fps", "60", "--path", str(ROOT), "--", "--server", f"--port={port}"],
                env=dict(os.environ, DORBIT_DATA_DIR=str(self.data)),
                stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
            )
        self.processes.append(process)
        return process, log

    def ready(self, process: subprocess.Popen, log: Path) -> None:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if "Server listening on UDP" in log.read_text():
                self.assertIsNone(process.poll())
                self.assertTrue(self.lock.is_dir())
                return
            if process.poll() is not None:
                break
            time.sleep(0.05)
        self.fail(f"Server did not become ready: {log.read_text()}")

    def test_stop_signals_and_repeated_restart_preserve_credits(self) -> None:
        for stop_signal in (signal.SIGTERM, signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=stop_signal):
                process, log = self.start()
                self.ready(process, log)
                # A group SIGINT models Ctrl+C; systemd mixed mode sends TERM to the launcher.
                if stop_signal == signal.SIGINT:
                    os.killpg(process.pid, stop_signal)
                else:
                    process.send_signal(stop_signal)
                self.assertEqual(process.wait(timeout=10), 0, log.read_text())
                self.assertIn("Server shutdown requested", log.read_text())
                self.assertFalse(self.lock.exists())
                self.assertEqual(self.ledger.read_text(), self.original)

    def test_second_server_cannot_remove_live_lock(self) -> None:
        first, log = self.start()
        self.ready(first, log)
        second, second_log = self.start()
        self.assertEqual(second.wait(timeout=10), 1, second_log.read_text())
        self.assertIn("Cannot acquire pilots.json.lock", second_log.read_text())
        self.assertTrue(self.lock.is_dir())
        self.assertIsNone(first.poll())
        self.assertEqual(self.ledger.read_text(), self.original)

    def test_crash_preserves_lock_and_requires_recovery(self) -> None:
        process, log = self.start()
        self.ready(process, log)
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        self.assertEqual(len(children), 1)
        os.kill(int(children[0]), signal.SIGKILL)
        self.assertEqual(process.wait(timeout=10), 137)
        self.assertTrue(self.lock.is_dir())
        restart, restart_log = self.start()
        self.assertEqual(restart.wait(timeout=10), 1, restart_log.read_text())
        self.assertIn("Cannot acquire pilots.json.lock", restart_log.read_text())
        self.assertEqual(self.ledger.read_text(), self.original)

    def test_hung_server_times_out_without_removing_lock(self) -> None:
        process, log = self.start()
        self.ready(process, log)
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        self.assertEqual(len(children), 1)
        os.kill(int(children[0]), signal.SIGSTOP)
        process.terminate()
        self.assertEqual(process.wait(timeout=25), 1, log.read_text())
        self.assertIn("Graceful shutdown timed out", log.read_text())
        self.assertTrue(self.lock.is_dir())
        self.assertEqual(self.ledger.read_text(), self.original)

    def test_invalid_or_interrupted_saves_are_preserved(self) -> None:
        for temporary in ("pilots.json.tmp", "pilots.json.bak.tmp"):
            with self.subTest(temporary=temporary):
                path = self.data / temporary
                path.write_text("interrupted transaction")
                process, log = self.start()
                self.assertEqual(process.wait(timeout=10), 1, log.read_text())
                self.assertIn("Interrupted save found", log.read_text())
                self.assertEqual(path.read_text(), "interrupted transaction")
                self.assertEqual(self.ledger.read_text(), self.original)
                self.assertFalse(self.lock.exists())
                path.unlink()
        self.ledger.write_text("{broken")
        process, log = self.start()
        self.assertEqual(process.wait(timeout=10), 1, log.read_text())
        self.assertIn("Invalid pilots.json schema", log.read_text())
        self.assertEqual(self.ledger.read_text(), "{broken")
        self.assertFalse(self.lock.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
