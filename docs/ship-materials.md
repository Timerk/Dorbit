# Ship material review

All twelve playable ships now use the approved Liberator material treatment in
flight, the docked overview and their shop thumbnails. Each ship retains its
colors and geometry. Coated colored armor, exposed satin metal, dark structure
and copper fittings have distinct surface responses. Each fitted Blender
component gets a padded UV tile, with small roughness differences between panels
and subtle tangent-space normal-map grain.

Cockpit glazing uses dark, smooth dielectric glass, retaining blue, olive or
amber tints while contrasting with the armor and existing frames. Glowing reactor
lenses retain emission. Glass and lights have no brushed hull grain. The maps
contain no painted lighting or reflections.

[Actual Godot roster overview](feedback/ship-materials-overview.jpg)

| Ship | Godot hangar | Six consistent game views | Surface settings |
| --- | --- | --- | --- |
| Aegis | [Hangar](../art/ship-review/materials/aegis/hangar.png) | [Views](../art/ship-review/materials/aegis/views.jpg) | [Manifest](../art/ship-review/materials/aegis/manifest.json) |
| Goliath | [Hangar](../art/ship-review/materials/goliath/hangar.png) | [Views](../art/ship-review/materials/goliath/views.jpg) | [Manifest](../art/ship-review/materials/goliath/manifest.json) |
| Bigboy | [Hangar](../art/ship-review/materials/bigboy/hangar.png) | [Views](../art/ship-review/materials/bigboy/views.jpg) | [Manifest](../art/ship-review/materials/bigboy/manifest.json) |
| Defcom | [Hangar](../art/ship-review/materials/defcom/hangar.png) | [Views](../art/ship-review/materials/defcom/views.jpg) | [Manifest](../art/ship-review/materials/defcom/manifest.json) |
| Leonov | [Hangar](../art/ship-review/materials/leonov/hangar.png) | [Views](../art/ship-review/materials/leonov/views.jpg) | [Manifest](../art/ship-review/materials/leonov/manifest.json) |
| Liberator | [Hangar](../art/ship-review/materials/liberator/hangar.png) | [Views](../art/ship-review/materials/liberator/views.jpg) | [Manifest](../art/ship-review/materials/liberator/manifest.json) |
| Nostromo | [Hangar](../art/ship-review/materials/nostromo/hangar.png) | [Views](../art/ship-review/materials/nostromo/views.jpg) | [Manifest](../art/ship-review/materials/nostromo/manifest.json) |
| Phoenix | [Hangar](../art/ship-review/materials/phoenix/hangar.png) | [Views](../art/ship-review/materials/phoenix/views.jpg) | [Manifest](../art/ship-review/materials/phoenix/manifest.json) |
| Piranha | [Hangar](../art/ship-review/materials/piranha/hangar.png) | [Views](../art/ship-review/materials/piranha/views.jpg) | [Manifest](../art/ship-review/materials/piranha/manifest.json) |
| Spearhead | [Hangar](../art/ship-review/materials/spearhead/hangar.png) | [Views](../art/ship-review/materials/spearhead/views.jpg) | [Manifest](../art/ship-review/materials/spearhead/manifest.json) |
| Vengeance | [Hangar](../art/ship-review/materials/vengeance/hangar.png) | [Views](../art/ship-review/materials/vengeance/views.jpg) | [Manifest](../art/ship-review/materials/vengeance/manifest.json) |
| Yamato | [Hangar](../art/ship-review/materials/yamato/hangar.png) | [Views](../art/ship-review/materials/yamato/views.jpg) | [Manifest](../art/ship-review/materials/yamato/manifest.json) |

The six views come from one actual game mesh, including its underside, with
studio fill lighting to reveal lower surfaces. Hangar views use the same camera,
lighting and scale across the roster. The original
[Liberator close view](feedback/liberator-material-detail.png),
[docked overview](feedback/liberator-material-menu.png) and
[flight capture](feedback/liberator-material-flight.png) show the accepted benchmark.

Drag to orbit the docked overview, scroll to zoom, and double-click to reset.
Broad reflection strips, a key light, fill and warm rim light show curvature and
metal. The isolated preview caches its view after 12 settling frames, refreshes
after camera/model/size changes, and stops drawing when hidden or after launch.
Its lights never enter the sector. Flight retains the sector's existing lighting,
so its highlights differ.

## Source and rebuilding

[ship_surface_atlas.py](../tools/ship_surface_atlas.py) deterministically generates
three 2048 × 2048 maps per ship from its saved Blender components: albedo, ORM
and tangent-space normal. Source maps and per-part settings live under
`art/ship-review/materials/<ship>/`. Each manifest records the material role,
tint, roughness and metallic response. ORM stores roughness in green and metallic
in blue; red is 1 because no ambient-occlusion bake is supplied.

Maps are embedded in each `assets/ships/<ship>.glb`. The exporter shares three
image/sampler entries; the [Godot import hook](../tools/import_ship_materials.gd)
shares three compressed texture resources across all of that hull's material
surfaces and restores clearcoat for colored paints. Source maps and review
pictures are excluded from the game pack by `art/.gdignore`.

Every export retains one mesh, its existing material count and base triangles,
centered 7 m bounds and forward orientation. The roster retains 762,142 base
triangles. Maps and UVs add download and texture-memory costs; Godot generates
mesh LODs and imports embedded maps with Basis Universal compression. Saved
Blender studies remain the editable geometry and studio finish source; runtime
surface maps are authored during export.

Combined GLB size grows from 22,559,412 to 81,352,700 bytes for this roster pass.
The accepted Liberator GLB is unchanged at 7,823,272 bytes. Other hulls receive
the maps and UVs without adding triangles or material surfaces.

From the repository root, using Blender 5.2.2 and Godot 4.7.2 (adjust paths):

```powershell
rtk proxy "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-exit-code 1 --python tools/export_ships.py
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --import
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script tools/render_ship_preview.gd -- --review
rtk proxy python tools/build_ship_material_review.py
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --import
```

Without ship IDs the exporter and thumbnail renderer process the whole roster.
Pass lowercase IDs after `--` to select a subset; export statistics for other
ships are preserved. The renderer's `--review` flag adds hangar and six mesh
views; without it, only shop thumbnails are rebuilt. Rendering requires a
graphics display. The final import refreshes shop thumbnails for the game pack.

## Validation

Checked with Godot's Compatibility renderer on Windows:

- All twelve source and packaged hulls retain finite geometry, centered bounds,
  UVs, three shared maps, coated colored paint and smooth, dark cockpit glazing.
  Texture samples check that glass contrasts with paint and stays dielectric.
  Reactor and engine lenses retain emission.
- Twelve actual hangar views, 72 consistent mesh views and twelve transparent
  shop thumbnails are rendered in Godot. Review composition checks framing.
- Hangar replay: 15 rendered checks and 9 headless checks pass, including real
  mouse orbit/zoom, world isolation, hull replacement and rendering suspension.
- Main-menu replay: 105 checks pass, including layouts at 960 × 600 and
  1440 × 900, authoritative hull switching, preparation and launch.
- Offline main-menu replay: 28 checks pass.
- Ship replay: 211 checks pass with the roster loaded in flight.
- Windows PCK export, packaged asset checks and native render checks for all
  twelve packaged hulls pass. Python compilation, local document links and
  diff checks pass.

These checks establish import, packaging and interaction behavior. They do not
measure representative ten-player performance or establish final art acceptance
for the remaining ships. Complete Windows executable export and Linux execution
are left to PR CI. Generated concepts retain more modeled detail than these
authored hulls.
