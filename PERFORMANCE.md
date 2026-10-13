# Dedicated server performance workload

The current benchmark measures one Linux dedicated server with ten automated headless clients, all four maps and twenty alien slots, laser fire, single rockets and launcher volleys. See the [13 October results](#current-content-results-13-october-2026). September results below describe older content. The original single-alien measurements remain below as a historical baseline. It does not measure rendered client FPS or validate the 60 FPS at 1440p target. Cross-network dedicated-server testing remains pending and is independent of this workload.

## Reproduce

Use a Linux x86-64 checkout with Python 3, curl and the pinned Godot editor. From the repository root:

```sh
rtk proxy bash tools/server.sh setup
rtk proxy python3 tools/benchmark_server.py --layout clustered --map 3 --seconds 120 --output build/capacity-frontier-01
rtk proxy python3 tools/benchmark_server.py --layout spread --seconds 240 --output build/capacity-spread-01
rtk proxy bash tools/server.sh check
```

RTK is a command wrapper, not a benchmark dependency. For a Windows-owned Git worktree under WSL2, run from PowerShell:

```powershell
rtk proxy wsl -e bash -lc 'cd /mnt/d/Dorbit-performance && python3 tools/benchmark_server.py --git git.exe --seconds 120 --warmup 15 --output build/performance-01'
```

Change the path to your checkout. `git.exe` handles the Windows paths in that worktree's `.git` file. Use the default `git` in a Linux-owned checkout. The output directory must be new, so a later run cannot overwrite earlier results. UDP port 24683 must be free. Run one benchmark at a time and avoid running tests or builds alongside it.

The runner imports the project, starts one server process, then ten independent client processes. It waits up to 30 seconds for all pilots to join, warms up for 15 engine seconds and measures for 120 engine seconds by default. `--seconds` must be at least 30 and `--warmup` at least 1. It enforces a completion timeout and cleans up only its own processes on success, failure or Ctrl+C. Logs, per-process CPU/RSS samples, source hashes, environment details and summaries remain in the output directory. A nonzero exit means the workload or its checks failed; retained measurements from such a run are diagnostic evidence only.

## What runs

`tests/server_workload.gd` extends the existing ENet test fixture in `tests/network_test.gd`, also used by `tests/dedicated_server_test.gd`. Each process creates one sector with the same multiplayer root path and its own physics world. The dedicated sector contains no local pilot or render meshes. A physics-frame callback calls its existing `Sector._physics_process` at the project's nominal 60 Hz; the benchmark does not accelerate ticks.

Each client receives normal roster, health, reward, snapshot and effect RPCs. At a nominal 20 Hz it sends normal flight and fire intent, using the replicated position and current life/encounter identifiers. In clustered mode, two pilots pursue each alien slot on the selected zero-based --map, which defaults to M1. In spread mode, pilots start across M1 through M4 in groups of 3, 3, 2 and 2 and advance to the next living alien slot after their current target dies. M3 and M4 pilots pair on a shared target for the stronger encounters. Pilots pursue phase-offset orbits approximately 100 m from their target, with vertical movement. The driver closes within 110 m before firing lasers. Clustered mode enables lasers only in the second half of its 2.1-second single-rocket request cycle; spread mode uses continuous laser fire. This lets rockets launch before the fitted lasers kill weaker targets. They request a single rocket every 2.1 seconds and load/fire a five-round launcher at ordinary cooldowns. All twenty aliens retain their normal tuning, collision checks, damage, rewards and respawn delays. Boost is off during combat and on during return travel after a rescue.

Before authentication, the fixture persists ten legal Goliaths with fifteen LF-3 lasers, fifteen SG3N-B02 shields, an HST-2 launcher and 100,000 rounds of each ammunition type. Clients select x3 lasers and retain the default R-310/ECO-10 rockets. Once clients launch through the normal RPC, the fixture places each pilot near its first assigned encounter before warmup. There are no fixture teleports, forced damage, health resets or shortened cooldowns during measurement. Ordinary rescues return pilots to M1; drivers fly to gates and request normal jumps to return to their assigned map. This is an equipped-fleet workload, not starter-ship balance validation. Current Skylab records and snapshot serialization are present; no industry jobs are started.

The drivers replace human input and the normal client prediction loop. They still instantiate client scenes and receive effect RPCs, but `--headless` uses dummy rendering. Client CPU and memory are excluded from server process measurements, although all eleven processes compete for the same machine. This is a server load test, not a normal rendered-client performance test.

The workload fails unless ten pilots remain throughout measurement, each records over 100 m of position changes and damages an alien, every assigned slot receives hits and dies, aliens fire, and at least two encounters overlap. Clustered mode checks all five slots on its map; spread mode checks all twenty. Every pilot must launch rockets, with launcher rounds and successful impacts in the window, and the combat journal must remain healthy. Distance sums authoritative position changes, including rescue and gate teleports. Results retain per-map combat ticks, per-pilot hits and rockets, per-slot deaths and journal sequence. Peer IDs and timings vary between runs; this is not a deterministic replay.

## Measurement definitions

- ENet outbound bytes and packets come from the server ENet host counters, reset after warmup and read at the end of measurement. They include ENet protocol traffic, fragmentation and retransmissions. They exclude IP/UDP and link-layer overhead. Aggregate rates divide by the Godot measurement window; they are not per-second peak bandwidth.
- CPU is Linux `/proc/PID/stat` user plus system CPU time divided by monotonic elapsed time. 100% means one logical CPU fully occupied. Current results also retain percentages using monotonic-raw time. The runner samples approximately once per second, separately from the clients.
- RSS is `/proc/PID/status` resident memory in MiB. HWM is the process lifetime resident high-water mark, including startup and warmup. RSS includes engine and benchmark instrumentation allocations. It is not Godot's allocator-only memory counter.
- Session tick time wraps the server's existing physics callback with `Time.get_ticks_usec`. It includes flight, combat and periodic snapshot construction/sending. It excludes outer engine work and most multiplayer polling. The separate living-alien distribution selects ticks where at least one world alien was alive before the callback, including the killing tick.
- Tick interval uses the same Godot clock between callback starts. Catch-up ticks and scheduling jitter can affect it. `ticks_per_second` uses Godot elapsed time; `ticks_per_system_second` uses system Unix time over the same measurement window. The external sampler records both Linux monotonic and monotonic-raw clocks as another clock comparison. None of these rates are rendered FPS.
- Engine physics time is Godot's `Performance.TIME_PHYSICS_PROCESS`, read each tick. This monitor refreshes periodically, so repeated values are not independent per-tick timings. Its percentiles describe the sampled monitor values.

Percentiles use the nearest-rank method. The server window excludes warmup. External CPU/RSS sampling detects the start marker within about 0.1 seconds and the end within about 1 second under normal scheduling. Its window can also differ from Godot elapsed time when the clocks disagree, as observed below. Instrumentation records timings and distances every tick and receives combat signals; its overhead is included. There is no uninstrumented baseline subtraction. System Unix time can be adjusted; compare it against the monotonic sample window before interpreting the rate.

## Single-alien results, 12 September 2026

Measured on 12 September 2026, from an independent Windows-owned worktree based on `origin/codex/dedicated-server` at `236f52437426b38a363acf608d51d20401c65b1b`. The committed [raw results](performance-results.json) include the exact workload source hashes, environment and process samples. The captured dirty status records the benchmark files being developed on that base.

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

The benchmark and all ten client logs were free of Godot errors. The runner retained logs and intermediate data under `build/performance-run-2`; `performance-results.json` preserves the final measurements and environment for review. `bash tools/server.sh check` passed all 43 dedicated-server checks. Python syntax, result JSON and source-hash checks passed. The runner rejected an invalid duration and an existing output directory before launching processes.

## Limits of the single-alien baseline

Ten pilots rapidly kill the current single alien, followed by its normal respawn delay. Whole-window averages therefore describe movement, replication and brief combat bursts. The living-alien timing distribution helps expose those bursts, but this is not sustained combat with many aliens.

These short local runs cannot establish VPS sizing, long-term memory stability, internet behavior, or performance for ten rendered Windows clients. No latency, loss or bandwidth constraints are injected. The host differs from the game's Ryzen 7 5800X reference PC. A separate rendered measurement on reference hardware at 1440p and a representative multi-machine encounter are still needed.

No optimizations are implemented here. Before changing code, profile snapshot serialization and replication separately from movement and combat, and compare a dedicated machine against this shared WSL host. If a future approved encounter adds more aliens, rerun with that content and sustained combat before choosing a server capacity target. The current results alone do not identify a production bottleneck.

## Five-alien results, 13 September 2026

The updated workload assigns two pilots to each of two Scouts, two Sentinels and one Heavy. Raw measurements and source hashes are in [alien-performance-results.json](alien-performance-results.json). The host is the same i7-13800H Windows laptop and Ubuntu WSL2 environment as the baseline. This run uses the current persistent credit ledger and the normal per-type respawn delays.

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

### Rendered client inspection

A separate Windows run uses tests/alien_sector_playthrough.gd for one visible client, plus nine headless tests/server_workload.gd clients and one headless dedicated workload server. All use port 24683, one shared new output directory, --seconds=60 and --warmup=15. Start the server with --role=server, then clients with --role=client and distinct --index=0 through --index=9. The rendered script replaces the workload script only for index 0; omit --headless on that process. Stop the owned processes after rendered-client.json and rendered-sector.png appear. This retains the ordinary server combat and replication but drives input automatically.

The rendered viewport is 1440 by 900 with 4x MSAA, GL Compatibility and default VSync. The GPU is NVIDIA RTX A500 Laptop GPU. This is not the Ryzen/Radeon reference hardware or a 1440p target validation. All eleven processes share the laptop. Godot viewport images were inspected directly because the native computer-use helper failed to connect after retries. A separate frozen lineup confirmed Scout, Sentinel and Heavy placeholder shapes, colors and markers; it is visual inspection, not gameplay or performance evidence.

The final rendered run averaged 60.04 FPS over 60.061 wall-clock seconds, with frame intervals of 17.405 ms at p95, 18.050 ms at p99 and 79.298 ms maximum. Frame intervals use Time.get_ticks_usec rather than Godot's supplied delta, which was fixed in the initial run. Sampling includes fixture overhead and one mid-run screenshot. Default VSync limits this result; the maximum shows that occasional stalls still occurred. The renderer consumes current alien and remote-pilot snapshots and receives ordinary laser effects. [Raw rendered results](alien-rendered-results.json) also preserve the separate Windows server timings from this run. They are not the Linux server measurements above. All ten pilots hit aliens and all five slots died in the rendered run.

Departure and combat captures showed the current sector's alien markers, selected-target health, returning state and weapon effects. Crowded off-screen teammate labels can overlap. Provisional combat tuning still needs human starter-ship and upgraded/group playtesting. No internet latency or packet loss was injected.

## Validation for the alien slice

Godot 4.7.2 passed 265 checks across the new alien-sector suite and existing network, shared-combat, dedicated-server, pilot-persistence, offline encounter and connection-menu suites. The 54 new checks include independent live fire, separate contributions, equal rewards including rescue eligibility, stale/unknown target rejection, ordinary and blocked returns, death and empty-sector respawns, late joins, reordered snapshots, Tab cycling and ray selection. The Linux runner and rendered workload both enforce activity checks. The full Windows check command also passed the starter hunt-and-repair replay. The new 54-check suite passed on Linux. Source import, Windows release export, Python syntax and git diff checks passed.

The optional legacy two-process listen-host replay timed out before the two processes joined on this host. Its Scout steering and reward expectations were updated, but that end-to-end replay and the manual two-client Windows-to-Linux replay remain unverified. The required Windows check command, new real-ENet suites and separate-process dedicated workloads passed.

## Current-content results, 13 October 2026

The finalized workload passed two separate Linux runs with ten authenticated pilots, all four maps and twenty world alien slots. The clustered run put two pilots on each M4 encounter; the spread run exercised and killed all twenty slots across M1 through M4. Every pilot moved, damaged an alien and launched rockets in both measurement windows. These are activity checks, not a latency or tick-budget pass criterion.

[Raw results](current-server-performance-results.json) retain process samples, source hashes, environment details and log hashes/counts. Both completed runs match the committed workload sources. The source base was `f004c486987bf234a067662266eb7ec9870bd2c4` with the benchmark changes recorded in dirty status. The host is an AMD Ryzen 7 9800X3D with 16 logical CPUs visible to Ubuntu 24.04.4 on WSL2 kernel 6.6.87.2 and 15.18 GiB Linux memory. Godot is the pinned official 4.7.2 Linux editor. The executable and isolated pilot saves are on Linux storage; the source checkout is on Windows C:. All eleven processes share the host, with ordinary desktop/development activity and no CPU pinning. This differs from the September laptop, so changes in timings are not a controlled before/after comparison.

| Measurement | Ten pilots clustered on M4 | Ten pilots spread over four maps |
| --- | --- | --- |
| Activity checks | Passed | Passed |
| Godot / system window, seconds | 120.014 / 120.236 | 240.006 / 239.374 |
| CPU mean / p95, % of one logical CPU, raw clock | 7.36 / 12.82 | 5.42 / 11.44 |
| RSS mean / maximum, MiB | 179.80 / 179.80 | 180.10 / 180.10 |
| Session mean / p95 / p99 / maximum, ms | 0.709 / 1.526 / 1.964 / 7.109 | 0.696 / 1.397 / 1.838 / 51.131 |
| Maximum callback interval, ms | 17.836 | 96.138 |
| Ticks per system second | 59.89 | 60.16 |
| Aggregate ENet outbound, Mbit/s / packets/s | 12.52 / 3236 | 6.47 / 2022 |
| Alien slots hit / killed | 5 / 5 | 20 / 20 |
| Alien deaths / shots | 10 / 127 | 38 / 90 |
| Rocket rounds / launcher rounds / successful impacts | 119 / 105 / 109 | 349 / 335 / 221 |
| Ticks with overlapping engaged aliens | 24.04% | 5.44% |
| Godot warnings in server log | 25 | 53 |

CPU percentages above use monotonic-raw time. External monotonic windows were approximately 3% shorter than their raw-clock windows. Both clocks and the original monotonic CPU percentages remain in the JSON. The nominal physics rate does not establish rendered FPS or a validated physical 60 Hz cadence. At least one of the twenty aliens was alive on every tick, so the living-alien distribution equals the whole-window distribution. Per-map combat ticks and overlap fractions show that this is bursty hunting with ordinary travel and respawns, rather than continuous combat for the entire window. Some pilots were rescued to M1 and flew back through normal gates, reducing clustered fan-out during those periods.

The completed spread run had a 51.131 ms session callback and a 96.138 ms callback interval. An earlier spread attempt with timed target rotation had a 148.713 ms callback. That attempt failed coverage and remains explicitly labeled diagnostic in the raw JSON; it is not capacity evidence. A finalized-driver M1 attempt also failed the overlap check despite every pilot hitting and launching rockets and every home slot dying. Its diagnostic counters recorded 13.79 Mbit/s and about 3,495 outbound packets/s, consistent with the review's fan-out estimate. M4 supplies stronger encounters for the validated clustered test. Early 30-second smoke attempts and the first cold import failed before representative coverage; they are excluded from the validated tables. No gameplay tuning or server optimization was changed to obtain coverage.

All final client, server and import logs were free of Godot errors. The server emitted the existing alien `looking_at` colinear-vector warnings, with counts above; this logging overhead is included. Logs and intermediate files remain under `build/capacity-frontier-01` and `build/capacity-spread-03`. Python syntax, raw JSON, final source hashes, invalid-duration rejection, existing-output rejection and diff checks passed.

Average CPU and memory on this host leave local compute headroom for ten pilots at current content. Outbound traffic is material, and the observed stalls exceed the 16.7 ms tick budget. These runs therefore do not establish smooth ten-player internet service or VPS capacity. Before the friend-group session, check the actual deployment's sustained upload headroom and profile the callback stalls on that host. A longer soak, injected latency/loss, active Skylab jobs and rendered Windows-client performance remain unmeasured.

To reproduce the validated scenarios after setup, using fresh output directories:

```sh
rtk proxy python3 tools/benchmark_server.py --layout clustered --map 3 --seconds 120 --warmup 15 --output build/capacity-frontier-01
rtk proxy python3 tools/benchmark_server.py --layout spread --seconds 240 --warmup 15 --output build/capacity-spread-03
```

For a Windows-owned worktree in WSL, also pass `--git git.exe` and select a Linux-storage executable with `--engine`. Cold asset imports may take several minutes; the runner retains `import.log` and allows up to ten minutes for import before launching the workload.
