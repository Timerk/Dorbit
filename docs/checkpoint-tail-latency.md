# Checkpoint tail latency follow-up, 19 October 2026

Status (updated 20 October): extras resupply batching implemented; measurement
blocked and synchronous checkpoint risk remains open. No new latency improvement
has been measured. The historical 101.604 ms checkpoint and
99.535 ms backup replacement in PERFORMANCE.md are observations of an older WSL
source run, not current exported-server or VPS results.

## Environment blocker and scope

This worktree is on Windows. `wsl -l -v` reports no installed Linux distributions.
No disposable Linux execution/storage environment is
available here. The parent's pinned Windows Godot 4.7.2 console executable is used
read-only with this worktree's own imports for correctness checks. No Linux
capture, p95/p99/max performance result, exported runtime, VPS capacity conclusion,
production access or deployment is claimed.

The existing `benchmark_server.py` launches the editor with a test script, rather
than the shipped dedicated executable. Production export presets exclude tests.
An exported benchmark harness remains a prerequisite for the requested exported
server measurement: simply passing the production binary as `--engine` does not
include this workload. Keep future source and exported results labeled separately.

## Instrumentation and checked workload

`PilotStore.replacement_trace` is empty in normal sessions: there are no clock
reads, sample appends or observer calls. Replacement adds conditional branches,
but keeps write, flush, same-handle readback, close and atomic rename in their
original order. Failure still stops effects and preserves original/temporary
evidence. The test-only adapter enables the observer and records open, UTF-8
encoding, write, flush (including error retrieval), readback, close and rename.
Every successful replacement has adjacent timestamp boundaries, its reason,
destination category and success flag. Readback failures omit rename; open
failures have no completed trace. Full replacement/checkpoint wrappers include
observer overhead; substep samples exclude the observer's aggregation work.
Elapsed timing includes preemption and cannot identify storage CPU cost alone.

Before measurement, all ten fixture CPUs are made due together and selected
ammo is set below the existing resupply threshold. The measured window must
actually contain multiple pilots resupplying in one callback; the pilot count,
checkpoint count, start and callback duration are retained. Before batching this
required multiple checkpoints; after batching the same pass needs just one.
The report accepts historical artifacts without the new pilot count. Industry
still uses real UTC time,
with every lab required to advance and change inventory. No clock acceleration
or measured-window teleport/damage injection is added. A single slow replacement
can still block the simulation after batching extras.

On an available disposable Linux host, first inspect both host and guest process
lists for competing Godot imports, games, tests and builds. Coordinate a quiet
window with other implementers; retain the process inventory and repeat the
inspection immediately before capture. Do not call a busy run representative.
Use a new Linux-native output directory, a unique `DORBIT_TEST_PORT_OFFSET`,
and the existing runner's per-process disposable profiles. Run sequentially:

```sh
rtk proxy python3 tools/benchmark_server.py --scenario single-map --seconds 120 --warmup 15 --output /var/tmp/dorbit-checkpoint-single-01
rtk proxy python3 tools/checkpoint_report.py /var/tmp/dorbit-checkpoint-single-01/results.json
rtk proxy python3 tools/benchmark_server.py --scenario spread --seconds 120 --warmup 15 --output /var/tmp/dorbit-checkpoint-spread-01
rtk proxy python3 tools/checkpoint_report.py /var/tmp/dorbit-checkpoint-spread-01/results.json
```

Packet capture needs root or CAP_NET_RAW. These commands use the source/editor
workload. Retain the runner exit status and check every log: a JSON file alone
does not certify a successful runner or a quiet machine. The report rejects
missing substeps, failed replacements, failed activity/shutdown/capture checks,
missing simultaneous extras and missing industry evidence. It emits nearest-rank
p95/p99/max per replacement category/substep plus existing checkpoint/callback
distributions, activity, clock comparisons and the runner's hardware, engine,
filesystem, source hashes and runtime command identity. It does not certify host
isolation, logs, clock accuracy or exported-runtime coverage.

Remaining work is an isolated Linux source capture, an explicitly identified
exported benchmark harness/capture for both scenarios, and evaluation of any
reproduced outlier. None requires live service or VPS modification. No production
operational change is part of this PR.

## Batched supplies and ordering

`SessionCombat.tick` prepares pilots' timers, rescue and repair, then gathers due
extras updates on copies and issues one `PilotStore.commit` for the pass. Only
after success does it apply credits, ammo, cargo, boosts and fitting stats or send
owner RPCs. Failure uses the existing immediate simulation stop and exit path.
Pilot firing follows this boundary, so journal debits cannot be overwritten by
staged supplies; checkpoint invalidation forces the next debit to verify the new
pair. Loot already batches separately and sees the resulting cargo. Pending
contract payouts also batch before supplies. Individual kill rewards remain
synchronous because later pilots can observe the kill and its new encounter state.
Scheduled industry already batches all labs. Station requests retain their
individual revision-protected transaction boundaries.
No `PilotStore` implementation change is needed.

`tests/extras_batch_test.gd` observes live state inside real checkpoint I/O with
three authenticated pilots, checks one checkpoint and post-commit effects, replays
subsequent journal debits, and forces a backup-write failure in a child server
process to verify exit before effects. It also checks batched pending payouts and
loot preserving automatic cargo costs. The benchmark counts resupplied pilots
separately from checkpoints. These are correctness checks, not latency results.

Before/after Linux measurements were not collected. Follow up on disposable Linux
storage using the commands above, retaining separate baseline and batched revisions.
An isolated VPS capture needs explicit operator approval; no live VPS or production
saves are part of this work.

## Batching correctness validation, 20 October

After importing with the pinned Windows Godot 4.7.2, the full
`python tools/check-game.py <engine> --suite windows --workers 3` run completed
64 commands in 301 seconds: 62 passed, while RPC compatibility and dedicated-server
checks failed to bind UDP ports during concurrent suites in other worktrees.
Both passed when rerun with disposable profiles and separate port offsets (16 and
44 assertions). No other processes were stopped. The original run passed pilot
persistence (37), combat journal (50), extras (130) and extras batching (29),
including the child-process failure-stop assertion. All 64 commands therefore
have passing results, with the two environmental retries recorded separately in
`build/validation/checks-windows-retry.json` alongside `checks-windows.json`.

The workload's `--check-only` parse, four checkpoint-report tests, fourteen
CI-performance tests and `git diff --check` also pass. These checks do not measure
Linux tail latency, exported runtime performance or VPS capacity.

## Historical correctness validation, 19 October

The pinned Windows engine passes `tests/checkpoint_trace_test.gd` (real successful
and failed replacements, disabled observer, substep boundaries, full adapter
commit including research, and reopening the committed ledger) and the workload's
`--check-only` parse. `python tests/checkpoint_report_test.py` passes three tests;
`python tests/ci_performance_test.py` passes fourteen tests. New trace/report checks
are registered in both platform manifests. These are correctness checks, not
measurements of a ten-client server's performance. Full platform suites and the
Linux socket accounting tests were not rerun for this narrow instrumentation change.
