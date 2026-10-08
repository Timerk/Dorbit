# Skylab industry

Current server saves use schema 8: the full industry snapshot is paired with a
combat journal. Upgrade the provisioning tool with the server and back up the
whole stopped-server data directory. See [combat persistence](combat-persistence.md)
for the current format, checkpoint and recovery rules; the industry policies below
remain unchanged.

Skylab replaces the existing menu placeholder with twelve clickable modules and
a detailed original station illustration following the user-approved
[station concept](menu-design/skylab-station-concept.png). The supplied
[Skylab specification](skylab-implementation-spec.md) defines gameplay rules; proposed ambiguities are
resolved below as explicit Drobit policies. This is an independent implementation,
not a recovered DarkOrbit server or historical balance table.

## Production and power

Collectors produce their named raw ores. All inventories are integer units with
independent Storage capacities. Recipes consume exactly:

| Output | Inputs per unit |
| --- | --- |
| Prometid | 20 Prometium + 10 Endurium |
| Duranium | 10 Endurium + 20 Terbium |
| Promerium | 10 Prometid + 10 Duranium + one catalyst |
| Seprom | 10 Promerium |

Xeno grants virtual catalyst throughput before real Xenomit is consumed. It never
adds ore to inventory, ship cargo or trading. Unequal Xeno/Promerium levels limit
the slower throughput without preventing upgrades. A bounded simulator allowance
bridges differently paced integer outputs: at most one spare whole virtual unit
plus fractional progress survives a minute. Spare whole throughput is discarded;
input/output blockage or a disabled/upgrading Promerium refinery clears the grant.
This allowance is simulator progress, not transferable stock.

Power is instantaneous capacity. Its configured admission order is Basic, Solar,
Storage, Transport, the three collectors, Prometid, Duranium, Promerium, Xeno and
Seprom. Demand and admitted usage are separate; shortages automatically recover.
Manual disable releases demand and clears that module's production progress.
Basic cannot be disabled. Storage capacities are a property of the completed
Storage level; disabling Storage releases its demand without deleting stock or
changing capacities. Basic's completed level continues to bound upgrade targets.

Within each production minute, collectors run first, then first-stage refining,
Promerium and Seprom. Competing first-stage refineries share available Endurium
proportionally to feasible desired output. Largest fractional remainders get the
last integer unit; exact ties alternate using a persisted turn. Output space is
checked before ingredients are consumed. Downstream consumption frees space for
the next minute. Blocked whole work is discarded, preventing a catch-up burst.

## Time and persistence

`Skylab` advances using authoritative server Unix seconds. Ore settles on fixed
UTC minute boundaries, retaining fractional progress between reads. Upgrade
completion, shipment arrival and robot expiry split elapsed intervals at their
actual times; bonuses never apply retroactively over an entire absence. At a
fully blocked fixed point, the solver skips empty minute ticks to its next event.

Online and offline use the same minute convention. Compared with a continuous
solver, stock visibility and downstream capacity reuse can lag by up to one
minute per stage. Integer output may lag by less than one output unit from
fractional progress; bounded Xeno allowance can add a further one-unit phase
difference. Frequent snapshots do not change the economic result beyond floating
rounding tolerance (tested fractional difference under 0.00001). Gross/hour and
net/hour are the last completed minute extrapolated to an hour, so low-rate
refineries can show alternating zero and nonzero values. Nominal/hour shows the
configured powered throughput separately. Productivity and construction progress
are distinct indicators.

The dedicated server schedules minute/timer advancement even with no clients.
Restart advances every persisted pilot before admission. Commands catch up before
validation, then commit synchronously under the existing ledger lock. The saved
equipment revision is the request sequence shared by all economy actions;
retries cannot charge twice or redeliver a shipment. Background industry does
not consume that request sequence. Inventory and job timestamps commit together
through the existing atomic replacement, backup and save-failure path. Owner-only
reliable snapshots expose inventories, rates, power, blockers, jobs and robots.

