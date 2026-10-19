# Performance and asset budgets

## Client asset budgets

Use these targets for new runtime assets; the existing detailed models are
grandfathered until a separate art pass. Exceptions need a rendered comparison
and a same-scene texture-memory / primitive-count measurement. Keep high-resolution
authoring sources under `art/`, outside Godot imports.

| Use | Imported size target (longest side) | Import policy |
| --- | --- | --- |
| Ship / alien PBR atlases | 2048 px per shared albedo, normal and ORM set | VRAM Compressed, mipmaps; share the set across surfaces |
| Tiling station, gate, rock and repair-bot detail | 256–512 px; unique station AO up to 2048 px | VRAM Compressed, mipmaps |
| Planet and panorama backgrounds | Up to 2048 px | VRAM Compressed, mipmaps; check smooth gradients before accepting |
| Quickslot-only art at about 66 px | 128–256 px | Lossless; include the largest supported HUD scale |
| Art shared by quickslots and shop/detail panels | Up to 512 px | Lossless, mipmaps; size for the largest actual use, not just the bar |
| Equipment atlas (2 × 2 tiles) | 1024 px total / 512 px per tile | Lossless, mipmaps; region coordinates derive from imported dimensions |
| Ship card / large menu ship render | 400 / 800 px | Lossless; retain larger sources for future layouts |
| Full-page hangar and Skylab illustrations | Up to 2048 px | Lossless; preserve text, transparency and gradients |

Set `compress/mode=2` and `mipmaps/generate=true` on external 3D textures.
Normal maps additionally use `compress/normal_map=1` (Enabled / RGTC), rather
than color compression. UI remains `compress/mode=0`; use `process/size_limit`
to retain editable source pixels. Existing shared item pictures use 512 px
because shop and refining panels display them larger than the flight bar.

The current exports are native Windows and a stripped Linux dedicated server:
both select `texture_format/s3tc_bptc=true`, with ETC2/ASTC disabled.
Compatibility uses S3TC/RGTC for these SDR textures; its high-quality/BPTC option
is not a quality upgrade in this renderer. Embedded ship and alien GLB images
already use **Embed as Basis Universal** (`gltf/embedded_image_handling=2`),
which transcodes to a supported compressed runtime format; preserve their shared
atlases and mipmaps. Before adding mobile or web, explicitly enable the required
ETC2/ASTC import/export variants and repeat native-browser/device visual checks.
See Godot's [image import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).

| Geometry | New-asset target at full detail | Distant target | Materials / draw surfaces |
| --- | ---: | ---: | ---: |
| Player ship or alien | 30k triangles; hero exception up to 60k | 5k at typical combat distance; 1k at marker distance | 4 preferred, 6 maximum; share texture sets |
| Transit gate | 50k triangles | 10k mid-distance, 2k far | 6 preferred, 8 maximum |
| Station | 150k triangles | 30k mid-distance, 10k far | 8 preferred, 12 maximum |
| Decorative rock / background prop | 5k triangles | 500–1k | 1–2 |

These are authoring targets, not a measured ten-player performance guarantee.
Keep imported automatic LOD generation enabled. Verify its effect with
`Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME` at fixed near/far cameras and
compare the far camera again with `Viewport.mesh_lod_threshold=0` (full detail).
Count every gate, pilot and alien in view; changes from frustum culling alone do
not prove LOD selection. If Compatibility does not reduce the same visible
geometry, propose separately authored/decimated gate LODs with visibility ranges;
do not silently replace accepted art. Godot describes the screen-space threshold
in its [mesh LOD guide](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html).

`tools/asset_review.gd` captures repeatable 1440 × 900 native Compatibility views,
texture/video/buffer memory monitors and a three-gate / ten-ship / five-alien
LOD comparison. Run it before and after reimporting with the same isolated
`APPDATA`, engine and graphics settings. Pass
`--review-output=res://build/asset-review/before` (then `after`) after `--`.
Run without `--headless`, with `--max-fps 60 --path . --script tools/asset_review.gd`.
The monitor's video-memory value is Godot's accounting, not the driver's total
physical VRAM allocation. The explicit all-PNG residency sample includes normally
on-demand menu artwork and must be reported separately from flight residency.
The [19 October measurements and paired screenshots](docs/asset-budgets-2026-10-19/README.md)
record a 32.6% texture-memory reduction in the controlled busy scene and confirm
that automatic LODs reduce submitted primitives in Compatibility.

## Dedicated server performance workload

The current workload measures one Linux dedicated server with ten independent headless clients, either spread over M1–M4 as 3/3/2/2 pilots or together on M1. Both simulate four maps and twenty aliens, with lasers, single rockets, Hellstorm, rewards, loot collection, extras automation, Skylab and the schema-8 combat journal. September results remain below as historical evidence and do not describe this content.

