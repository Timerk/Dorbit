# Skylab mechanics and Codex implementation handoff

Target: Drobit, an independent game. Reference: the attached German DarkOrbit Skylab screenshot. Research date: 2026-10-08.

## Scope and evidence

Implement the classic passive industry system shown in the screenshot. This document separates documented game rules, directly observed screenshot data, and proposed engineering choices. It is not a verified dump of DarkOrbit's server code or complete balancing tables. Missing historical values must remain explicit configuration requirements, not invented facts.

Primary sources:

- S1: https://board-en.darkorbit.com/threads/skylab-help.1212/ — general rules, recipes, energy, transport.
- S2: https://board-de.darkorbit.com/threads/faq-skylab.2737/ — German FAQ; cancellation, Xeno substitute, recipes.
- S3: https://board-en.darkorbit.com/threads/beginners-guide-to-skylab.1210/ — UI legend, transport exception, startup ore, module dialogs.
- S4: https://board-en.darkorbit.com/threads/skylab-robots-faq.1213/ — collector robots.

Old FAQs contain contradictions and mistakes. S1's transport section retains obsolete ship-to-lab paragraphs despite explicitly prohibiting that direction. S3 specifically says the transporter cannot be upgraded, overriding generic statements that every module reaches level 20. Use lab-to-ship transport and a level-1 transporter for this implementation. Exact startup state varies between descriptions; choose and document a bootstrap profile. Combat ore bonuses belong to a separate system and should be researched separately, since the English and German FAQs disagree on them.

## 1. Gameplay model

Players manage a persistent industrial facility outside the combat map. Raw ore feeds an automatic refining chain. Infrastructure, energy, stock, production throughput, and timed upgrades constrain output. Goods are transported into ship cargo for use by the game's existing trading or ore-upgrade systems. The useful interaction is allocating production and investing in infrastructure over time.

S1 documented rules: Basic sets the maximum level for other facilities. Solar supplies power. Storage has independent capacity for each ore. Collector throughput and power demand increase with upgrades; upgrading collectors stop producing but continue drawing power unless disabled. Refining requires ingredients, power, and output space. Upgrade acceleration costs less as the remaining work decreases. Only one transport runs at once. Sending is limited by free cargo at dispatch; delivery still adds goods if cargo has filled meanwhile. Premium halves transport duration.

The backend should advance production, upgrades, transport, and robot lifetimes independently of an open browser. Offline robot operation is explicitly documented in S4; persistent offline industry is the implementation target for the overall system.

## 2. Read the screenshot

The top strip is inventory, written as current stock / separate maximum stock. Dots are German thousands separators.

| Resource | Current | Maximum |
|---|---:|---:|
| Prometium | 0 | 4,018,569 |
| Endurium | 0 | 4,018,569 |
| Terbium | 1 | 4,018,569 |
| Prometid | 103,077 | 200,928 |
| Duranium | 105,424 | 200,928 |
| Xenomit | 0 | 20,093 |
| Promerium | 1,194 | 20,093 |
| Seprom | 578 | 1,827 |

These maxima belong to the displayed storage setup. They are a reference fixture, not a complete level progression formula. Xenomit's visible slot does not mean the Xeno module creates transferable inventory.

| Screenshot label | English / ID | Displayed level | Displayed power | Position |
|---|---|---:|---:|---|
| Prometium-Sammler | Prometium collector / prometiumCollector | 7 | 64 | Upper left |
| Endurium-Sammler | Endurium collector / enduriumCollector | 7 | 64 | Left middle |
| Terbium-Sammler | Terbium collector / terbiumCollector | 7 | 64 | Left lower |
| Solar-Modul | Solar / solar | 8 | 454 / 870 overall | Upper center |
| Transport-Modul | Transport / transport | 1 | 16 | Lower left |
| Lager-Modul | Storage / storage | 8 | 79 | Bottom left-center |
| Basis-Modul | Basic / basic | 9 | 96 | Bottom center-right |
| Prometid-Raffinerie | Prometid refinery / prometidRefinery | 6 | 0 | Upper right |
| Duranium-Raffinerie | Duranium refinery / duraniumRefinery | 6 | 0 | Right upper-middle |
| Promerium-Raffinerie | Promerium refinery / promeriumRefinery | 4 | 31 | Right middle |
| Xeno-Modul | Xeno / xeno | 5 | 40 | Right lower-middle |
| Seprom-Raffinerie | Seprom refinery / sepromRefinery | 3 | 0 | Bottom right |

