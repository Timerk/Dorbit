# Dorbit

A space game inspired by DarkOrbit, built with Godot. Windows players connect to a dedicated Linux server to fly, hunt aliens, earn rewards and repair together. Playing alone uses the same server encounter.

Milestones 1 and 2 have passed user playtesting. Milestone 3 has a dedicated server with provisioned pilot identities, persistent credits, hunting contracts, and station equipment purchases and fitting. The sector supports independent Scout, Sentinel and Heavy hunts. Outpost 01 has an original nebula/starfield background, a shaded planet, textured asteroid models and an industrial station. Combat uses procedural glowing lasers, shield ripples and hull sparks.

- [Game requirements and development plan](GAME_PLAN.md)
- [Development workflow](AGENTS.md)
- [Linux deployment, systemd, updates and rollback](DEPLOYMENT.md)
- [Blender ship review collection](art/ship-review/README.md)

## Play

### Flight HUD

The flight HUD follows the menu's graphite panels, amber accents and Rajdhani
typeface. Hunting Contracts and Local Radar share a small top margin; ship
health/boost, destination and target cards align along the bottom. The header
is removed, and credits/cargo quantities remain in the station menus. Cargo
FULL, pending rewards, notifications, station prompts, radiation and rescue
remain visible when relevant. Control keycaps use your current bindings.

Press **Ctrl + Alt** together during flight to customize the HUD. Drag a panel
or its title bar to move it, drag the lower-right corner to resize it, and use
its **×** to hide it. The editor's icon sidebar reopens or selects any instrument.
The reticle can be resized but always stays centered; it cannot be dragged to
another position, and older saved reticle positions are ignored.
The ammunition selector moves, resizes and hides as one horizontal bar. Its four
tiles stay together in x1–x4 order; select ammo by clicking a tile after editing.
Hide the sidebar to edit the whole screen; a Show sidebar button brings it back.
The grid makes editing clear and supports optional snapping. Panels preserve
their proportions and stop shrinking at 80% of their default size. **Escape**,
**Done**, or Ctrl + Alt finishes and saves positions, sizes and hidden panels on
this device. **Reset layout** restores the default arrangement. Custom layouts
adapt when resizing the game window. Editing stops your local controls and fire;
the multiplayer world continues. World contact markers still track their contacts,
and rescue/radiation effects still signal their gameplay states.

Review the [HUD editor](docs/feedback/hud-editor-1440.png) and a
[customized flight layout](docs/feedback/hud-customized-1440.png).

`tests/hud_customization_test.gd` checks real editor input, moving/resizing,
minimum sizes, closing/reopening, saved layouts, screen bounds and moved radar
buttons and ammunition tiles. Run with a renderer for editor and customized-flight screenshots in
`build/validation`, at 960, 1440 and 1920 pixel widths. Use an isolated APPDATA
profile for tests, as with the other settings/HUD checks.
The Windows build helper also runs `tests/hud_shortcut_export_test.gd` against
the exported pack: it launches actual offline flight and verifies Ctrl + left
Alt in both key orders with native Windows modifier flags.

See the [approved concept](docs/hud-design/README.md) and native
screenshots at [960×600](docs/feedback/hud-flight-960.png),
[1440×900](docs/feedback/hud-flight-1440.png) and
[1920×1080](docs/feedback/hud-flight-1920.png), plus
[contextual alerts](docs/feedback/hud-alerts-960.png),
[station actions](docs/feedback/hud-station-960.png) and
[radiation](docs/feedback/hud-radiation-960.png).
The sector overview shares the graphite surfaces, amber headings and waypoint
ring, with a muted grid and the existing contact colors. Native map screenshots:
[960×600](docs/feedback/hud-map-960.png),
[1440×900](docs/feedback/hud-map-1440.png) and
[1920×1080](docs/feedback/hud-map-1920.png).
`tests/hud_playthrough.gd` checks resizing, card alignment and separation,
caption displacement, native radar/map clicks, active-only autopilot and current
fire bindings/blockers. Its screenshots include illustrative contract/alert
states with simulation frozen; dedicated-server and contract tests separately
check authority and payouts. Run with a renderer for visual captures; both
check runners include its headless checks.

### Sector environment

The environment takes composition cues from DarkOrbit's planet and nebula maps,
adapted to full 3D flight. Original Blender assets replace the smooth placeholder
rocks and station. Distant freighter wrecks and an asteroid belt provide parallax
beyond the safe sector; they have no services, loot or collision. Physical
asteroids and the station retain their existing layout; aliens have random homes.

See [sector assets and regeneration](assets/sector/README.md) and
[environment validation](docs/sector-art/README.md) for screenshots and checks.
Blender is only required to regenerate assets, not to run, build or deploy the game.

### Navigation and radiation

The safe sector is a **2.4 km diameter sphere**, with free movement past its edge.
The upper-right radar follows your ship: forward is up, left/right match your
steering, and small arrows show contacts above or below. Green marks Outpost 01,
cyan marks other pilots, and aliens use their type colors. An amber ring identifies
your destination on the local radar. Use **− / +** to change range from 250 m to 2.4 km.
Press **M** or click Map for a larger sector overview. Click a contact or its row
to select a destination. Markers, names and height lines are clickable directly
on the map and highlight under the pointer. Hold left mouse and drag to rotate
horizontally or vertically; a short click selects instead of rotating. Right-mouse
drag also rotates. **Mouse wheel** zooms around the cursor, from 0.6× to
3×. **Reset view** restores rotation and zoom.
Choosing an alien also selects it for combat. Choosing the outpost or another
pilot clears the combat target. M or Esc returns to flight. Multiplayer keeps
running while the overview is open.

Press **P** to fly to the selected alien, friendly pilot or outpost. A small
**Autopilot enabled** label below the top-right radar appears while active.
P can be rebound in Settings. Clear
travel follows the shortest straight 3D route; obstacles use the shortest route
through sampled detour points, an approximation around the actual colliders.
Autopilot uses cruise speed and brakes to stop 20 m from ships or 50 m from the
outpost, within service range. It follows moving contacts without enabling
automatic fire or boost. Press P again, move or steer manually, change targets,
or open a menu to cancel. Target loss, rescue and disconnect also cancel it.
Radiation guidance takes priority until re-entry. A blocked route stops autopilot
with a message.

`tests/autopilot_test.gd` exercises direct and vertical travel, braking, real
asteroid detours, moving destinations, station arrival, cancellation and normal
authoritative ENet movement. Both check runners include it. Run with a renderer
to exercise the keyboard toggle and status label, and save 960 x 600 and 1440 x 900
captures under `build/validation`.

Review the [960 x 600 autopilot HUD](docs/feedback/autopilot-960.png) and
[1440 x 900 HUD](docs/feedback/autopilot-1440.png). The Windows check suite passed
on 7 October 2026; the autopilot fixture passed 37 rendered assertions,
including rebound keyboard input and status visibility. Linux execution is left to PR
CI. Routes and arrival tuning still need human playtesting.

The destination compass shows where to turn, distance and relative height.
Center its dot to face the destination; a hollow dot means it is behind you.
Radiation temporarily replaces your destination with the nearest safe return
point, then restores your choice when you re-enter. Alien homes are
randomized across the sphere at server startup and each respawn, retaining two
Scouts, two Sentinels and one Heavy.

The HUD warns within 120 m of the edge. Outside, an alert, red screen pulse and
border warn of **radiation**, and a return marker points to the nearest safe
space. Damage grows the longer you stay outside, using normal shields, hull and
rescue. Returning inside immediately resets exposure. Opening multiplayer menus
does not stop damage. Radiation currently starts at 1% of maximum hull per second,
increasing by 0.5 percentage points each second; these rates need playtesting.