These measurements do not validate rendered client FPS, internet transport or VPS capacity. The VPS SSH connection timed out on 14 October 2026; no live service, release, credentials or saves were changed. The Linux runs use WSL2 instead.

## Batched snapshots, 15 October 2026

Network schema 18 replaces per-entity snapshot, ammunition and boost RPCs with one binary world packet per viewer and tick; rarely changing fields are sent reliably only on change, and each entry names the profile revision it was packed with. `tests/snapshot_traffic_benchmark.gd` connects ten in-process headless clients to a dedicated server on Windows, keeps all ten pilots and five aliens on M1 moving, and reads the server's ENet host counters over 100 steady-state snapshots. ENet bytes include ENet/Godot headers but not IP/UDP headers.

| Build | ENet bytes per client per snapshot | Datagrams per client per snapshot | Per client at 20 Hz | Server outbound at 20 Hz |
|---|---|---|---|---|
| `main` at `ec9ecfb` | 6,881 | 15.9 | 1.10 Mbit/s | 11.0 Mbit/s |
| Batched snapshots | 913 | 0.9 | 0.15 Mbit/s | 1.5 Mbit/s |

That is 7.5 times less traffic and about 18 instead of 318 datagrams per client per second. `tests/snapshot_codec_test.gd` also reports the serialized payload for one viewer with ten pilots and five aliens (8,360 bytes before, 1,104 after) and checks that the packet stays below 1,200 bytes. The Linux workload tables below predate this change and were not rerun.

Run the comparison with `--headless --path . --script res://tests/snapshot_traffic_benchmark.gd`; copy the script into an older checkout to measure it with identical steps.

## Current-content results, 14 October 2026

The qualifying runs both completed with exit 0 at `9ece26e1738324ca8bc504fb99b670be13dfb1dd`. [Spread raw data](docs/performance-spread-2026-10-14.json) and [single-map raw data](docs/performance-single-map-2026-10-14.json) retain source SHA-256 hashes, exact invocation, process samples, persistence events, industry inventories and every over-budget callback. The captured dirty status consists of documentation/result archival work. No gameplay source changed between the two measurements.

The only gameplay fix in this branch changes alien orientation to use a local direction, avoiding approximate global point equality on distant maps. The four-map attempt exposed that error; a focused regression check passed before the qualifying runs. Combat tuning, save/protocol schemas and persistence semantics are unchanged.

| Environment | Value |
| --- | --- |
| Host | AMD Ryzen 7 9800X3D, 8 physical cores / 16 logical CPUs; 32 GiB installed RAM, 31.1 GiB visible to Windows |
| Host OS | Windows 11 Home, build 26200 |
| Linux | Ubuntu 24.04.4 LTS under WSL2, kernel 6.6.87.2-microsoft-standard-WSL2 |
| Linux resources | 16 logical CPUs, 15.18 GiB RAM, 4 GiB swap; no swap use in the recorded end-of-run snapshots |
| Engine | Official Godot 4.7.2 editor, ed1daf0bf, Linux x86-64, headless, max FPS 60 |
| Content | Four maps, twenty aliens; rockets/Hellstorm, extras, level-1 Skylabs and schema-8 journal; fittings detailed below |
| Topology | One dedicated server plus ten separate headless clients on IPv4 loopback ENet UDP 24683 |
| Filesystem | Source under Windows `/mnt/c`; engine and disposable profiles/saves on Linux ext4 `/dev/sdd` |
| Isolation | Shared desktop; no concurrent game tests/builds during qualifying windows, no CPU pinning, root for local raw capture |
| Release form | Source/editor workload with dedicated-server mode; not the stripped exported VPS runtime |

Each scenario used 15 seconds of warmup and a requested 120 seconds of measurement. The server retained ten pilots throughout. The spread pilot-ticks were exactly 3/3/2/2 on M1–M4 for the whole window. All ten were on M1 in the single-map window. RSS includes instrumentation; two-minute flat RSS does not establish long-session stability.

| Measured server metric | Spread across M1–M4 | Ten on M1 |
| --- | ---: | ---: |
| Godot / system window, seconds | 120.004 / 120.008 | 120.012 / 119.985 |
| External raw-clock window, seconds | 119.979 | 119.998 |
| Ticks / ticks per system second | 7200 / 59.996 | 7201 / 60.016 |
| Session callback, mean / p95 / max ms | 1.171 / 3.430 / 28.443 | 1.168 / 3.289 / 11.328 |
| Engine physics monitor, mean / p95 / max ms | 5.049 / 7.798 / 28.623 | 4.641 / 7.539 / 11.471 |
| Callbacks above 16.667 ms | 1 | 0 |
| CPU, mean / p95 / max, one logical CPU = 100% | 8.28% / 10.98% / 17.92% | 8.73% / 14.02% / 15.98% |
| RSS mean / max / lifetime HWM, MiB | 180.53 / 180.53 / 180.53 | 180.62 / 180.62 / 180.62 |
| Outbound UDP datagrams/s, total | 1972.99 | 3456.06 |
| Outbound IP bytes/s, total | 891,290 | 1,846,197 |
| Capture dropped frames | 0 | 0 |
| Ledger / journal bytes at end | 72,739 / 1,862 | 62,438 / 1,860 |
| Clean shutdown, ms | 5.044 | 3.369 |

