# Alien-sector fire receipt convergence

The repository review's Windows suite reported one intermittent fire-intent
convergence failure, followed by a successful isolated rerun. This follow-up
does **not** establish a gameplay defect or identify the original failing call.
An instrumented copy of the original test also passed locally: 60 assertions,
60.40 seconds, with both low-FPS receipts only 1 ms old when observed.

`tests/alien_sector_test.gd` now treats a frame yield as retry scheduling rather
than proof of network receipt. Each attempt yields first, sends the requested
unreliable flight RPCs, polls clients before the authority, and checks all server
receipts together before returning to combat. This removes the frame gap between
the current send and its receipt check and avoids depending on automatic polling
order among the fixture's separate multiplayer APIs. These remain real ENet RPCs;
the test neither invokes the handler locally nor rewrites command timestamps.

Godot's pinned engine polls the custom multiplayer APIs sequentially **before**
emitting `process_frame`; a claim that the signal precedes automatic polling
would be incorrect. See the pinned [SceneTree implementation](https://github.com/godotengine/godot/blob/ed1daf0bf/scene/main/scene_tree.cpp#L657).
The explicit barrier is test scheduling hardening, not evidence that this engine
ordering caused the previously reported failure.

The original 8-second convergence budget and production 500 ms expiry are
unchanged. The existing simultaneous damage, contribution, encounter reset and
stale encounter rejection assertions remain. An added regression keeps the
1 FPS scenario, temporarily owns multiplayer polling, crosses two frames without
heartbeats, checks that both intents expire, and requires actual ENet retries to
restore both fresh intents together. Automatic polling and the FPS cap are then
restored. No unconditional sleep or gameplay tuning change is used.

Diagnostics retain the last eight attempts per peer on failure, including the
call phase, attempt, send/observation/prior-receipt/current-receipt times, age,
peer IDs, client/server pilot lives, expected target/encounter, current alien life,
received command and match/freshness decisions. Low-FPS successes also print
their bounded samples so delayed polling can be distinguished from stale state.

## Validation

Validation used the pinned Windows Godot 4.7.2 console executable, a cold import
in this worktree, disposable profiles/saves and distinct UDP offsets. The normal
checks used `commands('windows', engine)` and `run_group` from
`tools/check-game.py`, selecting the four network integration groups, with one
worker and offsets starting at 20000. Focused repetitions used the same runner
and a new profile/port for each invocation.

The four normal network groups passed: `network_test` (19.77 s),
`network_combat_test` (21.04 s), `dedicated_server_test` (33.54 s), and
`alien_sector_test` (39.22 s, 62 assertions). The temporary mutation that removed
the explicit client/authority polls failed as expected in 44.55 s: 61 assertions
passed and two failed (receipt convergence and simultaneous fresh retry). Its
diagnostics identified `slow-frame retry after expiry`, matching targets/lives
but receipt ages growing from 3,000 to 10,001 ms over eight attempts. This
confirms that the added regression detects the missing receipt barrier. The
mutation was run from an ignored disposable script, never from production code.

Five focused repetitions of the final test passed all 62 assertions each in
38.75, 37.22, 32.17, 32.85 and 30.49 seconds. Earlier exploratory versions also
passed, but are excluded from these final-version repetition results. Local
raw results are in ignored `build/validation/fire-{baseline,normal,mutation,focused-final}.json`;
`build/validation/run-fire.py` contains the disposable selection/repetition runner.

The original intermittent suite failure has not been reproduced. The controlled
delayed-poll scenario tests the receipt barrier's contract; it does not reproduce
or prove a production fault. This test-only change does not require deployment,
save migration, service restarts or live-data work. The complete Windows suite,
Linux suite and representative friend-group gameplay were not rerun locally.
