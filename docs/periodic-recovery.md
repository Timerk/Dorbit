# Periodic off-machine recovery

This is an implemented operation and a schedule template, **not an installed
production schedule**. The repository finding does not establish whether an
external VPS routine already exists. Inventory that first to avoid duplicate stops.
Deployment artifacts remain separate pre-upgrade recovery copies.

An independent Linux machine pulls an age-encrypted whole-directory snapshot over
pinned OpenSSH. No paid destination or new backup service is required. The VPS
keeps only the public age recipient; keep the recovery private key in two secure
off-machine locations. The receiver needs no decryption key. Each run disconnects
players and resets session state. Choose a quiet maintenance time with the group.

The separate root-owned `dorbit-recovery` entry point reuses deployment's lock,
clean-stop/process checks, age encryption and readiness check. It refuses pending
deployments and inactive/dirty services. It includes `data/` (snapshot, combat
journal, rolling backup and all other files), `credentials/`, service/environment
configuration and `recovery.json` identifying the running release. It rejects
links and special files, caps inputs at about 1 GiB and needs 3 GiB staging space.
Provisioning must not run concurrently; it uses the same stopped-server maintenance
window rules as deployment. Never copy either half of the save pair while running.

On a clean stop, archiving/encryption failures attempt a readiness-checked restart.
A failed stop, dirty save, missing journal or interrupted/killed helper requires
operator recovery; locks are never deleted automatically. The game is restarted
before transfer. Disconnecting during transfer loses that backup, not the previous
completed copies. Temporary plaintext/ciphertext is removed on normal success or
exception; after host failure inspect root-only `recovery-*` directories in
`/var/lib/dorbit-deploy` before removing abandoned staging. Do not remove `lock`.

The receiver verifies the encrypted SHA-256 sent over authenticated SSH, fsyncs
and atomically publishes one archive, then retains the configured count (1–365).
Only its exact completed filename pattern is pruned. No age identity or save data
is printed. Checksum receipt establishes transfer integrity, not decryptability;
perform a restore rehearsal before relying on a new recipient. Allow space for
retained copies plus two incoming encrypted copies. Failed receipts never prune.

## Configuration decisions before installation

Record the destination host/disk and owner, network availability, maintenance time,
maximum acceptable progression loss (RPO), retention count, age recipient/key
custody, SSH key and a person/channel for failures. The template proposes daily
05:00 UTC plus up to five minutes jitter and 14 copies; these are examples, not
an accepted production RPO. A daily schedule loses up to about 24 hours of progress
after the last success, longer if any run fails or the receiver is offline. A
powered-off operator PC does not provide a daily guarantee. `Persistent=true`
runs a missed timer after boot; it does not reconstruct missed copies.

## VPS installation (manual maintenance action)

Review the committed helper before installing. Keep existing deployment helper,
key, sudo rule and service unchanged. From a trusted checkout on the VPS:

```bash
sudo install -o root -g root -m 0755 tools/vps-deploy.py /usr/local/sbin/dorbit-recovery
sudo test -s /etc/dorbit/backup-recipient.txt
sudo test -d /var/lib/dorbit/credentials
sudo install -d -o root -g root -m 0700 /var/lib/dorbit-deploy
```

Use the existing restricted `dorbit-deploy` login setup from DEPLOYMENT.md, with
a **new key on the receiver**, never the CI deployment key. Create a root-owned
0755 `/usr/local/sbin/dorbit-recovery-ssh` containing:

```sh
#!/bin/sh
exec sudo -n /usr/local/sbin/dorbit-recovery snapshot
```

Add only this rule with `sudo visudo -f /etc/sudoers.d/dorbit-recovery`, then run
`sudo visudo -c`:

```sudoers
dorbit-deploy ALL=(root) NOPASSWD: /usr/local/sbin/dorbit-recovery snapshot
```