The Godot, system and external raw clocks agree closely in these windows. The September 10% clock discrepancy was not reproduced. CPU is server-process utilization, not a percentage of all sixteen logical CPUs. Callback timing excludes outer engine work and most multiplayer polling. The physics monitor refreshes periodically, so its repeated samples are not independent per-tick measurements. Neither metric is rendered FPS or complete engine-frame CPU time.

| Measured persistence operation | Spread count; mean / p95 / max ms | M1 count; mean / p95 / max ms |
| --- | ---: | ---: |
| Combat journal debit | 124; 0.264 / 0.361 / 0.915 | 279; 0.214 / 0.320 / 0.665 |
| All full checkpoints | 72; 2.972 / 4.622 / 5.009 | 60; 2.220 / 3.159 / 3.821 |
| Economy/reward checkpoint | 45; 3.313 / 4.667 / 5.009 | 25; 2.617 / 3.634 / 3.821 |
| Loot checkpoint | 15; 2.493 / 4.488 / 4.488 | 23; 1.914 / 2.558 / 2.710 |
| Extras checkpoint | 10; 2.343 / 3.087 / 3.087 | 10; 1.887 / 3.150 / 3.150 |
| Industry checkpoint | 2; 2.021 / 2.051 / 2.051 | 2; 2.430 / 2.451 / 2.451 |
| Backup replacement | 72; 0.449 / 0.644 / 0.679 | 60; 0.259 / 0.354 / 0.518 |
| Primary replacement | 72; 0.264 / 0.422 / 0.492 | 60; 0.158 / 0.260 / 0.301 |
| Journal replacement | 49; 0.093 / 0.152 / 0.273 | 34; 0.082 / 0.135 / 0.149 |

Checkpoint categories partition the full-checkpoint samples; replacement samples are nested suboperations and must not be added to checkpoint totals. Only two industry events per run were observed, so their p95 equals their maximum. The diagnostic stall below remains evidence of a much larger tail even when a qualifying run's checkpoint maximum is smaller.

| Measured activity | Spread | Ten on M1 |
| --- | ---: | ---: |
| Successful laser volleys | 90 | 213 |
| Damage signals from pilots, including rocket hits | 95 | 256 |
| R-310 / ECO-10 projectiles launched | 4 / 30 | 23 / 95 |
| Rocket hits | 5 | 43 |
| Alien deaths / distinct killed slots | 45 / 10 | 25 / 5 |
| Alien laser shots | 43 | 53 |
| Collected cargo units | 596 | 645 |
| Ticks with at least two engaged aliens | 7.18% | 6.71% |

All pilots fired lasers and dealt damage. Each Skylab advanced and changed its resource inventory; ten automatic supply checkpoints occurred in each window. Combat was intermittent hunting with normal travel, protection and respawn delays, not continuous maximum weapon throughput. The different fittings and difficulty prevent attributing all timing differences to map partitioning.

Per-client outbound traffic below is measured across the capture window. Bytes/s means IP bytes including IPv4/UDP headers; raw files also retain UDP payload bytes/s. M1 means the home map, not the internal zero-based map identifier.

| Pilot | Spread map | Spread packets/s | Spread bytes/s | Ten-on-M1 packets/s | Ten-on-M1 bytes/s |
| --- | --- | ---: | ---: | ---: | ---: |
| pilot0 | M1 | 205.07 | 94,273 | 349.38 | 186,695 |
| pilot1 | M2 | 205.42 | 94,580 | 343.16 | 183,280 |
| pilot2 | M3 | 185.37 | 81,196 | 339.66 | 181,373 |
| pilot3 | M4 | 185.75 | 81,292 | 346.20 | 184,954 |
| pilot4 | M1 | 205.03 | 94,285 | 349.43 | 186,691 |
| pilot5 | M2 | 205.01 | 94,426 | 349.16 | 186,589 |
| pilot6 | M3 | 185.45 | 81,216 | 343.06 | 183,231 |
| pilot7 | M4 | 185.75 | 81,288 | 343.54 | 183,467 |
| pilot8 | M1 | 205.08 | 94,328 | 346.23 | 184,951 |
| pilot9 | M2 | 205.06 | 94,404 | 346.24 | 184,966 |