Ledger schema **6** combines industry, ammunition and per-ship combat boosts.
It migrates versions 1–6, including both earlier schema-5 layouts: main's resource
boost ledger and the initial industry preview. Existing jobs, stock, cargo, boosts,
wallets and ammunition survive. The retired industry wallet converts once at
100 credits per unit; overflow fails without writing or discarding a balance.
Active/queued boost robots become Advanced robots with the same lifetimes.
Invalid current records fail closed. Network schema **11** requires matching
client/server builds. Keep a separate pre-migration backup: the rolling `.bak`
is replaced by subsequent valid saves.

## Upgrades, robots and shipment policies

- All modules except Transport have levels 1–20. An unbuilt module can be built
  when Basic permits its target. Transport stays at level 1. Different modules
  can upgrade concurrently; each module has one job. Industrial output pauses
  during construction; completed infrastructure service remains available.
- Normal construction pays configured credits and raw ore upfront. Instant build
  costs exactly twice the normal credit price, with the same raw ore requirement.
  Its acceleration supplement equals the normal build price. Finishing an existing job costs
  `ceil(base acceleration credits × remaining/original duration)`. Cancellation keeps the old
  level and refunds neither credits nor raw ore. Disabling never pauses the job;
  enabled construction draws completed-level power.
- Standard robots cost 250 CR and add 1%; Advanced robots cost 5,000 CR and add 4%.
  Twelve active slots last 48 hours even offline or disabled. Queues do not age,
  refill automatically and prefer Advanced robots. Boosts add to 1.12× or 1.48×
  when every slot is filled with one kind. Numeric queue limits use the existing
  two-billion integer bound; a single purchase accepts at most one million.
- Shipments go only from lab to ship. One manifest runs at once; every mineral
  weighs one cargo unit, matching existing cargo rules. Positive integer amounts
  must fit free cargo at dispatch. Stock is removed immediately. The recipient
  is the owned ship active at dispatch, retained across switching and destruction;
  existing cargo already survives death. Delivery is atomic and may overfill the
  hold. Persisted cargo permits up to twice hull capacity, the maximum from one
  shipment plus cargo filled in transit. Overfull holds cannot collect space loot.
- Development transport duration is `max(60, units × 2)` seconds, halved for
  Premium with seconds rounded upward. **Instant send costs a flat 125,000 CR**,
  independent of cargo amount. Players can either dispatch the entered manifest
  instantly or deliver an existing shipment immediately for the same fee. Both
  commands validate funds and stock atomically and share the retry protection. Disabling Transport prevents dispatch
  but does not cancel an already paid shipment.

## Balance and account setup

[balance-v1.json](../assets/skylab/balance-v1.json) contains explicit entries for
every module level: credits, raw ores, duration, instant price, demand, production,
solar capacity, per-ore capacities and Xeno throughput. These are **development
balance values**, not historical values inferred from a screenshot. Numeric
level values, bootstrap, admission order and shipping prices/timing are data-driven.
Named algorithm policies describe the supported v1 engine; changing their values
requires implementing and versioning the corresponding algorithm. Debug assertions
reject unsupported algorithm names rather than silently suggesting another policy
was applied.

New/migrated labs have all twelve modules enabled at level 1, 1,200 units of each
raw ore and zero other stock. Solar capacity is 160 against demand 102, giving a
productive bootstrap even with a zero-credit wallet. Collectors produce 1,800/hour
each; first-stage refineries 60/hour; Promerium/Xeno 6/hour; Seprom 0.6/hour.
Storage starts at 10,000 per raw ore, 500 per first-stage alloy, 100 each for real
Xenomit/Promerium and 25 Seprom. Players can disable refining to accumulate build
ore. A Basic level-2 upgrade costs 500 CR plus 40 of each raw ore and takes 120 s.

Skylab uses credits exclusively. The server owns the wallet and prices; a client
cannot choose a conversion rate or shipment price. Premium defaults to off and
retains only the optional transport-duration flag. An operator can set that flag
while the server is stopped, rotating the credential:

```sh
python3 tools/pilots.py /absolute/data pilot /new/private/credential.json --rotate --premium on
```

The tool preserves jobs, robots, shipments, combat boosts and unrelated progression.
It supports both schema-5 layouts and the credits-only schema 7; legacy currency
conversion is backed up and never repeated. No Uridium grant option remains.

