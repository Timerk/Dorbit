# Dorbit

A space game inspired by DarkOrbit, built for Windows with Godot. The first milestone is a playable solo encounter with full 3D flight, target-lock combat, alien hunting, rewards, and station repairs.

Multiplayer for approximately 10 players comes next. Progress currently lasts for the running session only. Ships, scenery, and effects use procedural placeholder art.

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

These values are initial tuning settings, not a finished economy or combat balance.

## Develop on Windows

The helper downloads the official Godot 4.7.2 editor and verifies its SHA-256 checksum. Building also downloads the matching export-template archive, about 1.3 GB, and extracts only the Windows templates. Tools and generated builds stay out of Git.

Run from the repository root with PowerShell and RTK:

```powershell
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 setup
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 check
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 build
```

Use `run` to play from source or `editor` to open Godot. You can also import `project.godot` into an existing Godot 4.7.2 installation. RTK is a command wrapper, not a game dependency.

The project uses Godot Compatibility rendering with 4x MSAA by default. The first scene uses simple meshes and a procedural sky; it does not require Blender or downloaded art assets.

## Validation

`check` imports the project and runs headless integration tests against the actual scene and physics world, followed by a complete hunt-and-repair replay. It covers input actions, shield and hull damage, cooldowns, range, firing arcs, obstacles, rewards, repairs, rescue, movement, mouse steering, and pause.

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
- `scripts/visuals.gd` and `shaders/space.gdshader`: procedural placeholder art and effects.
- `scripts/hud.gd`: flight instruments, targets, objectives, and pause display.

Combat emits visual signals; visual effects do not award rewards or apply damage. This keeps the later multiplayer work independent of the placeholder art. The current encounter still runs locally and is not a multiplayer implementation.