### Inferred snapshot load

With network schema 16 and earlier, before batched snapshots, at exactly 20 Hz, the RPC loops implied `20 × [sum(n_map²) + 5 × 10 + 2 × 10]` calls/s for player snapshots, five local aliens per pilot, ammo and boost. That gives **1,920 RPC calls/s** at 3/3/2/2 and **3,400 RPC calls/s** with all ten on M1. This is a code-derived estimate. Measured UDP datagrams above include additional events, acknowledgements and fragmentation, and may also reflect RPC coalescing. The ten-on-M1 measurement tests the user's approximate 3,400 packets/s estimate; it does not turn the RPC formula into a wire-level count. Internet/Tailscale bytes and VPS capacity remain unmeasured.

## Reproduce

Use a Linux x86-64 checkout with Python 3, curl and the pinned Godot editor. Packet capture requires root or `CAP_NET_RAW`. After setup, run both scenarios sequentially:

```sh
rtk proxy bash tools/server.sh setup
rtk proxy sudo python3 tools/benchmark_server.py --scenario spread --seconds 120 --warmup 15 --output /var/tmp/dorbit-spread-01
rtk proxy sudo python3 tools/benchmark_server.py --scenario single-map --seconds 120 --warmup 15 --output /var/tmp/dorbit-single-01
rtk proxy python3 tests/benchmark_server_test.py
```

RTK is a command wrapper, not a benchmark dependency. For a Windows-owned Git worktree under WSL2, run from PowerShell:

```powershell
rtk proxy wsl -d Ubuntu -u root -e python3 /mnt/c/path/to/Dorbit/tools/benchmark_server.py --engine /home/USER/dorbit-tools/godot --git git.exe --scenario spread --seconds 120 --warmup 15 --output /home/USER/dorbit-runs/spread-01
```

Change the paths to your checkout and engine. Copy the pinned editor to Linux storage and make it executable first. Repeat with `--scenario single-map` and a new output directory. Add `--map 3` to put all ten single-map pilots on M4; `--map` takes a zero-based map and defaults to M1. `git.exe` handles Windows paths in the worktree's `.git` file. Use default `git` in a Linux-owned checkout. Use a Linux-native output directory to measure Linux save I/O. UDP port 24683 must be free; `DORBIT_TEST_PORT_OFFSET` can isolate another port. Run one benchmark at a time and avoid tests or builds alongside measurement. Never use live saves or run alongside the live VPS service without operator approval.

The runner imports the project, starts one server process, then ten independent client processes. It waits up to 30 seconds for all pilots, warms up for 15 engine seconds and measures 120 seconds by default. `--seconds` must be at least 30 and `--warmup` at least 1. Use at least 60 seconds to include a real UTC industry boundary. It enforces a completion timeout and cleans up only its own processes. Each process has its own `XDG_DATA_HOME` under the run directory. Logs, CPU/RSS samples, source hashes, environment, activity, traffic and timings remain there. A nonzero exit means checks failed; those measurements are diagnostic only. Successful runs close the disposable store cleanly and record shutdown timing.

## What runs

`tests/server_workload.gd` extends the existing ENet test fixture in `tests/network_test.gd`, also used by `tests/dedicated_server_test.gd`. Each process creates one sector with the same multiplayer root path and its own physics world. The dedicated sector contains no local pilot or render meshes. A physics-frame callback calls its existing `Sector._physics_process` at nominal 60 Hz. The benchmark does not accelerate ticks or override gameplay rules during measurement.

Each client receives normal roster, health, reward, snapshot and effect RPCs. At nominal 20 Hz it sends normal flight and fire intent using replicated positions and life/encounter identifiers. Pilots orbit about 65 m from their assigned living alien, steer toward loot within 100 m, and retreat toward the closest protected gate while their target is unavailable. Single-rocket requests occur every 2.1 seconds; Hellstorm load/fire requests every 6.2 seconds. Rejected requests retain ordinary validation. Boost flight is off. All twenty aliens retain normal collision, targeting, damage, death and respawn delays, including populations on empty maps.

Before warmup, the fixture equips ten Goliaths with ten SG3N-B02s, five G3N-7900s, HST-2, Slot CPU 1, Ammunition CPU, Generator Boost CPU, REP-2 and Repair Auto CPU. The spread scenario and single-map runs away from M1 fit fifteen LF-3s with x3; the M1 single-map scenario fits four LF-1s with x1 so home-map aliens survive long enough for both pilots and rockets to contribute. Each starts with 10 million disposable credits, 1,000 R-310s, 1,000 ECO-10s and ten duranium. CPUs are enabled; the ammo CPU buys the scenario's laser type. Initial map placement is a fixture teleport before warmup, followed by the normal map-change announcement. Immediately before measurement, selected ammo is set to 990 and checkpointed outside the window to exercise automatic resupply. No forced damage, accelerated industry clock or shortened cooldowns run during measurement. Starter level-1 Skylabs advance at real UTC minute boundaries. This is an upgraded hunting workload, not starter progression or continuous combat by all twenty aliens. Because fittings and encounter difficulty differ, the scenarios are not a controlled test of map partitioning alone.

