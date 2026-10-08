# Combat persistence

Schema 8 retains schema 7's pilot records and adds a combat journal so ordinary
laser volleys, rocket launches and timed-boost saves do not copy and rewrite every
pilot's equipment, cargo and industry. Each debit remains synchronous: the server
appends, flushes and verifies the record before consuming ammunition or applying
damage. Laser ammunition and all active resource reserves share one record.
Cooldown, target validation, damage ordering and rejected-shot costs are unchanged.

## Snapshot and journal

`pilots.json` contains `version: 8`, `pilots`, and `combat_journal` metadata with a
random 32-character hexadecimal `id` and integer `sequence`. The required
`pilots.json.combat` is UTF-8, with one JSON value per line and a final newline:

- The first line is the same metadata at the journal's compaction boundary.
- Each later line is `[body, sha256(body)]`, where `body` is a JSON string containing
  `sequence`, `ammo` and `boosts`. Updates replace only those fields for known pilots.
- Sequences are contiguous and belong to that snapshot's journal ID. Replay applies
  only records newer than the snapshot sequence. Checksums detect accidental damage;
  directory permissions and the existing exclusive lock protect ownership.

Startup validates the complete pair before admission. Incomplete records, invalid
updates, checksum failures, missing files and mismatched IDs or sequences fail
closed and preserve the files. No damaged tail is silently discarded.

The store retains the append handle to avoid repeated file-open latency. The
synchronous pilot combat pass verifies the snapshot and journal once, then flushes
and reads back each new record individually before its volley. Independent rocket
requests and timed-boost saves verify the pair themselves. Full snapshot writes
invalidate this shared check. No asynchronous task can publish damage ahead of a
save, and operators must leave both files untouched while the server owns the lock.

## Checkpoints and crash boundaries

Purchases, rewards, cargo and industry changes use full snapshots. Scheduled
industry advancement, clean shutdown and a 1 MiB journal limit also bound journal
growth. A checkpoint:

1. Verifies the existing pair and closes the append handle.
2. Writes a complete backup including every pending combat debit.
3. Flushes, verifies and replaces the primary snapshot with its current sequence.
4. Replaces the journal with a header at that sequence.

A process death before step 3 leaves the old primary plus its complete journal.
A death after step 3 but before step 4 leaves already-checkpointed records, which
replay skips; they cannot reverse an ammo purchase or ship change. Interrupted
temporary replacements require operator recovery under the existing policy.
An append may commit immediately before the process dies without delivering its
damage, as with the previous commit-before-damage implementation.

The flush guarantee remains the existing Godot runtime guarantee. This does not
add filesystem directory fsync or promise survival of every storage/power failure.
The optimization removes per-volley full rewrites; full checkpoints can still
stall the main thread. VPS storage latency and representative ten-player combat
still need measurement.

## Operations and recovery

Upgrade the server and `tools/pilots.py` together. Saves 1–7 migrate once to schema 8;
older builds reject it. Preserve a stopped-server copy of the **entire data
directory** before migration. The provisioning tool validates/replays pending
combat, then writes a complete schema-8 snapshot and compacts its journal. It
preserves ammo, boosts, industry and request revisions when rotating credentials.
Deployment archives already include the entire directory and reject a leftover
`pilots.json.combat.tmp` alongside the existing interrupted-write markers.

After a crash, stop all server processes and archive the whole directory first.
When both files are valid, retain the pair, archive any interrupted temporary
files, remove the stale empty lock and restart. Complete journal records replay.
When either file is damaged, prefer restoring a matching stopped-server backup
pair. Never combine unrelated snapshots and journals.

If only the rolling `pilots.json.bak` is usable, recovery is an explicit rollback:

1. Preserve the primary, journal, backup, temporary files and lock for inspection.
2. Copy the verified backup to `pilots.json` while the server is stopped.
3. For a schema-8 backup, create `pilots.json.combat` containing exactly its
   `combat_journal` metadata as **one JSON line followed by a newline**. This
   intentionally discards all combat after that backup sequence. For a legacy
   schema-1–7 restore, archive/remove the current journal before restarting.
4. Archive/remove temporary paths and the stale empty lock, correct the underlying
   disk problem, restart, then verify credits, ammunition, boosts and credentials.

Neither the server nor provisioning tool performs that rollback implicitly.

## Validation and timing

`tests/combat_journal_test.gd` checks atomic ammo/boost replay, restart before a
checkpoint, rocket debits, backups containing spent ammo, interrupted compaction
after a purchase, malformed journals, runtime edits and a real server process
exiting before damage on persistence failure, including an actual failed append.
It also checks the journal size limit, CRLF input, and real Godot/Python rotation
in both directions. Operator tests cover pending-debit rotation, new pilots,
Premium, stale checkpointed records and corruption preservation.
Both Windows and Linux suites include the journal correctness test.

For repeatable isolated measurements, run:

```text
godot --headless --path . --script res://tests/combat_persistence_benchmark.gd
```

The workload provisions ten disposable pilots, compares full-snapshot commits with
combat journal commits, and repeats with 999 stored items on one pilot. It measures
300 debits per case and 30 groups of ten volleys in the same synchronous combat
pass. Timings are observations, not CI thresholds or a complete simulation benchmark.

On 9 October 2026, Godot 4.7.2 on Windows (Ryzen 7 5700U), with this worktree's
validation suite stopped, produced the following local measurements. Other
worktrees also used the shared machine; these are not isolated hardware benchmarks.

| Ten pilots | Full snapshot, mean per debit | Journal, mean per debit | Ten volleys, mean before → after | Journal ten-volleys p95 / max |
| --- | ---: | ---: | ---: | ---: |
| Starter inventory | 23.87 ms | 0.24 ms | 238.96 → 2.46 ms | 3.09 / 4.91 ms |
| 999 additional stored items on one pilot | 42.73 ms | 0.86 ms | 427.58 → 8.93 ms | 10.57 / 11.25 ms |

The snapshot run with extra items had substantial timing variability (71.89 ms
p95 per debit), so the means should not be treated as hardware-independent
speedup promises. The journal cases fit the 16.7 ms tick budget for the persistence
portion of this workload. AI, movement, network processing and checkpoint writes
are additional costs. Linux/VPS timing and long-session multiplayer behavior are
still separate validation tasks.
