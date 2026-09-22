#!/usr/bin/env python3
"""GitHub-side release selection and restricted SSH deployment. No pilot credentials."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
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


def artifact_file(archive, name, target):
    """Read one allowlisted regular file; never extract archive-controlled paths."""
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        if len(members) != 1 or members[0].filename != name:
            raise ValueError("Artifact must contain exactly the expected file")
        member = members[0]
        if (member.orig_filename != name or member.is_dir() or
                stat.S_IFMT(member.external_attr >> 16) not in (0, stat.S_IFREG) or
                member.file_size > 512 * 1024**2):
            raise ValueError("Artifact member must be a bounded regular file")
        # Exclusive creation also refuses a pre-existing symlink at the fixed target.
        with source.open(member) as data, Path(target).open("xb") as output:
            shutil.copyfileobj(data, output)


def download_builds(preview=False):
    sha = commit(os.environ["PREVIEW_SHA" if preview else "GITHUB_SHA"])
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id, attempt = os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"]
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (run_id, attempt)):
        raise ValueError("Invalid build run")
    Path("dist").mkdir()
    for platform, filename in (("Linux", "server.tar.gz"), ("Windows", "windows.zip")):
        name = f"{'Preview' if preview else 'Dorbit'}-{platform}-{sha}-{attempt}"
        listing = api(f"repos/{repo}/actions/runs/{run_id}/artifacts?name={name}")
        if listing["total_count"] != 1 or len(listing["artifacts"]) != 1:
            raise ValueError("Expected exactly one artifact from this build attempt")
        artifact = listing["artifacts"][0]
        if artifact["name"] != name or artifact["expired"]:
            raise ValueError("Build artifact unavailable")
        # gh api streams the raw ZIP. gh run download and download-artifact extract it.
        with tempfile.TemporaryFile() as archive:
            run("gh", "api", f"repos/{repo}/actions/artifacts/{int(artifact['id'])}/zip", stdout=archive)
            archive.seek(0)
            artifact_file(archive, filename, Path("dist") / filename)


def verify_provenance(path, sha):
    repo = os.environ["GITHUB_REPOSITORY"]
    run("gh", "attestation", "verify", str(path), "--repo", repo,
        "--cert-identity", f"https://github.com/{repo}/.github/workflows/validate.yml@refs/heads/main",
        "--source-ref", "refs/heads/main", "--source-digest", sha,
        "--signer-digest", sha, "--deny-self-hosted-runners")


def ssh(command, **kwargs):
    user = "dorbit-preview-deploy" if os.environ.get("DEPLOY_TARGET") == "preview" else "dorbit-deploy"
    return run("ssh", "-F", "/dev/null", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
               "-o", "StrictHostKeyChecking=yes", "-o", "HostKeyAlgorithms=ssh-ed25519",
               "-o", "UserKnownHostsFile=" + str(Path.home() / ".ssh/dorbit_hosts"),
               "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15",
               "-o", "ServerAliveCountMax=3", "-i", str(Path.home() / ".ssh/dorbit_ci"),
               f"{user}@100.86.199.82", command, **kwargs)


def ssh_config():
    directory = Path.home() / ".ssh"
    directory.mkdir(mode=0o700, exist_ok=True)
    for name, variable in (("dorbit_ci", "DEPLOY_KEY"), ("dorbit_hosts", "KNOWN_HOSTS")):
        path = directory / name
        path.write_text(os.environ[variable].strip() + "\n")
        path.chmod(0o600)
    fingerprint = subprocess.check_output(["ssh-keygen", "-lf", str(directory / "dorbit_hosts")], text=True)
    if len(fingerprint.splitlines()) != 1 or fingerprint.split()[1] != "SHA256:P+Lvr8RDA46ECqUdkvNtiP8t/HOejVCmtJVqqsdE7io":
        raise ValueError("Unexpected VPS host key")


def preview_select():
    number = os.environ["PR_NUMBER"]
    if not re.fullmatch(r"[1-9][0-9]{0,8}", number):
        raise ValueError("Enter a PR number")
    repo = os.environ["GITHUB_REPOSITORY"]
    pr = api(f"repos/{repo}/pulls/{number}")
    if pr["state"] != "open" or not pr["head"]["repo"] or pr["head"]["repo"]["full_name"] != repo:
        raise ValueError("Preview accepts only open PRs with branches in this repository")
    sha = commit(pr["head"]["sha"])
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        output.write(f"sha={sha}\npr={number}\n")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
        output.write(f"Selected PR #{number}, exact head commit `{sha}`. Later pushes require another deployment.\n")


def preview_prepare():
    sha = commit(os.environ["PREVIEW_SHA"])
    number = os.environ["PR_NUMBER"]
    build_run = os.environ["GITHUB_RUN_ID"]
    attempt = os.environ["GITHUB_RUN_ATTEMPT"]
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (number, build_run, attempt)):
        raise ValueError("Invalid preview metadata")
    with zipfile.ZipFile("dist/windows.zip") as client:
        if client.read("REVISION").decode().strip() != sha:
            raise ValueError("Preview client revision mismatch")
    mode = "fresh" if os.environ.get("FRESH_SAVES") == "true" else "keep"
    checksum = digest("dist/server.tar.gz")
    command = f"prepare-preview {sha} {number} {mode} {checksum} {build_run} {attempt}"
    Path("recovery").mkdir()
    with Path("dist/server.tar.gz").open("rb") as archive:
        result = ssh(command, stdin=archive, stdout=subprocess.PIPE)
    state = json.loads(result.stdout)
    Path("recovery/transaction.json").write_text(json.dumps(state, indent=2))
    with Path("recovery/backup.tar.age").open("wb") as backup:
        ssh(f"backup {state['id']}", stdout=backup)
    if digest("recovery/backup.tar.age") != state["backup_sha256"]:
        raise ValueError("Preview recovery download checksum mismatch; activation refused")


def preview_report():
    repo = os.environ["GITHUB_REPOSITORY"]
    run_id = os.environ["GITHUB_RUN_ID"]
    message = "## Preview " + ("ready" if Path("activated").exists() else "did not complete") + "\n\n"
    sha = os.environ.get("PREVIEW_SHA", "")
    if re.fullmatch(r"[0-9a-f]{40}", sha):
        message += f"Commit: `{sha}`. Connect through Tailscale to `100.86.199.82:24568` with your private preview pilot.\n\n"
        message += f"[Matching Windows client and encrypted recovery copy](https://github.com/{repo}/actions/runs/{run_id}#artifacts). "
        message += f"Download `Preview-Windows-{sha}-{os.environ['GITHUB_RUN_ATTEMPT']}`, then extract windows.zip.\n\n"
    message += ("Use **Stop preview** when finished. Production has separate controls. "
                "If deployment failed, preview may be stopped with a pending transaction. "
                f"[Preview recovery instructions](https://github.com/{repo}/blob/main/DEPLOYMENT.md#preview-failure-and-recovery).\n")
    if Path("recovery/transaction.json").exists():
        state = json.loads(Path("recovery/transaction.json").read_text())
        message += f"\nPR #{state['pr']}; recovery directory: `/var/lib/dorbit-preview-deploy/{state['id']}`.\n"
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
        output.write(message)


def preview_stop():
    ssh("stop")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as output:
        output.write("Preview stopped. No preview processes remain; saves are retained. Deploy preview again to start it.\n")


def release_manifest():
    sha = commit(os.environ["GITHUB_SHA"])
    manifest = {"commit": sha, "run_id": int(os.environ["GITHUB_RUN_ID"]),
                "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
                "files": {name: digest(Path("dist") / name) for name in ("server.tar.gz", "windows.zip")}}
    Path("dist/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def publish():
    sha = commit(os.environ["GITHUB_SHA"])
    # The manifest and packages have already been attested; do not rewrite them.
    manifest = json.loads(Path("dist/manifest.json").read_text())
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
    # Authenticate the manifest before trusting its run ID or checksums.
    verify_provenance("dist/manifest.json", sha)
    manifest = json.loads(Path("dist/manifest.json").read_text())
    build = api(f"repos/{repo}/actions/runs/{int(manifest['run_id'])}/attempts/{int(manifest['run_attempt'])}")
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
        verify_provenance(Path("dist") / name, sha)
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
    {"publish": publish, "release-manifest": release_manifest,
     "release-download": download_builds, "preview-download": lambda: download_builds(preview=True),
     "select": select, "prepare": prepare,
     "activate": activate, "report": report, "ssh-config": ssh_config,
     "preview-select": preview_select, "preview-prepare": preview_prepare,
     "preview-report": preview_report, "preview-stop": preview_stop}[sys.argv[1]]()