The drivers replace human input and the normal client prediction loop. They still instantiate client scenes and receive effect RPCs, but `--headless` uses dummy rendering and the workload sets combat effects to Off on those clients. Client CPU and memory are excluded from server measurements, although all eleven processes compete for the same machine. This is a server load test, not rendered-client performance validation. The earlier effects-enabled spread run exposed a cosmetic `RocketEffect.look_at` precision error on M4; that presentation issue remains uncorrected and is outside these effects-Off measurements.

Checks require ten pilots to remain; each moves over 100 m, fires lasers and damages an alien. Aliens must fire and die with overlapping encounters; single rockets and Hellstorm must launch, rockets hit, pickups add cargo, industry checkpoint and change every lab's inventory, and extras commit supplies. Map membership is checked across the window. Distance includes rescue teleports; pickup units are positive cargo deltas. Results retain per-peer and per-alien activity, map pilot-ticks and industry inventories. Spawn locations and timing vary between runs.

## Measurement definitions

- CPU is Linux `/proc/PID/stat` user plus system CPU time divided by `CLOCK_MONOTONIC_RAW` elapsed time. 100% means one logical CPU fully occupied. Samples occur about once per second. September runs instead used monotonic time.
- RSS is `/proc/PID/status` resident memory in MiB. HWM is the process lifetime resident high-water mark, including startup and warmup. RSS includes engine and benchmark instrumentation allocations. It is not Godot's allocator-only memory counter.
- Session tick time wraps the server's existing physics callback with `Time.get_ticks_usec`. It includes flight, combat and periodic snapshot construction/sending. It excludes outer engine work and most multiplayer polling. The separate living-alien distribution selects ticks where the alien was alive before the callback, including the killing tick.
- Optional phase timers in `FlightSession` and `SessionCombat` record industry, flight, combat, snapshots and combat subpasses. They are disabled in normal sessions. Over-budget callback records retain the phases for that exact tick. These are elapsed times and can include OS scheduling pauses; a long phase alone does not establish its CPU cost.
- Tick interval uses the same Godot clock between callback starts. Catch-up ticks and scheduling jitter can affect it. `ticks_per_second` uses Godot elapsed time; `ticks_per_system_second` uses system Unix time over the same measurement window. The external sampler records both Linux monotonic and monotonic-raw clocks as another clock comparison. None of these rates are rendered FPS.
- Engine physics time is Godot's `Performance.TIME_PHYSICS_PROCESS`, read each tick. This monitor refreshes periodically, so repeated values are not independent per-tick timings. Its percentiles describe the sampled monitor values.

- Outbound traffic is actual IPv4 UDP datagrams captured on loopback with `AF_PACKET`, filtered by server source port and pilot destination port. Only the outgoing copy counts. Traffic includes ENet control/acknowledgements, gameplay RPCs and reliable fragmentation. IP bytes include IPv4/UDP headers; UDP payload bytes include ENet/Godot overhead. Neither includes Ethernet, Tailscale or internet overhead. ENet combines RPCs into datagrams, so RPC counts differ from packet counts. Dropped-frame captures fail validation.
- The server also records ENet host outbound bytes and packets, reset after warmup and read when measurement ends. They need no packet capture and include ENet retransmissions and fragmentation, but exclude IP/UDP headers. They cover the Godot measurement window and can cross-check the captured UDP payload.
- The test-only `benchmark_store.gd` adapter times unchanged `PilotStore.commit_combat` and `persist` calls. Journal timing includes debit validation, flush and verification. Checkpoints include serialization, backup, primary replacement and journal compaction, categorized as industry, loot, extras or economy. Economy includes rewards. Start timestamps permit comparison with callback stalls. Rocket-request persistence occurs in multiplayer polling and may fall outside the physics callback. Shutdown timing covers disconnect, boost flush and store close.

Percentiles use nearest rank. The server window excludes warmup. External samples and packet counter boundaries detect JSON markers with 0.1-second polling. Result serialization and scheduling can extend the external window; its raw-clock duration is recorded. Instrumentation, timing arrays and persistence events contribute memory and runtime overhead. There is no baseline subtraction. Compare system Unix and monotonic clocks before interpreting rates. The historical clock discrepancy below applies to those runs.

