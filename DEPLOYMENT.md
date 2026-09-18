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

## Private group access with Tailscale

Tailscale is the chosen private network. The VPS and both operator PCs have joined
the same network. For a new server, use the netcup console to bootstrap access
and authorize each operator PC's public SSH key. Keep private keys on their PCs.
On the Ubuntu VPS, follow the official
[Linux installation instructions](https://tailscale.com/download/linux).
After installation, run from the VPS console:

```bash
sudo tailscale up
tailscale ip -4
tailscale status
```

Open the login URL on the operator's computer and authorize the VPS in the
existing Tailscale account. Do not store login URLs, auth keys or credentials in
the repository. Use ordinary OpenSSH through the Tailscale address, with
authorized keys for the administrative Linux user. Keep password and root SSH
login disabled. Tailscale SSH (`--ssh`) is not needed for this setup.

Before adding friends, configure and test the access policy in the Tailscale
admin console. Give the VPS a `tag:dorbit` tag owned by administrators, define
an operator group and a pilot group with the actual account email addresses,
and allow these connections:

| Source | Destination | Access |
| --- | --- | --- |
| Operators | `tag:dorbit` | TCP 22 for administration; UDP 24567 for play |
| Pilots | `tag:dorbit` | UDP 24567 only |

Use the configured game port if different. Game access does not require a Linux
account or an authorized SSH key.
Review existing broad allow rules: a restrictive grant does not cancel another
grant that already permits all traffic. Preserve unrelated network access.
Use policy tests to confirm a pilot can reach the game port and cannot reach
SSH or unrelated services. See the official
[grants](https://tailscale.com/docs/features/access-control/grants) documentation.

On Windows, verify `tailscale status`, then connect with
`ssh ADMIN_USERNAME@SERVER_TAILSCALE_IP`. Use that same server address in Dorbit,
with the matching client build and existing pilot credential. Check the saved
credits after connecting, disconnecting and reconnecting. Test from an external
network too. Tailscale's own packet-filter rules mean host UFW rules alone are
not a substitute for the Tailscale access policy.

Once private administration and gameplay work, inspect the VPS and provider
firewall rules and remove the temporary public UDP game-port opening. Keep the
netcup console available while validating access. Invite friends individually,
check the account plan supports the intended group size, have them install and
sign in to Tailscale, and provision one private pilot credential per person.
The server needs neither a subnet router nor an exit node. Check the server's
device-key expiry policy so unattended hosting does not unexpectedly lose access.

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

systemd attempts to restart crashes after five seconds, with a limit of five starts per
minute. An explicit stop stays stopped. After fixing a repeated startup failure,
run `sudo systemctl reset-failed dorbit` and `sudo systemctl start dorbit`.

The Linux launcher converts SIGTERM and Ctrl+C into a graceful game shutdown,
which releases the save lock. `KillMode=mixed` sends the initial systemd stop
signal to that launcher so Godot can finish cleanup. The launcher allows 20
seconds, then forces termination with a failed exit status; systemd's 30-second
timeout also kills remaining processes if the launcher itself hangs. Install
the updated unit and run `daemon-reload` when upgrading an existing deployment.

Persistence still limits crash recovery: forced termination can leave
`pilots.json.lock` or an interrupted write behind. The server then refuses to
start. Follow the stopped-server recovery procedure in README.md; the service
does not automatically delete locks or replace saves. Verify stop/restart and
reboot behavior on the deployed engine and unit before treating routine
unattended restarts as working. An enabled service alone does not establish
recovery after a crash or power loss.

## Update and roll back

Prepare the next commit as above while the old release is running. Keep the old
release and matching client build until the new one passes a connection check.
Stop the service and retain a dated off-machine copy of the entire data directory
before switching releases. On the first upgrade from the old launcher, its stop
can leave a lock: confirm all old processes have exited and follow the recovery
procedure before starting the new release. Install the new `dorbit.service` and
run `sudo systemctl daemon-reload` to activate `KillMode=mixed`.
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

## Validation and current limitation

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

On 2026-09-14, release `0a6c29389fb6402bf8a768d1826f46115353fe47` passed 44
dedicated-server checks and 37 persistence checks in WSL and on the netcup nano
G11s. The installed OS reports Ubuntu 24.04.5 LTS; the panel's chosen image was
labelled Ubuntu 24.04.4 UEFI amd64. The service ran as `dorbit`, with saves outside
the release, key-only SSH administration and a host firewall restricted to the
operator's current public IP. No development-machine firewall or services changed.

Two automated Windows clients connected over the internet to a separate test
ledger on the VPS, fought, received 38/37 credits, repaired and disconnected with
zero failures. The operator's real pilot then joined, disconnected and rejoined
the main service. The temporary replay service and its firewall opening were
removed from active use. A matching Windows client and private launcher were
prepared locally; credentials were not committed.

The reboot test failed game readiness. systemd launched the service, but the
leftover `pilots.json.lock` prevented startup. SIGTERM and SIGINT both left the
same lock in isolated WSL tests. The operator recovery procedure restored service
without changing the ledger, after preserving a stopped-server copy on the VPS
and on the operator's PC. Journals from the previous boot remained available.

The shutdown follow-up adds a Linux launcher and cooperative game shutdown to
address this observed failure. Real-process WSL tests cover SIGTERM, Ctrl+C and
repeated restart with a nonzero saved wallet, plus concurrent-server rejection,
crash handling and preservation of invalid/interrupted saves. Crashes and forced
termination still require the documented recovery; locks are never blindly deleted.
The updated unit still needs installation on the live service and an actual VPS
reboot check. Abrupt crashes and power loss still require operator recovery.
Sustained load with the friend group and restricted friend-group VPN grants
remain pending.
Authentication, network protocol and save format are unchanged.

On 2026-09-14, a local WSL rehearsal prepared committed releases `5c08d13` and
`519ff70` with `tools/deploy-server.sh`; both passed all 44 dedicated-server,
37 persistence and five process-shutdown tests. Using a disposable data directory
outside the releases, the rehearsal atomically switched A -> B -> A and launched
each through `tools/server.sh run`. A separate matching headless client
authenticated on every start and received the same 137-credit wallet. Each
SIGTERM stop exited successfully and removed the lock; the ledger remained
byte-for-byte unchanged. These revisions differ only in documentation, so this
validates release switching and compatible-client reconnects, not a future save
migration. It did not install a local service or alter any firewall, and does not
replace the actual VPS checks below.

On 2026-09-18, the original raw-Godot SIGTERM/SIGINT failure was reproduced in
WSL. The shutdown branch passed 44 dedicated-server, 37 persistence and five
process-shutdown tests there. Committed releases `519ff70` and `9065041` were
then prepared on the VPS with `tools/deploy-server.sh`; both passed the same
checks. A separate systemd service used the shipped unit settings, its own data
directory and UDP port 24689. A Windows client authenticated, disconnected and
reconnected after initial startup, systemd restart, update from A to B and
rollback from B to A. Its wallet stayed at 137 credits, the ledger remained
byte-for-byte unchanged, and each explicit stop removed the lock. The releases
differ only in documentation. The temporary service and credentials were removed;
the running production service and its saves were not touched by the rehearsal.

Tailscale now connects the VPS and both operator PCs. Administration uses
OpenSSH with a separate authorized key per PC. SSH and game reconnect checks
passed over Tailscale, and the public-IP UFW allowances for TCP 22 and UDP 24567
were removed. Restrict the Tailscale access policy before inviting friends;
operator connectivity alone does not verify separation of operator/pilot access.
