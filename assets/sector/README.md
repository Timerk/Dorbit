# Outpost 01 sector art

Original models and textures generated for Dorbit by
[tools/generate_sector_assets.py](../../tools/generate_sector_assets.py). No external
artwork, fonts or DarkOrbit game assets are included. The station designation uses
Blender's built-in font.

- `asteroid-0/1/2.glb`: three irregular cratered rocks, 1,280 triangles each;
  unit radius at most 0.98, scaled to each existing spherical collider.
- `rock-albedo.png`, `rock-normal.png`: seamless 512 px procedural stone textures,
  applied with local triplanar mapping in Godot.
- `outpost-01.glb`: segmented docking aperture, armor plates, solar arrays and
  service hull; six material groups to limit draw calls.
- `station-panels.png`: generated panel/seam texture embedded into the station GLB.
- `derelict.glb`: damaged freighter with exposed ribs and unpowered engines,
  placed beyond the playable sector; four material groups.

From the repository root in PowerShell:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python tools/generate_sector_assets.py
powershell -ExecutionPolicy Bypass -File tools/dev.ps1 check
```

Blender 5.2.2 LTS was used. The script uses Blender's bundled Python/NumPy.
Commit regenerated GLBs, textures and Godot `.import` metadata. Runtime scripts
load these resources only on rendered clients; server obstacle generation remains
independent of model geometry and consumes the original fixed random sequence.

The background uses [space.gdshader](../../shaders/space.gdshader), with static
nebula calculations cached in the sky radiance cubemap and sharp stars drawn at
screen resolution. [planet.gdshader](../../shaders/planet.gdshader) supplies ocean,
land, cloud cover, a terminator and an atmospheric limb without extra transparent
sphere layers. Neither shader uses time or camera position to animate the sky.

Composition references: [DarkOrbit X-8 installations](https://darkorbitwiki.com/maps/x-8-map/)
and the [classic screenshot collection](https://www.mobygames.com/game/42741/dark-orbit/screenshots/).
These were inspected for the industrial station, layered scenery and planet/nebula
composition. Reference images are not distributed with Dorbit.
