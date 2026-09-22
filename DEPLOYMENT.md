# Linux dedicated server deployment

Use Ubuntu 24.04 LTS on x86-64 with systemd. This runs the current server from
source using the checksum-pinned Godot runtime in `tools/server.sh`. No export
templates or deployment framework are needed. Use matching client and server
revisions. The current server requires provisioned pilot credentials and a save
directory. The first VPS is a netcup nano G11s in Nuremberg.

## GitHub releases and manual deployment

Merges to `main` run the existing Linux and Windows checks. When both pass,
GitHub publishes `build-<full commit SHA>` under **Releases** with `server.tar.gz`,
`windows.zip` and `manifest.json`. The manifest identifies the exact commit,
validation run and SHA-256 hashes. Both builds use that commit. The Linux archive
contains the checked source and pinned runtime; it excludes import caches, test
output and downloaded ZIP files. Neither build contains real pilot credentials.

Publishing does not contact the VPS. Only **Actions > Deploy server > Run workflow**
deploys production. The separate preview actions below support PR playtesting.
Release assets remain available
after ordinary Actions artifacts expire. Do not delete or replace a release used
by the VPS, especially its previous client. Protect `main`, review workflow changes,
and restrict modification/deletion of `build-*` tags with a repository ruleset.
Repository administrators and people who can modify these workflows remain trusted.

### One-time operator setup

These are instructions for the operator, not steps already performed by this PR.
They do not require a game restart. Keep the netcup console available while
configuring access. Use `ssh dorbit-vps` as `dorbit-admin` for VPS administration.
The local alias is not available inside GitHub Actions.

