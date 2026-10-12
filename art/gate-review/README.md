# Transit gates and illustrated star system

The user approved [this generated concept](concept.png) and requested its
implementation, followed by a connected-maps screen using background pictures.
This work depends on the campaign backgrounds in PR #85.

## Gate

The editable [Blender model](transit-gate.blend) contains packed textures.
`tools/build_gate.py` reproduces its geometry, metal textures and runtime
`assets/sector/transit-gate.glb` with Blender 5.2:

```powershell
rtk proxy blender --background --python tools/build_gate.py
```

The aperture is 25.2 m across. Mirrored armor, inset service panels and vent
louvers surround it; four externally clamped conduits and three power modules
give the approved silhouette. Five shared materials cover titanium, graphite,
cobalt, chrome and cyan emitters. The standard glTF base-color factors preserve
the authored tints; the builder sets those explicitly because Blender drops a
constant multiply node during export. Godot generates mesh LODs on import.
The highest-detail source is 174,328 triangles; active sectors show one to three
gates, sharing their mesh and material resources. The animated portal adds one
quad and two texture samples. Two local lights illuminate only gate armor.
The portal stays readable without bloom on the OpenGL Compatibility renderer.

There are no gate collision bodies. The 50 m jump radius, 75 m protection radius,
two-second cooldown, eight gate locations and four-map routing are unchanged.
Dedicated servers instantiate none of this rendering.

![Gate in the actual M1 sector](gate-hero.png)

![Normal flight approach with the jump prompt](gate-flight.png)

## Star system

The four sector previews in `assets/ui/maps` are clean 720×450 captures of the
actual campaign scenery, without HUD, ship or gate labels. `NetworkPlot` crops
them to image cards rather than stretching them. Thin orthogonal lines show all
four real paired links. Current location, encounter tier, hover route highlighting,
tooltips and keyboard focus provide navigation context. Click a destination, or
use arrow keys and Enter, to select its next gate. Selecting the current map does
not change the waypoint. The overview scales to the window; the Local sector
tab retains its existing contact, rotation and zoom tools.

![Illustrated star system with M4 route preview](star-system.png)

## Review and regeneration

```powershell
rtk proxy godot --path . --script res://tests/gate_art_preview.gd
# Regenerate sector thumbnails as well:
rtk proxy godot --path . --script res://tests/gate_art_preview.gd -- --thumbnails
rtk proxy godot --headless --editor --path . --import
rtk proxy godot --path . --script res://tests/connected_maps_playthrough.gd
```

The gate fixture captures front, rear, later vortex flow and ordinary flight.
The connected-map replay checks responsive cards, real routes, mouse and keyboard
selection, and every reciprocal jump at 960×600, 1280×720 and 1920×1080.
`sector_visuals_test.gd` checks all eight gate transforms, collision exclusion,
surface budget and portal textures alongside unchanged client/server obstacles.
Runtime images, shader and model are also inspected from an exported Windows
resource pack. The concept is an art-direction reference; these screenshots show
the actual runtime result.
