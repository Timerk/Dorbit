# CI performance investigation — 8 October 2026

The import caches work, and removing duplicate Linux validation works. The main
remaining problems are frequent whole-cache invalidation and roughly six minutes
of serial tests even when imports are warm. This investigation changes no
workflow or game settings. Deploy preview is outside its scope.

The reviewed source is `origin/main` at
`0eeb9613f1e1264e949605523d805ee963afb1d2`. Measurements come from job logs and
step timestamps, with an additional disposable-project experiment on Windows.
The runs have different revisions and hosted machines; these are observations,
not a controlled benchmark or a promised speedup. Queue time is excluded from job
durations. Failed jobs are identified explicitly.

## What the existing changes achieved

| Evidence | Linux | Windows |
| --- | ---: | ---: |
| [Run 230](https://github.com/Timerk/Dorbit/actions/runs/37788521361), import cache miss: initial import | 451 s | 495.82 s |
| [Run 234](https://github.com/Timerk/Dorbit/actions/runs/37791874368), same respective import keys restored: initial import | 5 s | 11.79 s |
| Run 234: cache restore step | 2 s | 2 s |
| Run 234: complete job | 6 m 7 s, **failed later in export readiness** | 7 m 21 s, successful |

The import-time reduction is about 99% on Linux and 98% on Windows. Both logs
explicitly report cache hits. Linux's packaging helper really copies restored
imports into the disposable `git archive` staging directory: its warm import
proves this path is effective. The later readiness failure in run 234 does not
indicate a cache failure. The subsequent
[run 235](https://github.com/Timerk/Dorbit/actions/runs/37792974968) passed its
exported-server readiness and shutdown checks.

The existing tool caches also work. Their restore steps typically take 2–4 s;
cached Windows setup takes about 1 s. The new Linux `godot-linux-4.7.2-v2` cache
initially existed only in PR 61's merge-ref scope, so a first main build using it
still has to populate main's cache.

The old Linux workflow ran checks in the checkout and then again in release
staging. In [run 218](https://github.com/Timerk/Dorbit/actions/runs/37778596040),
these steps took 12 m 34 s and 12 m 48 s, respectively, and the Linux job took
26 m 16 s. The revised workflow has only the staging validation. On a cache hit,
[run 222](https://github.com/Timerk/Dorbit/actions/runs/37781358063) completed its
successful Linux job in 6 m 17 s. The exact saved time cannot be attributed solely
to deduplication because caching and revisions also changed, but the duplicate
suite and import are visibly gone.

## Why improvements are inconsistent

1. **One changed input invalidates every imported asset.** The key hashes all of
   `assets/**`, all of `project.godot`, and `tools/import*.gd`, with no fallback.
   A small SVG addition, catalog update, README edit under assets, or unrelated
   project setting can force reimporting all twelve textured hulls. For example,
   `1016aca` only adds stdout-flush settings to `project.godot`, yet changes the
   import key. The latest main Windows
   [job in run 239](https://github.com/Timerk/Dorbit/actions/runs/37798635731/job/113384607043)
   reported a miss and spent 291.43 s importing.
2. **PR caches cannot warm main or another PR.** This is GitHub's intended cache
   isolation. A main build must populate its own cache; simultaneous runs can all
   miss before the first finishes saving. Long-lived branches with different
   asset/settings inputs also miss main's exact key. These restrictions are
   documented in [GitHub's caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
3. **Caches save only after the job succeeds.** A failed cold build will not save
   its imports or tools through the combined cache action. Exact hits are
   immutable and are not refreshed. This behavior is also documented in the
   caching reference above.
4. **Warm imports do not remove test time.** Run 234's Windows test invocations
   total 359.89 s. Its second import, inside `dev.ps1 build`, takes only 4.93 s.
   That repeated scan is a small cost, not another eight-minute import.

At the initial cache inventory snapshot, 23 entries occupied 3.15 GB. Recent
entries were present and successfully restored; the inspected evidence does not
point to cache eviction as the current cause.

## Ranked options

| Priority | Option | Expected benefit and constraints |
| --- | --- | --- |
| 1 | Reuse unchanged imported assets across small changes | Avoid most of the observed 5–9 minute cold-import penalty. Start with independently keyed hull imports or a validated per-asset cache manifest; retain OS/engine isolation and import-setting/hook dependency checks. |
| 2 | Run independent test groups concurrently | The warm Windows suite is about 6 minutes. A two-worker split has an ideal test-only floor near 3 minutes, before contention and setup. Measure rather than assuming linear scaling. |
| 3 | Cancel superseded PR validation | Save runner usage and reduce competing obsolete runs. Scope cancellation to the PR; preserve main build/release runs so publication is not interrupted. |
| 4 | Skip game builds for documentation-only PR changes | Avoid entire jobs for strictly non-runtime documentation/review inputs. Keep required status checks reporting success and retain current main release behavior. Do not skip runtime assets, export/import settings, workflows, tooling or tests. |
| 5 | Reduce unnecessary fixture waits | Target the slow fixtures below. Replace fixed waits with bounded waits for actual state; preserve real ENet, physics and restart checks. |
| 6 | Reduce artifact compression overhead | Set `compression-level: 0` for the already compressed ZIP/TAR.GZ uploaded by validation. Current uploads are only 3–13 s, so this is a small improvement. Keep the existing inner package format used by release consumers. |

The pinned [upload-artifact action documentation](https://github.com/actions/upload-artifact/blob/ea165f8d65b6e75b540449e92b4886f43607fa02/README.md)
supports disabling its outer compression for data that compresses poorly. It
does not require changing the package downloader or release manifest.

Before parallelizing tests, fix their shared resources. Many fixtures inherit
`network_test.gd` and bind fixed UDP port 24683; Windows also uses one APPDATA
profile, with intentional restart sequences. Allocate separate ports, settings
profiles and pilot data per worker, preserve ordering within persistence/restart
groups, and import once before starting workers. Separate runner jobs avoid port
collisions but add checkout/tool/import overhead and may multiply cold imports.
Do not simply launch the existing suite in parallel.

Run 234's largest Windows tests were:

| Fixture | Seconds |
| --- | ---: |
| autopilot | 36.85 |
| main menu | 27.12 |
| economy | 26.94 |
| ships | 24.07 |
| flight playthrough | 20.62 |
| offline main menu | 20.26 |

These six account for 155.86 s. `network_test.gd` provides a fixed 150 ms default
`settle`; other checks already poll state with deadlines. Autopilot also waits
for real physics frames. Avoid globally shortening timers or accelerating the
whole engine without validating their effects on networking and timing coverage.

## A broad fallback key needs additional validation

An isolated Liberator experiment used the pinned Godot 4.7.2 Windows executable,
the tracked GLB/import settings, the import hook, and Compatibility rendering.
Each restored project received only `.godot/imported`; no editor index was
restored. The hook prints a recognizable marker when it runs.

| Scenario | Seconds | Hook ran |
| --- | ---: | --- |
| Cold import | 20.546 | Yes |
| Restored, identical inputs | 3.557 | No |
| Restored, root-scale import setting changed to 2.0 | 3.708 | **No** |
| Restored, hook print changed | 3.613 | **No** |
| Restored, GLB generator metadata changed with equal byte length | 22.203 | Yes |

This reproduces a correctness hazard: a clean project can accept old derived
data after settings/hook changes, even though source-byte changes are detected.
Godot's [reimport implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp)
uses the editor's expected import-metadata hash and separate source/destination
hashes. The current exact-input workflow prevents this stale-settings case.
Adding a broad `restore-keys` prefix alone would remove that protection.

A safe incremental approach must discard affected derived files when their
source, `.import` settings, import hook or relevant project settings differ.
Invalidate all hulls when their shared hook changes. Include related texture and
scene dependencies, not just each GLB's own bytes. Do not restore cached tracked
assets or scripts over the checked-out revision.

The existing `tools/profile-imports.py` also passed unchanged: Basis cold/warm/
restored imports were 22.911/4.135/3.750 s; uncompressed imports were
4.299/3.327/3.538 s. These one-hull local timings are not whole-CI benchmarks or
GPU-memory measurements. Keep current compression and single-threaded imports
until separate runtime/quality and font-import reliability checks justify a
change. Larger runners would help CPU-bound cold imports but do not eliminate
serial timer waits; they are a later option to benchmark against cost.

## Validation for a follow-up implementation

- Compare a cold run and identical-input warm run on each OS, recording restore,
  import, tests and export separately. Preserve all current test coverage.
- Change only a runtime script: imported assets should remain warm.
- Change one SVG or hull: unaffected expensive hulls should stay warm.
- Change `.import` settings and the shared import hook: affected scenes must
  actually reimport. Test the generated scene, not only cache-hit output.
- Verify main and PR cache isolation, successful-only publication, and exported
  client/server protocol and resource checks.
- For parallel tests, repeat complete suites with isolated ports/profiles/data;
  preserve restart sequences and surface every process failure.

The durable next step is safe incremental asset reuse, followed by isolated
test concurrency. Small upload/setup tweaks cannot explain or remove the
multi-minute runtime by themselves.
