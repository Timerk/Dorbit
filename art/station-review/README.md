# Outpost 01 station study

The generated [concept](concept.png) guides the editable [Blender study](outpost-01.blend)
and the actual [Godot hero view](godot-hero.png). The concept was generated with
the built-in ImageGen tool from the user's tall blue station reference. It is
design guidance; the source mesh supplies consistent rear and underside geometry.

The model follows the tall central spine, blue/silver fitted armor, six open
hangars, side buttresses, sloped crown, four tapered docking blades and cyan
guidance strips. Named mesh parts and packed textures remain editable in Blender.
The runtime export combines them into one mesh with eight material surfaces and
automatic Godot distance LODs. Exact generated microdetail is simplified into
modeled ribs, grilles, cabinets, gantries and portable panel/normal maps. The
export bakes actual geometric ambient occlusion into a separate UV set so
recesses retain depth with runtime shadows disabled; it bakes no sun or glow.

The blue armor uses smoother metallic paint and a polished coat; titanium trim
has a low-roughness metal finish, while machinery retains a rougher surface.
The sky's reflection exposure is three times its visible background exposure,
so metals catch the nebula without brightening the space backdrop. This also
improves sky reflections on ships and other reflective scenery. Baked recess
occlusion has a reduced effect on direct light so it preserves sun highlights.

`model-stats.json` records geometry, bounds and export size. Dimensions are
approximately 170 × 294 × 170 metres, in Godot X/Y/Z. The origin sits in the
lowest hangar, approached from +Z. Station services and protection stay centered
there. Higher hangars are physical spaces but add no new menu/service locations.
The original player launch/rescue spawn remains clear. The 53 simple collision
boxes include the floors, ceilings, jambs, rear walls, command hull, buttresses,
maintenance piers, docking blades and underside reactor. Small fittings have no
individual collider. The same manifest is shipped in client and server builds.

Rebuild from the repository root:

```powershell
rtk proxy 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/build_station.py
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --editor --import
rtk proxy .tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/render_station_preview.gd
```

Append `-- --interactive` to the last command for a model review window: drag
with the left mouse to orbit and use the wheel to zoom. The ordinary render
command captures the [rear](godot-rear.png), [underside](godot-underside.png),
[hangars](godot-hangars.png), [flight view](godot-flight.png) and an actual
[service-hangar approach](godot-dock.png), alongside the hero. These are Godot
Compatibility renders using the game environment and exported materials.
The additional [hero with High shadows](godot-hero-shadows.png) shows the same
model with the game's optional High shadow setting; the other views use shadows Off.

The concept's cinematic lighting is not baked into the surface maps. In-game
shadow settings, ambient lighting and camera distance affect its appearance.
Art acceptance, scale and multiplayer performance still need user playtesting.