Append the receiver's public key to the existing root-owned authorized_keys with
`restrict,command="/usr/local/sbin/dorbit-recovery-ssh"` before `ssh-ed25519 ...`.
Do not replace other keys. This key can request only a snapshot (and therefore
interrupt gameplay); it cannot deploy, fetch plaintext, open a shell or forward
ports. Restrict receiver-to-VPS networking to TCP 22 over the private network.
Verify the existing recipient's private identity is available off-machine.

## Receiver installation and first run

On a separate Ubuntu/systemd machine, from the trusted checkout:

```bash
sudo apt-get install -y python3 openssh-client age
sudo useradd --system --user-group --create-home --home-dir /var/lib/dorbit-backup-login --shell /usr/sbin/nologin dorbit-backup
sudo install -d -o dorbit-backup -g dorbit-backup -m 0700 /var/lib/dorbit-backup
sudo install -d -o dorbit-backup -g dorbit-backup -m 0700 /var/lib/dorbit-backup-login/.ssh
sudo install -d -o root -g root -m 0755 /usr/local/lib/dorbit
sudo install -o root -g root -m 0644 tools/recovery-backup.py /usr/local/lib/dorbit/recovery-backup.py
sudo -u dorbit-backup ssh-keygen -t ed25519 -N '' -f /var/lib/dorbit-backup-login/.ssh/id_ed25519
```

Stop and inspect existing accounts/files rather than rerunning creation. Install
the new public key on the VPS as above. Privately provision a 0600 SSH config
owned by `dorbit-backup` in its `.ssh/config`:

```sshconfig
Host dorbit-recovery
    HostName VPS_TAILSCALE_IP
    User dorbit-deploy
    IdentityFile /var/lib/dorbit-backup-login/.ssh/id_ed25519
    IdentitiesOnly yes
    UserKnownHostsFile /var/lib/dorbit-backup-login/.ssh/known_hosts
    StrictHostKeyChecking yes
    BatchMode yes
```

Pin the VPS host key in that 0600 known_hosts using its independently verified
console fingerprint; never trust unverified ssh-keyscan output. Test at the agreed
maintenance time (this command stops/restarts production):

```bash
sudo -u dorbit-backup python3 -I /usr/local/lib/dorbit/recovery-backup.py /var/lib/dorbit-backup dorbit-recovery --keep 14
```

First do the disposable rehearsal below. After the first real receipt, decrypt it
privately and verify its contents and release metadata without replacing live data.
Only after those checks and interval/retention decisions, edit the templates to
match and install on the **receiver**, never the game VPS:

```bash
sudo install -m 0644 deploy/dorbit-recovery.service deploy/dorbit-recovery.timer /etc/systemd/system/
sudo systemd-analyze verify /etc/systemd/system/dorbit-recovery.service /etc/systemd/system/dorbit-recovery.timer
sudo systemctl daemon-reload
sudo systemctl enable --now dorbit-recovery.timer
sudo systemctl list-timers dorbit-recovery.timer
```

## Failure reporting and supervision

Nonzero exits mark `dorbit-recovery.service` failed; safe success/failure messages
go to receiver journald. Inspect `systemctl status dorbit-recovery.service` and
`journalctl -u dorbit-recovery.service`; inspect the VPS service privately if a stop
or restart failed. No email/webhook is silently configured. Before relying on the
schedule, connect the receiver's existing monitoring to service failure **and**
the newest completed archive's age (alert beyond the chosen RPO plus runtime/jitter).
Test a failed SSH connection and a missed run and confirm the chosen owner gets
the alert. Journald alone is passive failure reporting, not an unattended alert.
An interrupted receiver can leave `.lock` or `.incoming-*`: ensure no receiver
process remains, inspect them, retain completed copies, then remove only abandoned
incoming directories and the empty `.lock` before retrying. Never auto-clear locks.

## Disposable restore rehearsal and actual restore