Real Xenomit is also an eighth cargo/trade resource. Its ivory mineral artwork is
original generated art with [prompt provenance](menu-design/xenomit-generation-prompt.txt).
The development price is 200 CR and Heavy loot adds 1–3 units; existing seven
prices remain unchanged. Xenomit in ship cargo can be sold through existing
station trading. It cannot be sent back to the lab. Lab Xenomit remains zero in
the bootstrap; virtual Xeno sustains normal production without an acquisition
mechanic for real lab catalyst. Ship refining and combat boosts retain their separate existing menu and rules;
Skylab shipments integrate through the shared cargo ledger.

Complete historical level curves, production/upgrade/robot economics, transport
pricing remain playtesting/configuration gaps.
The new Xenomit loot raises mean Heavy box value from 4,270 to 4,670 CR. Premium
has only the documented transport-duration effect. Advertising, coupons and
discount interactions are not implemented.

## UI and verification

Skylab is available from the existing navigation docked or in flight. The top
strip shows stock/separate capacity; Skylab fills the available navigation content
area, with station artwork covering its canvas while preserving its aspect ratio.
The detailed station scene arranges collectors
left, infrastructure center/bottom and refineries right, with Xeno near Promerium.
Live caption labels and leader lines identify all twelve modules; clicking either
the label or machinery opens a graphite/amber window. Basic shows facility levels,
Solar a power breakdown, Storage stock/capacity/net rates, refineries an ingredient
flow, and Xeno active/inactive catalyst support. A persistent footer holds enable,
level, power and productivity. Upgrade compares Instant and Normal costs in a
table and shows separate completed/target levels, countdown, finish and cancel.
Blocked upgrades include a direct link to Basic. Collector Productivity
shows a compact bonus/active summary, queues, next expiry and purchases without
scrolling; individual expiry times are available on hover. Cards use distinct generated transparent
Standard and Advanced robot images. Transport displays stock, free
cargo, requested total, arrival, recipient and the in-flight manifest, plus a visible
Instant send control alongside ordinary Send. The transport inputs reject fractional,
negative and out-of-range quantities. Refresh
requests authoritative state; offline menus are read-only visual previews.

The screenshot fixture has its exact stocks, levels, four zero-productivity
refineries, 454 demand / 870 solar capacity and independent reference capacities.
Those capacities are supplied only by `screenshot_snapshot`, separate from live
balance curves. Disabled/upgrading states chosen for the fixture are explicitly
visual interpretations, not claims about the original screenshot's hidden state.

Both Windows `tools/dev.ps1 check` and Linux `tools/server.sh check` include:

- `skylab_test.gd`: recipes, capacities, conservation, shared-input fairness,
  unequal catalyst throughput, job lifecycle, robots, offline equivalence,
  blocked decades, shipment validation, Premium and screenshot arithmetic.
- `skylab_persistence_test.gd`: real authenticated RPCs, migration, shared request
  retries, original-recipient delivery, overfull cargo, restart and save failure.
- `skylab_ui_test.gd`: actual module/control interactions at 960×600 and 1440×900.
  Run without `--headless` to save native captures under `build/validation/`.
- `pilots_test.py`: provisioning, corruption preservation, schema-7 rotation,
  benefits and adding a pilot without changing existing industry.

Current native captures: [station](menu-design/skylab-implemented.png),
[upgrade](menu-design/skylab-upgrade-implemented.png),
[robots](menu-design/skylab-robots-implemented.png) and
[shipment](menu-design/skylab-transport-implemented.png).

Validation on 2026-10-08: simulation checks passed 100 assertions, authenticated
persistence 25, and the rendered UI replay 106. Operator provisioning passed 12
Python tests. These include flat-fee direct/active shipments, atomic affordability,
network retries, credits-only migration, preserved robot lifetimes, conversion
overflow and repeat migration prevention. Station and module windows were inspected
at 960×600, 1440×900 and 1920×1080. The full-area/robot-art follow-up passed its
rendered UI replay and isolated PCK menu/transparent-art checks. Every Windows
regression check passed before that visual follow-up across the full run,
the corrected resource-boost fixture rerun and the resumed remaining checks. The
Windows-target PCK independently loaded every menu and the new station/robot assets.
Linux/WSL is unavailable locally; Linux runtime checks remain CI validation.
`rtk` is unavailable, so local checks use native tools.
