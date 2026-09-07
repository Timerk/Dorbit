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
| Tab | Cycle nearby enemy targets |
| Space | Toggle automatic laser fire |
| Shift | Boost using rechargeable energy |

Full 3D movement does not require realistic spacecraft physics. Acceleration, braking, turning speed, camera behavior, and boost values remain tuning decisions.

## Combat

Players select an enemy and engage it with weapons that track the target. Precise manual aiming is not the basis of the initial combat system.

The starting combat proposal is:

- Lasers track the selected enemy within weapon range and a generous forward firing arc.
- Obstacles can block line of sight.
- Shields absorb damage before the hull.
- Destroying an alien grants a reward.
- The station supports repairs.
- Player ships and aliens use consistent targeting, weapon, shield, and damage rules where applicable.

Weapon ranges, firing arcs, damage, shield recovery, and alien behavior need playtesting. Additional weapons and abilities can follow after basic laser combat is enjoyable.

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

The first progression implementation should use one currency, a small selection of equipment upgrades, and a second ship to work toward. A material system can be considered later.

Proposed progression principles:

- Start with a ship that is already enjoyable to fly and fight with.
- Let early weapon, shield, and engine upgrades provide clear improvements.
- Give later ships different strengths while retaining meaningful power progression.
- Offer predictable progress through hunting and missions.
- Reward useful contributions to group fights. Determine reward-sharing rules during implementation.
- Allow rare drops to add excitement without making luck necessary for basic advancement.
- Avoid extreme grind and paid power advantages.

Exact prices, ship roles, upgrade limits, rewards, and sector unlocks remain open.

## Multiplayer and hosting

### Dedicated server direction

The user chose a dedicated Linux server at the start of Milestone 3. Everyone connects to the same server; playing alone means being the only connected pilot. The server runs independently of any player's game client and controls movement, alien behavior, damage, rewards and action validation. The normal client has a connection menu and does not fall back to a playable offline world.

The first implementation runs headlessly from source with Godot 4.7.2 on Linux x86-64, initially in Ubuntu on WSL2. It supports ten client pilots without a host ship and keeps simulating when everyone disconnects. The original solo/listen-host modes remain development fixtures behind `--offline`, not a separate progression path for normal play.

This first server slice still uses temporary session credits. Stable identities, private-group access control, server-owned saves, restart recovery and backups follow before equipment purchases. Save ownership belongs to the server; there is no client-owned wallet to transfer between worlds.

A small Linux VPS will follow local validation. Provider selection, measured resource requirements, service deployment, player identity details and backup operations remain to be implemented. No public account service or automatic matchmaking is included in the initial server.

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

Before deploying progression, finalize pilot identity, private-group access, save recovery and independent hosting operations.

The next step is testing Windows clients against the dedicated server in WSL2, followed by server-owned persistent progression. Full Milestone 3 completion still requires purchases, additional content and repeat-session playtesting.
