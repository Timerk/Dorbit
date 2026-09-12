# Dorbit

A space game inspired by DarkOrbit, built with Godot. Windows players connect to a dedicated Linux server to fly, hunt aliens, earn rewards and repair together. Playing alone uses the same server encounter.

Milestones 1 and 2 have passed user playtesting. Milestone 3 begins with the dedicated server; credits still last only for the current connection. Persistent identities, saves and purchases are next. Ships, scenery and effects use procedural placeholder art.

- [Game requirements and development plan](GAME_PLAN.md)
- [Development workflow](AGENTS.md)

## Play

Launch `build/windows/Dorbit.exe` after building, or download the `Dorbit-Windows` artifact from a successful GitHub Actions run. Extract the artifact before playing and keep the included third-party notices with the executable.

Enter the server address and UDP port in the connection menu, then choose **Connect**. Use matching client and server builds.

1. Hold right mouse and move the mouse to steer. Use W/S for forward/backward movement, A/D to strafe, and Q/E to descend/rise.
2. Fly forward from the station toward the red Sentinel marker. Tab or left click selects it. Space toggles automatic lasers.
3. Keep the alien ahead, within 170 m, and clear of obstacles. Shift boosts while energy is available. Releasing movement brakes the ship.
4. Destroy the alien to receive 75 credits. Return within 60 m of the green outpost marker, slow below 8 m/s, and press R to repair. Repairs require five seconds without taking damage.

Shields regenerate after six seconds without damage. Destruction returns the ship to the station after three seconds and costs up to 10 credits. Hull repairs cost a small amount, capped at the available balance so a player with no credits can recover. The alien returns after 12 seconds.

Esc opens the flight menu and releases the mouse. The server keeps running. F11 toggles fullscreen, F3 shows performance, and F4 switches antialiasing between high and low. F10 quits from the pause screen. Losing focus releases your controls; incoming damage can continue.

While paused, F5/F6 cycle window resolutions from 960 x 600 up to 3840 x 2160, offering only sizes that fit the current screen with room for borders and the taskbar. Selecting a resolution switches to windowed mode; F11 uses the desktop resolution for fullscreen. You can also resize the window manually. The pause menu shows the current pixel dimensions. Display settings are session-only. Mouse steering uses unscaled screen motion so viewport scaling does not change sensitivity.

These values are initial tuning settings, not a finished economy or combat balance.

## Dedicated server and connections

The server supports **ten client pilots**, with no host player. It controls movement, boost, the shared Sentinel, damage, repairs, rewards, destruction and respawning. It keeps running when the last player leaves. **F7** opens the connection menu; **Disconnect** returns to that menu. A server shutdown also returns clients to the menu.

Other living pilots have cyan markers with shield and hull bars and current/maximum values. Hull turns red at 35 or below. Their health reflects server state, including repairs. Markers disappear on destruction and return on respawn.

A kill splits the **75-credit pool** among connected contributors; integer shares differ by at most one credit. Dead contributors remain eligible while connected. Spectators receive no reward. Each contributor receives one kill. Repairs and the up-to-10-credit rescue fee are charged to the requesting pilot's server-owned session balance.

**Saves and accounts are not implemented yet.** Disconnecting or restarting the server resets progression. This first server build is for private testing; private-group access control follows with persistent identities. The former solo/listen-host modes are only development fixtures, accessible by launching with `--offline` after Godot's `--` separator (or `Dorbit.exe -- --offline`).

### Start a server in Ubuntu / WSL2

Requires Linux x86-64, `bash`, `curl`, `python3` and `sha256sum`. On this Windows checkout, run in PowerShell:

```powershell
wsl -d Ubuntu -- bash /mnt/c/Users/timbe/Desktop/Projekte/Dorbit/tools/server.sh setup
wsl -d Ubuntu -- bash /mnt/c/Users/timbe/Desktop/Projekte/Dorbit/tools/server.sh run
```

`setup` downloads and verifies the pinned Godot 4.7.2 Linux runtime. It is needed once. `run` imports the project and starts a headless server on **UDP 24567**. Leave that terminal running; **Ctrl+C** stops the server. No graphical Linux desktop or export-template download is needed.

Find Ubuntu's address from PowerShell:

