#!/usr/bin/python3 -I
"""Root-owned forced-command helper. Install manually; CI cannot update this file.

The deployment key can replace Dorbit code running as dorbit, which has save access.
This helper offers no arbitrary root commands, unit edits, plaintext downloads or shell.
"""

import fcntl
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import shutil
import subprocess
import sys
import tarfile
import time
import uuid

STATE = Path("/var/lib/dorbit-deploy")
RELEASES = Path("/opt/dorbit/releases")
CURRENT = Path("/opt/dorbit/current")
DATA = Path("/var/lib/dorbit/data")
UNIT = Path("/etc/systemd/system/dorbit.service")
ENV = Path("/etc/dorbit/server.env")
RECIPIENT = Path("/etc/dorbit/backup-recipient.txt")
SERVICE = "dorbit.service"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def save(path, value):
    temporary = path.with_suffix(".next")
    with temporary.open("w") as output:
        json.dump(value, output)
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)
    descriptor = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def active_commit():
    target = CURRENT.resolve(strict=True)
    require(target.parent == RELEASES and re.fullmatch(r"[0-9a-f]{40}", target.name),
            "Current release is not a commit directory")
    return target.name


def unpack(archive, destination):
    """Reject traversal, links, special files and archive bombs before extracting."""
    with tarfile.open(archive, "r:gz") as source:
        members = []
        names = set()
        total = 0
        for member in source:
            path = PurePosixPath(member.name)
            require(not path.is_absolute() and ".." not in path.parts and
                    (member.isfile() or member.isdir()), "Unsafe archive member")
            require(path not in names, "Duplicate archive member")
            names.add(path)
            total += member.size
            require(len(names) <= 30000 and total <= 1024**3, "Archive too large")
            member.mode = 0o755 if member.isdir() or member.mode & 0o111 else 0o644
            members.append(member)
        # No links are accepted, so later entries cannot redirect extraction.
        source.extractall(destination, members=members, filter="data")


def stopped():
    require(run("systemctl", "show", SERVICE, "--property=MainPID", "--value") == "0",
            "Service still has a main process")
    processes = subprocess.run(["pgrep", "-u", "dorbit"], capture_output=True)
    require(processes.returncode == 1, "Dorbit processes remain; operator recovery required")


def clean_data():
    for name in ("pilots.json.lock", "pilots.json.tmp", "pilots.json.bak.tmp"):
        require(not (DATA / name).exists(), "Save lock or interrupted write requires operator recovery")
    require((DATA / "pilots.json").is_file(), "Missing pilot ledger")


def prepare(sha, previous, checksum):
    require(not (STATE / "pending.json").exists(), "Pending deployment requires operator recovery")
    require(active_commit() == previous, "Current commit differs from expected_current")
    require(not (RELEASES / sha).exists(), "Target release already exists; inspect it manually")
    require(not os.path.lexists(CURRENT.with_name("current.next")), "current.next requires inspection")
    require(run("systemctl", "is-active", SERVICE) == "active", "Service must initially be running")
    require(run("systemctl", "show", SERVICE, "--property=DropInPaths", "--value") == "",
            "Unit overrides require operator review")
    require(run("systemctl", "show", SERVICE, "--property=FragmentPath", "--value") == str(UNIT),
            "Unexpected service unit")
    require(re.fullmatch(r"age1[0-9a-z]+", RECIPIENT.read_text().strip()), "Missing age recipient")
    # Fail before stopping if the fixed encryption command is unavailable.
    run("age", "--version")
    require(shutil.disk_usage(STATE).free > 3 * 1024**3, "Need 3 GiB free for staging and recovery")
    transaction = STATE / uuid.uuid4().hex
    transaction.mkdir(mode=0o700)
    archive = transaction / "server.tar.gz"
    with archive.open("wb") as output:
        remaining = 512 * 1024**2
        while chunk := sys.stdin.buffer.read(min(1024**2, remaining + 1)):
            remaining -= len(chunk)
            require(remaining >= 0, "Upload too large")
            output.write(chunk)
    require(digest(archive) == checksum, "Server checksum mismatch")
    staged = transaction / "release"
    staged.mkdir()
    unpack(archive, staged)
    require((staged / "REVISION").read_text().strip() == sha, "Server revision mismatch")
    # CI may deploy game code as dorbit, but must not supply a root-capable unit.
    require((staged / "deploy/dorbit.service").read_bytes() == UNIT.read_bytes(),
            "Unit changed; an operator must review and install it first")
    state = {"id": transaction.name, "commit": sha, "previous": previous,
             "created_at": datetime.now(timezone.utc).isoformat(),
             "previous_link": os.readlink(CURRENT), "phase": "stopping"}
    save(transaction / "transaction.json", state)
    save(STATE / "pending.json", state)
    # From here, any failure leaves the transaction pending for the operator.
    run("systemctl", "stop", SERVICE)
    stopped()
    backup = transaction / "backup.tar"
    with tarfile.open(backup, "w") as output:
        output.add(DATA, arcname="data")
        output.add(UNIT, arcname="dorbit.service")
        output.add(ENV, arcname="server.env")
        output.add(transaction / "transaction.json", arcname="transaction.json")
    run("age", "-r", RECIPIENT.read_text().strip(), "-o", str(transaction / "backup.tar.age"), str(backup))
    backup.unlink()
    state["backup_sha256"] = digest(transaction / "backup.tar.age")
    state["phase"] = "backed-up"
    save(transaction / "transaction.json", state)
    save(STATE / "pending.json", state)
    # Transfer the backup even if stop left a lock. Activation will refuse it.
    print(json.dumps(state))