1. Create an **age** recovery key on your own computer with `age-keygen -o dorbit-recovery.key`.
   Keep the private key outside Git and GitHub, with a second secure copy. The command
   prints an `age1...` public recipient. Only that public recipient goes on the VPS.
   Install age using its [official installation instructions](https://github.com/FiloSottile/age#installation).
   Decryption does not require a paid service. Losing this key makes encrypted backups unusable.
2. Create a new SSH key used only by this workflow, for example
   `ssh-keygen -t ed25519 -f dorbit-ci -C dorbit-github-deploy`. Leave its passphrase
   empty for unattended use. Do not reuse either PC's personal administrative key.
3. Copy the reviewed `tools/vps-deploy.py` from this PR to the VPS administrative
   account. On the VPS, install dependencies and the restricted helper:

   ```bash
   sudo apt-get update
   sudo apt-get install -y age python3 procps iproute2
   sudo useradd --system --user-group --no-create-home \
     --home-dir /var/lib/dorbit-deploy-login --shell /bin/sh dorbit-deploy
   sudo install -d -o root -g root -m 0755 /var/lib/dorbit-deploy-login
   sudo install -d -o root -g root -m 0755 /var/lib/dorbit-deploy-login/.ssh
   sudo install -d -o root -g root -m 0700 /var/lib/dorbit-deploy
   sudo install -o root -g root -m 0755 vps-deploy.py /usr/local/sbin/dorbit-deploy
   ```

   Stop and inspect if the account or files already exist. Use `sudoedit` to create
   `/etc/dorbit/backup-recipient.txt` containing only your `age1...` public recipient.
   Make it root-owned and mode 0644. Create `/usr/local/sbin/dorbit-ci-command`:

   ```sh
   #!/bin/sh
   exec sudo -n /usr/local/sbin/dorbit-deploy "$SSH_ORIGINAL_COMMAND"
   ```

   Make that wrapper root-owned and mode 0755. Create
   `/var/lib/dorbit-deploy-login/.ssh/authorized_keys`, root-owned and mode 0644,
   containing this single line, replacing the example public key with `dorbit-ci.pub`:

   ```text
   restrict,command="/usr/local/sbin/dorbit-ci-command" ssh-ed25519 YOUR_NEW_PUBLIC_KEY dorbit-github-deploy
   ```

   Run `sudo visudo -f /etc/sudoers.d/dorbit-deploy` and enter:

   ```sudoers
   dorbit-deploy ALL=(root) NOPASSWD: /usr/local/sbin/dorbit-deploy *
   ```

   Run `sudo visudo -c`. This account has no general sudo, shell, SCP, SFTP,
   forwarding or PTY through its key. Its only commands upload a release, fetch
   an encrypted backup and activate that transaction. The root-owned Python
   helper validates the arguments and archive; it runs no uploaded code as root.
   Uploaded game code runs as `dorbit` and therefore can access its saves. Treat
   deployment access as privileged game access. CI cannot replace the helper or
   install a different systemd unit. If a future release changes the unit, an
   operator must review and install it separately, preserving its predecessor.
   The current unit matches the reviewed repository unit byte for byte.
4. In the Tailscale admin console, add `tag:dorbit-ci`, owned by administrators.
   Create an OAuth client with **auth_keys write** permission limited to this tag.
   Save its client ID and secret for GitHub. The Action creates an ephemeral tagged
   machine and removes it at job cleanup. It uses ordinary OpenSSH, not Tailscale SSH.
   Add this grant to your existing policy:

   ```json
   {
     "src": ["tag:dorbit-ci"],
     "dst": ["100.86.199.82"],
     "ip": ["tcp:22"]
   }
   ```

   Add `"tag:dorbit-ci": ["autogroup:admin"]` to `tagOwners`. Remove any broad
   grants that would also allow CI access elsewhere. Grants add access; this rule
   cannot override an existing allow-all rule. Preserve the operator and pilot
   rules described below. Add a policy test for source `tag:dorbit-ci` accepting
   `100.86.199.82:22` and denying `100.86.199.82:24567` and other tailnet devices.
   Use the console's policy preview to confirm TCP 22 is the only permitted service.
   CI does not need game-port access; readiness checks run on the VPS over SSH.
5. In GitHub **Settings > Environments**, create `dorbit-production`. Allow deployment
   only from `main`. If your repository plan supports required reviewers, add yourself
   and prevent self-review where practical. The manual trigger is always required;
   do not add a push trigger to the deployment workflow. Under this environment add:

   | Kind | Name | Value |
   | --- | --- | --- |
   | Secret | `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
   | Secret | `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
   | Secret | `DORBIT_DEPLOY_SSH_KEY` | Entire new `dorbit-ci` private key |
   | Variable | `DORBIT_KNOWN_HOSTS` | `100.86.199.82 ssh-ed25519 AAAA...` using the verified VPS public host key |

   Get the host public key with `sudo cat /etc/ssh/ssh_host_ed25519_key.pub` over
   your already verified administrative connection. Independently confirm with
   `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` that its fingerprint is
   `SHA256:P+Lvr8RDA46ECqUdkvNtiP8t/HOejVCmtJVqqsdE7io`. Copy only its key type and
   base64 key after `100.86.199.82`. The workflow checks this fingerprint and enables
   strict SSH host checking. Do not accept an unverified `ssh-keyscan` result.
   No pilot login, personal SSH key, recovery private key or VPS sudo password belongs
   in GitHub. Permit Actions to create Releases in repository settings if disabled.
6. Before the first deployment, preserve the matching client for the current
   pre-CI release, `90650412c9027500f2e2e82d800a62e8af63b45c`. Confirm the live commit
   again with `ssh dorbit-vps 'readlink /opt/dorbit/current'`. Create a clean
   `windows.zip` containing its matching exported client, license notices and a
   UTF-8 `REVISION` file containing that full SHA. Exclude private launchers,
   profiles, credentials and saves. Upload it to a GitHub Release named
   `build-90650412c9027500f2e2e82d800a62e8af63b45c`, targeting that commit, with notes
   explaining it is the archived pre-CI rollback client. If you cannot verify the
   original client's revision, rebuild it from that exact commit using `tools/dev.ps1`.
   This legacy release has no tested manifest, so the Action cannot deploy it as
   a new CI release. It can preserve its client for manual rollback. Later releases
   and their paired clients are published automatically.

### Click Deploy

1. Open **Releases** and choose a `build-...` release. Follow its checks link and
   confirm the run finished successfully. Download `windows.zip` for players.
   Its `REVISION` identifies the matching server commit. Players still use their
   existing private pilot credential and Tailscale connection.
2. Read the current commit using `ssh dorbit-vps 'readlink /opt/dorbit/current'`.
   Warn players that the restart will disconnect them.
3. Open **Actions > Deploy server > Run workflow**, select branch `main`, paste
   the complete release tag and the full current commit into `expected_current`,
   then click **Run workflow**. Approve the environment job if configured.
4. Read the job summary. Success means a fresh game-listening log and a UDP socket
   owned by that service invocation remained ready for ten seconds. A restart loop,
   startup error or inactive game socket fails the job. This is stronger than
   systemd's `active` status; it is not an authenticated player or performance test.
   Join with the matching Windows client and check your saved credits.
5. Download the run's `dorbit-recovery-...` artifact and keep it privately off the
   VPS. GitHub retains it for 90 days or the repository's shorter retention limit.
   It contains `backup.tar.age`, public transaction metadata and the previous
   Windows client. It never contains plaintext saves or credentials. Retain both
   GitHub Releases until you no longer need rollback.

Before touching the service, the Action verifies the selected release's hashes,
successful `main` validation run and matching previous client. The VPS checks the
actual current commit again. It stops Dorbit, confirms no `dorbit` processes remain,
then encrypts the entire data directory, unit, port environment and previous-link
record. It downloads and uploads that recovery copy before activation. Failure to
preserve it off-machine prevents the switch. A stale lock or interrupted write
also prevents activation. The previous release directory is never deleted.

GitHub queues deployments without cancelling a running one. A VPS file lock and
durable `pending.json` block concurrent requests and retries after interrupted
transactions. Operators must also avoid manual updates while a deployment runs.
Cancellation, network loss or power loss can leave the server stopped or switched
but unverified. Recovery is deliberately manual.

### Failure and rollback

Do not repeatedly click Run. Read the failed step and the summary, then connect
as `dorbit-admin`. Do not print saves or full journals into GitHub logs.

```bash
sudo cat /var/lib/dorbit-deploy/pending.json
readlink /opt/dorbit/current
sudo systemctl status dorbit --no-pager
sudo journalctl -u dorbit -n 100 --no-pager
```

If there is no pending transaction and failure was before service stop, the
original service was not changed. Correct the release, credentials, network or
preflight issue. Failed staging directories consume disk; inspect and remove only
the specific unused directory, never a release or backup still needed for recovery.

If a transaction is pending, record its `id`, `previous`, `previous_link` and phase.
Its files are in `/var/lib/dorbit-deploy/<id>/`, readable only by root. If the runner
lost contact before uploading the recovery artifact, copy `backup.tar.age` from
that directory using your administrative account and keep it off-machine before
proceeding. For example, on the VPS, replace `TRANSACTION_ID` below:

```bash
sudo install -o dorbit-admin -g dorbit-admin -m 0600 \
  /var/lib/dorbit-deploy/TRANSACTION_ID/backup.tar.age \
  /home/dorbit-admin/dorbit-recovery-TRANSACTION_ID.tar.age
```

Then on your PC run
`scp dorbit-vps:dorbit-recovery-TRANSACTION_ID.tar.age .`.
If encryption or stop failed, a complete encrypted backup may not exist.
Keep the service stopped and follow README.md's stopped-server copy procedure first.
Never remove the lock just to make deployment proceed.

On your own computer, decrypt the downloaded recovery copy into a private directory:

```bash
age --decrypt -i dorbit-recovery.key -o backup.tar backup.tar.age
tar -tf backup.tar
```

It contains `data/`, `dorbit.service`, `server.env` and `transaction.json`.
Keep decrypted files private. Do not upload them to GitHub. A rollback requires a
decision about save compatibility. Restoring the old application does not undo a
save migration. For these current schema-v1 releases, use the old application with
current valid saves only after confirming compatibility. Otherwise preserve the
failed release's entire stopped data directory, inspect both copies and follow
README.md's recovery steps. Restoring an earlier ledger loses later progress and
credential rotations; make that decision explicitly, not in a script.

For a compatible application rollback, after stopping the service and confirming
no `dorbit` processes remain, use the recorded previous link. Replace the example
values with those from the transaction; inspect any existing `current.next` first:

```bash
sudo systemctl stop dorbit
pgrep -u dorbit                    # Must report no processes before continuing.
previous=releases/PREVIOUS_FULL_COMMIT
sudo test -d "/opt/dorbit/$previous"
sudo ln -s "$previous" /opt/dorbit/current.next
sudo mv -Tf /opt/dorbit/current.next /opt/dorbit/current
sudo systemctl reset-failed dorbit
sudo systemctl start dorbit
```

The CI helper refuses unit changes, so the unit and port settings normally remain
unchanged. If an operator changed them, restore the reviewed saved `dorbit.service`
and `server.env` to their original paths, run `sudo systemctl daemon-reload`, and
then start Dorbit. Check the new invocation's listening log and UDP socket, and
connect with the previous Windows client from the recovery artifact or old Release.
Verify credits after reconnect. Only after successful recovery, archive the resolved
`pending.json` into its transaction directory with
`sudo mv /var/lib/dorbit-deploy/pending.json /var/lib/dorbit-deploy/TRANSACTION_ID/resolved-pending.json`.
Do not delete the recovery directory.
If a failed deployment installed the selected commit's directory, inspect it before
reusing or removing it; the helper refuses to overwrite existing releases.

### CI deployment validation

The deployment tests use temporary directories and simulated systemd commands.
They cover traversal/link archives, unit changes, mismatched current commits, stale
locks, backup receipts, pending transactions, preservation of saves/previous releases,
failed readiness and an active systemd service without game readiness. The ordinary
Linux checks still exercise real Godot processes and disposable saves.
Release-selection tests also reject failed, incomplete, fork, PR and non-main
validation runs and confirm that a successful selection preserves the old client.

The existing VPS was inspected read-only on 2026-09-22. It still ran `9065041`,
owned UDP 24567, used the expected unit without overrides and matched the pinned
SSH fingerprint. This implementation has not installed its account/helper on the
VPS, configured GitHub/Tailscale credentials or interrupted the live game. The
first complete private CI deployment, encrypted recovery restore and player login
remain operator checks after setup and explicit approval. No gameplay, protocol,
authentication, save schema, local firewall or local service changes are included.

## Preview a PR before merging

After this infrastructure PR is merged, use **Actions > Deploy preview > Run
workflow** on `main` and enter a PR number, such as `15`. Leave **fresh_saves**
unchecked to keep that PR's progress. A stacked PR includes the code from its
prerequisite branches; they do not need to merge before you test the combined build.

The Action records the open PR's exact head commit, then checks and builds Linux
and Windows from it. A later push does not change that selection. Only PR branches
in this repository are accepted. Builds have no deployment secrets, do not retain
checkout credentials, and run separately from the deployment job. That job checks
out the trusted workflow commit and handles the archives without executing PR code.
Only manually dispatched workflows from `main` can use the preview environment.
Keep preview deployment secrets in that environment, never as repository secrets.
Do not use `pull_request_target` to execute PR code with secrets.

When the job finishes, open its summary and download
`Preview-Windows-<commit>-<attempt>` from the linked run's artifacts. Extract that
download, then extract `windows.zip` and run `Dorbit.exe`. Its `REVISION` file must
match the summary's commit. Use your private preview pilot credential and connect
through Tailscale to `100.86.199.82`, port `24568`. Your production credential is
not the preview credential. No credential or private launcher is in the download.
On PowerShell, after extracting the client, for example:

```powershell
$env:DORBIT_PILOT_FILE = 'C:\private\dorbit-preview-pilot.json'
.\Dorbit.exe
```

Enter the preview address and port in the game's connection menu. Keep this
PowerShell session separate from your production launcher. A successful job means
the new game's listening log and service-owned UDP socket stayed ready for ten
seconds. It still needs your human playtest. Run Deploy preview again after fixes.
Use a new workflow run rather than rerunning only failed jobs: artifact names
include the attempt number, so partial reruns cannot mix old and new builds.

Open **Actions > Stop preview > Run workflow** when finished or before a production
session with friends. It stops only `dorbit-preview.service` and verifies that no
processes owned by `dorbit-preview` remain. Saves and release files stay on disk.
Deploy preview again to start it. Preview has no systemd boot enablement and stays
off after a VPS reboot. Both actions share one concurrency group and cannot overlap.
GitHub can replace an older pending run when another is submitted, so avoid
submitting multiple pending actions. If a deployment is running, Stop preview waits for it; an administrator can stop the
service directly if immediate intervention is needed.

One preview runs at a time, with no CPU/memory limits. It shares the VPS's resources
and kernel with production. A separate account and unit isolate file access and
service control; this is for the operator's own code, not arbitrary outside code.

### Preview setup on the VPS

These steps are prepared for operator approval. They have not been run against
the VPS during implementation. They create no paid infrastructure and do not
require stopping production. Port 24568 was free during the read-only check;
check it again with `sudo ss -lunp 'sport = :24568'` before installing.

Use the age recovery key and verified SSH host key described above. Generate a
different deployment SSH key, `dorbit-preview-ci`, for preview. Copy this PR's
reviewed `tools/vps-deploy.py` and `deploy/dorbit-preview.service` to your VPS
administrative account. As `dorbit-admin`, install:

```bash
sudo apt-get install -y age python3 procps iproute2
sudo useradd --system --user-group --no-create-home --home-dir /var/lib/dorbit-preview/runtime --shell /usr/sbin/nologin dorbit-preview
sudo useradd --system --user-group --no-create-home --home-dir /var/lib/dorbit-preview-login --shell /bin/sh dorbit-preview-deploy
sudo install -d -o root -g root -m 0755 /opt/dorbit-preview /opt/dorbit-preview/releases /var/lib/dorbit-preview /var/lib/dorbit-preview/saves /etc/dorbit-preview
sudo install -d -o dorbit-preview -g dorbit-preview -m 0700 /var/lib/dorbit-preview/runtime
sudo install -d -o root -g root -m 0700 /var/lib/dorbit-preview-deploy
sudo install -d -o root -g root -m 0755 /var/lib/dorbit-preview-login /var/lib/dorbit-preview-login/.ssh
sudo install -o root -g root -m 0755 vps-deploy.py /usr/local/sbin/dorbit-preview-deploy
sudo install -o root -g root -m 0644 dorbit-preview.service /etc/systemd/system/dorbit-preview.service
```

The executable must have that exact installed name. It selects fixed preview
paths and commands. SSH input cannot select production paths or its service.
Keep all parent directories root-owned as above, so the game cannot redirect the
active release/data links. The unit also hides production data/configuration and
limits writes to preview releases, saves and runtime files. Do not add the preview
users to the `dorbit` or administrative groups.

Use `sudoedit /etc/dorbit-preview/server.env` to enter `DORBIT_PORT=24568`.
Create `/etc/dorbit-preview/backup-recipient.txt` with your `age1...` public recovery
recipient. Both files must be root-owned and mode 0644. Create a fresh seed ledger
and private test credential with the existing deployed provisioning tool:

```bash
python3 /opt/dorbit/current/tools/pilots.py /home/dorbit-admin/dorbit-preview-seed preview /home/dorbit-admin/dorbit-preview-pilot.json --init
sudo install -d -o root -g root -m 0700 /etc/dorbit-preview/seed
sudo install -o root -g root -m 0600 /home/dorbit-admin/dorbit-preview-seed/pilots.json /etc/dorbit-preview/seed/pilots.json
```

This creates a new test pilot; it does not read or modify production saves. Copy
`dorbit-preview-pilot.json` privately to your PC using `scp dorbit-vps:dorbit-preview-pilot.json .`
from a private directory outside Git. The seed contains only its authentication
verifier and initial progress. Each new PR gets a copy and the same preview login.
The current deployed tool produces schema v1; PR #15's normal server migration
accepts it. A future branch that drops that migration needs a separately prepared
compatible seed; it must never fall back to production data.

Create `/usr/local/sbin/dorbit-preview-ci-command`, root-owned and mode 0755:

```sh
#!/bin/sh
exec sudo -n /usr/local/sbin/dorbit-preview-deploy "$SSH_ORIGINAL_COMMAND"
```

Create `/var/lib/dorbit-preview-login/.ssh/authorized_keys`, root-owned and mode
0644, with only the new preview public key:

```text
restrict,command="/usr/local/sbin/dorbit-preview-ci-command" ssh-ed25519 YOUR_PREVIEW_PUBLIC_KEY dorbit-preview-ci
```

Use `sudo visudo -f /etc/sudoers.d/dorbit-preview-deploy` to add:

```sudoers
dorbit-preview-deploy ALL=(root) NOPASSWD: /usr/local/sbin/dorbit-preview-deploy *
```

Run `sudo visudo -c`, `sudo systemd-analyze verify /etc/systemd/system/dorbit-preview.service`
and `sudo systemctl daemon-reload`. Do not enable the unit or start it manually
before the first deployment has created its release/data links. Its unit-file
state must be `static`; it deliberately has no `[Install]` section.

### Preview GitHub and Tailscale setup

Create a GitHub environment named `dorbit-preview`, restricted to `main`. Use the
same secret names as production, with separate preview values:

| Kind | Name | Preview value |
| --- | --- | --- |
| Secret | `DORBIT_DEPLOY_SSH_KEY` | Entire private `dorbit-preview-ci` SSH key |
| Secret | `TS_OAUTH_CLIENT_ID` | Separate preview Tailscale OAuth client ID |
| Secret | `TS_OAUTH_SECRET` | Its OAuth client secret |
| Variable | `DORBIT_KNOWN_HOSTS` | Same verified `100.86.199.82 ssh-ed25519 AAAA...` line |

The manual Run workflow click is your approval. A second environment approval is
optional for this solo preview workflow. Keep protection on `main` and secure your
GitHub account, since someone who can change trusted workflows can misuse secrets.

Create `tag:dorbit-preview-ci`, owned by administrators, and an OAuth client with
`auth_keys` write permission limited to that tag. Add this Tailscale grant:

```json
{"src": ["tag:dorbit-preview-ci"], "dst": ["100.86.199.82"], "ip": ["tcp:22"]}
```

Allow your existing operator group to reach `100.86.199.82` on `udp:24568` too.
Friend/pilot access to production need not include preview. Check policy tests
and remove broader grants that defeat these restrictions. Neither CI tag needs
game-port access. Keep public SSH and game ports closed; no development-machine
firewall or service changes are needed.

### Preview failure and recovery

No automatic action deletes locks, restores a ledger or rolls back a migration.
The **fresh_saves** option archives that PR's whole old data directory only after
the encrypted stopped-server backup has been uploaded off the VPS. It resets
preview progress explicitly; other PR directories remain unchanged.

The fixed preview locations are:

| Purpose | Location |
| --- | --- |
| Service | `dorbit-preview.service` |
| Release and data links | `/opt/dorbit-preview/current`, `/var/lib/dorbit-preview/data` |
| Installed releases | `/opt/dorbit-preview/releases/<commit>-<transaction>` |
| Per-PR saves | `/var/lib/dorbit-preview/saves/pr-<number>` |
| Pending transaction | `/var/lib/dorbit-preview-deploy/pending.json` |
| Recovery directories | `/var/lib/dorbit-preview-deploy/<transaction>/` |
| Last successful preview | `/var/lib/dorbit-preview-deploy/active.json` |

Stop preview, then inspect its pending transaction and journal privately as
`dorbit-admin`. Stop preview also works when a recovery transaction is pending,
but does not clear it. If the runner disconnected, retrieve `backup.tar.age` using
the administrative copy procedure above, substituting the preview recovery path.
Decrypt off the VPS. A preview backup contains `previous-data/` if a preview was
selected, `selected-data/` if the target PR already had saves, the old unit/env,
transaction metadata and the previous preview's build-run reference when present.
The root-only `archived-data/` directory additionally retains a fresh reset's old
data. Do not replace a valid ledger just because a deployment failed.

For a rollback, stop preview and confirm `pgrep -u dorbit-preview` reports no
processes. Preserve any current data first. Use `previous_link` and `previous_data`
from the transaction to restore the preview release and data symlinks. Both must
stay inside the preview directories. Decide save compatibility before restarting,
following README.md's recovery procedure. A first deployment has no previous links;
recover or explicitly reset its test data before trying again. After successful
recovery, move `pending.json` into its transaction directory as `resolved-pending.json`.

Artifacts are retained for 90 days or your repository's shorter limit. Keep the
matching Windows client and encrypted recovery download privately if you need a
longer rollback window. The run/attempt in `active.json` identifies the exact old
client artifact. Old preview releases and backups are not automatically deleted;
remove only inspected, unused preview directories when you need disk space.

Local tests cover PR selection, isolated saves, explicit reset, repeated same-commit
deployment and stopping after failures. The preview unit can be checked without
installing a service. A full Tailscale/SSH preview deployment and human reconnect
remain checks after operator setup and approval. Production has not been interrupted.

## Prepare a release manually

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
The updated unit has passed live stop/start and VPS reboot/reconnect checks.
Abrupt crashes and power loss still require operator recovery.
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

After the operator approved deployment, release `9065041` and its unit were
installed on the live service. The old service was stopped, all old Godot
processes were confirmed gone, and the entire data directory and previous unit
were preserved on the VPS and copied to the operator PC. The old launcher's
empty stale lock was removed once using the documented operator recovery checks.
Subsequent stops released the lock through normal game cleanup.

A live stop/start and a full VPS reboot both restored readiness. The boot ID
changed, Tailscale and Dorbit started automatically, and a Windows client joined,
disconnected and rejoined with the same 150-credit pilot wallet. The ledger stayed
byte-for-byte unchanged. The previous boot's journal recorded the cooperative
shutdown and successful service stop. This verifies orderly reboot recovery;
it does not establish recovery after a power cut, SIGKILL or interrupted write.
