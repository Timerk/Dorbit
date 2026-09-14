# Linux dedicated server deployment

Use Ubuntu 24.04 LTS on x86-64 with systemd. This runs the current server from
source using the checksum-pinned Godot runtime in `tools/server.sh`. No export
templates or deployment framework are needed. Use matching client and server
revisions. The current server requires provisioned pilot credentials and a save
directory. The first VPS is a netcup nano G11s in Nuremberg.

## Prepare a release

Run these commands on the Linux host as your normal administrative user, in a
checkout of this repository. Preparing a release does not touch a running server.
Private repository checkout credentials belong to this user, not the service user.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl python3 git tar
git fetch origin
# Replace with the full commit SHA you intend to deploy.
revision=COMMIT_SHA
bash tools/deploy-server.sh "$revision"
revision=$(git rev-parse --verify "${revision}^{commit}")
release="$PWD/build/server-releases/$revision"
```

The script archives only committed files, downloads and verifies Godot, imports
the project and runs the existing dedicated-server checks. Failed preparation
removes its temporary directory. Existing releases are never overwritten. To
rebuild the same commit, pass a different output directory as the second argument.
Preparation needs outbound HTTPS and enough disk space for a runtime and import
cache per retained release. Run only one preparation at a time because the server
checks use fixed test ports. No compilation is required.

## Install once

The following commands are for the chosen Linux server. Do not run them on the
development machine just to validate this document.

```bash
sudo useradd --system --user-group --home-dir /var/lib/dorbit --no-create-home --shell /usr/sbin/nologin dorbit
sudo install -d -m 0755 /opt/dorbit/releases /etc/dorbit
target="/opt/dorbit/releases/$revision"
sudo test ! -e "$target" && sudo cp -a "$release" "$target"
sudo chown -R dorbit:dorbit "$target"
sudo ln -s "releases/$revision" /opt/dorbit/current
sudo install -d -o dorbit -g dorbit -m 0700 /var/lib/dorbit /var/lib/dorbit/data /var/lib/dorbit/credentials
# Replace tim with the first pilot's stable ID. Use --init only on a new server.
sudo -u dorbit python3 "$target/tools/pilots.py" /var/lib/dorbit/data tim /var/lib/dorbit/credentials/tim.json --init
sudo install -m 0644 "$target/deploy/dorbit.service" /etc/systemd/system/dorbit.service
printf 'DORBIT_PORT=24567\n' | sudo tee /etc/dorbit/server.env
sudo systemd-analyze verify /etc/systemd/system/dorbit.service
sudo systemctl daemon-reload
sudo systemctl enable --now dorbit
```

Stop if a command fails. If the user or release already exists, inspect it instead
of repeating creation or copying over it. The `dorbit` account has no login shell
or sudo access. It owns releases because the existing helper imports on startup
and Godot writes its import cache. `/var/lib/dorbit` is its home, with saves in
`/var/lib/dorbit/data`, outside release directories. Give the pilot only their
credential file through a private channel and set `DORBIT_PILOT_FILE` when
launching their matching Windows client. See README.md for provisioning, token
rotation and the existing save recovery procedure. Never commit credentials.

Edit `/etc/dorbit/server.env` with `sudoedit` to set `DORBIT_PORT` to an unused UDP
port from 1024 through 65535, then run `sudo systemctl restart dorbit`. Use the
same port in clients. A reachable VPS must allow that UDP port through its
provider and host firewalls. These scripts do not configure either firewall.
Pilot authentication is required, but ENet traffic is unencrypted and the client
does not authenticate the server. Use a private VPN for ordinary group play, as
described in README.md. Restrict direct public-IP testing to the intended testers.

## Run and inspect

```bash
sudo systemctl status dorbit --no-pager
sudo journalctl -u dorbit -n 100 --no-pager
sudo journalctl -u dorbit -f
sudo ss -lunp
sudo systemctl stop dorbit
sudo systemctl start dorbit
```

Confirm the log reports the dedicated server listening on the configured port
and `ss` shows its UDP socket. `Type=simple` being active alone does not prove
readiness. Startup includes the project's import step. Logs go to journald;
retention and survival across reboots follow the host's journald configuration.

systemd restarts crashes after five seconds, with a limit of five starts per
minute. An explicit stop stays stopped. After fixing a repeated startup failure,
run `sudo systemctl reset-failed dorbit` and `sudo systemctl start dorbit`.

Persistence limits automatic recovery: forced termination can leave
`pilots.json.lock` or an interrupted write behind. The server then refuses to
start. Follow the stopped-server recovery procedure in README.md; the service
does not automatically delete locks or replace saves. Verify stop/restart and
reboot behavior on the deployed engine before treating unattended recovery as
working. An enabled service alone does not establish recovery after a crash.

## Update and roll back

Prepare the next commit as above while the old release is running. Keep the old
release and matching client build until the new one passes a connection check.
Then, with `revision` and `release` set to the new prepared release:

```bash
previous=$(readlink /opt/dorbit/current)
target="/opt/dorbit/releases/$revision"
sudo test ! -e "$target" && sudo cp -a "$release" "$target"
sudo chown -R dorbit:dorbit "$target"
sudo ln -s "releases/$revision" /opt/dorbit/current.next
sudo mv -Tf /opt/dorbit/current.next /opt/dorbit/current
sudo systemctl restart dorbit
sudo journalctl -u dorbit -n 100 --no-pager
```

Record `previous` before switching. Run updates one at a time and stop on errors;
an existing `current.next` needs inspection. Switching the symlink is atomic.
Restarting disconnects players. Saved credits stay in the shared data directory;
position, health and encounter objectives reset.
Check the UDP socket and connect with a matching Windows client. If startup or
the connection check fails, restore the recorded link and matching clients:

```bash
sudo ln -s "$previous" /opt/dorbit/current.next
sudo mv -Tf /opt/dorbit/current.next /opt/dorbit/current
sudo systemctl reset-failed dorbit
sudo systemctl restart dorbit
```

This rolls back application files only. It does not copy, migrate or restore
saves. Only switch between releases compatible with the current save schema.
Follow README.md's stopped-server copy procedure before updates and retain the
copy off the VPS. Do not roll back to a build from before pilot persistence.
Service and port settings
stay outside releases. If a future release changes the unit, explicitly install
that unit and run `daemon-reload` before restarting; retain the previous unit and
environment file if changing them so they can be restored too.

## Validation boundaries

WSL supports release preparation, the existing server checks, foreground startup,
custom-port UDP binding and `systemd-analyze verify`. Validate there without
installing the unit or changing local services or firewalls.
Use a Linux-native checkout in WSL; Linux Git cannot resolve the Windows paths
in a Windows-created worktree's metadata.

Locally verified in Ubuntu on WSL2: a clean committed release downloaded and
verified Godot, passed all 43 dedicated-server checks, and started through a
symlink as an unprivileged user on UDP 24791. Bash syntax and unit-file validation
passed. Missing arguments, invalid revisions and existing releases were rejected;
a simulated download failure left no release or staging directory.

On the real VPS, verify service installation under `dorbit`, automatic crash
restart, startup after a reboot, journal retention, and update/rollback with
matching clients. Cross-network UDP connectivity and resource use with the friend
group need that host and external clients. Neither VPS selection nor those checks
block preparing releases locally.