```powershell
wsl -d Ubuntu -- hostname -I
```

Enter that WSL IPv4 address in the Windows client's connection menu, with port **24567**. WSL's address can change after restarting. On this machine, the WSL IP worked for UDP; `127.0.0.1` did not. Localhost may work with other WSL networking configurations.

From a Linux checkout, the equivalent commands are:

```bash
bash tools/server.sh setup
bash tools/server.sh run
```

Append `--port=24600` to `run` to choose another UDP port, and use the same port in the client. For a VPS, clients use its reachable IP or DNS address and its firewall must allow the selected UDP port. Other PCs reaching WSL need suitable mirrored networking or UDP routing and Windows/WSL firewall rules; TCP-only `netsh portproxy` does not forward this game's UDP traffic. The helper does not change firewall rules.

## Develop on Windows

The helper downloads the official Godot 4.7.2 editor and verifies its SHA-256 checksum. Building also downloads the matching export-template archive, about 1.3 GB, and extracts only the Windows templates. Tools and generated builds stay out of Git.

Run from the repository root with PowerShell and RTK:

```powershell
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 setup
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 check
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 build
```

Use `run` to play from source or `editor` to open Godot. You can also import `project.godot` into an existing Godot 4.7.2 installation. RTK is a command wrapper, not a game dependency.

If RTK is not installed, run these directly in PowerShell from the checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 run
```

Setup is needed only once. To produce `build/windows/Dorbit.exe`, replace `run` with `build`. To run the automated checks, replace it with `check`. Running from source does not need export templates or a separate build.

The project uses Godot Compatibility rendering with 4x MSAA by default. The first scene uses simple meshes and a procedural sky; it does not require Blender or downloaded art assets.

## Validation

For a repeatable ten-client Linux server workload, CPU/memory measurements and their limits, see [PERFORMANCE.md](PERFORMANCE.md). Headless simulation measurements do not establish rendered client FPS.

`check` imports the project and runs headless integration tests against the actual scene and physics world, network checks with separate ENet peers, and a complete hunt-and-repair replay. It covers input actions, shield and hull damage, cooldowns, range, firing arcs, obstacles, rewards, repairs, rescue, movement, mouse steering, pause, joining, replication, and disconnects.

For a rendered hunt-and-return replay:

```powershell
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/flight_playthrough.gd
```

The replay opens a 2560 x 1440 window, disables VSync for measurement, and saves screenshots under `build/validation`. Keep its window focused while it runs. These changes apply only to the replay. The normal game uses VSync.

GitHub Actions runs the Windows checks, exports the Windows client, and tests the dedicated server on Linux for each pull request. `bash tools/server.sh check` runs the 43 dedicated-server checks locally, including ten simultaneous client connections, damage, rewards, repairs, respawning, empty-server operation, reconnecting, collision parity and reordered snapshots.

For a two-client Windows-to-Linux replay, run the server on port 24684, then start two Windows Godot processes with `--path . --script res://tests/dedicated_client_playthrough.gd -- --address=YOUR_WSL_IP --label=a` (use `--label=b` for the other). Start both within ten seconds. Each replays the hunt and repair loop; rendered runs save screenshots under `build/validation`.

## Code layout

- `scripts/ship.gd`: shared combat state and weapon validation.
- `scripts/pilot.gd`: flight input and chase camera.
- `scripts/alien.gd`: alien movement and engagement.
- `scripts/sector.gd`: encounter lifecycle, targeting, rewards, repairs, and rescue.
- `scripts/flight_session.gd`: session menu, ENet connection lifecycle, host flight simulation, and client prediction/interpolation.
- `scripts/session_combat.gd`: host-owned alien encounter, per-player wallets, repairs, respawns, and combat snapshots/effects.
- `scripts/visuals.gd` and `shaders/space.gdshader`: procedural placeholder art and effects.
- `scripts/hud.gd`: flight instruments, targets, objectives, and pause display.

Combat emits visual signals; visual effects do not award rewards or apply damage. Shared play sends movement and fire intent to the host at 20 Hz and receives authoritative snapshots at 20 Hz, with local flight prediction and smoothing of other players and the alien. Only the host simulates combat; repair requests identify the requesting peer, never a client-supplied price or damage amount.