S3's legend identifies bars plus a number as level, lightning as power requirement, and the cog percentage as productivity. Each of the four refineries here reads 0%. The blue building/arrow symbols appear to mark ongoing upgrades, unlike the ordinary bar symbols; treat this as a visual inference. This image does not establish whether an upgrading module's level label shows completed or target level. Store both in the new game and label them explicitly.

Power check: 3 × 64 + 16 + 79 + 96 + 31 + 40 = 454. Solar capacity is 870, leaving 416 spare. Power is an instantaneous capacity budget, not an inventory depleted every second.

Do not diagnose all 0% refineries as power failures: there is spare global power. Empty raw stock could block first-stage refining, but power 0 could also reflect switched-off facilities. Inspect module detail state to explain each case. Prometid and Duranium stock remaining does not prove their refineries currently run.

## 3. Facilities and refining

Use 12 distinct modules: Basic, Solar, Storage, Transport, three collectors, four refineries, and Xeno. Each collector supplies its named raw ore. Refineries automatically withdraw inputs from the shared lab inventory and deposit outputs there.

S2 documented recipes, per output unit:

| Output | Inputs |
|---|---|
| 1 Prometid | 20 Prometium + 10 Endurium |
| 1 Duranium | 10 Endurium + 20 Terbium |
| 1 Promerium | 10 Prometid + 10 Duranium + 1 Xenomit or equivalent Xeno substitute |
| 1 Seprom | 10 Promerium |

S2 also specifies that Xeno's substitute cannot be stored or used elsewhere. It supports Promerium production, indirectly supporting Seprom. Keeping Xeno appropriately leveled avoids needing real Xenomit; the FAQ's wording about unequal levels is ambiguous, so do not implement a new hard upgrade prerequisite from it. Cancellation forfeits paid credits and raw materials. Basic cannot be switched off. Other upgradeable facilities reach level 20.

Derived arithmetic: one Promerium ultimately represents 200 Prometium + 200 Endurium + 200 Terbium plus one Xeno equivalent. One Seprom represents ten times those quantities. Endurium is shared by both first-stage refineries: 10 + 10 = 20 Endurium per paired Prometid/Duranium output. This explains why raw balances can stay near zero despite working collectors.

Production rate is separate from recipe ratio. Higher levels should increase output per unit time, not make the same ore cheaper to refine. Inventory change is gross production minus downstream consumption minus transfers and upgrade costs. Display both gross and net rates so the player can understand bottlenecks.

## 4. Upgrade lifecycle

S3 describes module Info and Upgrade tabs, with credits, raw-ore requirements, duration, and instant-build pricing shown before purchase. It explicitly limits Transport to level 1. Its startup guide mentions 105,600 units of the primary ores, but does not give an unambiguous complete initialization record.

Implement these proposed transaction semantics:

1. Advance the account to server time before validating the request.
2. Require a built/eligible module, no existing job on it, and target level within the completed Basic level. Basic can upgrade itself up to 20.
3. Deduct the configured credit and ore costs atomically. A speed-up currency supplements the required build cost; it does not conjure missing ores.
4. Persist current level, target level, start time, and finish time.
5. Pause production by that collector/refinery during its upgrade. Allow different modules to upgrade concurrently; only one upgrade per module.
6. On completion, apply the new level once and recompute capacities, power, and rates.
7. Canceling removes the job without a credit/raw-ore refund; keep the old level. Do not invent a premium refund policy.

Choices requiring explicit configuration: whether Basic, Solar, and Storage retain their old service while upgrading; whether disabling a module affects its construction timer; whether construction draws old-level or target-level energy; exact instant-build formula. Suggested defaults: infrastructure retains completed-level service; disabling never pauses construction; enabled construction uses completed-level power; speed-up price is ceiling(initial speed-up price × remaining duration / original duration). These defaults are engineering choices, not verified DarkOrbit internals.

Never require every collector to reach level 20 before building refineries: the FAQs frame this as advice, not a mandatory unlock.

## 5. Xeno implementation policy

Keep real Xenomit inventory distinct from virtual catalyst supply. Do not accumulate virtual units in the Xenomit storage slot, ship cargo, or sale inventory.

Suggested implementation: each level of Xeno has a configurable virtual-catalyst throughput. An enabled, powered, non-upgrading Xeno grants throughput to Promerium production. Apply that grant before consuming real Xenomit for any remaining production. Higher Xeno than needed simply leaves spare throughput unused. Lower Xeno limits catalyst-supported throughput rather than blocking upgrades. This policy resolves incomplete documentation for Drobit; its numerical capacity and exact historical fallback order are unverified.

## 6. Transport

Historical rule to implement: one lab-to-ship shipment, at most the ship's free cargo when ordered. On arrival, add the shipment even if the ship filled meanwhile; overfull cargo prevents further ore collection until enough space is freed. Xeno substitute cannot be shipped.

