# Dorbit

A space game inspired by DarkOrbit, built for Windows with Godot. The first milestone is a playable solo encounter with full 3D flight, target-lock combat, alien hunting, rewards, and station repairs.

Milestone 2 starts with shared flight for up to 10 players. Shared combat is the next step; the complete solo encounter remains available. Progress currently lasts for the running session only. Ships, scenery, and effects use procedural placeholder art.

- [Game requirements and development plan](GAME_PLAN.md)
- [Development workflow](AGENTS.md)

## Play

Launch `build/windows/Dorbit.exe` after building, or download the `Dorbit-Windows` artifact from a successful GitHub Actions run. Extract the artifact before playing and keep the included third-party notices with the executable.

1. Hold right mouse and move the mouse to steer. Use W/S for forward/backward movement, A/D to strafe, and Q/E to descend/rise.
2. Fly forward from the station toward the red Sentinel marker. Tab or left click selects it. Space toggles automatic lasers.
3. Keep the alien ahead, within 170 m, and clear of obstacles. Shift boosts while energy is available. Releasing movement brakes the ship.
4. Destroy the alien to receive 75 credits. Return within 60 m of the green outpost marker, slow below 8 m/s, and press R to repair. Repairs require five seconds without taking damage.

Shields regenerate after six seconds without damage. Destruction returns the ship to the station after three seconds and costs up to 10 credits. Hull repairs cost a small amount, capped at the available balance so a player with no credits can recover. The alien returns after 12 seconds.

Esc pauses and releases the mouse. F11 toggles fullscreen, F3 shows performance, and F4 switches antialiasing between high and low. F10 quits from the pause screen. Losing focus pauses the local encounter.

While paused, F5/F6 cycle window resolutions from 960 x 600 up to 3840 x 2160, offering only sizes that fit the current screen with room for borders and the taskbar. Selecting a resolution switches to windowed mode; F11 uses the desktop resolution for fullscreen. You can also resize the window manually. The pause menu shows the current pixel dimensions. Display settings are session-only. Mouse steering uses unscaled screen motion so viewport scaling does not change sensitivity.

These values are initial tuning settings, not a finished economy or combat balance.

## Shared flight (Milestone 2, first step)

Press **F7** to open the session menu. On one computer, choose **Host flight session**. On the other, enter the host's LAN or VPN IP address and choose **Join host**. Use the same build on both PCs. For two game instances on one PC, enter `127.0.0.1` in the joining instance.

The host listens on **UDP port 24567**. If Windows Firewall prompts, allow the game on the network you are using. LAN and VPN connections (for example, Tailscale) need a reachable host address; direct internet connections require UDP port forwarding to the host. There is no automatic NAT traversal or server browser.

Players fly around the same outpost with host-controlled movement and boost. Other pilots have cyan markers. This is a combat-free flight test: shared aliens, combat, rewards, and persistence are not implemented yet. Entering or leaving shared flight resets the ship at the station; existing solo credits remain local.

Esc or F7 releases your controls while the shared world keeps running. Choose **Leave session / return to solo** to disconnect. If the host leaves, clients return to solo with a status message. Hosting ends when the host closes the game; there is no host migration. Only one host can use a given UDP port on a PC.

Local automated checks cover real ENet peers, late joining, movement authority, input validation/timeouts, and disconnection/reconnection. Cross-PC internet play, latency tuning, and full-group performance still need testing.

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

`check` imports the project and runs headless integration tests against the actual scene and physics world, network checks with separate ENet peers, and a complete hunt-and-repair replay. It covers input actions, shield and hull damage, cooldowns, range, firing arcs, obstacles, rewards, repairs, rescue, movement, mouse steering, pause, joining, replication, and disconnects.

For a rendered hunt-and-return replay:

```powershell
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/flight_playthrough.gd
```

The replay opens a 2560 x 1440 window, disables VSync for measurement, and saves screenshots under `build/validation`. Keep its window focused while it runs. These changes apply only to the replay. The normal game uses VSync.

GitHub Actions runs the headless checks, exports Windows, and uploads the playable build for each pull request.

## Code layout

- `scripts/ship.gd`: shared combat state and weapon validation.
- `scripts/pilot.gd`: flight input and chase camera.
- `scripts/alien.gd`: alien movement and engagement.
- `scripts/sector.gd`: encounter lifecycle, targeting, rewards, repairs, and rescue.
- `scripts/flight_session.gd`: session menu, ENet connection lifecycle, host flight simulation, and client prediction/interpolation.
- `scripts/visuals.gd` and `shaders/space.gdshader`: procedural placeholder art and effects.
- `scripts/hud.gd`: flight instruments, targets, objectives, and pause display.

Combat emits visual signals; visual effects do not award rewards or apply damage. The combat encounter still runs locally. Shared flight sends player commands to the host at 20 Hz and receives authoritative snapshots at 20 Hz, with local flight prediction and smoothing of other players. Shared combat will build on this transport.
