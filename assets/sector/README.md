# Outpost 01 sector art

Original models and textures generated for Dorbit by
[tools/generate_sector_assets.py](../../tools/generate_sector_assets.py). No external
artwork, fonts or DarkOrbit game assets are included in the runtime models.

- `asteroid-0/1/2.glb`: three irregular cratered rocks, 1,280 triangles each;
  unit radius at most 0.98, scaled to each existing spherical collider.
- `rock-albedo.png`, `rock-normal.png`: seamless 512 px procedural stone textures,
  applied with local triplanar mapping in Godot.
- `outpost-01.glb`: concept-guided cobalt tower, six recessed hangars, armored
  buttresses, command crown and four docking blades; eight material surfaces.
  Built by [tools/build_station.py](../../tools/build_station.py), also called by
  the sector generator. Editable source and engine renders live in
  [art/station-review](../../art/station-review/README.md).
- `outpost-01-collision.json`: 53 simple physics boxes exported with the model;
  loaded identically by clients and dedicated servers, included in both packs.
- `outpost-01_cobalt/blue/graphite/titanium/normal.png`: portable surface textures
  extracted by Godot from the GLB. Source textures are packed in the `.blend`.
- `outpost-01_occlusion.png`: geometry-derived ambient occlusion in a separate
  UV set, baked by Blender for readable recesses even with runtime shadows off.
- `station-panels.png`, `outpost-01_station-panels.png`: legacy ring-station maps,
  retained for existing references; the new station does not use them.
- `derelict.glb`: damaged freighter with exposed ribs and unpowered engines,
  placed beyond the playable sector; four material groups.

From the repository root in PowerShell:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/generate_sector_assets.py
powershell -ExecutionPolicy Bypass -File tools/dev.ps1 check
```

Blender 5.2.2 LTS was used. The script uses Blender's bundled Python/NumPy.
Commit regenerated GLBs, textures and Godot `.import` metadata. Runtime scripts
load render resources only on clients; server obstacle generation consumes the
original fixed random sequence for asteroids and the shared station box manifest.

The background uses [space.gdshader](../../shaders/space.gdshader), with a detailed
panorama sampled at screen resolution, sharp procedural stars and a separate
radiance exposure for reflections. [planet.gdshader](../../shaders/planet.gdshader)
wraps dedicated surface textures onto real spheres and draws a terminator,
surviving city lights and the collector excavation. A thin additive atmosphere
shell extends beyond the solid limb. The [texture sources and full prompts](campaign-textures.md)
document the generated original artwork; it is separate from the Blender assets.

The [campaign backdrop builder](../../scripts/sector_backdrop.gd) composes all
four sectors from original procedural geometry and the existing asteroid,
derelict and metal-panel assets. Beveled human modules, broken defense rings,
segmented alien collectors, salvage arms and relay pylons merge by material
instead of creating a draw call for each component. Distant belts use three
MultiMeshes per map, with 480 rocks of varied sizes. Planets have detailed terrain,
ruined settlements, bombardment scars and mines. Broken carrier decks and ribs,
layered ring modules and debris fields reinforce the invasion history. Each map
has its own sky palette and stellar lighting. The narrow [mining stream shader](../../shaders/mining_stream.gdshader)
animates resource flow without particles or simulation nodes.

These landmarks are outside the flight boundary and have no colliders or
navigation contacts. Only the current map's backdrop is visible; dedicated
servers create none of it. The outer maps reuse the original textured asteroid
meshes inside their unchanged spherical physics envelopes. See the
[approved concepts](../../art/map-background-concepts/README.md) and
[rendered campaign review](../../docs/sector-art/campaign-backgrounds.md).

Composition references: [DarkOrbit X-8 installations](https://darkorbitwiki.com/maps/x-8-map/)
and the [classic screenshot collection](https://www.mobygames.com/game/42741/dark-orbit/screenshots/).
These were inspected for the industrial station, layered scenery and planet/nebula
composition. Reference images are not distributed with Dorbit.