Proposed reliable implementation:

- Accept a positive integer amount per transferable resource; reject unknown keys and negative/fractional/overflow quantities.
- Validate total cargo weight, sufficient stock, and absence of another active shipment inside one account transaction.
- Remove ore from lab inventory at dispatch and place it in a shipment record. This permits production to refill the freed storage immediately.
- Record recipient ownership, dispatch/arrival timestamps, manifest, and delivery status.
- Deliver exactly once to the defined recipient. Choose explicitly whether the destination is the dispatch ship, active ship, or account cargo; historical switching/destruction behavior is not established here.
- A speed-up delivers the existing shipment; it must never purchase or duplicate its manifest.
- Use configured cargo units per ore. Assume one unit each only if that matches Drobit's existing cargo rules.

Exact normal throughput, instant-send pricing, advertisements, coupons, and discount interactions were not verified from a reliable primary specification. Configure them independently. Premium's verified effect is duration × 0.5.

## 7. Robots

S4 documented optional collector boosts: a credit robot costs 250 credits and adds 1%; an Uridium robot costs 50 Uridium and adds 4%. Each collector has 12 active slots. Active robots last 48 hours, including logged-out time and time with the collector switched off. Queued robots do not age. Purchases can create an unlimited queue. Expired slots refill automatically, prioritizing Uridium robots.

Use additive boosts as the proposed implementation: multiplier = 1 + 0.01 × creditRobotCount + 0.04 × premiumRobotCount. Thus all-credit slots yield 1.12× and all-premium slots 1.48×. Do not boost refineries or solar power. The precise stacking formula is not explicitly written in S4 and should remain a named policy.

Persist individual activation/expiry timestamps or equivalent batches. During offline advancement, process expiries and replacements at their actual times; applying the currently visible bonus to the entire absence produces incorrect output.

## 8. Backend model and simulation — proposed engineering design

Use the game's existing backend, persistence, authentication, currency, and cargo systems. Avoid a standalone client-only economy.

Suggested state:

```ts
type ModuleId = 'basic' | 'solar' | 'storage' | 'transport'
  | 'prometiumCollector' | 'enduriumCollector' | 'terbiumCollector'
  | 'prometidRefinery' | 'duraniumRefinery' | 'promeriumRefinery'
  | 'xeno' | 'sepromRefinery';

type ModuleState = {
  level: number; // completed level; 0 means not built
  enabled: boolean;
  upgrade: null | { targetLevel: number; startedAt: number; finishesAt: number };
};

type LabState = {
  accountId: string;
  lastSimulatedAt: number;
  version: number;
  inventory: Record<string, number>;
  modules: Record<ModuleId, ModuleState>;
  productionCarry: Record<string, number>;
  shipment: null | {
    id: string; recipientId: string; manifest: Record<string, number>;
    dispatchedAt: number; arrivesAt: number; delivered: boolean;
  };
  robotState: Record<string, unknown>; // use explicit typed queues in implementation
};
```

Derive runtime state separately from enabled: unbuilt, upgrading, disabled, running, blocked-no-power, blocked-input, and blocked-output-full. Multiple blocker flags can coexist. Manual off is a player preference; shortage is a temporary condition. Automatically retry shortages when conditions change, rather than forcing the player to toggle the module.

Simulation requirements:

- Use authoritative server timestamps. Clock manipulation in the client must not affect results.
- Keep integer ore inventory and persisted fractional production progress. Fractional progress must not grant free inputs or produce huge catch-up bursts after a long blockage.
- Advance across upgrade completions, robot expiries, delivery events, stock exhaustion, and capacity boundaries. All rates within each interval must respect available ingredients and output space.
- Treat shared inputs fairly and deterministically. Suggested policy: proportional throughput allocation for Prometid/Duranium when competing for insufficient Endurium. Fixed iteration order would otherwise favor one refinery.
- If using ticks instead of an event-based solver, use the same fixed tick convention online and offline, retain tick phase, document sub-tick error, and avoid per-second loops over months.
- Power is allocated as capacity. Define a deterministic admission priority if insufficient; do not randomly shut down modules. Show the blocked module and how much power is missing.
- Do not consume ingredients when the requested output cannot fit. Recompute as downstream consumption frees space.
- Apply all commands after catch-up under an account lock or optimistic concurrency check. Use request IDs for mutation retries.
- Persist timestamps and state together; reconnects and server restarts must not repeat completed jobs or deliveries.

Suggested command surface: getLabSnapshot, setModuleEnabled, startUpgrade, cancelUpgrade, finishUpgradeInstantly, startShipment, finishShipmentInstantly, buyCollectorRobots. Snapshot returns server time, inventories/capacities, gross/net rates, per-module blockers, and job finish times.