Map size targets roughly **20–45 s across** with representative engine fittings,
using the reachable speeds in [ship PR 34](https://github.com/Timerk/Dorbit/pull/34).
It is not a hard travel-time limit: slower/empty hulls take longer, engine-heavy
fittings can be faster, and boost/acceleration affect the trip. See
[the game plan](GAME_PLAN.md#sector-size-radiation-and-3d-navigation) for examples.
The ship roster from PR 34 is included. Network schema 7 requires matching
server/client builds; clients from before the map update cannot connect.

Review the [960×600 radar and guidance](docs/feedback/map-navigation-960.png),
[1440×900 layout](docs/feedback/map-navigation-1440.png) and
[sector overview](docs/feedback/map-overview-960.png),
[rotated view](docs/feedback/map-overview-rotated-960.png) and
[zoomed view](docs/feedback/map-overview-zoom-960.png), plus the
[radiation alert](docs/feedback/map-radiation.png).
The map integration fixture (`tests/map_layout_test.gd`) checks 100 random homes,
respawn and late-join replication, every boundary axis, increasing authoritative
damage, re-entry, rescue, menu behavior and packet budgets over ENet. The flight
replay (`tests/map_layout_playthrough.gd`) crosses the edge through actual flight,
turns back to safety and checks ship-relative guidance, keyboard/menu behavior,
real mouse range/contact selection, rescue cleanup and both layouts with a renderer.
Both check runners include these fixtures. The single-encounter network combat
test keeps unrelated aliens away from its scripted encounter so random spawning
cannot alter damage and repair expectations. Human travel, encounter-density and
radiation tuning remain pending; Linux execution is left to PR CI.

### Preview test credits

On a preview server with test tools enabled, press **B** at Outpost 01 and choose
**Preview: +100,000,000 CR**. You can repeat this when you need another
shopping budget, without disconnecting or restarting the server. Credits save
immediately, can buy normal equipment, and survive reconnects and restarts.
Seeded sessions test item behavior; use an unseeded pilot to evaluate progression
speed and prices.

The operator enables this once in the preview service environment, for example
`/etc/dorbit-preview/server.env`, then deploys or restarts preview:

```ini
DORBIT_PREVIEW_TOOLS=1
DORBIT_PREVIEW_PILOTS=preview
```

`DORBIT_PREVIEW_PILOTS` is a comma-separated list of stable pilot IDs. Both
settings are required. Keep them out of the production service environment.
Clients cannot enable tools through their own environment or select a different
wallet. The button is hidden for other pilots and on servers without this opt-in.
Grants obey station-service rules and the credit cap. Duplicate requests cannot
grant twice, including after a reconnect or restart. Use matching client/server
builds; the original PR #15 client does not have this button.

The authenticated preview-credit checks run with both Windows and Linux check
commands. They cover disabled tools, allowed pilots, actual shop purchases,
duplicate requests, restart persistence, the credit cap and failed saves.
[Review the shop at 960 x 600](docs/feedback/preview-test-credits.png).

### Launch and controls

Launch `build/windows/Dorbit.exe` after building, or download the `Dorbit-Windows-<commit>-<attempt>` artifact from a successful GitHub Actions run. Extract the artifact, then its `windows.zip`, before playing and keep the included third-party notices with the executable.

Set `DORBIT_PILOT_FILE` to your private credential file as described below. Enter the server address and UDP port in the connection menu, then choose **Connect**. Use matching client and server builds.

After connecting, the **main menu** keeps your pilot docked before entering the
map. Visit **Shop** to buy ships and equipment, **Hangar** to activate a hull and
equip it, **Quests** to accept hunting contracts, or **Cargo trade** to sell saved
resources. **Settings** and **Connection** are also available. **Skylab** and
**Galaxy Gates** open coming-soon pages. Choose the amber **START** button on Overview
to spawn at Outpost 01 with your selected ship and fitting. Esc or Back returns to
the overview; these actions do not launch. Docked ships are hidden from other
pilots and cannot move, fight or collect loot. Each reconnect returns to this menu
with your saved credits, inventory, ships, cargo and quests.

To leave the map without disconnecting, press **Esc** and choose **Quit to main
menu**. This works from anywhere on the map and returns you to the docked console,
where Shop, Hangar and Quests are available before choosing **Start** again. Your
progression and current ship health/charge remain; returning does not repair or
refill the ship. Normal shield recovery and service cooldowns continue. If rescue
is pending, it finishes in the menu before Start becomes available. **Quit to
desktop** remains a separate action.

[Review the native menus and offline instructions](docs/menu-design/implementation.md).

The menu integration replay runs in both check commands and exercises actual
ENet admission, purchases, fitting, quests, launch, observer visibility and
reconnects. Run Godot with `--path . --script res://tests/main_menu_test.gd` in a
rendered window to capture the overview and station pages at 960 x 600 and
1440 x 900 under `build/validation/main-menu-*.png`.

[Overview](docs/menu-design/overview-implemented.png),
[Shop](docs/menu-design/shop-implemented.png), and
[Hangar](docs/menu-design/hangar-implemented.png) show the current layout.

The docked overview now has a live ship preview: drag to rotate, scroll to zoom,
or double-click to reset. The [ship material review](docs/ship-materials.md)
shows all twelve hulls with textured coated armor, exposed metal and distinct
cockpit glass in both the hangar and flight.

Downloading an artifact from the validation workflow does not deploy its server. To playtest an open PR, run **Actions > Deploy preview** for that PR, download the Windows client from that preview run and connect to the preview address and UDP port. See [preview playtesting](DEPLOYMENT.md#preview-a-pr-before-merging) for setup. Production uses its own matching release client. Incompatible client/server RPC definitions are rejected during connection with a build-mismatch message, before combat starts. This handshake requires both sides to be updated; older servers are rejected too.

1. Hold right mouse and move the mouse to steer. Use W/S for forward/backward movement, A/D to strafe, and Q/E to descend/rise.
2. Start with an amber Scout near the station approach. Tab selects the on-screen alien closest to the mouse cursor, or screen center while steering; left click selects the ship under the pointer. The lock persists beyond weapon range and when you turn away or the alien returns home. Space toggles automatic lasers. Enemy encounter resets stop automatic fire while retaining the lock; death clears it.
3. Keep the alien ahead, within 170 m, and clear of obstacles. Shift boosts while energy is available. Releasing movement brakes the ship.
4. Scout, Sentinel and Heavy kills grant pools of 30, 75 and 180 credits respectively, split equally among eligible contributors. Return within 60 m of the green outpost marker, slow below 8 m/s, and press R to repair. Repairs require five seconds without taking damage.

Shields split each hit between shield and hull: starter generators absorb 40%, aliens absorb 80%, and depleted shield damage spills into hull. After six seconds without damage, shields recover at one twelfth of capacity per second. Destruction returns the ship to the station after three seconds and costs up to 10 credits. Hull repairs cost up to 15 credits according to the missing hull percentage, capped at the available balance so a player with no credits can recover. Scouts respawn after 10 seconds, Sentinels after 12, and the Heavy after 18. Each encounter respawns independently.

Esc opens the flight menu and releases the mouse. Choose **Settings** there or in the connection menu. The Controls tab adjusts mouse sensitivity from 0.1x to 3x and rebinds movement, steering, targeting, fire, boost and repair. Select an action, then press a key or mouse button. Occupied bindings swap actions; Esc cancels capture. Restore default controls resets bindings and sensitivity. HUD prompts follow your bindings.

The Audio tab has master/effects volume, mute and a test sound. The Graphics tab contains fullscreen, VSync, antialiasing, the performance overlay and window resolution. VSync is off by default; enable it to synchronize rendering with your screen's refresh rate and reduce tearing. Resolution choices fit the current screen with room for borders and the taskbar. Selecting one switches to windowed mode; fullscreen uses the desktop resolution. You can also resize the window manually. Mouse steering uses unscaled screen motion so viewport scaling does not change sensitivity.

Changes apply immediately except anisotropic strength changes, which require restarting the game. Controls and graphics persist in `user://settings.cfg`, and existing audio preferences remain in `user://audio.cfg`. Esc returns to the previous menu. Fixed shortcuts remain available outside settings: F11 toggles fullscreen, F3 shows performance, F4 toggles antialiasing, and F5/F6 cycle resolutions while paused. F10 quits from a menu. The server keeps running while menus are open; losing focus releases your controls, but incoming damage can continue.

Graphics also includes 3D render scale (Off/native, 85%, 75%, 50%), anisotropic
filtering (Off/2x/4x/8x/16x), bloom/glow and ambient occlusion toggles, shadows
(Off/Low/Medium/High), and combat effects (Off/Low/High). Antialiasing offers
Off/2x/4x/8x MSAA. Settings save on this device. Reduced render scale keeps the
HUD and menus sharp.
Combat effects Off removes existing and future laser/impact/explosion meshes;
audio and gameplay continue. Low simplifies effects and caps them at 32 effect
roots with fewer child meshes.
High retains the new lasers, shield ripples and ship-sized destruction effects.
The default remains native rendering, new lighting/filtering options off, and
High combat effects. The game continues to use Godot's Compatibility renderer.
Compatibility reads anisotropic strength at startup. Strength choices write
`user://graphics-renderer.cfg`, loaded by Godot before renderer initialization
on the next launch; the menu shows the active strength and any pending restart.
Filtering Off switches material samplers immediately. Ship hulls, previews and
asteroids follow the filtering mode; asteroid textures include mipmaps. Existing
Off/4x antialiasing profiles migrate to the corresponding MSAA choice.

Run `tests/graphics_test.gd` headlessly with an isolated APPDATA profile, then
repeat with `-- --restart` and then `-- --filter-restart 2`,
`-- --filter-restart 3`, and `-- --filter-restart 4`, to
check menu application, every startup filtering strength, persistence, malformed
preferences and effects-independent damage/rewards. `tools/dev.ps1 check`
includes all five runs. Run `tests/graphics_playthrough.gd` with a rendered window
and an isolated profile to exercise keyboard toggles/popups and capture native
Graphics menu and effect screenshots under `build/validation/graphics`.

These values are initial tuning settings, not a finished economy or combat balance.

### Laser ammunition

Laser ammo is selected with **1 / 2 / 3 / 4** or the bottom-center ammo symbols.
x1 uses fitted laser damage; x2, x3 and x4 apply 2x, 3x and 4x damage, including
laser bonuses against aliens. Each fitted laser on the active ship consumes one
round per successful volley. For example, four fitted lasers consume four rounds.
Blocked shots use none, and insufficient rounds for the whole volley stop fire.
The destination tracker is now at top center.

The HUD and shop use generated metallic energy-cartridge artwork. Pilot lasers
match their icons: ice-blue x1, cyan x2, amber x3 and violet x4; aliens fire red.
Each network shot carries its firing ammo type so observers see the same color.
See the [ImageGen prompts](docs/ammo-art/generation-prompts.md) for the asset source.

Each new pilot receives **10,000 x1 shots**. Ammo is shared across owned ships and
survives rescue, reconnects and server restart. In **Shop > Ammo**, x1/x2/x3 cost
**10 / 50 / 100 credits per 100 shots**, as confirmed by the user. The quantity
field buys batches of 100, up to 10,000 batches / 1,000,000 rounds per order.
x4 is reserved for future quests and special rewards
and cannot be bought. Station purchase restrictions and duplicate protection apply.

Save schema **4** adds ammo and gives existing pilots the starter inventory once.
Back up the ledger before updating; older servers cannot read schema 5. Consumption
is committed before each volley, and a failed save stops progression. Client and
server need matching builds. Run `res://tests/ammo_test.gd` headlessly or with a
renderer to check purchases, multipliers, inventory recovery and HUD interactions;
rendered runs save shop and flight views under `build/validation/ammo-*.png`.

Review the [flight ammo bar](docs/feedback/ammo-flight-1440.png) and
[ammo shop](docs/feedback/ammo-shop-960.png). Windows ammo checks passed 129
assertions headlessly and 138 with OpenGL, covering million-round orders,
per-laser consumption, fitting changes, ship switches and all four network colors.
Related equipment, reference-equipment, ships, shop and network combat checks passed.
Earlier validation passed 28 combat effect checks, the rendered color gallery,
220 rendered HUD checks, the full Windows check helper and seven Python tests.
Human pricing and group-combat performance playtesting remain necessary; Linux
and exported-client checks are left to CI.

## Dedicated server and connections

The server supports **ten client pilots**, with no host player. It controls movement, boost, all five aliens, damage, repairs, rewards, destruction and respawning. It keeps running when the last player leaves. **F7** opens the connection menu; **Disconnect** returns to that menu. A server shutdown also returns clients to the menu.

The client remembers the last successfully connected address and UDP port on this device in `user://connection.cfg`. Failed or cancelled attempts do not replace it. After a disconnect, the fields stay filled in; choose **Connect again** or press Enter on the focused button to retry. You can edit either field or cancel a pending connection. Reconnecting is always manual. Connection messages identify the attempted endpoint and report failure or timeout without guessing the network cause.

Other living pilots have cyan markers with shield and hull bars and current/maximum values. Hull turns red at 30% or below. Their health reflects server state, including repairs. Markers disappear on destruction and return on respawn.

Each alien kill splits its credit pool among connected pilots who damaged that alien in its current life; integer shares differ by at most one credit. Dead contributors remain eligible while connected. Spectators receive no reward. Each contributor receives one kill. Leash returns reset health and contribution eligibility; returning aliens cannot be damaged. Station protection blocks combat in both directions. Repairs and the up-to-10-credit rescue fee are charged to the requesting pilot's saved server balance. Credits are capped at 2 billion.

Credits survive disconnects and server restarts. Ship position, health, kills and encounter objectives reset on a new connection. The former solo/listen-host modes are development fixtures with temporary wallets, accessible by launching with `--offline` after Godot's `--` separator or `Dorbit.exe -- --offline`. Offline mode opens the main menu: START enters the solo encounter, and the Esc menu's Quit to main menu returns to it. Every page can be browsed offline before and after launch, including all three Settings tabs. During flight, use **Esc > Ship menus**, or **B** (Shop), **I** (Hangar), **C** (Quests) and **F7** (Connection). These open the same header and sidebar without docking. **Resume flight** or **Esc** closes the menus; START is shown only on the preflight Overview. Hangar shows the solo starter fitting; catalog and quest selections are local previews. Buying, selling, fitting, hull activation and accepting or abandoning quests stay disabled until connected to a dedicated server. Offline fixtures cannot read or transfer the dedicated server's wallets.

### Hunting contracts

Press C at Outpost 01 to accept repeatable hunts: 3 Scouts for 900 credits, 2 Sentinels for 4,500, and 1 Heavy for 30,000. All three can run together, with one active run of each offer. The final qualifying kill automatically pays its reward in flight and clears that hunt. The board and flight HUD track all active hunts. C or Esc returns to flight.

Accepting or abandoning a hunt requires the same position, speed and damage cooldown as repairs. Each eligible contributor earns a full kill of matching progress after acceptance, separately from split kill credits. Death preserves progress. Abandonment costs nothing and removes only the selected hunt. Completed or abandoned offers can be accepted again at the station. Counts and rewards need playtesting.

Contracts and their accepted terms are saved with the pilot. Kill progress, credit shares, automatic rewards and cleared runs commit together. Completed runs cannot pay twice. A wallet too close to the credit cap keeps the whole reward pending and pays automatically after credits are spent. Existing version-1 ledgers without contracts load with no active hunts; legacy single-contract saves retain their run and progress, and completed legacy hunts pay automatically on connection. Malformed contract data stops startup for recovery. Updated saves use the `contracts` collection; use matching client and server builds and back up saves before upgrading. Older single-contract builds cannot read the new progression correctly.

### Provision the private group

The operator assigns each pilot a stable lowercase ID and a random 256-bit token. There is no self-registration or password service. Stop the server before adding pilots or rotating credentials. Keep data outside the checkout and exported build, on a local filesystem.

On Linux, as the user that will run the server:

```bash
umask 077
mkdir -p "$HOME/dorbit-data" "$HOME/dorbit-credentials"
python3 tools/pilots.py "$HOME/dorbit-data" alex "$HOME/dorbit-credentials/alex.json" --init
python3 tools/pilots.py "$HOME/dorbit-data" sam "$HOME/dorbit-credentials/sam.json"
export DORBIT_DATA_DIR="$HOME/dorbit-data"
bash tools/server.sh run
```

Use `--init` only for the first pilot in a new ledger. A missing or invalid save prevents startup. The tool never prints tokens. Give each player only their own credential file through a private channel. Protect `pilots.json`, its backups, and credential files; the saved verifier can also authenticate. The Linux helper applies `umask 077`; apply it yourself if launching Godot directly. On Windows, use a directory accessible only to your user account.

On the Windows client, launch from PowerShell with the credential path set:

```powershell
$env:DORBIT_PILOT_FILE = 'C:\Users\YOUR_USER\Dorbit\alex.json'
& 'C:\Games\Dorbit\Dorbit.exe'
```

The client reads this file when connecting. The file contains only `id` and `token`; it contains no balance. For another pilot, restart with that pilot's file. Connection-menu integrations can supply `FlightSession.credential_id` and `credential_token` before calling the existing `join(address, port)` method. The menu remembers successful server addresses separately from pilot credentials.

Authentication uses a fresh server challenge and HMAC-SHA256 proof. The token is never sent over ENet. Unknown IDs, wrong proofs and duplicate logins fail before spawning or receiving world snapshots. The first connected login keeps its session; the newcomer is rejected. After an abrupt network loss, wait for ENet to detect the disconnect before retrying. Authentication attempts time out after five seconds. Gameplay RPCs use the authenticated peer mapping and never accept a pilot ID or balance.

ENet gameplay traffic is not encrypted and this handshake does not authenticate the server. Use a trusted LAN or private VPN, such as WireGuard, for the group. It is not a public-internet account or transport security service.

To replace a lost or exposed credential while preserving credits, stop the server and run:

```bash
python3 tools/pilots.py "$HOME/dorbit-data" alex "$HOME/dorbit-credentials/alex-new.json" --rotate
```

Distribute the new file and restart. The old token no longer works. To revoke access without redistributing a token, rotate it and retain the new file with the operator. Keep the same ID to keep the wallet. Do not rename a pilot or change credentials while the server runs.

### Station equipment

Press **B** within 60 m of Outpost 01 while moving at most 8 m/s and five seconds clear of damage to open the station shop. Purchases go into inventory. Press **I** for ship equipment, with the active hull's model preview and owned-ship selector on the left, its laser, shared generator and reserved extra slots in the middle, and scrollable inventory on the right. Drag an item into a compatible empty slot to equip it, or from a slot back into inventory to remove it for free. Shields and engines share generator slots. Remove an installed item before replacing it. You can also select an item and click an empty slot, or use Tab and Enter with the slot and removal controls. The screen previews resulting stats and explains blocked actions. The server keeps running while it is open.

B, I and C switch between Shop, Hangar and Quests in the shared sidebar. Only one page is visible at a time; Esc resumes flight and F7 opens Connection. The flight pause popup stays hidden while browsing menus.

The shop has category tabs, a scrollable item grid, a large item preview and a purchase summary. Browse Weapons, Generators, Shields or Engines, select a card, then type a quantity or use **+ / −** to change it by one. Use BUY to purchase the selected 1–999 copies into storage. The summary shows the total cost and remaining balance; insufficient funds reject the entire batch. Selecting another item resets the quantity to one. All equipment shows 18 reference models: five lasers, seven shields and six engines. LF-4 and SG3N-B00 show their stats but remain unavailable until future loot/assembly. Ships lists all twelve modeled hulls with their stats, credit prices and ownership. Buy ship delivers an empty hull to the hangar. Choose it in Ship equipment and press ACTIVATE at the station; fittings and cargo stay with their hulls, and switching does not repair or refill them. Each model can be owned once, including the free Phoenix; the starter Liberator counts as already owned. See [playable ships](docs/ships.md) for the roster, prices and reference sources. The summary shows owned copies, the price, the remaining balance and any purchase blocker. Purchases do not equip items or change ship stats.

Review the new [lasers](docs/feedback/darkorbit-lasers.png), [shields](docs/feedback/darkorbit-shields.png), [engines](docs/feedback/darkorbit-engines.png), [unavailable LF-4](docs/feedback/darkorbit-unavailable.png) and [mixed fitting](docs/feedback/darkorbit-fitting.png) at 960 x 600. The shop test covers category filters, catalog scrolling, real mouse card selection, B/I/C navigation, authenticated purchases, double-click blocking, ownership updates, insufficient funds, station restrictions and layout with preview tools at 960 x 600 and 1440 x 900. It runs in both standard check commands. To capture fresh shop screenshots, run Godot with `--path . --script res://tests/shop_test.gd` in a rendered window.

Review quantity purchasing at [960 x 600](docs/feedback/shop-quantity-960.png) and [1440 x 900](docs/feedback/shop-quantity-1440.png). On 7 October 2026, the shop test passed 82 headless and 90 rendered Windows checks, including real typing and plus/minus clicks, invalid input, batch affordability, unique stored item IDs, duplicate requests, restart persistence and a 999-item purchase. Equipment checks passed 134 assertions including an atomic failed bulk save; the reference catalog passed 131, main menus 277, offline menus 258 and RPC compatibility 13. The compatibility fixture retains its existing ObjectDB cleanup warning. Linux and exported-client checks are left to PR CI.

[Review the equipment screen at 960 x 600](docs/feedback/rebalance-equipment.png) and [the lower generator and extra slots](docs/feedback/rebalance-extra-slots.png). Open Hangar in the docked main menu to prepare equipment before Start, or press I near the station during flight. Inventory groups weapons, shield generators, speed generators and extras in that order. Choose All equipment or a category in the inventory filter. Shift + left click equips a stored item into the first compatible empty slot on the active ship; full slots leave the item in inventory with an explanation. Shields and speed generators share the generator slots; extras remain reserved. Back and Esc return to the docked overview without launching; Start keeps the prepared fitting.

The equipment test drives Godot's mouse drag routing through authenticated RPCs for install and removal, rejects incompatible and occupied slots, and checks ordinary clicks, docked Shift-click fitting, rapid-click and pending-request blocking, station restrictions and persistence. It also checks Hangar navigation, Back/Esc, filter retention and launch with the prepared fitting. Presentation fixtures check grouping across the expanded equipment catalog, every category filter, selection clearing, scrolling with 31 and 39 stored items, and flight/docked layouts at 960 x 600 and 1440 x 900 with Start accessible. Review the [docked grouped inventory](docs/feedback/inventory-category-groups.png) and [shield filter](docs/feedback/inventory-category-filter.png). Run `res://tests/equipment_test.gd` with a renderer to capture fresh views under `build/validation`.

The regular Liberator has 116,000 hull. New pilots start with LF-1, SG3N-A01 and the original Ion engine installed: 65 laser damage, 1,000 shield capacity at 40% absorption, and +8 m/s cruise and boost speed. The Liberator has 33 m/s base cruise, 75 m/s base boost and 400 cargo units, giving 41/83 m/s with its starter engine. Existing starter items and purchased Ion engines retain their fitting and bonuses; Ion engines are no longer sold. LF-1 costs 10,000 CR and SG3N-A01 costs 8,000 CR. New G3N engines add +2/+3/+4/+5/+7/+10 m/s. Uridium-priced items cost their reference price times **100 credits**: LF-2 is 500,000 CR, LF-3 and SG3N-B02 are 1,000,000 CR each, SG3N-B01 is 250,000 CR, and G3N-6900/G3N-7900 are 100,000/200,000 CR. See the complete [item table and sources](GAME_PLAN.md#darkorbit-reference-equipment-catalog).

LF-3 adds 175 base damage and 15% more for that laser against aliens (201.25 total) per installed copy. Its bonus never multiplies other lasers. FS-01 adds 3,200 shield, 70% absorption and +6.25% regeneration; its regeneration bonuses add together and multiply normal shield recovery after the existing six-second delay. Shield capacity adds, while absorption is weighted by each generator's capacity. Current fitting and installation previews show these special bonuses. Fitting changes do not repair or refill your ship. Inventory and fittings survive rescue, reconnects and restart. Equipment purchases require the persistent dedicated server; the offline development fixture uses the same starter combat and flight values. Reference prices need human progression playtesting with the existing rewards.

Client and server must use matching builds. Network schema 10 includes equipment purchase quantities and resource boost synchronization, retaining hull model, maximum hull, alien damage, shield regeneration bonuses, radiation exposure, docked state and explicit launch RPCs; the compatibility handshake rejects older builds before gameplay. Save schema 5 preserves equipment, cargo and resource boosts. Update the operator provisioning tool with the server so credential rotation recognizes every new model.

The reference catalog test (`res://tests/darkorbit_equipment_test.gd`) runs in both check helpers. It exercises every purchasable model through authenticated purchase, duplicate protection, installation, stat replication and removal. It rejects LF-4, SG3N-B00 and legacy-engine purchases, then checks mixed shields, cumulative fusion regeneration, fractional LF-3 alien damage through real physics shots, UI bonus displays, bonus restoration when switching hulls and restart persistence. A rendered run produces the review captures above under `build/validation`. On 6 October 2026 it passed 131 assertions both headlessly and on Windows OpenGL; the rendered shop test passed 53. The full Windows check script passed, including ten authenticated clients and the flight replay. The compatibility and flight replays emitted their existing ObjectDB cleanup warnings on exit; the new rendered runs were clean. Six Python operator-tool tests passed, including credential rotation preserving all new models. Linux execution and exported client checks are left to PR CI; WSL is unavailable on this machine. Item artwork remains the existing category placeholders, and reference prices need human economy playtesting.

Rebalance validation on 3 October 2026: the complete Windows headless check passed, the rendered equipment replay passed 70 assertions at 960 x 600 and 1440 x 900, and the rendered Scout hunt completed with survival, reward and station repair. The dedicated server check included ten authenticated clients. The new balance fixture passed 26 assertions covering damage split, depletion, destruction with remaining shield, regeneration, all laser/generator slot limits, authoritative fitting/replication and restart. Its stationary physics fights measured 9.67 seconds for one laser against a Scout, 12.61 seconds for three lasers against a Sentinel, and 7.99 seconds for three four-laser pilots against a Heavy. These controlled fights do not measure pursuit, evasive flight or the live economy. Four Python provisioning tests passed. The Linux runner includes the new balance test; Linux execution is left to PR CI. Human balance and progression playtesting remain necessary.

### Credit income

Kills now pay shared pools of **300 CR (Scout), 1,500 CR (Sentinel), and 10,000 CR
(Heavy)**. Resource sales pay **10 / 20 / 40 / 80 / 160 / 320 / 640 CR** per unit
from Prometium through Seprom. Matching contracts add the full reward above to
each eligible pilot. Five Scout contracts plus sold loot fund a 10,000-CR LF-1;
Sentinel hunts fund early ships, while Heavy contracts support the larger hull
prices. See [income assumptions](GAME_PLAN.md#credit-income-tuning-for-the-ship-roster)
for solo/group totals and provisional pacing. Existing accepted and pending
contracts keep their saved terms; new offers use the increased payouts. Held
cargo sells at current prices. Use matching client and server builds.

`tests/economy_test.gd` earns and purchases an upgrade from a zero wallet using
minimum Scout loot, checks three-pilot Heavy shares and full contract payouts,
rejects repeated destruction payouts, and reloads the earned equipment and
credits after restart. Both check runners include it. Timing still needs human
playtesting; the test exercises transactions rather than travel time.

Credit-income validation on 6 October 2026: the full Windows check passed,
including the 18-assertion economy fixture and ten authenticated clients. The
rendered resource replay passed 82 assertions; the rendered contract replay
passed 28, including pursuit, station repairs preserving partial progress,
automatic payment, fitting and restart. Six Python provisioning tests passed.
The contract replay seeds a 10,000-CR purchase budget; zero-wallet funding is
checked separately by the economy fixture. Review the
[updated resource prices](docs/feedback/economy-resources.png) and
[confirmed Scout payment](docs/feedback/economy-contract-reward.png). Existing
ObjectDB cleanup warnings remain in some older checks. Linux-only deployment
and shutdown tests cannot run on Windows and are left to CI. Human progression
playtesting is still required.

### Saves, backups and recovery

The ledger is `DORBIT_DATA_DIR/pilots.json`, schema version 3. Version 1 saves migrate before the server opens its port, retaining credits and adding starter equipment once; versions 1 and 2 also receive empty per-ship cargo. Keep matching server, client and provisioning-tool versions; older builds cannot read the new hull models or version 3 cargo. The migration uses the normal backup and failure path. Modern records with missing or invalid equipment fail validation rather than receiving replacements. Credential rotation preserves inventory, fittings, cargo and other pilot fields.

Every reward, repair charge, rescue fee, purchase and fitting change is committed before the server confirms it. All contributors' shares use one commit. Writes go to a sibling temporary file, flush and verify its contents, then rename over the destination. `pilots.json.bak` keeps the previous complete ledger. A save failure stops simulation and exits the server with code 1 before granting the pending transaction.

Each pilot's equipment record contains owned ship IDs, the active ship, item IDs with a single ship/slot location, and a successful-request sequence. Empty ship and slot strings mean storage. Inventory is sent reliably only to its owner; snapshots carry combat and movement stats for all ships. Purchase and fitting requests supply the next sequence and the current life, never a pilot ID, price or stat bonus. Retrying a successful sequence refreshes inventory without applying another transaction. After reconnecting, review the server inventory before making a new purchase.

Only one server or provisioning tool may own the directory. `pilots.json.lock` is an exclusive directory lock. Clean shutdown removes it. On Linux, use `tools/server.sh run`: its launcher translates SIGTERM and Ctrl+C into a scene-tree shutdown, allowing the server to release the lock. Signaling Godot directly bypasses this launcher. A crash, SIGKILL, power loss or shutdown timeout can still leave the lock behind and requires operator recovery. Missing, malformed, unsupported or out-of-range data fails closed. The server does not replace an invalid ledger with zero balances, and it detects primary-file edits made while running.

Recovery is an operator action:

1. Stop the server and confirm no other process uses this data directory. Copy the entire directory elsewhere before changing anything, including `.bak`, `.tmp`, `.bak.tmp` and the lock.
2. Inspect the primary and backup. If the primary is valid, keep it. If it is invalid or missing, copy a known-good backup to `pilots.json`. A temporary file may contain an unconfirmed transaction; preserve it for inspection rather than promoting it automatically.
3. Move leftover temporary files out of the data directory, remove the now-stale empty `pilots.json.lock` directory, and fix any disk-space or permission problem. Restart with the same `DORBIT_DATA_DIR`. The server validates the ledger before opening its port.
4. Reconnect with an existing pilot and verify their credits. Restoring an older backup rolls back later transactions and credential rotations. Rotate exposed credentials again after a restore.

Keep dated copies of the ledger on another disk or machine, especially before provisioning and server updates. Stop the server while taking a copy. The automatic `.bak` is only one transaction old and does not protect against disk loss. Godot's runtime flush does not guarantee directory metadata reaches physical storage before sudden power loss; recovery may require the backup after a machine or storage failure. Process restarts retain completed saves. Public accounts remain outside this slice; owned ships, fittings and cargo persist.

### Start a server in Ubuntu / WSL2

Requires Linux x86-64, `bash`, `curl`, `python3` and `sha256sum`. On this Windows checkout, run in PowerShell:

```powershell
wsl -d Ubuntu -- bash /mnt/c/Users/timbe/Desktop/Projekte/Dorbit/tools/server.sh setup
wsl -d Ubuntu -- env DORBIT_DATA_DIR=/home/YOUR_LINUX_USER/dorbit-data bash /mnt/c/Users/timbe/Desktop/Projekte/Dorbit/tools/server.sh run
```

`setup` downloads and verifies the pinned Godot 4.7.2 Linux runtime. It is needed once. Provision pilots inside Ubuntu before `run`, using the instructions above. Replace the checkout path and `YOUR_LINUX_USER` with your own paths. Each new `wsl` invocation needs `DORBIT_DATA_DIR`; an export in another Ubuntu terminal does not carry over. `run` imports the project and starts a headless server on **UDP 24567**. Leave that terminal running; **Ctrl+C** stops the server. No graphical Linux desktop or export-template download is needed.

Find Ubuntu's address from PowerShell:

```powershell
wsl -d Ubuntu -- hostname -I
```

Enter that WSL IPv4 address in the Windows client's connection menu, with port **24567**. WSL's address can change after restarting. On this machine, the WSL IP worked for UDP; `127.0.0.1` did not. Localhost may work with other WSL networking configurations.

From a Linux checkout, the equivalent commands are:

```bash
bash tools/server.sh setup
bash tools/server.sh run
```

Append `--port=24600` to `run` to choose another UDP port, and use the same port in the client. For a VPS, clients use its reachable IP or DNS address and its firewall must allow the selected UDP port. Other PCs reaching WSL need suitable mirrored networking or UDP routing and Windows/WSL firewall rules; TCP-only `netsh portproxy` does not forward this game's UDP traffic. The helper does not change firewall rules.

## Develop on Windows

To build and play this checkout or T3 worktree offline, run this one command from
its root folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\play.ps1
```

`play.ps1` installs the pinned Godot engine if missing, builds
`build/windows/Dorbit.exe`, and launches it with `-- --offline`. Run the same
command after changing code. Existing tools and imported assets are reused;
each new worktree gets its own tools on the first run. Setup or build errors
stop the script before launch. The script also works from another directory
when invoked by its full path.

Offline play uses temporary progression and previews of the station menus;
purchases, fitting and quests require the dedicated server. Use the deployment
workflow and matching client/server builds for online play.

The helper downloads the official Godot 4.7.2 editor and verifies its SHA-256 checksum. Building also downloads the matching export-template archive, about 1.3 GB, and extracts only the Windows templates. Tools and generated builds stay out of Git.

Run from the repository root with PowerShell and RTK:

```powershell
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 setup
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 check
rtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 build
```

Use `run` to play from source or `editor` to open Godot. You can also import `project.godot` into an existing Godot 4.7.2 installation. RTK is a command wrapper, not a game dependency.

If RTK is not installed, run these directly in PowerShell from the checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 setup
powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 run
```

Setup is needed only once. To produce `build/windows/Dorbit.exe`, replace `run` with `build`. To run the automated checks, replace it with `check`. Running from source does not need export templates or a separate build.

The project uses Godot Compatibility rendering with 4x MSAA by default. The first scene uses simple meshes and a procedural sky; it does not require Blender or downloaded art assets.

## Validation

### Resource cargo and selling

Destroyed Scouts, Sentinels and Heavies leave glowing resource boxes. Fly within 12 m to collect them automatically. The Liberator holds 400 units, with one unit per resource; other hulls use their reference capacities in the [ship catalog](docs/ships.md). A full hold leaves loot in space; partial pickups take valuable resources first. Boxes are shared, with the nearest living ship collecting first, and expire after three minutes. The server keeps at most 64 boxes.

Press B at Outpost 01 and select **Trade raw materials**. Seven ore cards show the resource images, unit prices, held quantities and sale totals. Use minus/plus or type a quantity, then choose **SELL** to sell that amount; **Sell all cargo** sells the entire hold. Sales require the usual station conditions: alive, within 60 m, no faster than 8 m/s and five seconds since the last hit. Resource value increases in this order: Prometium, Endurium, Terbium, Prometid, Duranium, Promerium, Seprom. Provisional prices are 1, 2, 4, 8, 16, 32 and 64 CR per unit. Stronger aliens drop larger quantities and higher resource tiers. Full drop tables are in [GAME_PLAN.md](GAME_PLAN.md#enemy-resources-cargo-and-station-sales).

Cargo belongs to each owned ship and survives death, reconnects and restarts. Collected cargo and sale credits are server-owned saves. Uncollected boxes remain session state. Save versions 1 and 2 migrate to version 3 with empty cargo. Preserve a pre-migration ledger backup when deploying; older servers cannot load version 3. Credential rotation with `tools/pilots.py` retains cargo.

`res://tests/resources_test.gd` checks actual ENet kills, replicated and late-join loot, two-pilot pickup conservation, full and partial holds, client authority, station restrictions, per-resource and sell-all actions, duplicate sales, restart recovery, wallet limits, expiry and failed writes. Run it headlessly or with the renderer to capture the cargo panel and loot markers at 960 x 600 under `build/validation`. Windows and Linux check scripts include it. Operator-tool tests cover cargo-preserving migration and credential rotation, and reject corrupted cargo without altering the ledger.

Review captures show the [full cargo panel](docs/feedback/resources-full-hold.png), [confirmed sale](docs/feedback/resources-sold.png) and [resource box in space](docs/feedback/resources-in-space.png). Prices and capacities still need human balance playtesting.

On 2 October 2026, the resource integration test passed 47 assertions on Windows headless, Windows OpenGL and Linux headless. Both full check scripts passed. Rendered equipment checks passed 53 assertions after adding the cargo page. The Windows release export passed, and its protocol fingerprint matched the Windows and WSL Linux source runtimes. Operator-tool tests passed three cases; Linux shutdown and migration checks passed seven cases, including corrupt cargo and a version-2 ledger backup. Some combat and compatibility replays emitted ObjectDB cleanup warnings on exit while passing their assertions; the resource runs did not.

### Refining and resource upgrades

Open **Refining** in the shared menu near Outpost 01. Its **Refining** tab shows
the ore recipe tree; select Prometid, Duranium or Promerium, choose an amount and
confirm. Prometid uses 20 Prometium + 10 Endurium; Duranium uses 10 Endurium +
20 Terbium; Promerium uses 10 Prometid + 10 Duranium without Xenomit. Seprom
production waits for Skylab, while existing Seprom loot is usable now.

Missing intermediates are refined automatically: existing Prometid and Duranium
are used first, then only their shortfall is made from raw ores. The preview shows
the actual cargo cost and automatic steps; Max includes shared Endurium costs.
One Promerium from raw ores uses 200 each of Prometium, Endurium and Terbium.
The complete batch saves together, with no partial spending on shortages or failure.

The **Update** tab has a resource bar above illustrated equipment cards. Drag a
held resource onto lasers, shields or engines, then choose an amount and confirm
on the right. Selecting both cards also works without dragging. Compatible drop
targets highlight; a drop never spends cargo by itself. Each equipment card's
bottom-left square shows its currently applied resource, with remaining rounds
or time below. Previewing a replacement keeps the old icon until confirmed;
depletion clears it.

The boost amount field caps typed input, spinner changes and Max at current stock.
Selecting another resource or receiving a cargo update refreshes the cap. Empty
stock shows zero and disables editing and applying boosts.

Prometid adds 15% weapon damage; Duranium adds 10% shield capacity/speed; Promerium adds
30% weapon damage and 20% capacity/speed; Seprom adds 60% weapon damage and
40% capacity, with no engine bonus. Each unit provides ten individual laser
rounds or ten minutes. Four lasers use four rounds per volley, and a final
partial volley boosts only the remaining rounds. Adding the same resource
extends the reserve at a fixed percentage. Replacing it requires acknowledging
the discard warning. Rockets show Coming later and cannot consume resources.

Boosts stay with their hull. Timers count while online in the active ship,
including menus and rescue, and pause when disconnected or using another hull.
Shield capacity and fitted cruise/boost speeds reflect the active multiplier;
applying a shield boost does not refill charge or alter absorption.
Durations checkpoint every five seconds and flush on disconnect/shutdown and
successful station changes; an abrupt crash can restore up to five seconds.
Weapon rounds commit before damage. Server writes validate ingredients,
compatibility, quantities, station restrictions and duplicate protection.

This requires matching network-schema-10 builds. Ledger schemas 1–4 migrate to
schema 5, preserving progression and adding empty reserves; keep a backup for
rollback. The provisioning tool preserves and validates boosts during rotation.
`res://tests/resource_upgrades_test.gd` exercises authenticated refining and
upgrades, partial volleys with mixed lasers, online timing, restart, duplicate
protection, unsupported resources, failed writes and real mouse menu actions.
Run it with a renderer for 960 × 600 and 1440 × 900 screenshots under
`build/validation`. Both check runners include it. Human balance playtesting
remains necessary.

The upgrade fixture includes real drag-and-drop at 960 × 600 and 1440 × 900,
including drops onto corner badges, compatibility, replacement confirmation,
pending/offline actions and icon updates on depletion. Review the
[refining menu](docs/feedback/refining-menu.png),
[compact Update tab](docs/feedback/resource-upgrades-compact.png) and
[active boosts and replacement warning](docs/feedback/resource-upgrades-menu.png).
Human economy and balance playtesting remains necessary.

### Existing gameplay checks

For a repeatable ten-client Linux server workload, CPU/memory measurements and their limits, see [PERFORMANCE.md](PERFORMANCE.md). Headless simulation measurements do not establish rendered client FPS.

`check` imports the project and runs headless integration tests against the actual scene and physics world, network checks with separate ENet peers, and a complete hunt-and-repair replay. It covers input actions, shield and hull damage, cooldowns, range, firing arcs, obstacles, rewards, repairs, rescue, movement, mouse steering, pause, joining, replication, and disconnects.

Settings checks also cover rebinding, conflicts, cancellation, default restoration, sensitivity, volume, graphics and persistence across processes. Run `res://tests/display_test.gd` with a renderer and an isolated `APPDATA` directory to capture all three settings tabs at 960 x 600, 1440 x 900 and 1920 x 1080, and check fullscreen/resolution changes. Run it again with `-- --restart` to check saved values and restore the test profile's defaults. The test changes local preferences, so do not run it against your normal player profile.

Settings review captures at the minimum window size: [Controls](docs/feedback/settings-controls.png), [Audio](docs/feedback/settings-audio.png), [Graphics](docs/feedback/settings-graphics.png).

For a rendered hunt-and-return replay:

```powershell
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/flight_playthrough.gd
```

The replay opens a 2560 x 1440 window, disables VSync for measurement, and saves screenshots under `build/validation`. Its scripted hunt ignores focus loss from capture tools; normal play still pauses input and disables fire on focus loss. These changes apply only to the replay. The normal game uses VSync.

GitHub Actions runs the Windows checks, exports the Windows client, and tests the dedicated server on Linux for each pull request. `bash tools/server.sh check` covers ten authenticated clients, combat, reconnects, restart recovery, duplicate logins, malformed credentials, corrupted saves and write failures. It also starts separate Linux processes to test SIGTERM, Ctrl+C, repeated restart, concurrent-server exclusion, crashes and shutdown timeout. Tests provision isolated disposable data directories under Godot's user-data directory or the system temporary directory; they do not read production credentials or saves.

The Scout hunt-and-repair replays follow the selected alien through 3D flight. For a two-client Windows-to-Linux replay, provision two fresh test pilots and run the server on port 24684 with a disposable data directory. Set a different `DORBIT_PILOT_FILE` for each Windows Godot process, then launch with `--path . --script res://tests/dedicated_client_playthrough.gd -- --address=YOUR_WSL_IP --label=a`, using `--label=b` for the other. Start both within ten seconds. Each replays the hunt and repair loop; rendered runs save screenshots under `build/validation`.

## Feedback validation

Cursor targeting and persistent locks were checked on 2 October 2026 with Godot 4.7.2 on Windows. Run `res://tests/targeting_test.gd` headlessly for 13 assertions, or with a renderer for 14 assertions including captured-mouse steering and real cursor/Tab input. The checks cover cursor retargeting, repeated Tab, acquisition beyond 550 m, lock retention beyond weapon range and behind the camera, returning enemies, snapshot resets, destruction and candidate filtering. The [900 m lock capture](docs/feedback/targeting-distant-lock.png) shows the retained target with OUT OF RANGE feedback. The rendered Scout hunt-and-repair replay and gameplay, network, dedicated-server, persistence and connection checks also passed. These are automated local checks; the revised targeting still needs human playtesting.

The RPC compatibility regression, `res://tests/rpc_compatibility_test.gd`, reproduces the checksum and wrong-argument errors from mixed gameplay branches. Its 13 checks now reject extra methods, changed arguments or transport channels, legacy servers and incompatible pilot proofs before spawning. Matching builds reconnect, apply authoritative pilot laser damage and create the client's laser mesh. A rendered run also captured the [replicated pilot laser](docs/feedback/network-pilot-laser.png). `tools/dev.ps1 build` compares the source runtime's fingerprint with the actual exported Windows executable and fails the build if they differ. RPC names are sorted as ordinary strings because Godot's `StringName` order differs between editor and release runtimes. The Linux source runtime under WSL and the Windows source/release runtimes produce the same fingerprint. Packet-content changes without signature changes must increment `FlightSession.NETWORK_SCHEMA`.

For a connection diagnostic, launch the game or source runtime with `--headless -- --print-protocol`. It prints one `DORBIT_PROTOCOL=<hash>` line and exits without starting a server or joining one; credentials are not needed. Matching builds should report the same hash.

Combat feedback was checked on 13 September 2026 with Godot 4.7.2, Windows and an NVIDIA RTX A500 Laptop GPU. The rendered flight replay passed click/Tab targeting, disabled fire, range, arc and real wall obstruction, shield/hull impacts, kill reward and return/repair. The final hunt measured 2.35 ms average and 3.70 ms p95 at 2560 x 1440 with VSync disabled. These local development measurements are not a reference-hardware performance guarantee.

The two-process shared replay passed on UDP 29682, including authoritative rewards of 38 and 37 credits and both pilots returning to repair. Headless encounter checks passed 43 assertions, shared combat 42, and the dedicated server 44 with ten authenticated clients. The dedicated run used UDP 29683 to avoid another thread's fixed test port. Display checks passed at 960 x 600, 1440 x 900 and 1920 x 1080, including changing the volume/mute controls and loading the saved values into a fresh audio node.

Run `res://tests/feedback_busy_playthrough.gd` with the renderer to inspect ten pilot models and one alien under 100 laser and 100 impact requests per second. Two eight-second runs measured 4.17 and 5.56 ms p95 at 1440p and kept transient effects below the 80-node limit. They exercise presentation load, not multiplayer simulation or the unmerged multi-alien content. Screenshots are saved under `build/validation`; checked-in review captures are linked from the PR. Desktop automation could not connect to its native helper, so validation used Godot's input-driven replays and rendered captures. Listening comfort and a representative group fight on the reference PC still need human playtesting.

### Sound and integration

Review captures: [range](docs/feedback/feedback-range.png), [arc](docs/feedback/feedback-arc.png), [obstruction](docs/feedback/feedback-los.png), [shield hit](docs/feedback/feedback-shield-impact.png), [hull hit](docs/feedback/feedback-hull-impact.png), [co-op reward and destruction](docs/feedback/shared-reward-client.png), [station return](docs/feedback/04-repaired.png), [busy encounter](docs/feedback/feedback-busy.png), and [audio controls at minimum window size](docs/feedback/display-960.png).

Settings > Audio opens master and effects volume controls and mute. Preferences stay on this device in `user://audio.cfg`. All cues are original procedural PCM generated by `scripts/feedback_audio.gd`; no third-party audio assets or audio attribution are required. Up to six sounds play at once, with per-cue repetition limits and attenuation to silence beyond 350 m.

Lasers now use bright cores, soft additive halos and brief muzzle/contact flashes. Pilot fire is cyan; hostile fire is orange-red. Hits ripple across curved shields and throw hot, cooling sparks from hulls. Larger destruction flashes, flares and radial streaks scale to the destroyed ship's modeled diameter and last 1.2 seconds. Scouts produce smaller blasts than Sentinels and Heavies; player hulls use their catalog diameter (3.5 m for Phoenix, 7 m by default). The loot box and its HUD marker appear after the explosion has gone. The effects work in Compatibility rendering without bloom. Each short-lived effect root owns its meshes and animations, with a 64-root ordinary limit and a destruction reserve to 80. Incoming laser cues provide cosmetic contact direction; missing or reordered cues fall back to the camera-facing side. Damage, rewards and loot collection remain unchanged. The reliable destruction cue now carries its diameter, so clients and servers need matching updated builds.

Review the [laser and shield hit](docs/feedback/combat-laser-shield-1440.png), [hull sparks](docs/feedback/combat-laser-hull-1440.png), [incoming fire](docs/feedback/combat-hostile-1440.png), [larger destruction](docs/feedback/combat-destruction-1440.png) and [loot revealed afterward](docs/feedback/combat-loot-1440.png). Run `res://tests/combat_effects_playthrough.gd` with a renderer for fresh 960 x 600 and 1440 x 900 captures under `build/validation`. It exercises real shot validation, shield/hull damage, death, rewards and delayed loot presentation. The headless combat-effects test runs in both check helpers and covers moving hits, death visibility, cleanup, saturated budgets, modeled destruction size and unchanged combat state. Resource integration checks cover replicated explosion sizes and loot visibility on real ENet clients.

The October rework passed the full Windows headless check, 12 focused effect assertions, the rendered gallery at both sizes, and 13 rendered protocol/shot assertions. The hunt-and-repair replay passed at 2560 x 1440 with an isolated settings profile (13.42 ms average / 16.05 ms p95). The busy presentation fixture passed its 80-root limit with ten pilot models, one alien, and 100 laser plus 100 impact requests per second at 2560 x 1440 (24.24 ms p95 on AMD Radeon(TM) Graphics). The busy fixture applies VSync and sizing after device settings load, and verifies its actual render size. These are local presentation measurements, not a reference-hardware or multiplayer capacity benchmark. Existing integration fixtures still occasionally emit collinear-up or ObjectDB exit warnings.

The larger-explosion follow-up passed 21 focused effect assertions, 89 resource integration assertions both headlessly and with OpenGL, 75 encounter assertions with an isolated settings profile, and 13 protocol/shot assertions. Rendered captures verify hidden loot during destruction and its reveal afterward at 960 x 600 and 1440 x 900, plus [Scout](docs/feedback/combat-destruction-scout-1440.png) and [Heavy](docs/feedback/combat-destruction-heavy-1440.png) blasts from the same camera and wreck position. The 2560 x 1440 busy fixture retained its effect limit with the longer explosions (23.97 ms p95 on this machine).

On 18 September, alien variety was integrated with the merged feedback changes. Enemy captions use type and slot number; the station and selected target take priority over secondary contacts. The Windows gameplay/network/persistence checks passed, as did the rendered 2560 x 1440 Scout hunt and feedback replay. A separate 60-second run with one rendered client, nine headless clients and a dedicated server kept ten pilots connected: all five aliens fought and died, with overlapping encounters on 33.8% of ticks. The capped 1440 x 900 client averaged 59.97 FPS with 16.82 ms p95 frame time on the RTX A500 Laptop GPU. This is a local integration check, not an internet or reference-hardware benchmark. The busy encounter capture above now shows that run.

Purchases play a confirmation cue only after the server commits a new transaction. Failed and duplicate purchases stay silent. Clients and server must use matching builds.

`tests/hunting_contracts_test.gd` checks authenticated concurrent contracts, shared kill progress, automatic payouts, restart recovery, abandonment, repeatability, legacy migration and failed saves. Both check helpers run it. For a rendered replay, run Godot with `--path . --script res://tests/contracts_playthrough.gd`. It provisions a disposable pilot and server on UDP 24690, accepts all three hunts, follows Scout respawns and repairs between kills, completes the Scout hunt with automatic payment in flight, and saves frames under `build/validation/contracts-*.png`.

The contract board hides pause-menu audio controls. Equipment purchases and fitting share the version-3 persistence path with concurrent contracts and automatic payouts. The replay starts with a 10,000-credit purchase budget, buys and installs a second LF-1 after the Scout hunt, and checks that credits, all accepted contracts and fitting survive a server restart. Inventory uses an owner-only reliable channel; world snapshots send one player per packet with equipment stats and active contracts.

On 2 October 2026, the full Windows check command passed after the concurrent-hunt update, and the expanded contract checks passed 43 assertions. The rendered replay accepted all three hunts, paid the Scout reward in flight for 180 total credits, kept the other hunts active, and repeated the Scout offer at the station. The board was inspected at 960 x 600.

The Mission Control board now separates hunt selection from acceptance. Hunting contracts and Active contracts tabs share a left-hand list; the right pane shows the selected briefing, accepted objective progress and reward. The footer accepts or abandons that run, reports remaining slots and explains station restrictions. Saved terms and wallet-full pending rewards remain visible. Review the [available hunts](docs/feedback/contracts-offers.png) and [active contracts](docs/feedback/contracts-active.png) at 960 x 600. The rendered replay checks mouse selection and actions, keyboard selection and acceptance, retained focus, filtering, abandonment, saved terms, pending rewards and minimum-window layout before continuing the live hunt, purchase and restart loop.

On 3 October 2026, the revised rendered contract replay passed 26 checks on Windows OpenGL, with captures inspected at 960 x 600 and 1440 x 900. Headless hunting-contract checks passed 43 assertions and equipment checks passed 68. The replay verifies the exact Scout payout in flight and preserves the returned wallet through repeat acceptance, purchase and restart; rescue fees incurred during the live return are accounted for separately.

## CI performance

Validation checks the exact Linux release staged by `git archive` once. Packaging
still runs the full server suite before publishing a release; it does not reuse a
success result from the working checkout. Godot setup verifies the pinned archive
again before extracting the staging executable.

Linux and Windows cache only `.godot/imported` as derived project data, alongside
the existing pinned tool caches. Import keys include OS, Godot version, all assets
and their import settings, `project.godot`, and scene import hooks. There are no
broad fallback keys. Script/class indexes and editor state are regenerated. PR
validation saves caches in GitHub's isolated PR merge-ref scope; main builds
cannot restore those caches. Preview build jobs run with `cache-mode: read` and
restore-only actions, so PR code cannot write caches into the dispatch's main
scope. A preview with changed import inputs may still require a cold import.

Both check helpers print `TIMING:` lines and append command durations and results
to the GitHub run summary, including failed checks. This separates the initial
asset import from each test without dropping coverage. Linux Python checks are
timed too. Compare a cache-miss run with a later cache hit on the same inputs.

For a focused texture compression comparison, run:

```powershell
python tools/profile-imports.py .tools/godot/Godot_v4.7.2-stable_win64_console.exe --ship liberator
```

The profiler imports one hull in disposable projects with Basis Universal and
uncompressed embedded textures, then measures warm imports and restoring only
`.godot/imported` into another clean project. It writes durations and imported
file sizes to `build/validation/import-profile-results.json`; it never changes
the game's import settings. Use the Linux executable on Linux. The current
2048-pixel atlases and Basis compression remain in place: faster uncompressed
imports need a separate assessment of GPU memory and runtime performance before
changing game assets. CI caches stay on GitHub runners. VPS runs use the
dedicated-server export described below and skip asset imports.

`tools/deploy-server.sh` validates the exact source commit, then builds the
`Linux Dedicated Server` preset. Godot strips textures/materials to placeholders
while preserving resource references. The package contains the pinned Linux
release runtime, PCK and existing service/provisioning helpers, without source
art or an editor/import cache. `tools/server.sh run` starts the exported runtime
directly; local source runs and older releases retain their existing import path.
CI compares source/exported protocol, ship data and all 30 obstacle colliders,
checks clean startup/restart without source assets, and exercises Linux
shutdown/save safety against the exported executable. No VPS service unit change
is required. New preview branches must include this export support.

## Code layout

- `scripts/ship.gd`: shared combat state and weapon validation.
- `scripts/pilot.gd`: flight input and chase camera.
- `scripts/alien.gd`: type tuning, per-alien life/contributions, movement and leash returns.
- `scripts/sector.gd`: encounter lifecycle, targeting, rewards, repairs, and rescue.
- `scripts/flight_session.gd`: session menu, ENet connection lifecycle, host flight simulation, and client prediction/interpolation.
- `scripts/session_combat.gd`: server-owned independent alien encounters, per-player wallets, repairs, respawns, and combat snapshots/effects.
- `scripts/pilot_store.gd`: validated pilot ledger, challenge verification, atomic replacement and previous-save backup.
- `scripts/cargo_resources.gd`: resource values, enemy loot tables, per-model capacities and cargo validation.
- `scripts/resource_loot.gd`: bounded shared resource boxes, collection timing and placeholder visuals.
- `tools/pilots.py`: operator provisioning and credential rotation with the server stopped.
- `scripts/visuals.gd` and `shaders/space.gdshader`: procedural placeholder art and effects.
- `scripts/hud.gd`: flight instruments, targets and objectives.
- `scripts/settings_menu.gd`: flight menu and Controls, Audio and Graphics tabs.
- `scripts/game_settings.gd`: saved control/display preferences and input bindings.

Combat emits visual signals; visual effects do not award rewards or apply damage. Shared play sends movement and fire intent to the host at 20 Hz and receives authoritative snapshots at 20 Hz, with local flight prediction and smoothing of other players and aliens. Only the host simulates combat; repair requests identify the requesting peer, never a client-supplied price or damage amount.

Save schema 5 combines ammunition inventory and per-ship resource boost reserves.
Schema 4 ammunition saves retain their rounds and receive empty boosts; schema 4
boost saves retain their reserves and receive the one-time starter ammunition.
Each fired volley commits both debits together before applying damage.