def ready(timeout=120, stable_seconds=10):
    """Require game initialization and a live UDP socket belonging to this invocation."""
    port = None
    for line in ENV.read_text().splitlines():
        if line.startswith("DORBIT_PORT="):
            port = line.removeprefix("DORBIT_PORT=")
    require(port and port.isdecimal() and 1024 <= int(port) <= 65535, "Invalid configured port")
    invocation = run("systemctl", "show", SERVICE, "--property=InvocationID", "--value")
    require(bool(invocation), "Missing service invocation")
    deadline = time.monotonic() + timeout
    healthy_since = None
    while time.monotonic() < deadline:
        require(run("systemctl", "show", SERVICE, "--property=InvocationID", "--value") == invocation,
                "Service restarted during readiness check")
        require(run("systemctl", "is-active", SERVICE) == "active", "Service exited during startup")
        journal = run("journalctl", "--quiet", "--no-pager", "-o", "cat", f"_SYSTEMD_INVOCATION_ID={invocation}")
        sockets = run("ss", "-H", "-lunp", f"sport = :{port}")
        group = run("systemctl", "show", SERVICE, "--property=ControlGroup", "--value")
        pids = re.findall(r"pid=(\d+)", sockets)
        owned = any(f"0::{group}" in Path(f"/proc/{pid}/cgroup").read_text().splitlines()
                    for pid in pids if Path(f"/proc/{pid}/cgroup").exists())
        require("ERROR:" not in journal, "Game startup reported an error; inspect VPS journal privately")
        if f"Server listening on UDP {port}." in journal and owned:
            healthy_since = healthy_since or time.monotonic()
            if time.monotonic() - healthy_since >= stable_seconds:
                return
        else:
            healthy_since = None
        time.sleep(1)
    raise RuntimeError("Game readiness timed out")


def activate(state, receipt):
    require(state["phase"] == "backed-up" and receipt == state["backup_sha256"],
            "Expected verified off-machine backup receipt")
    require(active_commit() == state["previous"], "Current release changed during deployment")
    stopped()
    clean_data()
    transaction = STATE / state["id"]
    staged = transaction / "release"
    account = pwd.getpwnam("dorbit")
    # Extraction rejects links. Grant the game only its own release tree.
    for directory, dirs, files in os.walk(staged):
        for name in dirs + files:
            os.chown(Path(directory) / name, account.pw_uid, account.pw_gid)
    os.chown(staged, account.pw_uid, account.pw_gid)
    target = RELEASES / state["commit"]
    require(not target.exists(), "Target release appeared during deployment")
    staged.rename(target)
    next_link = CURRENT.with_name("current.next")
    next_link.symlink_to(f"releases/{state['commit']}")
    next_link.replace(CURRENT)
    state["phase"] = "starting"
    save(transaction / "transaction.json", state)
    save(STATE / "pending.json", state)
    try:
        run("systemctl", "reset-failed", SERVICE)
        run("systemctl", "start", SERVICE)
        ready()
    except Exception:
        run("systemctl", "stop", SERVICE)
        raise
    state["phase"] = "ready"
    save(transaction / "transaction.json", state)
    (STATE / "pending.json").unlink()
    print(f"Game ready: {state['commit']}; previous release retained: {state['previous']}")


def main(command):
    # sudoers accepts only this entry point. Validate every argument again here.
    os.environ.clear()
    os.environ.update(PATH="/usr/sbin:/usr/bin:/sbin:/bin", LANG="C.UTF-8")
    os.umask(0o077)
    require(os.geteuid() == 0, "Must run via the restricted sudo rule")
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if match := re.fullmatch(r"prepare ([0-9a-f]{40}) ([0-9a-f]{40}) ([0-9a-f]{64})", command):
            prepare(*match.groups())
            return
        match = re.fullmatch(r"(backup|activate) ([0-9a-f]{32})(?: ([0-9a-f]{64}))?", command)
        require(match is not None, "Command not allowed")
        action, transaction, receipt = match.groups()
        state = json.loads((STATE / "pending.json").read_text())
        require(state["id"] == transaction, "Wrong transaction")
        if action == "backup":
            require(receipt is None, "Unexpected argument")
            with (STATE / transaction / "backup.tar.age").open("rb") as backup:
                shutil.copyfileobj(backup, sys.stdout.buffer)
        else:
            activate(state, receipt)


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 2, "Expected a single forced-command argument")
        main(sys.argv[1])
    except Exception as error:
        # Never forward subprocess output, journal lines, ledger content or secrets.
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        print("Deployment refused or failed. Inspect the pending transaction and journal as dorbit-admin; "
              "follow DEPLOYMENT.md. No automatic rollback was attempted.", file=sys.stderr)
        sys.exit(1)
