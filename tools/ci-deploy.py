#!/usr/bin/env python3
"""GitHub-side release selection and restricted SSH deployment. No pilot credentials."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", path]))


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def commit(value):
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("Expected a full lowercase commit SHA")
    return value


def download(tag, name, directory):
    run("gh", "release", "download", tag, "--pattern", name, "--dir", str(directory))


def ssh(command, **kwargs):
    return run("ssh", "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
               "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlgorithms=ssh-ed25519",
               "-o", "UserKnownHostsFile=" + str(Path.home() / ".ssh/dorbit_hosts"),
               "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15",
               "-o", "ServerAliveCountMax=3", "-i", str(Path.home() / ".ssh/dorbit_ci"),
               "dorbit-deploy@100.86.199.82", command, **kwargs)


def publish():
    sha = commit(os.environ["GITHUB_SHA"])
    manifest = {"commit": sha, "run_id": int(os.environ["GITHUB_RUN_ID"]),
                "files": {name: digest(Path("dist") / name) for name in ("server.tar.gz", "windows.zip")}}
    Path("dist/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    repo = os.environ["GITHUB_REPOSITORY"]
    notes = (f"Commit: `{sha}`\n\nMatching Windows client: **windows.zip**. "
             f"Linux server: **server.tar.gz**. Both were checked from this exact commit.\n\n"
             f"Checks: https://github.com/{repo}/actions/runs/{manifest['run_id']}\n\n"
             "Deploy only after that run finishes successfully. Use Actions > Deploy server "
             f"and enter `build-{sha}`. Nothing deploys automatically. Keep this release for rollback.")
    Path("dist/notes.md").write_text(notes)
    # Upload everything to a draft first. Never overwrite an existing published build.
    run("gh", "release", "create", f"build-{sha}", "dist/server.tar.gz", "dist/windows.zip",
        "dist/manifest.json", "--draft", "--target", sha, "--title", f"Tested build {sha}",
        "--notes-file", "dist/notes.md")
    run("gh", "release", "edit", f"build-{sha}", "--draft=false", "--latest=false")


def select():
    tag = os.environ["RELEASE"]
    if not tag.startswith("build-"):
        raise ValueError("Choose a build-<full commit> release")
    sha = commit(tag.removeprefix("build-"))
    previous = commit(os.environ["EXPECTED_CURRENT"])
    if sha == previous:
        raise ValueError("That release is already expected to be running")
    repo = os.environ["GITHUB_REPOSITORY"]
    release = api(f"repos/{repo}/releases/tags/{tag}")
    if release["draft"] or release["prerelease"]:
        raise ValueError("Choose a published tested release")
    Path("dist").mkdir()
    download(tag, "manifest.json", "dist")
    manifest = json.loads(Path("dist/manifest.json").read_text())
    build = api(f"repos/{repo}/actions/runs/{int(manifest['run_id'])}")
    workflow = api(f"repos/{repo}/actions/workflows/validate.yml")
    if not (manifest["commit"] == sha == build["head_sha"] and
            build["head_repository"]["full_name"] == repo and
            build["workflow_id"] == workflow["id"] and build["event"] == "push" and
            build["head_branch"] == "main" and build["status"] == "completed" and
            build["conclusion"] == "success"):
        raise ValueError("Release must come from a successful main push validation run")
    for name in ("server.tar.gz", "windows.zip"):
        download(tag, name, "dist")
        if digest(Path("dist") / name) != manifest["files"][name]:
            raise ValueError("Release checksum mismatch")
    with zipfile.ZipFile("dist/windows.zip") as client:
        if client.read("REVISION").decode().strip() != sha:
            raise ValueError("Client revision mismatch")
    # This also supports a manually archived pre-CI client with a REVISION file.
    Path("recovery").mkdir()
    download(f"build-{previous}", "windows.zip", "recovery")
    with zipfile.ZipFile("recovery/windows.zip") as client:
        if client.read("REVISION").decode().strip() != previous:
            raise ValueError("Rollback client revision mismatch")
    Path("selection.json").write_text(json.dumps({"commit": sha, "previous": previous,
        "archive_sha256": manifest["files"]["server.tar.gz"]}))
    print(f"Selected commit {sha}; previous commit {previous}")


def prepare():
    selected = json.loads(Path("selection.json").read_text())
    command = "prepare {commit} {previous} {archive_sha256}".format(**selected)
    with Path("dist/server.tar.gz").open("rb") as archive:
        result = ssh(command, stdin=archive, stdout=subprocess.PIPE)
    # Only public transaction metadata comes back, never journals or plaintext saves.
    state = json.loads(result.stdout)
    Path("recovery/transaction.json").write_text(json.dumps(state, indent=2))
    with Path("recovery/backup.tar.age").open("wb") as backup:
        ssh(f"backup {state['id']}", stdout=backup)
    if digest("recovery/backup.tar.age") != state["backup_sha256"]:
        raise ValueError("Recovery download failed checksum verification; server remains stopped")


def activate():
    state = json.loads(Path("recovery/transaction.json").read_text())
    ssh(f"activate {state['id']} {state['backup_sha256']}")
    Path("activated").touch()


def report():
    success = Path("activated").exists()
    repo = os.environ["GITHUB_REPOSITORY"]
    tag = os.environ["RELEASE"]
    # Inputs are untrusted even in an always() reporting step.
    safe_tag = tag if re.fullmatch(r"build-[0-9a-f]{40}", tag) else "invalid release input"
    message = f"## Deployment {'succeeded' if success else 'did not complete'}\n\n"
    message += f"Selected release: {safe_tag}\n\n"
    if success:
        message += "Fresh game-listening log and service-owned UDP socket stayed ready for 10 seconds.\n\n"
    else:
        message += ("The VPS may be stopped or awaiting recovery. Do not rerun blindly. "
                    "No automatic save restoration or lock deletion occurred.\n\n")
    if Path("recovery/transaction.json").exists():
        state = json.loads(Path("recovery/transaction.json").read_text())
        message += f"Recovery directory on VPS: `/var/lib/dorbit-deploy/{state['id']}`\n\n"
        message += f"Previous release: `{state['previous']}`\n\n"
    if safe_tag == tag:
        message += f"[Matching Windows client](https://github.com/{repo}/releases/tag/{tag})\n\n"
    message += ("Download this run's dorbit-recovery artifact and keep it privately. It contains an "
                "encrypted stopped-server backup and the previous Windows client. "
                f"[Failure and rollback instructions](https://github.com/{repo}/blob/main/DEPLOYMENT.md#failure-and-rollback).\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
        summary.write(message)


if __name__ == "__main__":
    {"publish": publish, "select": select, "prepare": prepare,
     "activate": activate, "report": report}[sys.argv[1]]()
