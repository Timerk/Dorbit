# Native menus and offline review

The native Godot menus follow the [approved UI references](README.md).
Overview, Hangar, Shop, Cargo Trade, Quests, Connection and the three Settings
tabs use the same header, sidebar and hangar backdrop. Skylab adds the approved
station and persistent industry; Galaxy Gates remains a Coming soon page.
Ship specifications appear on Overview and Hangar;
START appears only on preflight Overview.

## Offline review

Launch `Dorbit.exe -- --offline` to inspect every page without a deployment.
Hangar shows the solo starter fitting; catalog and quest selections are previews.
Buying, selling, fitting, activation and contract actions require a server and
remain disabled offline. Skylab shows a read-only bootstrap fixture; all industry
mutations require the dedicated server. Device settings remain editable.

START enters the solo encounter. During flight, Esc > Ship menus opens the same
console; B, I, C and F7 open Shop, Hangar, Quests and Connection. Resume flight or
Esc closes it. START stays hidden in flight. Browsing preserves position, health
and the temporary wallet, including away from the station.

Esc > Quit to main menu returns solo players to preflight Overview. Connected
clients dock through the server without disconnecting or losing progression;
station service checks and the running world still apply. Returning from a
temporary development host stops it and opens offline Overview.

## Runtime screenshots

These native captures show the reviewed implementation at 1440 x 900. Connected
fixtures use synchronized starter ownership and a seeded test wallet. Cargo
Trade and the flight captures use the offline fixture. Empty cargo/storage
reflect starter state, rather than the illustrative concept inventory.

| Page | Capture |
| --- | --- |
| Overview | [overview-implemented.png](overview-implemented.png) |
| Hangar | [hangar-implemented.png](hangar-implemented.png) |
| Shop | [shop-implemented.png](shop-implemented.png) |
| Cargo Trade | [cargo-trade-implemented.png](cargo-trade-implemented.png) |
| Quests | [quests-implemented.png](quests-implemented.png) |
| Controls | [settings-controls-implemented.png](settings-controls-implemented.png) |
| Audio | [settings-audio-implemented.png](settings-audio-implemented.png) |
| Graphics | [settings-graphics-implemented.png](settings-graphics-implemented.png) |
| Connection | [connection-implemented.png](connection-implemented.png) |
| Skylab | [skylab-implemented.png](skylab-implemented.png) |
| Galaxy Gates | [galaxy-gates-implemented.png](galaxy-gates-implemented.png) |
| Flight menu | [flight-menu-implemented.png](flight-menu-implemented.png) |
| Offline flight Hangar | [flight-hangar-offline.png](flight-hangar-offline.png) |
| Offline flight Cargo Trade | [flight-cargo-offline.png](flight-cargo-offline.png) |

## Assets and validation

The [runtime assets](../../assets/ui/menu/README.md) include the generated empty
hangar, unchanged ship renders, original SVG icons and licensed Rajdhani fonts.
Quests previews the existing procedural alien model in an isolated viewport.
The eight [mineral renders](../../assets/ui/resources/README.md) retain their
high-resolution transparency, lossless imports and mipmap filtering.

Focused fixtures cover docked and flight navigation, offline blocked actions,
purchases, fitting, quest actions, settings persistence and connection behavior.
Native layout checks cover 960 x 600, 1440 x 900 and 1920 x 1080. The export check
loads every menu and dynamic asset from the packaged game and checks solo
launch/return. These checks supplement the full Windows/Linux validation suite.