## Checks and attempts on 14 October

The two qualifying runs used the same engine and benchmark revision, sequentially. Both passed the workload activity checks, clean shutdown, all server/client log error checks and zero-drop packet capture. Startup collinear-up-vector warnings from alien patrol orientation still occurred; they were warnings, not failed calls in these runs.

| Run directory under `/home/linuxmossi/dorbit-benchmark-runs/` | Requested measurement | Outcome |
| --- | ---: | --- |
| `smoke-single-01` | 60 s | Startup failed before measurement because fixture rocket IDs were invalid; corrected and validation added |
| `smoke-single-02` | 60 s | Failed pilot/combat/rocket activity checks; capture also dropped two frames |
| `smoke-single-03` | 60 s | Passed the earlier fixture's activity, logs and capture checks; used for harness validation, not the final tables |
| `spread-01` | 120 s | Failed map membership after rescues; also exposed distant-map alien orientation error |
| `spread-02` | 120 s | Failed map membership before the window; retained diagnostic checkpoint stall |
| `spread-03` | 120 s | Passed activity/map/capture checks; runner rejected a client cosmetic rocket look-at error |
| `spread-04` | 120 s | Qualified; current spread tables and raw artifact |
| `single-map-01` | 120 s | Qualified; current M1 tables and raw artifact |
| `single-m4-01` | 120 s | 15 October validation of `--map 3` and ENet host counters from an uncommitted tree; passed all checks with ten pilots on M4. ENet bytes/packets matched captured UDP payload/datagrams within 0.05%. Not used in the tables |

Linux checks run with the same Godot executable passed: `tests/dedicated_server_test.gd` 44 assertions, `tests/connected_maps_test.gd` 440 assertions, `tests/combat_journal_test.gd` 34 assertions, and `tests/benchmark_server_test.py` three Python tests. Headless asset import, workload parse checks, Python compilation, JSON/source-hash validation, local document-link checks and `git diff --check` were also completed. The packet accounting tests are included in the Linux check suite.

VPS SSH used `BatchMode=yes` and an eight-second connection timeout to `dorbit-vps`; connection failed before any remote command ran. No service restart, production connection, deployment or save access occurred. Full Windows/Linux correctness suites, an exported-runtime performance run, rendered clients, injected internet conditions and longer sessions were not run. The VPS and isolated bare-metal Linux measurements could not be collected in this session. Local logs and disposable test saves remain in the run directories; public JSONs contain measurement summaries, not the pilot ledger or its credential verifiers.

## Diagnostic checkpoint stall

An earlier 120-second four-map attempt at `56be979` failed the intended map-membership check because a frontier pilot was rescued to M1 before measurement. Its [diagnostic raw result](docs/performance-diagnostic-spread-2026-10-14.json) is retained separately and is not a qualifying 3/3/2/2 capacity result. It captured a real synchronous save stall on the same WSL ext4 filesystem:

| Correlated operation | Duration |
| --- | ---: |
| Physics callback starting at Godot 153,324,068 µs | 102.784 ms |
| Loot/boost-flush phase in that callback | 102.431 ms |
| Loot checkpoint starting at 153,325,074 µs | 101.604 ms |
| Maximum backup replacement in this run | 99.535 ms |
| Checkpoint p95 over 103 commits | 3.513 ms |
| Maximum primary / journal replacement | 0.504 / 0.204 ms |

The callback exceeded the 16.7 ms budget by 6.2 times. The checkpoint occupied almost the entire callback; ordinary snapshot work did not run in that tick. Timings localize the delay to the backup replacement call, which includes write, flush, readback, close and rename. They do not distinguish slow storage from a scheduling pause during that call. No VPS conclusion follows from this WSL observation.

The smallest candidate mitigation is to combine simultaneous extras supply changes into one verified full checkpoint per combat pass, preserving commit-before-effects. That reduces repeated backup/primary replacements when several pilots resupply together. It cannot eliminate a slow individual replacement. Before changing persistence threading or guarantees, trace replacement substeps and repeat on an isolated Linux filesystem or an explicitly approved isolated VPS workload. No persistence or replication optimization is implemented in this PR.

The qualifying spread run also exceeded the tick budget without persistence. Its callback at Godot 129,023,480 µs took 28.443 ms, of which snapshot work took 27.531 ms; no timed save overlapped it. Snapshot p95 was 2.657 ms across all ticks, including ticks without a snapshot. Elapsed timing cannot separate snapshot CPU work, UDP-send delay and OS preemption. The smallest serialization change to test next is to build each alien's packed state once per snapshot and reuse it for viewers on that map. At 3/3/2/2, this would reduce `pack_alien` calls from 50 to 20 per snapshot while preserving the existing RPC format and owner packets. This is a candidate optimization, not a measured speedup or a guarantee that the outlier disappears. Profile construction and send time separately before pursuing broader packet batching.

