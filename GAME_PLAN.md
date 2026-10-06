# Dorbit game requirements and development plan

Status: Milestones 1 and 2 accepted after user playtesting, including internet combat, rewards, death, repairs, health synchronization and good observed performance with five clients, including a laptop below the original reference hardware. Milestone 3 starts with a dedicated Linux server before persistent progression. Ten-player performance still needs representative measurement; combat balance remains provisional.

This document records the planning discussion. Proposed values and open questions are marked separately so they can be adjusted through playtesting.

## Vision

Build a modern space game inspired by DarkOrbit, with full 3D flight, good performance, multiplayer with friends, alien hunting, and satisfying progression without pay-to-win.

The initial audience is a private group of approximately 10 simultaneous players. A public release is a possible long-term outcome, with no release deadline currently planned.

The core loop is to explore sectors, fight aliens, collect rewards, return to a station, improve the ship, and tackle harder encounters.

## Agreed direction

| Area | Decision |
| --- | --- |
| Engine | Godot |
| Initial platform | Native Windows application |
| Movement | Full 3D flight from the beginning |
| Camera | Third-person camera behind the ship |
| Combat | DarkOrbit-style target selection and automatic weapon tracking |
| Multiplayer | Approximately 10 concurrent players |
| Enemies | Aliens controlled by the game server |
| Hosting | A dedicated Linux server; all players connect as clients, including when playing alone |
| Local server testing | Ubuntu on WSL2, followed by a small Linux VPS |
| Persistence | Save progression between sessions, starting with the progression milestone |
| Progression | Frequent small upgrades and larger goals requiring several sessions |
| PvP | Planned after cooperative gameplay works |
| Monetization | No paid gameplay advantages; no monetization needed for the private version |

Browser support is not an initial requirement. It remains a possible future investigation, without a commitment to compatibility. The game will use full 3D movement from the first prototype.

## Flight and controls

The following controls are agreed as the starting layout. Check comfort and usability in the first prototype.

| Input | Action |
| --- | --- |
| W / S | Move forward / backward |
| A / D | Strafe left / right |
| Q / E | Move down / up |
| Hold right mouse and move mouse | Turn the ship; the camera follows |
| Left click an enemy | Select that target |
| Tab | Select the on-screen enemy closest to the mouse cursor |
| Space | Toggle automatic laser fire |
| Shift | Boost using rechargeable energy |
| M | Open/close the sector overview and choose a destination |

Flight should have noticeable weight and inertia while staying responsive and arcade-like. Ships retain momentum through turns, build speed gradually, and use assisted braking on release plus stronger counter-thrust when reversing. Mouse steering eases over a few frames. There is no unlimited coasting or manual braking requirement.

Settings are available from the connection menu and the Esc flight menu. Players can adjust mouse sensitivity, master/effects volume and mute, and rebind flight and combat actions to a single key or mouse button. Assigning an occupied binding swaps the actions; default controls can be restored. Fullscreen, window resolution, VSync, antialiasing and the performance overlay live on the Graphics tab. VSync is disabled by default and can be enabled to synchronize rendering with the screen's refresh rate. Changes apply immediately and persist on the device. Menu shortcuts remain fixed so settings and navigation stay accessible. In multiplayer, menus stop the local pilot's input and fire while the server continues running.

Original flight tuning before the ship roster: 36 m/s cruise, 78 m/s boost, 40 m/s² acceleration, 60 m/s² braking, 80 m/s² counter-thrust, and a 65 ms mouse-steering response time constant. From cruise, release stops the ship in about 0.6 seconds; mouse steering completes about 95% of a turn command within 0.2 seconds. These values remain tuning decisions.

## Combat

Players select an enemy and engage it with weapons that track the target. Precise manual aiming is not the basis of the initial combat system.

The starting combat proposal is:

- Lasers track the selected enemy within weapon range and a generous forward firing arc.
- Obstacles can block line of sight.
- Shields absorb their configured fraction of each hit; the remainder damages hull immediately. Any shield share exceeding remaining charge also damages hull.
- Destroying an alien grants a reward.
- The station supports repairs.
- Player ships and aliens use consistent targeting, weapon, shield, and damage rules where applicable.

Weapon ranges, firing arcs, damage, shield recovery, and alien behavior need playtesting. Additional weapons and abilities can follow after basic laser combat is enjoyable.

### Combat feedback and station navigation

Implemented for Scout, Sentinel and Heavy encounters during Milestone 3:

- The selected target has larger lock brackets, its type and slot number, distance, shield and hull readouts. Friendly contacts say FRIEND with their peer ID; enemies say HOSTILE with their type and slot number. Station and selected-target captions are placed first. Secondary enemy and friendly captions are suppressed when they overlap; their off-screen labels and duplicate 3D labels are omitted.
- Automatic fire distinguishes no target, disabled fire, active fire, out of range, outside the firing arc and blocked line of sight. Feedback consumes the existing `SpaceShip.firing_blocker` result used by shot validation. A client's interpolated geometry can briefly differ from the server under latency; the server still decides whether a shot fires.
- Shield damage produces a thin expanding ring; hull damage produces crossed sparks; destruction produces a larger expanding burst. Clients observe authoritative health decreases without replaying damage. The existing reward message reports the local pilot's actual awarded share.
- Outpost 01 retains its distance marker, with a labeled edge arrow when outside the view. Station and target captions take priority over friendly captions.
- Original procedural laser, shield, hull, destruction and confirmed station-service sounds use a six-voice pool, distance attenuation and repetition limits. Settings > Audio contains master/effects sliders and mute, saved locally in `user://audio.cfg`. Dedicated servers create no audio node and no impact meshes. Presentation never changes damage, prices or rewards.