Run `python3 -m unittest discover -s tests -p 'recovery_backup_test.py' -v` with
`age` and `age-keygen` on PATH. It generates a temporary identity, schema-8 pilot
with 2,345 credits, pending combat debits/boosts, cargo and credential, takes an
encrypted snapshot with simulated systemd, decrypts into a fresh temporary
directory, compares every data file, replays the journal and verifies the token's
hash against the restored verifier. Secrets and archive contents stay out of logs.
This tests real age and save replay; it does not establish live systemd/SSH behavior
or a client login. Missing age tools skip only the cryptographic rehearsal; CI
installs them and runs it. No gameplay or network/save schema changes are involved.

For a real restore, first pause the receiver timer and preserve its selected copy.
On a trusted recovery machine with mode-0700 working directory and `umask 077`:

```bash
age -d -i /secure/dorbit-recovery.key -o backup.tar SELECTED_COPY.tar.age
tar -tf backup.tar
mkdir recovered
tar --extract --file backup.tar --directory recovered --no-same-owner
```

Only extract authenticated archives from this helper; inspect entries first.
Keep decrypted files private. Read `recovered/recovery.json` for the required
server commit; obtain that exact server release and matching Windows clients.
Rehearse on a disposable server with isolated port/user/data first, restore the
whole `data/` and credentials together, replay/validate with the matching tooling,
then authenticate with a restored pilot and verify credits, ammo, boosts, cargo
and industry. Retain the encrypted source and separate pre-restore copy.

Actual replacement is separate operator work: stop Dorbit, confirm MainPID=0 and
no `dorbit` processes, preserve the entire old data/credentials/config, follow
README.md's save recovery checks, then replace the complete directory (never
overlay individual snapshot/journal files). Set restored data/credentials owner
`dorbit:dorbit`, directories 0700 and files 0600. Review saved service/environment
before installing; do not blindly overwrite root configuration. Switch to the
matching server release, start, verify UDP readiness and authenticate/reconnect
with the matching Windows client. Older backups roll back progression and token
rotations; rotate exposed credentials again. Resume the receiver timer only after
readiness and a successful new receipt. No production restore or schedule was
performed by the repository tests.

After the disposable validation above, a concrete replacement sequence on the VPS
is below. Run from the private working directory containing `recovered/`, with
the matching release already installed using DEPLOYMENT.md. Stop on every error.
Review the saved configuration separately; this sequence retains current config:

```bash
set -e
sudo systemctl stop dorbit
test "$(sudo systemctl show dorbit --property=MainPID --value)" = 0
if sudo pgrep -u dorbit >/dev/null; then echo 'Dorbit processes remain'; exit 1; fi
revision=$(python3 -c 'import json; print(json.load(open("recovered/recovery.json"))["commit"])')
sudo test -d "/opt/dorbit/releases/$revision"
sudo test ! -e /opt/dorbit/current.next
before="/var/lib/dorbit-before-restore-$(date -u +%Y%m%dT%H%M%SZ)"
sudo mkdir -m 0700 "$before"
sudo cp -a /etc/systemd/system/dorbit.service /etc/dorbit/server.env /opt/dorbit/current "$before/"
sudo mv /var/lib/dorbit/data /var/lib/dorbit/credentials "$before/"
sudo cp -a recovered/data recovered/credentials /var/lib/dorbit/
sudo chown -R dorbit:dorbit /var/lib/dorbit/data /var/lib/dorbit/credentials
sudo find /var/lib/dorbit/data /var/lib/dorbit/credentials -type d -exec chmod 0700 {} +
sudo find /var/lib/dorbit/data /var/lib/dorbit/credentials -type f -exec chmod 0600 {} +
sudo ln -s "releases/$revision" /opt/dorbit/current.next
sudo mv -Tf /opt/dorbit/current.next /opt/dorbit/current
sudo systemctl reset-failed dorbit
sudo systemctl start dorbit
sudo journalctl -u dorbit -n 100 --no-pager
sudo ss -lunp
```

Confirm the configured UDP socket and matching-client login/reconnect before
resuming the receiver timer with `sudo systemctl start dorbit-recovery.timer`
on that host. If replacement fails, leave the service stopped, preserve the
partial restore, and inspect the recorded `before` directory; do not overlay it
onto the restored pair or delete the only pre-restore copy.