## Historical baselines, September 2026

The sections below preserve the measurements and validation claims from their original revisions. Their workloads predate connected maps, rockets, industry, extras and the combat journal. Commands and source hashes here describe those revisions; the current runner above has a different workload.

### Single-alien results, 12 September 2026

Measured on 12 September 2026, from an independent Windows-owned worktree based on `origin/codex/dedicated-server` at `236f52437426b38a363acf608d51d20401c65b1b`. The committed [raw results](docs/performance-results.json) include the exact workload source hashes, environment and process samples. The captured dirty status records the benchmark files being developed on that base.

| Environment | Value |
| --- | --- |
| Host | Intel Core i7-13800H, 14 physical cores, 20 logical CPUs, about 64 GiB RAM |
| Host OS | Windows 11 Enterprise, build 26200 |
| Linux | Ubuntu 24.04.2 LTS, WSL2 kernel 5.15.167.4 |
| Linux resources | 20 logical CPUs visible, 31.2 GiB RAM, 8 GiB swap, no observed swap use |
| Engine | Official Godot 4.7.2 editor, `ed1daf0bf`, Linux x86-64, headless, max FPS 60 |
| Topology | One server plus ten clients in the same WSL instance, IPv4 loopback ENet UDP |
| Filesystem | Windows D: drive mounted at `/mnt/d`; source run, not an exported release server |
| Other activity | Normal Windows desktop and development tools remained running; no concurrent game tests/builds, CPU pinning or isolated host |

The completed smoke run and initial two-minute run passed the activity checks. The final two-minute run adds living-alien timing and clock comparison instrumentation; its measurements are reported below.

| Final run measurement | Result |
| --- | --- |
| Measurement window | 120.011 Godot seconds; 119.798 system Unix seconds |
| External sample window | 132.518 monotonic seconds; 120.471 monotonic-raw seconds |
| Server CPU, one logical CPU = 100% | Mean 3.49%; p95 4.98%; max 5.97%, using monotonic time |
| Server resident memory | Mean 110.55 MiB; sampled max and lifetime HWM 111.50 MiB |
| Simulation ticks | 7,201; 60.003 per Godot second; 60.109 per system Unix second |
| Session callback | Mean 0.399 ms; p95 1.120 ms; p99 1.641 ms; max 2.755 ms |
| Living-alien callbacks | 279 samples; mean 0.606 ms; p95 1.554 ms; p99 2.554 ms; max 2.755 ms |
| Callback interval, Godot clock | Mean 16.665 ms; p95 17.615 ms; p99 18.115 ms; max 19.217 ms |
| Engine physics monitor | Mean 1.603 ms; p95 2.372 ms; max 2.897 ms |
| Activity | Minimum roster 10; each pilot travelled 2,126 to 2,183 m and landed 9 to 18 hits |
| Combat | 153 player hits, 9 alien deaths, 9 alien shots; alien alive for 3.87% of ticks |

The clock discrepancy matters. Linux monotonic time advanced approximately 10% faster than monotonic-raw in both the workload and a separate two-second probe. In the final run, system Unix time was much closer to Godot elapsed time. Dividing the tick count by the slightly broader external monotonic window gives approximately 54.3 ticks/s. The same CPU-time delta divided by monotonic-raw time would give approximately 10% higher CPU utilization. These observations do not establish which clock matches physical elapsed time on this host, and the underlying cause was not investigated further. Do not interpret the nominal 60 Hz result as a validated wall-clock cadence or compare these timings directly with results from a different clock environment.

The benchmark and all ten client logs were free of Godot errors. The runner retained logs and intermediate data under `build/performance-run-2`; `docs/performance-results.json` preserves the final measurements and environment for review. `bash tools/server.sh check` passed all 43 dedicated-server checks. Python syntax, result JSON and source-hash checks passed. The runner rejected an invalid duration and an existing output directory before launching processes.

### Limits of the single-alien baseline

Ten pilots rapidly kill the current single alien, followed by its normal respawn delay. Whole-window averages therefore describe movement, replication and brief combat bursts. The living-alien timing distribution helps expose those bursts, but this is not sustained combat with many aliens.

These short local runs cannot establish VPS sizing, long-term memory stability, internet behavior, or performance for ten rendered Windows clients. No latency, loss or bandwidth constraints are injected. The host differs from the game's Ryzen 7 5800X reference PC. A separate rendered measurement on reference hardware at 1440p and a representative multi-machine encounter are still needed.

No optimizations are implemented here. Before changing code, profile snapshot serialization and replication separately from movement and combat, and compare a dedicated machine against this shared WSL host. If a future approved encounter adds more aliens, rerun with that content and sustained combat before choosing a server capacity target. The current results alone do not identify a production bottleneck.

