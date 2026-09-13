# Dedicated server performance workload

This benchmark measures one Linux dedicated server with ten automated headless clients in the existing single-alien sector. It does not measure rendered client FPS or validate the 60 FPS at 1440p target. Cross-network dedicated-server testing remains pending and is independent of this workload.

## Reproduce

Use a Linux x86-64 checkout with Python 3, curl and the pinned Godot editor. From the repository root:

```sh
rtk proxy bash tools/server.sh setup
rtk proxy python3 tools/benchmark_server.py --output build/performance-01
rtk proxy bash tools/server.sh check
```

RTK is a command wrapper, not a benchmark dependency. For a Windows-owned Git worktree under WSL2, run from PowerShell:

```powershell
rtk proxy wsl -e bash -lc 'cd /mnt/d/Dorbit-performance && python3 tools/benchmark_server.py --git git.exe --seconds 120 --warmup 15 --output build/performance-01'
```

Change the path to your checkout. `git.exe` handles the Windows paths in that worktree's `.git` file. Use the default `git` in a Linux-owned checkout. The output directory must be new, so a later run cannot overwrite earlier results. UDP port 24683 must be free. Run one benchmark at a time and avoid running tests or builds alongside it.

The runner imports the project, starts one server process, then ten independent client processes. It waits up to 30 seconds for all pilots to join, warms up for 15 engine seconds and measures for 120 engine seconds by default. `--seconds` must be at least 30 and `--warmup` at least 1. It enforces a completion timeout and cleans up only its own processes on success, failure or Ctrl+C. Logs, per-process CPU/RSS samples, source hashes, environment details and summaries remain in the output directory. A nonzero exit means the workload or its checks failed; retained measurements from such a run are diagnostic evidence only.

## What runs

`tests/server_workload.gd` extends the existing ENet test fixture in `tests/network_test.gd`, also used by `tests/dedicated_server_test.gd`. Each process creates one sector with the same multiplayer root path and its own physics world. The dedicated sector contains no local pilot or render meshes. A physics-frame callback calls its existing `Sector._physics_process` at the project's nominal 60 Hz; the benchmark does not accelerate ticks or alter gameplay state.

Each client receives normal roster, health, reward, snapshot and effect RPCs. At a nominal 20 Hz it sends normal flight and fire intent, using the replicated position and current life/encounter identifiers. Pilots pursue phase-offset orbits approximately 100 m from the alien, with vertical movement, and fire whenever it is alive. Boost is off. The server retains ordinary collision checks, weapon cooldowns, damage, death, rewards and the 12-second alien respawn delay. No teleports, forced damage or shortened cooldowns create the encounter.

The drivers replace human input and the normal client prediction loop. They still instantiate client scenes and receive effect RPCs, but `--headless` uses dummy rendering. Client CPU and memory are excluded from server process measurements, although all eleven processes compete for the same machine. This is a server load test, not a normal rendered-client performance test.

The workload fails unless ten pilots remain throughout measurement, each travels over 100 m and damages the alien, and the alien fires and dies. Distance sums authoritative position changes, including any ordinary rescue teleport. It records hits per peer, alien shots/deaths and the fraction of ticks with a living alien. Peer IDs and exact timings vary between runs; the workload is repeatable, not a deterministic replay.

## Measurement definitions

- CPU is Linux `/proc/PID/stat` user plus system CPU time divided by monotonic elapsed time. 100% means one logical CPU fully occupied. The runner samples approximately once per second, separately from the clients.
- RSS is `/proc/PID/status` resident memory in MiB. HWM is the process lifetime resident high-water mark, including startup and warmup. RSS includes engine and benchmark instrumentation allocations. It is not Godot's allocator-only memory counter.
- Session tick time wraps the server's existing physics callback with `Time.get_ticks_usec`. It includes flight, combat and periodic snapshot construction/sending. It excludes outer engine work and most multiplayer polling. The separate living-alien distribution selects ticks where the alien was alive before the callback, including the killing tick.
- Tick interval uses the same Godot clock between callback starts. Catch-up ticks and scheduling jitter can affect it. `ticks_per_second` uses Godot elapsed time; `ticks_per_system_second` uses system Unix time over the same measurement window. The external sampler records both Linux monotonic and monotonic-raw clocks as another clock comparison. None of these rates are rendered FPS.
- Engine physics time is Godot's `Performance.TIME_PHYSICS_PROCESS`, read each tick. This monitor refreshes periodically, so repeated values are not independent per-tick timings. Its percentiles describe the sampled monitor values.

Percentiles use the nearest-rank method. The server window excludes warmup. External CPU/RSS sampling detects the start marker within about 0.1 seconds and the end within about 1 second under normal scheduling. Its window can also differ from Godot elapsed time when the clocks disagree, as observed below. Instrumentation records timings and distances every tick and receives combat signals; its overhead is included. There is no uninstrumented baseline subtraction. System Unix time can be adjusted; compare it against the monotonic sample window before interpreting the rate.

## Results

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

## Limits and suggested follow-up

Ten pilots rapidly kill the current single alien, followed by its normal respawn delay. Whole-window averages therefore describe movement, replication and brief combat bursts. The living-alien timing distribution helps expose those bursts, but this is not sustained combat with many aliens.

These short local runs cannot establish VPS sizing, long-term memory stability, internet behavior, or performance for ten rendered Windows clients. No latency, loss or bandwidth constraints are injected. The host differs from the game's Ryzen 7 5800X reference PC. A separate rendered measurement on reference hardware at 1440p and a representative multi-machine encounter are still needed.

No optimizations are implemented here. Before changing code, profile snapshot serialization and replication separately from movement and combat, and compare a dedicated machine against this shared WSL host. If a future approved encounter adds more aliens, rerun with that content and sustained combat before choosing a server capacity target. The current results alone do not identify a production bottleneck.
