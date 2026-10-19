# Lazy map scenery validation — 2026-10-19

Clients now build only M1 scenery at startup. `activate_map` builds another map's
backdrop, gates and asteroid meshes on its first local visit. The 149 static
collision shapes, all 20 aliens, shared gate range/protection checks and reciprocal
arrival positions remain available from startup. Gate triggers are distance checks
against `SectorMaps.GATES`; there were no `Area3D` gate triggers to defer.

Scenery stays cached until the sector is destroyed. This saves construction and
memory for unvisited maps, while return visits reuse the same nodes. After visiting
all four maps, scenery memory approaches the previous eager allocation, with a
small additional wrapper/cache cost. Alien model loading and other startup systems
are unchanged.

There was no existing gate transition effect. First visits now render an opaque
transit cover before sending/performing the jump. Geometry is constructed only on
accepted entry, and the cover fades over 180 ms after the destination's first draw.
Rejected/cancelled jumps and disconnects clear it. Rendering waits apply only to
rendered clients; headless simulation stays synchronous.

## Measurements

Baseline: `origin/main` at `0afcaa83791fe2fdad679cf2a6b46bbb05fe76b0`.
Both revisions used the same completed import cache and benchmark scripts, three
fresh processes per mode with disposable profiles and server ledgers. Initial asset
import time is excluded. Results below are medians; all samples and check summaries
are in [the raw report](performance-lazy-scenery-2026-10-19.json).

Windows laptop: Ryzen 7 5700U, 15.4 GiB RAM, integrated AMD Radeon Graphics;
Godot 4.7.2 editor/debug source runtime, Compatibility, 1440 × 900, default 4x MSAA.
This is not the project's RX 7600 reference PC or a production Linux export.

| Mode | Metric | Before | After |
| --- | --- | ---: | ---: |
| Client | Engine start to scene ready | 8.313 s | 6.944 s |
| Client | Scene construction | 5.498 s | 4.308 s |
| Client | Engine start through ten frames | 12.062 s | 10.345 s |
| Client | Static memory | 122.409 MiB | 119.407 MiB |
| Client | Peak static memory | 128.069 MiB | 124.754 MiB |
| Client | Video memory | 622.009 MiB | 590.919 MiB |
| Headless dedicated server | Engine start to scene ready | 1.936 s | 1.620 s |
| Headless dedicated server | Scene construction | 0.060 s | 0.052 s |
| Headless dedicated server | Engine start through ten frames | 2.053 s | 1.738 s |
| Headless dedicated server | Static memory | 87.251 MiB | 87.417 MiB |
| Headless dedicated server | Peak static memory | 115.782 MiB | 116.074 MiB |
| Headless dedicated server | Video memory | 0.000 MiB | 0.000 MiB |

Client engine-to-ready time fell about 16.5%, scene construction about 21.6%,
static memory about 3.0 MiB and reported video memory about 31.1 MiB. The source
server already skipped scenery before this change and still reports zero video
memory. Its small static increase (about 0.17 MiB) and timing variation do not
establish a server optimization.

`ready_ms` times scene load/creation after the benchmark script initializes;
`engine_ready_ms` uses engine uptime and includes earlier startup work. Static and
video counters are sampled after ten frames. Static memory is Godot's allocator;
video memory is Godot's resource accounting, not OS process/GPU residency. The JSON
also records texture/buffer bytes and peak static memory. These are warm-cache,
single-client measurements on a shared development machine, not capacity results.

## Interaction validation

1520 headless assertions passed across scenery, connected-map networking, alien-sector,
map-layout, autopilot, connection, display and graphics tests, including settings
restart cases. The scenery test verifies only M1 exists initially, all unvisited
maps have their collider/obstacle/gate data, first entry builds only that map,
visuals align with collider positions/radii, revisits reuse nodes, and direct
server builder calls create no render nodes.

The rendered `connected_maps_playthrough.gd` passed 171 assertions in 68.15 s.
Its gate route was M1 → M2 → M3 → M4 → M3 → M2 → M4 → M2 → M1, covering all
eight directed gates. Each map passed a real asteroid collision query, detour
planning/clearance checks, alien patrol movement and actual autopilot flight into
gate jump range. The replay also checks protection, radiation, intent reset,
contacts, home rescue and rejected first-jump cover cleanup. The separate
authenticated network test checks authority, combat, stale visits and transfers.

Measured first-visit jump input completion was 212/272/334 ms for M2/M3/M4;
cached returns took 7.7–10.6 ms in this replay. These include input/render frames
and synchronous construction, not network latency; the transit cover hides the
first-visit pause. Lower-spec hardware can still take longer under the cover.

## Screenshots

All four palettes, planets, debris fields, station and all eight gate approaches
were visually inspected. The following are JPEG copies of the actual 1920 × 1080
viewport captures; original PNGs remain in `build/validation`.

| Map scenery | Gate approaches |
| --- | --- |
| [M1](feedback/lazy-scenery/lazy-scenery-m1.jpg) | [M1 → M2](feedback/lazy-scenery/connected-map-gate-m1-m2.jpg) |
| [M2](feedback/lazy-scenery/lazy-scenery-m2.jpg) | [M2 → M1](feedback/lazy-scenery/connected-map-gate-m2-m1.jpg), [M2 → M3](feedback/lazy-scenery/connected-map-gate-m2-m3.jpg), [M2 → M4](feedback/lazy-scenery/connected-map-gate-m2-m4.jpg) |
| [M3](feedback/lazy-scenery/lazy-scenery-m3.jpg) | [M3 → M2](feedback/lazy-scenery/connected-map-gate-m3-m2.jpg), [M3 → M4](feedback/lazy-scenery/connected-map-gate-m3-m4.jpg) |
| [M4](feedback/lazy-scenery/lazy-scenery-m4.jpg) | [M4 → M2](feedback/lazy-scenery/connected-map-gate-m4-m2.jpg), [M4 → M3](feedback/lazy-scenery/connected-map-gate-m4-m3.jpg) |

## Reproduce

With the pinned runtime and completed imports:

```powershell
rtk proxy python tools/benchmark_scenery.py .tools/godot/Godot_v4.7.2-stable_win64_console.exe build/validation/scenery.json
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/sector_visuals_test.gd
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/connected_maps_test.gd
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/connected_maps_playthrough.gd
```

Use an isolated device profile for direct test/replay commands, as the existing
check runner does. `benchmark_scenery.py` creates isolated profiles and ledgers
automatically; `--project` can point at a baseline checkout containing the same
benchmark script and compatible imports. `--mode client` / `--mode server` select
one workload. No gameplay balance, network/save schema or production deployment
changes are included.
