# Liberator material benchmark

The Liberator now uses the same textured PBR finish in flight, the docked
overview and its shop thumbnail. Coated blue armor, exposed satin metal,
dark structure and copper fittings have distinct surface responses. Each fitted
Blender component gets its own padded UV tile, with small roughness differences
between panels and subtle tangent-space normal-map grain. Texture colors contain
no painted lighting or reflections.

[Godot hangar render](feedback/liberator-material-hangar.png) ·
[Closer material view](feedback/liberator-material-detail.png) ·
[Docked overview](feedback/liberator-material-menu.png) ·
[Actual flight view](feedback/liberator-material-flight.png)

The overview renders the active hull in an isolated 3D hangar. Drag the ship to
orbit, scroll to zoom, and double-click to reset the camera. Broad environment
reflection strips, a key light, fill and warm rim light show the hull's curvature
and metal. The preview caches its view after 12 settling frames, refreshes after
camera/model/size changes, and stops drawing when hidden or after launch. Its
lights and camera never enter the sector's world.

Only the Liberator receives the new surface atlas in this pass. Other active
hulls can be inspected in the same hangar with their existing materials; extend
the finish after reviewing this benchmark. The hull geometry remains the earlier
concept interpretation, with less modeled detail than the generated target.
Flight uses the sector's existing lighting, so its highlights differ from the
controlled hangar.

## Source and rebuilding

[Surface maps and per-part settings](../art/ship-review/materials/liberator/manifest.json)
are generated deterministically by [ship_surface_atlas.py](../tools/ship_surface_atlas.py)
from the saved Blender components. The 2048 × 2048 albedo, ORM and normal maps
are embedded in `assets/ships/liberator.glb`. ORM contains roughness in green and
metallic in blue; red is 1 because no ambient-occlusion bake is supplied.

The glTF export shares three image/sampler entries. Godot's
[import hook](../tools/import_liberator.gd) also shares the three compressed texture
resources across all ten material surfaces and restores the blue paint clearcoat.
The GLB retains its single mesh, 98,228 base triangles, centered 7 m bounds and
forward orientation. It grows from 2,016,468 to 7,857,488 bytes with UVs and maps.
The saved `.blend` file remains the editable geometry source.

From the repository root, using Blender 5.2.2 and Godot 4.7.2 (adjust paths):

```powershell
rtk proxy "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-exit-code 1 --python tools/export_ships.py -- liberator
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --import
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script tools/render_ship_preview.gd
```

The exporter accepts lowercase ship IDs after `--` and preserves other export
statistics when selecting a subset. The Liberator thumbnail is rendered in Godot
after import; exporting Blender geometry does not replace it with the earlier
studio finish. Thumbnail rendering requires a graphics display.

## Validation

Checked with Godot's Compatibility renderer on Windows:

- Hangar replay: 15 rendered checks and 9 headless checks pass, including real
  mouse orbit/zoom, world isolation, hull replacement and rendering suspension.
- Main-menu replay: 105 checks pass, including layouts at 960 × 600 and
  1440 × 900, authoritative hull switching, preparation and launch.
- Ship replay: 211 checks pass, with the textured Liberator loaded in flight.
- Both source assets and an exported Windows PCK retain UVs, all three shared
  maps, coated paint, all twelve hulls, bounds, materials and previews.
- The hangar also renders successfully from the exported PCK, including its
  shaders and textures. Python compilation and diff checks pass.

These checks establish import, packaging and interaction behavior. They do not
measure representative ten-player performance or establish final art acceptance.
Texture memory and initial shader compilation add costs despite unchanged
triangle and material counts. A complete Windows executable export and Linux
execution are left to PR CI.