Alien feedback integration retains the per-alien reward-share calculation and has passed a rendered ten-client run with all five aliens fighting and dying. Equipment purchase sounds use the server-confirmed transaction revision: failed and duplicate requests do not trigger a cue, and wallet snapshots never infer purchases. Ship models are not a dependency.

The rendered replay covers click/Tab selection, fire-state reasons using real collision geometry, shield/hull hits, rewards and return/repair. Two processes verify 38/37-credit cooperative shares. A ten-pilot presentation fixture checks bounded effects and crowded labels; it is not a multi-alien or network capacity benchmark. See [README.md](README.md#feedback-validation) for evidence and limits.

### Huntable sector and initial enemy variety

Milestone 3 now includes multiple simultaneous aliens in the current sector. This slice precedes equipment and hunting contracts. It adds no connected sectors, bosses, loot tables, missions or art pipeline.

- Five stable identities support independent encounters, with random homes across the sector at startup and after each death. Every alien owns its identity, movement, target choice, health, contribution list, life number, death and respawn timer. The server controls these and all rewards, including when no pilots are connected.
- Scouts are starter encounters; Sentinels require additional lasers or cooperative hunting. The Heavy is intended for upgraded pilots or a small group. Their colored contacts appear on the radar and sector overview. Enemy hull, shields and damage were increased for the starter equipment rebalance; movement, rewards and respawn timers stay unchanged.
- Each kill splits that type's credit pool equally among connected pilots who damaged that alien in its current life. Contributors awaiting rescue remain eligible; disconnected pilots are removed. Integer remainders go in ascending peer-ID order. Persistence commits the shares before clients see them.
- Killing or resetting one alien must leave other encounters, contributions and active fire intact. Player rescue also leaves encounters independent.
- Station protection remains a 75 m sphere. Aliens cannot attack protected pilots. Protected pilots cannot damage aliens.
- Exceeding the home leash, or losing all eligible targets after engagement, starts a return. Health and contributions reset and the life number advances. Returning aliens reject damage and cannot attack until they reach home. If direct flight is blocked, a 30-second server timeout places them at home so a rock cannot strand an invulnerable slot. Old fire commands cannot cross a reset or respawn.
- Joining clients receive every alien's current identity, transform, health, life, engagement/return state and respawn countdown. Snapshot ordering is tracked per entity.
- Left click selects the visible alien intersected by the camera ray. Tab selects the available on-screen alien closest to the mouse cursor each time, using screen center while right-mouse steering captures the cursor. Selection has no combat-range limit. Repeated Tab over the same enemy retains the lock and fire intent; Tab with no on-screen candidate preserves an existing lock. Locks persist through distance, camera turns and a living alien's return home until manual retargeting or deselection. Target death, player rescue and disconnect clear the lock. Encounter resets stop automatic fire without clearing a living target, so stale fire cannot cross lives. Weapon range, firing arc, protection and line of sight still decide whether lasers fire.
- Names and numbered markers distinguish contacts. Scouts have smaller amber-accented hulls, Sentinels retain the reference shape with red accents, and Heavies use larger purple-accented hulls with an extra armor block.

Provisional tuning lives in `Alien.TYPES`, `Sector.ALIEN_KINDS` and `Sector.MAP_RADIUS`. These values need human balance playtesting.

| Type | Count | Hull / shield | Speed | Laser damage / interval | Weapon range | Detection | Home leash | Credits | Respawn |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Scout | 2 | 1,000 / 500 | 29 m/s | 1,500 / 0.85 s | 120 m | 155 m | 170 m | 30 | 10 s |
| Sentinel | 2 | 4,000 / 2,000 | 18 m/s | 5,000 / 0.75 s | 155 m | 180 m | 230 m | 75 | 12 s |
| Heavy | 1 | 10,000 / 5,000 | 12 m/s | 12,000 / 0.9 s | 165 m | 220 m | 180 m | 180 | 18 s |

Home coordinates are server-selected random points throughout the safe sphere, with clearance for the entire home leash plus 35 m, station detection/protection, asteroids and other homes. IDs 0 and 3 remain Sentinels, 1 and 2 Scouts, and 4 Heavy. Patrols stay within 18 m horizontally and 8 m vertically of home before engagement. Returning living aliens keep their current home; a death chooses a new home on respawn. Timers never create extra nodes. Clients and late joiners receive authoritative homes and transforms.

Hunting contracts will stack on this work and use `Alien.kind` plus each kill's contribution eligibility. Merge alien variety first, hunting contracts second. The existing `SessionCombat.destroyed()` reward path holds the eligible contributor list until rewards are committed and applied.

### Sector size, radiation and 3D navigation

The user requested a substantially larger map, random alien positions, radiation instead of invisible walls, and a navigation display for full 3D flight. The safe sector is a sphere with a provisional 1,200 m radius (2.4 km diameter), up from 700 m. This increases safe volume about fivefold. The outpost, service/protection radii and physical asteroid cluster retain their positions. Decorative derelicts and the distant belt move outward beyond the enlarged safe sphere.

Crossing the diameter should be on the order of 20–45 seconds for representative fitted ships, with meaningful differences between hulls and engine/shield choices. These are tuning targets, not hard limits. [PR 34's merged ship roster](https://github.com/Timerk/Dorbit/pull/34) supplies 26–38 m/s base cruise; Ion engines add 8 m/s each. At steady cruise, a Liberator with three engines (57 m/s) takes 42.1 s; a Vengeance with six engines (86 m/s) takes 27.9 s; a Goliath with eleven engines (118 m/s) takes 20.3 s. Acceleration adds time, boost temporarily reduces it, and shorter routes take less time. Empty/low-engine hulls can exceed 45 s and extreme engine fittings can cross in under 20 s. Travel feel and the five-alien density need human playtesting.

The edge has no movement clamp. Within 120 m of it, the HUD warns of radiation ahead. Outside, a persistent alert, soft red full-screen pulse and red border signal danger, with a marker pointing toward the nearest safe re-entry point. Radiation damage starts at 1% of maximum hull per second and adds 0.5 percentage points per second of continuous exposure. It uses the existing shield absorption/hull damage and rescue rules. Exposure resets immediately inside the sphere or on rescue. Only the authority applies damage; multiplayer menus do not stop exposure. These rates remain provisional.

Following playtesting, the user approved replacing the paired world-axis maps with ship-relative navigation. One local radar keeps forward at the top, left/right aligned with steering, and height arrows for contacts above or below. Its range buttons select 250, 500, 1,000 or 2,400 m. A destination compass shows turn guidance, distance and relative height; forward contacts use a filled dot and contacts behind use a hollow dot. Manual alien selection updates the waypoint. Radiation temporarily guides toward the nearest safe re-entry point, then restores the chosen destination.

The user accepted the current map and navigation after playtesting. The center destination panel aligns its bottom with the ship-health and selected-enemy panels at every supported window size.

The sector overview supports direct clicks on contact markers, names and height lines, with hover feedback. A left click selects on release; holding left mouse and dragging at least six pixels rotates the view horizontally and vertically without selecting. Right-mouse drag also rotates. Mouse wheel zooms around the pointer from 0.6× to 3× without requiring a modifier key, with clipping inside the map panel. Reset view restores the original angle, zoom and center. These controls affect presentation only.

M opens a larger sector overview with a rotatable height projection and contact list. Clicking a contact or its row sets the destination and returns to flight; alien destinations also use normal combat selection, while outpost/friendly destinations clear the combat target. M or Esc closes it. Opening releases steering and disables automatic fire. Solo simulation pauses; multiplayer and radiation continue on the server. Rescue and disconnect close the overview, and missing contacts fall back to the outpost. This adds navigation controls within the current sector, with no fog of war or arbitrary-coordinate waypoints. Network schema 6 adds exposure and random home state and deliberately rejects older builds, including PR 34's schema 4.

### Death and recovery

The agreed starting direction is to retain owned ships and installed equipment, respawn at the station, and apply a modest repair cost. Losing some unbanked loot is a possible additional penalty to test.

Death should create consequences without routinely erasing hours of progress. Exact repair costs and loot-loss rules are deliberately undecided.

### PvP

Player-versus-player combat is a planned feature, introduced after cooperative combat is working. Its eventual presence is agreed; its location and rules are not yet settled.

Protected starting areas and dangerous PvP sectors are the current recommendation. Open-world attacks, duels, safe-area boundaries, and PvP-specific penalties remain design questions.

## Progression and rewards

Progression should include some grinding, substantially less than the original DarkOrbit experience. Players should receive useful smaller improvements regularly while saving for larger purchases.

Initial balancing proposals:

| Goal | Proposed effort |
| --- | --- |
| First equipment upgrade | Within the first 15 to 30 minutes |
| Further small upgrade | A few successful hunts or missions |
| Progress toward a major purchase | Noticeable during a normal evening of play |
| New ship or major equipment upgrade | Several sessions |

These are playtesting targets, not fixed timers or final economy values.

Progression uses credits, equipment upgrades and collectible resources sold at the station. The user requested all twelve modeled base hulls as purchasable ships, with newer DarkOrbit stats and credit prices; Uridium-priced hulls cost 100 times their reference price in credits. Yamato and Defcom are user-requested exceptions at 150,000 credits each, between Piranha and Nostromo, retaining the newer stats. See [playable ships](docs/ships.md) for the exact roster and assumptions.

Proposed progression principles:

- Start with a ship that is already enjoyable to fly and fight with.
- Let early weapon, shield, and engine upgrades provide clear improvements.
- Give later ships different strengths while retaining meaningful power progression.
- Offer predictable progress through hunting and missions.
- Reward useful contributions to group fights. Determine reward-sharing rules during implementation.
- Allow rare drops to add excitement without making luck necessary for basic advancement.
- Avoid extreme grind and paid power advantages.

Exact prices, ship roles, upgrade limits, rewards, and sector unlocks remain open.

Preview playtesting includes an optional station-shop button to add 100,000 test
credits without restarting the server. The server enables it only for explicitly
allowlisted private test pilots; it is disabled by default. Grants commit through
the normal persistence path with duplicate-request protection and preserve owned
equipment and contract progress. Production does not enable these tools. Seeded
wallets are for testing equipment behavior, not measuring the economy's progression
speed. See README.md for configuration and use.

### Docked main menu and launch

Normal clients connect to the persistent server into a docked pilot console before
entering the map. The user requested a station-console layout inspired by the
supplied reference, with a central green Start button, blue navigation panels,
saved credits and active-ship preparation. Hangar, shop, quests (the existing
hunting contracts), cargo trading, settings and connection management use the
existing screens. Skylab and Galaxy Gates are visible coming-soon pages; their
gameplay is not implemented in this milestone.

Docked pilots can buy ships/equipment, activate owned hulls, fit items, trade saved
cargo and accept or abandon hunts through the same server-validated persistence
paths. Their internal ship state is hidden from other pilots and has no collision,
movement, fire, alien targeting or loot pickup until Start is acknowledged by the
server. Fitting and launch preserve current health, charge and cooldowns. Esc and
screen Back actions return to the console without launching. Start closes station
pages and launches the selected hull at the existing station spawn. Reconnection
requires a fresh explicit launch; saved progression is retained. Menus opened
after launch retain the existing live-world station and pause behavior.

After launch, Esc > Quit to main menu leaves the map from any position without
disconnecting. The server returns the internal ship to its station spawn, removes
it from other pilots' maps, clears movement/fire and its current encounter
contributions, and invalidates commands from that flight. Credits, inventory,
fitting, cargo and quests remain. Returning grants no immediate repair or refill;
normal shield recovery, weapon and damage cooldowns continue while docked. A
pending rescue completes in the menu with its existing fee and timer; Start is
unavailable until the ship is alive. Start can then launch the prepared ship again.

The console fits 960 x 600 through 1440 x 900 and larger windows; station panels
scale to leave its persistent launch/navigation header accessible. Client and
server builds must match (network schema 7 adds docked state and launch RPCs).

### First station equipment shop and fitting

The first Milestone 3 equipment slice added fittings for the Liberator starter. It now supports the twelve modeled hulls, each with its own slot counts, owned equipment and cargo.

- Each equipment item is individually owned, either in storage or installed in exactly one slot on one owned ship. Players may buy multiple copies of each model.
- Ships own their fittings. Installing, removing and transferring items between owned ships is free at the station. Switching ships will not move equipment automatically.
- The starter follows the regular Liberator: four laser slots, six shared generator slots and two extra slots reserved for future equipment. A generator slot accepts either a shield generator or an engine.
- Lasers add damage, shield generators add shield capacity, and engines add speed. Damage, capacity and speed bonuses stack by addition. Shield absorption is the capacity-weighted average of installed shield generators, never the sum of their percentages. Hull and base movement belong to the ship; empty slots never prevent flight.
- New pilots receive one laser, one shield generator and one engine installed. Existing saves receive the same starter fitting exactly once, retaining credits and unrelated progression fields.
- Press B near the station for the shop and I for a separate ship equipment screen. Both use the repair checks: alive, within 60 m, speed at most 8 m/s, and at least five seconds since damage. The server checks every action again.
- The shop has category navigation, a scrollable two-column item catalog, a selected-item preview and a purchase summary. Weapons contain lasers; generators have shield and engine submenus. All equipment shows 18 reference models: five lasers, seven shields and six engines, including unavailable LF-4 and SG3N-B00 previews. Ships lists all twelve modeled base hulls with stats, credits and ownership. Selecting categories or items never purchases anything. Equipment uses the same artwork as inventory; ships use their saved model renders.
- The shop shows visual item cards, prices and credits, and delivers equipment to inventory and empty hulls to the hangar. The equipment screen shows the active ship's model preview and an owned-ship selector on the left, its actual laser and shared generator slots in the middle, and scrollable storage inventory on the right. Activate an owned hull for free at the station; switching preserves absolute hull, shield charge, boost energy and cooldowns, clamped to the new fitting. Drag items to compatible empty slots to install them, or back to inventory to remove them. Selecting an item and clicking an empty slot, plus a removal button, also supports keyboard use. Occupied slots require removal first.
- Current and proposed damage, shield capacity, absorption, cruise and boost speeds remain visible. Unavailable purchases and fitting actions explain why. B, I and C switch station screens; Esc returns to flight. Generated item art and a temporary ship preview do not depend on the final ship models.
- Fitting changes never repair hull, refill shields or boost energy, or reset weapon cooldowns. Added shield capacity starts empty and recovers through the normal shield regeneration rules. Removing capacity discards excess charge.
- The server commits a purchase's credit deduction, new item and request sequence together. Successful requests cannot run again, even after restart. A new intentional purchase uses the next sequence. Inventory and fittings survive death, reconnects and server restarts.
- No equipment selling, trading, rarity, equipment leveling, loot acquisition or assembly are included. Resource cargo and sales are described below.

### DarkOrbit reference equipment catalog

The user requested the models in four supplied screenshots, with their damage, shield, absorption and speed values. All purchases use credits: multiply a DarkOrbit Uridium price by **100**. Screenshot values take precedence over older FAQ entries (SG3N-A03 costs 128,000 credits; SG3N-B01 has 9,500 capacity). LF-4 and SG3N-B00 show their stats but remain unavailable until a future loot/assembly system, as explicitly chosen by the user. The server rejects their purchase intents; neither is a free item.

| Model | Price | Bonus per installed item |
| --- | --- | --- |
| LF-1 | 10,000 CR | +65 damage per shot |
| MP-1 | 40,000 CR | +70 damage per shot |
| LF-2 | 500,000 CR (5,000 U) | +140 damage per shot |
| LF-3 | 1,000,000 CR (10,000 U) | +175 damage per shot; +15% for this laser against aliens (201.25 total) |
| LF-4 | Unavailable: future loot/assembly | +200 damage per shot |
| SG3N-A01 | 8,000 CR | +1,000 shield / 40% absorption |
| SG3N-A02 | 16,000 CR | +2,000 shield / 50% absorption |
| FS-01 | 256,000 CR | +3,200 shield / 70% absorption; +6.25% shield regeneration |
| SG3N-A03 | 128,000 CR | +5,000 shield / 60% absorption |
| SG3N-B00 | Unavailable: future assembly | +9,000 shield / 70% absorption |
| SG3N-B01 | 250,000 CR (2,500 U) | +9,500 shield / 70% absorption |
| SG3N-B02 | 1,000,000 CR (10,000 U) | +10,000 shield / 80% absorption |
| G3N-1010 | 2,000 CR | +2 m/s cruise and boost |
| G3N-2010 | 4,000 CR | +3 m/s cruise and boost |
| G3N-3210 | 8,000 CR | +4 m/s cruise and boost |
| G3N-3310 | 16,000 CR | +5 m/s cruise and boost |
| G3N-6900 | 100,000 CR (1,000 U) | +7 m/s cruise and boost |
| G3N-7900 | 200,000 CR (2,000 U) | +10 m/s cruise and boost |

Missing laser damage comes from the official [assembly/upgrading balance FAQ](https://board-en.darkorbit.com/threads/new-assembly-upgrading-system-faq.124627/) (LF-1 65, MP-1 70, LF-2 140) and the newer [equipment FAQ](https://board-es.darkorbit.com/threads/faqs-objetos-de-equipamiento-armas-generadores-y-extras.147201/) (LF-3 175 plus 15% against NPCs, LF-4 200). Published FAQs differ for MP-1; the balance update's 70 is used. The newer equipment table clarifies that LF-3's bonus is a percentage, resolving the older English FAQ's ambiguous flat 15. The older [generator FAQ](https://board-en.darkorbit.com/threads/generators-faq.968/) supplies former Uridium shop prices for B01/B02 and explains cumulative fusion regeneration. The screenshots govern the updated shield capacities and listed credit prices. These reference prices replace the former provisional shop prices; progression speed needs playtesting.

The starter uses the regular Liberator's 116,000 hull and 4 laser / 6 generator / 2 extra slots, confirmed by the [official ship FAQ](https://board-es.darkorbit.com/threads/faqs-naves-y-disenos.147561/). The user chose the regular ship rather than the supplied Liberator Plus hull. The persisted `pathfinder` model ID stays unchanged so existing equipment, ownership and cargo need no destructive migration; the UI calls it Liberator. The subsequent ship integration expands Liberator cargo to its reference 400 units without losing saved cargo.

Empty Liberator fittings have no laser damage or shield capacity, 33 m/s cruise and 75 m/s boost (330 DarkOrbit units converted at 0.1 m/s per unit). New pilots retain the agreed starter fitting: one LF-1, one SG3N-A01 and one original Ion engine, for 65 damage, 1,000 shield with 40% absorption, 41 m/s cruise and 83 m/s boost. Persisted `laser` and `shield` IDs now display LF-1 and SG3N-A01; the original `engine` ID remains valid with its +8 m/s bonus. Original Ion engines stay owned and transferable but are hidden from the shop and cannot be purchased. Existing purchases and assignments are preserved without a save migration. Four starter lasers deal 260 per shot. Six starter shields provide 6,000 capacity with 40% absorption. New G3N models use the screenshot bonuses in m/s for both cruise and boost. Acceleration remains 40 m/s² and laser interval remains 0.42 seconds. Extra-slot items follow later.

Installed LF-3 bonuses add 26.25 damage per copy (15% of 175) only when shooting an alien, on top of additive base laser damage; they never multiply other installed lasers. Each installed FS-01 adds 6.25 percentage points to the regeneration bonus (two give +12.5%); the multiplier applies to the normal capacity-based recovery rate, retains Dorbit's existing six-second recovery delay, and caps at maximum shield. Removing or storing either model removes its special bonus. Fitting never grants charge. Current fitting and proposed changes display both bonuses. Equipment remains server-authoritative, with both additional stats replicated to clients. Network schema 6 includes hull model, maximum hull and both equipment bonuses, and requires matching client/server builds; save schema 3 is unchanged. Updated provisioning tools accept every reference model and preserve them during credential rotation.

For 80% absorption, a 100-damage hit takes 80 shield and 20 hull. With only 30 shield remaining it takes 30 shield and 70 hull. No shield means the entire hit damages hull. Starter shields use 40%; all current aliens use 80%. Hull can reach zero while shield remains. Shield recovery waits six seconds without damage, then restores one twelfth of maximum capacity per second. Station fitting never refills charge. Repairs cost `ceil(missing hull fraction × 14.4)` credits, capped at the wallet, preserving the old full-hull price of 15 CR at the new scale; rescue still costs up to 10 CR.

Alien values are Dorbit playtesting choices, not copied DarkOrbit alien stats. With continuous in-range fire and no regeneration, one starter laser kills a Scout in about 9.7 seconds; three lasers kill a Sentinel in about 12.6 seconds; four lasers kill a Heavy in about 23.9 seconds. Scouts suit starter solo hunts, Sentinels reward filling laser slots, and Heavy damage encourages a group. Kill pools, contracts and resource payouts stay unchanged. The former 15–30 minute purchase estimates no longer describe this balance; actual progression timing and multi-pilot encounters need human playtesting.

### Enemy resources, cargo and station sales

This agreed Milestone 3 addition extends alien hunting with physical resource boxes, limited ship cargo and resource sales at Outpost 01. The seven resources follow the supplied reference order, with increasing value. Existing kill credits and hunting-contract rewards remain in place.

| Resource | Credits per unit | Scout drop | Sentinel drop | Heavy drop |
| --- | --- | --- | --- | --- |
| Prometium | 1 | 6 to 10 | 10 to 16 | 18 to 24 |
| Endurium | 2 | 2 to 4 | 6 to 10 | 12 to 18 |
| Terbium | 4 | 1 to 2 | 4 to 6 | 8 to 12 |
| Prometid | 8 | None | 2 to 4 | 6 to 10 |
| Duranium | 16 | None | 1 to 2 | 4 to 6 |
| Promerium | 32 | None | None | 2 to 4 |
| Seprom | 64 | None | None | 1 to 2 |

Each alien leaves one shared box at its destruction position. The server rolls quantities once; damage repeats and client claims cannot create drops. Stronger types always drop more total units and include more valuable resources.

Living ships collect automatically within 12 m. The nearest ship with free capacity collects first; exact distance ties use peer-ID order. Any connected pilot can collect, independently of kill-credit contribution eligibility. Partial pickups take the most valuable resources first and leave excess units for another pilot or a later trip. Uncollected boxes expire after three minutes. At most 64 boxes exist; a new drop replaces the oldest when that limit is reached. Late joiners receive current boxes. Space loot resets with the server session.

The Liberator holds 400 units; every resource uses one unit. Capacity is defined by ship model for future ship types, and cargo belongs to each individual owned ship. The flight HUD shows usage and FULL status; the station cargo page lists resource quantities, prices and total sale value. Collected cargo survives death, reconnects and server restarts. A future death penalty needs a separate decision.

Press B at Outpost 01 and choose Trade raw materials. Seven horizontal ore cards use the colored images from the supplied resource screenshots, with unit prices, held amounts, minus/plus and editable quantity controls, sale totals and Sell buttons. Select a quantity of one resource or sell all active-ship cargo. Sales use the station restrictions: alive, within 60 m, at most 8 m/s and five seconds since damage. The server validates the selected amount and saves cargo removal, credit payment and the transaction sequence together before confirming success. Duplicate and stale requests cannot pay twice. A sale that exceeds the wallet limit leaves all cargo intact. Cargo collection also commits before removing units from space; a save failure stops progression.

Save schema 3 adds validated per-ship cargo. Versions 1 and 2 migrate once to empty holds while retaining credits, equipment, contracts and unrelated progression. The operator provisioning tool preserves cargo when rotating credentials. Older servers cannot read schema 3; rollback requires a pre-migration ledger backup.

Capacity, pickup distance, box lifetime, quantities and prices are provisional playtest values. Resource income changes the previous equipment-price estimates; hunting and selling need human economy playtesting before prices are finalized. Crafting, refining, resource missions and additional playable ships are outside this addition.

## Multiplayer and hosting

### Dedicated server direction

The user chose a dedicated Linux server at the start of Milestone 3. Everyone connects to the same server; playing alone means being the only connected pilot. The server runs independently of any player's game client and controls movement, alien behavior, damage, rewards and action validation. The normal client has a connection menu and does not fall back to a playable offline world.

The first implementation runs headlessly from source with Godot 4.7.2 on Linux x86-64, initially in Ubuntu on WSL2. It supports ten client pilots without a host ship and keeps simulating when everyone disconnects. The original solo/listen-host modes remain development fixtures behind `--offline`, not a separate progression path for normal play.

The persistence slice adds operator-provisioned stable pilot IDs and private credentials, with one login per pilot. The server saves credits after each reward or charge and restores them on reconnect or restart. Invalid saves and write failures stop progression for operator recovery; each successful write retains the previous ledger as a backup. Save ownership belongs to the server; there is no client-owned wallet to transfer between worlds. Position, health and encounter objectives remain session state. Equipment purchases follow this slice.

A netcup Linux VPS has passed initial two-client internet testing. The graceful shutdown fix is deployed and has passed a live stop/start and full VPS reboot with unchanged saved credits. A separate VPS systemd service passed a two-release update/rollback rehearsal. Abrupt crashes and power loss still require operator recovery. Scheduled off-machine backups remain hosting work. Pilot provisioning, token rotation and save recovery are documented in README.md. ENet traffic remains unencrypted; the user chose Tailscale for private friend-group access. The VPS and both operator PCs are enrolled, with key-only OpenSSH and game access over Tailscale; restricted friend-group grants remain to be configured as described in DEPLOYMENT.md. No public account service or automatic matchmaking is included in the initial server.

### PR playtesting on the existing VPS

One manually deployed preview instance shares the current VPS with production.
The operator chooses an open PR from this repository; Linux server and Windows
client are checked and built from the same frozen head commit before preview
deployment. Gameplay PRs can remain unmerged during playtesting, including stacked
branches such as equipment and contracts. Fork PRs cannot deploy.

Preview has its own service, Linux user, deployment key, UDP port, private test
pilot and save directory per PR. An explicit fresh-save option archives old test
data first. Production saves and pilot credentials are never copied into preview.
The operator can stop preview before a production session with friends. Preview
does not start at boot. No CPU or memory limits are needed for the current solo
development phase; both instances share host resources. Production deployment
remains a separate manual action. See DEPLOYMENT.md for setup and recovery.

## Performance

Reference PC supplied by the user:

- CPU: AMD Ryzen 7 5800X.
- RAM: 16 GB.
- GPU: AMD Radeon RX 7600.

Other players generally have Ryzen 5 7600X-class or better CPUs, 32 GB RAM, and RX 6800-class or better GPUs.

The proposed target is 60 FPS at 1440p on the reference PC, with adjustable graphics settings. This is a development target requiring measurement, not an established minimum specification or a performance guarantee.

Test representative encounters with approximately 10 players, active aliens, and weapon effects. Determine the alien count and scene complexity budget through measurement. Check performance throughout development, starting with the first prototype.

## Art and tools

Use placeholder ships, a simple station, and basic effects initially. Custom modeling is not a prerequisite for the first playable version.

Blender is a free, open-source option for creating models later. Properly licensed third-party assets are another option.

Develop an original name, ship and alien designs, interface, and audio for any eventual public release. Dorbit is the current project name; DarkOrbit is the gameplay reference.

The precise visual style and detailed asset pipeline remain open. Improve models, lighting, effects, and sound progressively after the core gameplay works.

The user requested a separate Blender review collection of recognizable DarkOrbit ships. Following review, the broad first collection was removed and replaced with detailed base Aegis and Goliath models using the supplied image catalogue. The user approved that style and requested ten additional base hulls: Bigboy, Defcom, Leonov, Liberator, Nostromo, Phoenix, Piranha, Spearhead, Vengeance and Yamato. Subsequent reviews requested a Liberator shape correction and closer geometry, colors and detail across the collection. The user selected Aegis as the finished-quality benchmark; preserve that model while refining the other eleven against their supplied references. PR 14's editable studies remain in `art/ship-review`, outside Godot's imports. The user subsequently requested gameplay integration of all twelve; derived GLB meshes and model previews live under `assets/ships` and `assets/ui/ships`. The source studies are preserved. See [playable ships](docs/ships.md) for stats, pricing, export conventions and remaining art limitations.

### Outpost 01 environment art

The user requested a DarkOrbit-inspired map art pass during Milestone 3. The current
sector uses original blue/violet nebulae, a starfield, an ocean planet with cloud
cover and atmospheric shading, textured irregular asteroids, an industrial docking
station and distant derelict freighters. DarkOrbit map screenshots inform the
composition; no DarkOrbit assets are included.

Blender-generated GLBs and seamless stone textures are committed with their
generator. Godot remains the runtime and uses the existing Compatibility renderer.
Static nebula calculations bake into the sky cubemap; the background asteroid belt
uses three instanced meshes. Distant scenery has no collision or interaction and
now sits beyond the enlarged safe sector. Dedicated servers create only the existing
obstacle physics. The original 24 asteroid positions/radii, station colliders and
station services remain unchanged; sector size, radiation and random alien homes
are described above.

This is a visual pass on the current huntable sector. Connected maps, jump gates,
new ships and encounters remain separate work. Visual density and performance on
the group's devices still need human playtesting.

## Development milestones

### Milestone 1: Flight and one complete combat encounter

Create the Godot project in `D:\Dorbit` with one small sector, a placeholder station, one player ship, and one alien encounter.

Completion criteria:

1. Launch a playable Windows build.
2. Fly freely around the station using the agreed controls and camera.
3. Select an alien and fight it using automatically tracking lasers.
4. Take shield and hull damage.
5. Destroy the alien and receive a reward.
6. Return to the station and repair.
7. Support player destruction and respawning.

Use simple art and temporary balancing values. Save persistence is not required for this milestone. Record initial performance and evaluate flight, camera comfort, and target selection.

### Milestone 2: Shared multiplayer encounter

Connect two Windows computers over the internet and run the encounter in a shared sector. Establish server-controlled combat and rewards, then test with the full friend group.

Implementation steps:

1. Shared flight: host/join by address using ENet over UDP port 24567, up to 10 players, host-simulated movement and boost, replicated ships, and recoverable joins/disconnects. Accepted after the user verified multiple local instances and two physical PCs on the same network.
2. Shared combat: the host simulates one alien and validates damage, destruction, repairs, and rewards. Health and encounter state replicate to clients, while visual effects remain separate. The original solo encounter remains available.
3. Test two Windows PCs over the internet, tune prediction/interpolation under latency, and measure a representative friend-group encounter.

The initial transport works with LAN or VPN addresses, or a publicly reachable host with UDP port forwarding. It does not provide automatic NAT traversal, matchmaking, or host migration. The user successfully tested cross-network play; the exact connection method was not recorded. Opening a menu stops that player's movement and fire commands but leaves the shared world, including incoming damage, running.

Initial cooperative rules for playtesting:

- The alien attacks the nearest living player outside the station's protected 75 m radius, within its existing detection and leash ranges.
- A kill splits the 75-credit pool equally among currently connected players who damaged that alien during its current life, including contributors awaiting rescue. Integer remainders are distributed in ascending peer-ID order; shares differ by at most one credit. Disconnected players lose eligibility. Each eligible player receives one kill toward the encounter objective.
- Each player has a host-owned session wallet starting at zero. Shared credits are separate from solo credits and reset when that player leaves/rejoins. No persistent identities or saves are introduced here.
- The host validates repairs against that player's position, speed, time since damage, hull, and balance. Existing repair prices and the up-to-10-credit rescue fee remain provisional.
- Players respawn individually after three seconds at the station without resetting the alien for other players. The alien respawns once after 12 seconds. Old fire commands cannot carry into a new player or alien life.
- No PvP damage is enabled. Ships can block weapon line of sight but cannot push each other.

Completion criteria:

- Players see each other and interact with the same aliens.
- Damage, destruction, and rewards remain consistent across clients.
- Joining, leaving, and ordinary network latency are handled sensibly.
- A representative group encounter is checked for performance.

### Milestone 3: Repeatable progression

Add saved progression, equipment purchases, a second ship, a few alien types, and simple missions.

Implementation order after the agreed server architecture change:

1. Dedicated Linux server, normal Windows clients, WSL2 connection and shared-encounter validation.
2. Stable pilot identities, private-group access and server-owned saves, including restart recovery and backups.
3. Equipment purchases, a second ship, additional alien types and simple missions, with provisional prices tuned through playtesting.

Completion criteria:

- Players can hunt, earn rewards, repair, and buy meaningful upgrades.
- Progress survives restarting the server.
- Repeated sessions support frequent small upgrades and longer-term goals.
- Group reward rules and death penalties can be evaluated through playtesting.

### First station hunting contracts

Each pilot can run the Scout, Sentinel and Heavy hunting contracts together, with one active run per offer. Press C at Outpost 01 to accept hunts or abandon individual contracts. These station actions use the repair restrictions: alive, within 60 m, at most 8 m/s, and five seconds since the last hit. Opening the board stops local controls while the shared world continues. The flight HUD shows every active hunt.

The contract board follows the supplied Mission Control reference: hunting and active-contract tabs, a selectable hunt list beside the station uplink image, and a detail pane with briefing, objective progress and credit reward. Selecting a hunt previews it; a separate footer button accepts or abandons the selected run. The footer shows remaining contract slots and explains blocked station actions. The existing three hunts, concurrent acceptance and automatic payouts remain the scope.

| Alien | Required kills | Fixed contract reward |
| --- | --- | --- |
| Scout | 3 | 90 credits |
| Sentinel | 2 | 150 credits |
| Heavy | 1 | 200 credits |

Counts and rewards are provisional values for short hunting trips. Accepted contracts retain their original terms if later updates tune the offers.

Only qualifying kills after acceptance count. The existing encounter contribution rules decide eligibility, including connected contributors awaiting rescue. Every eligible pilot with a matching contract earns one full kill of progress, independently of the split kill-credit pool. Death preserves all contracts and progress. The final qualifying kill automatically grants the fixed hunting reward once and clears that run, wherever the pilot is. Other hunts remain active.

A full wallet keeps the completed contract until it can receive the entire reward, then pays automatically when there is room. Abandonment clears only the selected run without charging credits. A cleared offer can be accepted again at the station. The server saves kill progress, kill-credit shares, automatic rewards and cleared runs together before publishing them. Contracts and pending rewards survive reconnects and server restarts. Stale abandonment requests identify their original accepted run. Existing single-contract saves migrate with their accepted terms and progress intact; completed legacy hunts pay automatically.

Hunting quests do not require returning to the station for payment. Future resource-collection or special-item quests may require station delivery; those quest types are outside this slice. This slice depends on persistent pilots and the multiple-alien sector. It adds no timers, daily limits, chains, party missions or mission scripting framework. Equipment and ship purchases remain separate feature work.

### Milestone 4: Expansion and polish

Gradually add connected sectors, additional enemies and equipment, PvP rules, improved art and sound, and independent server hosting.

The order within this stage should follow playtesting feedback. A large universe, extensive ship roster, and public release are not prerequisites for a successful private game.

## Open decisions

The following do not prevent beginning the first prototype:

- Exact movement, camera, weapon, and alien tuning.
- Repair costs and whether destruction loses unbanked loot.
- PvP locations, safe-area rules, and PvP penalties.
- Equipment prices, reward amounts, ship roles, and progression limits.
- Detailed art direction and asset selection.
- Final performance budgets for aliens and effects.

Before deploying progression, configure the private network, dated off-machine backups and independent hosting operations.

Local and LAN dedicated-server play have passed manual testing. Cross-network dedicated-server testing remains pending and does not block pilot identity and persistence work. Full Milestone 3 completion still requires purchases, additional content and repeat-session playtesting.
