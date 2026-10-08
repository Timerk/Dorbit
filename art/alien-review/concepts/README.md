# Alien modeling references

Generated with the built-in image generation tool on 8 October 2026 for the
existing Scout, Sentinel and Heavy alien spacecraft. The exact prompt set is
saved in [prompts.json](prompts.json). No input reference images were used.

| Alien | Reference sheet | Modeling direction |
| --- | --- | --- |
| Scout | [Scout](scout.png) | Small, narrow hull; swept crescent wings; amber armor and sensors. |
| Sentinel | [Sentinel](sentinel.png) | Broader wedge hull; armored forward talons; crimson armor and sensors. |
| Heavy | [Heavy](heavy.png) | Thick layered hull and belly armor; reinforced shoulders; violet armor and sensors. |

Each sheet includes a perspective render, top, side, front, rear and underside
views, plus closeups of coated armor, exposed metal and recessed machinery.
The proposed finish uses fitted gunmetal armor, colored coating, machined trim,
restrained emissive sensors and light edge wear. The user approved these concepts
on 8 October 2026 and requested editable models and renders.

Use the large perspective view as the primary design reference. Generated views
are not calibrated orthographic drawings: some wing angles, panels, weapon
details and engine shapes differ between views. Resolve them in one editable
mesh, then render consistent construction views from that mesh. The images do
not establish physical dimensions or alter existing gameplay scales.

The closeups guide material authoring; they are not seamless textures or
UV-ready base-color, roughness, metallic, normal or emission maps. Author those
maps for the final mesh, with lighting excluded from base color and glow kept
in a separate emission channel. Keep large silhouette features in geometry and
fine grain or scratches in surface maps.

These files contain the approved concept images. The
[model review](../README.md) provides authored Blender models, portable textured
GLB exports and consistent renders. The existing `art/.gdignore` keeps this
collection out of Godot imports; runtime integration remains separate work.