## 9. UI requirements

Match the screenshot's functional layout with original artwork: ore strip across the top, collectors left, infrastructure center/bottom, refineries right, Xeno adjacent to Promerium. The center structure is navigation artwork; connecting lines do not imply player-adjustable routing or pipes with separate storage.

Each module is clickable and opens a detail panel:

- Info: completed level, effective state, power, inputs/output per hour, gross/net contribution, blockers, enable control where supported.
- Upgrade: next-level effects, costs, construction duration, eligibility, normal-build and instant-build actions; active job progress and cancellation consequence.
- Collector Productivity: robot slots, individual expiry/remaining time, queue counts, purchase controls, effective bonus.
- Transport: ore amount fields, stock, free cargo, total requested, estimated arrival, existing manifest and countdown.

Keep productivity separate from upgrade progress. A 0% cog is not a construction progress indicator. Tooltips should explain each icon. Show current/target levels separately during an upgrade. Refresh re-fetches the authoritative snapshot; it does not generate ore.

## 10. Balancing data still required

Supply a versioned table for every module and level containing build cost, duration, premium speed-up base price, power demand, collector/refinery throughput, solar capacity, per-ore storage capacities, and Xeno throughput. A single screenshot cannot determine these curves.

Do not fit an exponential progression from the screenshot. Its quantities are valid for a debug fixture, but they are not proof of a mathematical formula or rounding convention. The same applies to level-specific construction duration and rate values found in casual player recollections.

Define bootstrap state that cannot softlock: completed infrastructure, enabled raw collectors or enough starter ore to construct them, sufficient starting power, and affordable initial costs. Document which profile is a faithful historical choice versus custom Drobit balance. If complete historical tables are absent, implement the engine first with clearly labeled development balance data.

## 11. Acceptance criteria

1. A collector produces configured ore over server time up to its own capacity; login frequency does not alter output materially.
2. Prometid consumes exactly 20 Prometium and 10 Endurium per unit; Duranium consumes 10 Endurium and 20 Terbium.
3. Promerium consumes exactly 10 of each first-stage alloy plus one catalyst equivalent; Seprom consumes exactly 10 Promerium.
4. Output-full or input-empty modules never destroy ingredients or create negative stock. They recover when the condition clears.
5. Manual off stops that module's output and releases its configured demand; Basic off is rejected.
6. No non-Basic upgrade exceeds completed Basic level; Transport upgrade is rejected.
7. Different modules can upgrade concurrently. Upgrading collectors/refineries do not produce.
8. Canceling an upgrade retains the old level and does not refund credits/raw ores.
9. Xeno support never creates transferable Xenomit. Lower/higher Xeno levels follow the documented Drobit policy consistently.
10. A shipment removes its manifest exactly once, admits no simultaneous second shipment, and delivers exactly once across retries/restarts.
11. Cargo can become overfull at delivery without losing shipped ore; collection respects the resulting limit.
12. Robots expire after 48 hours even while disabled/offline; queued robots do not age and refill premium-first.
13. The screenshot fixture produces power demand 454 and solar capacity 870 and displays the listed inventory values, module labels, and four 0% refinery indicators.
14. Save/reload and repeated snapshot requests do not duplicate ore. Splitting elapsed time into many requests gives the same economic result within the defined tick/rounding tolerance.
15. Long offline intervals containing storage-full periods, input shortages, robot replacements, and upgrade completion match a continuously advanced reference simulation.

## 12. Prompt to hand to Codex

Implement the Skylab system described in this specification inside the existing Drobit game. First inspect the repository instructions and current server/account persistence, cargo, economy, UI, and timer architecture. Reuse those systems. Treat sections marked documented as gameplay rules; treat proposed choices as explicit implementation policies, keeping them configurable. Do not claim development balance values are historical DarkOrbit values.

Build the server-authoritative simulation and transactions before wiring the UI. Use data-driven level tables and the exact refinery recipes. Support persistent production, separate ore capacities, power, per-module concurrent timed upgrades, virtual Xeno support, single-flight ship deliveries, and collector robots. Preserve existing ore trading and combat upgrade behavior through adapters rather than duplicating it. Use original visuals arranged according to the screenshot's functional layout.

Add meaningful tests for resource conservation, capacity/input boundaries, shared-input fairness, offline equivalence, upgrade completion, robot replacement, and duplicate-delivery prevention. Include the screenshot data as a debug fixture without treating it as a universal balance table. Report any missing balance data or conflicts with existing game mechanics explicitly. Finish with the implemented behavior, validation performed, and remaining configuration gaps.
