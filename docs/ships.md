# Playable ships

All twelve base hulls from [PR 14](https://github.com/Timerk/Dorbit/pull/14)
are playable. Buy a hull under **B > Ships**, then choose it in **I > Ship
equipment** and press **Activate selected ship** at the station. Each model can
be owned once. Phoenix is free; the starter Liberator already counts as owned.
Purchased hulls have empty fittings and cargo. Equipment and cargo stay with
their hull when switching; move equipment through storage or fit another hull.
Switching is free and uses the normal station range, speed, damage and alive
checks. It preserves current absolute hull, shield charge, boost energy and
weapon cooldown, clamping hull/shields to the new maximum. Use station repairs
to fill the larger hull after upgrading. Old flight/fire commands cannot cross
a switch.

The user selected the newer base-ship stats, matching the existing 116,000-HP
Liberator, and **100 credits per Uridium**. Original credit prices are retained.
Yamato and Defcom have user-requested prices of **150,000 CR each**, between
Piranha and Nostromo, while retaining the newer base-ship stats.
Goliath retains the agreed 8,000,000-CR price, based on its earlier 80,000-Uridium
price; the newer wiki lists 50,000 Uridium. There is no second currency.

| Hull | HP | DarkOrbit speed | Base cruise (m/s) | Lasers | Shared generators | Extras | Cargo | Price (CR) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Phoenix | 104,000 | 320 | 32 | 1 | 1 | 1 | 100 | 0 |
| Liberator | 116,000 | 330 | 33 | 4 | 6 | 2 | 400 | 40,000 (starter owned) |
| Piranha | 164,000 | 360 | 36 | 6 | 8 | 2 | 600 | 100,000 |
| Nostromo | 220,000 | 340 | 34 | 7 | 10 | 3 | 700 | 195,000 |
| Bigboy | 260,000 | 260 | 26 | 8 | 15 | 3 | 700 | 285,000 |
| Leonov | 164,000 | 360 | 36 | 6 | 6 | 1 | 1,000 | 1,500,000 |
| Vengeance | 280,000 | 380 | 38 | 10 | 10 | 2 | 1,000 | 3,000,000 |
| Spearhead | 200,000 | 370 | 37 | 5 | 12 | 2 | 500 | 4,500,000 |
| Goliath | 356,000 | 300 | 30 | 15 | 15 | 3 | 1,500 | 8,000,000 |
| Aegis | 375,000 | 300 | 30 | 10 | 15 | 3 | 2,000 | 8,000,000 |
| Defcom | 250,000 | 340 | 34 | 12 | 8 | 2 | 800 | 150,000 |
| Yamato | 260,000 | 260 | 26 | 8 | 12 | 2 | 1,000 | 150,000 |

DarkOrbit speed is converted at 0.1 m/s per map unit to fit this game's sector
scale, preserving the ships' speed ratios. Dorbit's boost adds 42 m/s; each
installed Ion engine adds the existing 8 m/s to both speeds. The fitted starter
now cruises at 41 m/s and boosts at 83 m/s. Acceleration, braking, damage from
lasers and shield behavior retain existing equipment tuning. Hulls have no
inherent laser damage or shields without equipment.

These are base hulls with slots, health, speed and cargo. Extras remain reserved;
ship skills, nanohull, rocket launchers, drones and cosmetic/Plus variants are
future systems. Leonov uses its normal 164,000-HP, 360-speed, 1,000-cargo stats:
this game has no company home maps for its DarkOrbit home-map advantage.

## Sources and era

Values checked on 6 October 2026 against individual DarkOrbit Wiki ship pages:
[Phoenix](https://darkorbit.fandom.com/wiki/Phoenix),
[Liberator](https://darkorbit.fandom.com/wiki/Liberator),
[Piranha](https://darkorbit.fandom.com/wiki/Piranha),
[Nostromo](https://darkorbit.fandom.com/wiki/Nostromo),
[Bigboy](https://darkorbit.fandom.com/wiki/BigBoy),
[Leonov](https://darkorbit.fandom.com/wiki/Leonov),
[Vengeance](https://darkorbit.fandom.com/wiki/Vengeance),
[Spearhead](https://darkorbit.fandom.com/wiki/Spearhead),
[Goliath](https://darkorbit.fandom.com/wiki/Goliath),
[Aegis](https://darkorbit.fandom.com/wiki/Aegis),
[Defcom](https://darkorbit.fandom.com/wiki/Defcom), and
[Yamato](https://darkorbit.fandom.com/wiki/Yamato).
Earlier values are shown in the official forum's
[ship exhibition](https://board-en.darkorbit.com/threads/ship-exhibition.119074/).
In particular, the original low-HP credit Yamato/Defcom are different from the
newer hulls selected for this roster. These references inform the statistics;
the million-credit prices still need economy playtesting against Dorbit rewards.

## Assets and compatibility

`assets/ships/catalog.json` is the shared runtime/provisioning source of hull
stats. Existing `pathfinder` save values are an alias for Liberator, retaining
ship IDs, fitting locations, wallet, contracts and cargo. Its hold expands from
200 to 400 units without discarding cargo. Ledger schema remains 3. Older tools
and servers cannot read newly purchased models: use matching updated builds
and provisioning tools, and back up the ledger before upgrading. Network schema
4 adds model identity and maximum hull to every player snapshot; older clients
are rejected by the existing compatibility handshake.

The [Dorbit concept refinement](../art/ship-review/concepts/README.md) supplies
new multi-angle design references and updated editable models, guided by the
user's Liberator hangar image. Six actual mesh renders per ship provide consistent
angles; generated sheets are design guidance and can disagree in small details.

Following user review, Nostromo's forebody is longer and tapers to a sharper bow.
Its length relative to wing span increases by about 30%. Armor, cockpit and
cheek fittings follow the hull, while the paired rear turbines retain their
round shape. See the [revised model views](../art/ship-review/previews/nostromo-views.jpg)
and [Nostromo game capture](feedback/refined-nostromo-flight.png).

`tools/export_ships.py` exports the saved `.blend` files without changing
them. Run Blender in background mode with `--python tools/export_ships.py`.
The exporter removes the studio and references, consolidates each hull into
one mesh with material surfaces, reduces bevel subdivisions, retains evaluated
normals and PBR colors, and normalizes the bounding diameter to 7 m. Godot's
imported nose points -Z with +Y up. Procedural studio grain is omitted. Ship
previews derive from the revised saved renders. The existing simple collision
sphere and chase camera remain shared across hulls; these are approximate game
sizes, since PR 14 supplied no physical scale. Godot generates mesh LODs on
import. The dedicated server never instantiates hull render meshes.

## Validation

Ship visual refinement checked on 7 October 2026 with Blender 5.2.2 LTS and
Godot 4.7.2 on Windows: all twelve saved files reopen with finite, nondegenerate
geometry, packed concepts and six final 1600 x 1440 renders each. Review sheets
pass the render-boundary check. All twelve GLB exports load with one centered
7 m hull mesh, materials, finite vertices, shop previews and no studio nodes.
The rendered authenticated ship replay passed 211 checks with no failures or
stderr errors. See the updated [flight](feedback/refined-ships-flight.png) and
[shop](feedback/refined-ships-shop.png) captures.

The full roster's base export triangle total rises from 689,638 to 762,142;
Liberator is now the largest hull at 98,228 triangles. Godot still generates LODs
on import. These checks establish loading and presentation compatibility, not
ten-player performance on the reference hardware or final art acceptance.
The exported Windows client and Linux checks are left to PR CI.

`tests/ships_test.gd` covers authenticated purchases of the roster, exact prices,
empty fittings, final valid and first invalid slots, switching, station
restrictions, command life invalidation, owner/observer/late-join replication,
cargo isolation, rescue, duplicate request handling and restart persistence.
It also captures flight, shop and fitting views when run with a renderer.
Windows and Linux check runners include it. The Python provisioning test covers
all hull capacities/slots and credential rotation with a populated hangar.

Local validation on 6 October 2026: the complete Windows headless check passed;
the rendered ship replay passed 209 assertions, including Buy/Activate controls
and layouts at 960×600 and 1440×900. Five Python provisioning tests passed. The
Windows export passed, matched the source protocol fingerprint, and loaded all
twelve meshes, previews and the catalog from its packaged assets. Linux
execution is left to PR CI because WSL is not installed on this machine. These
checks do not establish ten-player frame-rate performance or economy pacing.

Review the [minimum-size ship shop](feedback/ships-shop-960.png),
[larger ship shop](feedback/ships-shop-1440.png),
[Goliath fitting screen](feedback/ships-goliath-equipment-960.png), and
[Goliath in flight](feedback/ships-goliath-flight.png).
