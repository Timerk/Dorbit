#!/usr/bin/python3 -I
"""Pull encrypted recovery from a pinned SSH alias onto a separate Linux host."""

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

NAME = re.compile(r"recovery-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}\.tar\.age")


def collect(destination: Path, host: str, keep: int):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*", host) or not 1 <= keep <= 365:
        raise ValueError("Invalid SSH alias or retention")
    if not destination.is_dir() or destination.is_symlink():
        raise ValueError("Create a private destination directory first")
    if os.name == "posix" and destination.stat().st_mode & 0o077:
        raise ValueError("Destination must have mode 0700")
    # Atomic directory lock also works in portable tests. Interrupted locks require inspection.
    lock = destination / ".lock"
    lock.mkdir(mode=0o700)
    try:
        with tempfile.TemporaryDirectory(prefix=".incoming-", dir=destination) as temporary:
            wire = Path(temporary) / "wire"
            with wire.open("wb") as output:
                subprocess.run(["ssh", "-T", "-oBatchMode=yes", "-oStrictHostKeyChecking=yes",
                                "-oConnectTimeout=30", "-oServerAliveInterval=15",
                                "-oServerAliveCountMax=3", host, "snapshot"], stdout=output,
                               stderr=subprocess.DEVNULL, check=True, timeout=1800)
                output.flush()
                os.fsync(output.fileno())
            with wire.open("rb") as source:
                checksum = source.read(65)
                if not re.fullmatch(rb"[0-9a-f]{64}\n", checksum):
                    raise ValueError("Invalid recovery response")
                archive = Path(temporary) / "backup.tar.age"
                with archive.open("wb") as output:
                    shutil.copyfileobj(source, output)
                    output.flush()
                    os.fsync(output.fileno())
            with archive.open("rb") as source:
                actual = hashlib.file_digest(source, "sha256").hexdigest().encode()
            if actual != checksum[:64] or not 1 <= archive.stat().st_size <= 2 * 1024**3:
                raise ValueError("Recovery checksum or size mismatch")
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            name = f"recovery-{stamp}-{uuid.uuid4().hex}.tar.age"
            archive.replace(destination / name)
            sync_directory(destination)
            # Prune only this tool's completed archives, only after verified durable receipt.
            copies = sorted(p for p in destination.iterdir() if NAME.fullmatch(p.name)
                            and p.is_file() and not p.is_symlink() and p.name != name)
            for old in copies[:max(0, len(copies) - keep + 1)]:
                old.unlink()
            sync_directory(destination)
            print(f"Recovery received and verified: {name}; retention {keep}")
    finally:
        lock.rmdir()


def sync_directory(path):
    if os.name == "posix":
        descriptor = os.open(path, os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("host", help="SSH config alias with dedicated recovery key and pinned host key")
    parser.add_argument("--keep", type=int, required=True, help="Completed copies to retain (1..365)")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        collect(args.destination, args.host, args.keep)
    except Exception:
        # Never emit remote stderr, credentials, save contents or subprocess arguments.
        print("Recovery backup failed; inspect service status and VPS journal privately. "
              "Previous completed copies retained unless pruning had already begun.", file=sys.stderr)
        sys.exit(1)