### Five-alien results, 13 September 2026

The updated workload assigns two pilots to each of two Scouts, two Sentinels and one Heavy. Raw measurements and source hashes are in [alien-performance-results.json](docs/alien-performance-results.json). The host is the same i7-13800H Windows laptop and Ubuntu WSL2 environment as the baseline. This run uses the current persistent credit ledger and the normal per-type respawn delays.

| Measurement | Result |
| --- | --- |
| Window | 120.011 Godot seconds; 120.096 system seconds |
| Server callback | Mean 0.427 ms; p95 1.116 ms; p99 1.522 ms; max 10.745 ms |
| Server CPU, one core = 100% | Mean 3.44%; p95 4.98%; max 6.97%, using Linux monotonic time |
| Server RSS | Mean 114.74 MiB; max and lifetime HWM 115.94 MiB |
| Simulation | 7,201 ticks; 59.96 per system second |
| Activity | All ten pilots landed 39 to 114 hits; all five slots died and respawned |
| Combat | 611 player hits; 176 alien shots; 40 alien deaths |
| Overlap | At least two engaged living aliens on 31.44% of ticks; at least one living alien on 63.67% |

The WSL clock discrepancy persists: the external window was 130.217 monotonic seconds and 120.198 monotonic-raw seconds. CPU percentages use the former, so they understate utilization relative to the raw clock. Callback durations and simulation rate are separate measurements, not rendered FPS. These results do not establish VPS capacity or internet performance.

The executable on the Windows-mounted drive initially exceeded the runner's startup deadline. The completed run used the same Godot 4.7.2 executable copied to Linux storage, selected with the new optional --engine argument. The source project remained in the Windows worktree. The failed startup attempt produced no measurement.

#### Rendered client inspection

A separate Windows run uses tests/alien_sector_playthrough.gd for one visible client, plus nine headless tests/server_workload.gd clients and one headless dedicated workload server. All use port 24683, one shared new output directory, --seconds=60 and --warmup=15. Start the server with --role=server, then clients with --role=client and distinct --index=0 through --index=9. The rendered script replaces the workload script only for index 0; omit --headless on that process. Stop the owned processes after rendered-client.json and rendered-sector.png appear. This retains the ordinary server combat and replication but drives input automatically.

The rendered viewport is 1440 by 900 with 4x MSAA, GL Compatibility and default VSync. The GPU is NVIDIA RTX A500 Laptop GPU. This is not the Ryzen/Radeon reference hardware or a 1440p target validation. All eleven processes share the laptop. Godot viewport images were inspected directly because the native computer-use helper failed to connect after retries. A separate frozen lineup confirmed Scout, Sentinel and Heavy placeholder shapes, colors and markers; it is visual inspection, not gameplay or performance evidence.

The final rendered run averaged 60.04 FPS over 60.061 wall-clock seconds, with frame intervals of 17.405 ms at p95, 18.050 ms at p99 and 79.298 ms maximum. Frame intervals use Time.get_ticks_usec rather than Godot's supplied delta, which was fixed in the initial run. Sampling includes fixture overhead and one mid-run screenshot. Default VSync limits this result; the maximum shows that occasional stalls still occurred. The renderer consumes current alien and remote-pilot snapshots and receives ordinary laser effects. [Raw rendered results](docs/alien-rendered-results.json) also preserve the separate Windows server timings from this run. They are not the Linux server measurements above. All ten pilots hit aliens and all five slots died in the rendered run.

Departure and combat captures showed the current sector's alien markers, selected-target health, returning state and weapon effects. Crowded off-screen teammate labels can overlap. Provisional combat tuning still needs human starter-ship and upgraded/group playtesting. No internet latency or packet loss was injected.

### Validation for the alien slice

Godot 4.7.2 passed 265 checks across the new alien-sector suite and existing network, shared-combat, dedicated-server, pilot-persistence, offline encounter and connection-menu suites. The 54 new checks include independent live fire, separate contributions, equal rewards including rescue eligibility, stale/unknown target rejection, ordinary and blocked returns, death and empty-sector respawns, late joins, reordered snapshots, Tab cycling and ray selection. The Linux runner and rendered workload both enforce activity checks. The full Windows check command also passed the starter hunt-and-repair replay. The new 54-check suite passed on Linux. Source import, Windows release export, Python syntax and git diff checks passed.

The optional legacy two-process listen-host replay timed out before the two processes joined on this host. Its Scout steering and reward expectations were updated, but that end-to-end replay and the manual two-client Windows-to-Linux replay remain unverified. The required Windows check command, new real-ENet suites and separate-process dedicated workloads passed.
