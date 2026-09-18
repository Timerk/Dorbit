# DarkOrbit ship model review

Twelve editable base-ship Blender models built around the supplied DarkOrbit image catalogue. This revision rebuilds Liberator and adds reference-led mechanical and surface detail to all twelve ships, including Aegis and Goliath. The previous 82-model collection remains removed. Nothing is connected to gameplay.

[Overview of all twelve revised ships and their source pictures](previews/additional-ships-overview.jpg)

| Ship | Blender file | Reference comparison | Five-view sheet |
| --- | --- | --- | --- |
| Aegis | [aegis.blend](models/aegis.blend) | [Compare](previews/aegis-comparison.jpg) | [Views](previews/aegis-views.jpg) |
| Goliath | [goliath.blend](models/goliath.blend) | [Compare](previews/goliath-comparison.jpg) | [Views](previews/goliath-views.jpg) |
| Bigboy | [bigboy.blend](models/bigboy.blend) | [Compare](previews/bigboy-comparison.jpg) | [Views](previews/bigboy-views.jpg) |
| Defcom | [defcom.blend](models/defcom.blend) | [Compare](previews/defcom-comparison.jpg) | [Views](previews/defcom-views.jpg) |
| Leonov | [leonov.blend](models/leonov.blend) | [Compare](previews/leonov-comparison.jpg) | [Views](previews/leonov-views.jpg) |
| Liberator | [liberator.blend](models/liberator.blend) | [Compare](previews/liberator-comparison.jpg) | [Views](previews/liberator-views.jpg) |
| Nostromo | [nostromo.blend](models/nostromo.blend) | [Compare](previews/nostromo-comparison.jpg) | [Views](previews/nostromo-views.jpg) |
| Phoenix | [phoenix.blend](models/phoenix.blend) | [Compare](previews/phoenix-comparison.jpg) | [Views](previews/phoenix-views.jpg) |
| Piranha | [piranha.blend](models/piranha.blend) | [Compare](previews/piranha-comparison.jpg) | [Views](previews/piranha-views.jpg) |
| Spearhead | [spearhead.blend](models/spearhead.blend) | [Compare](previews/spearhead-comparison.jpg) | [Views](previews/spearhead-views.jpg) |
| Vengeance | [vengeance.blend](models/vengeance.blend) | [Compare](previews/vengeance-comparison.jpg) | [Views](previews/vengeance-views.jpg) |
| Yamato | [yamato.blend](models/yamato.blend) | [Compare](previews/yamato-comparison.jpg) | [Views](previews/yamato-views.jpg) |

Open a `.blend` file in Blender. Middle-drag orbits; the wheel zooms. Numpad 7 shows the top, numpad 1 the front, and numpad 3 the side. Press Home to frame the visible ship. F12 renders the saved review camera.

The Outliner separates armor and mechanical assemblies. Five named cameras provide perspective, rear, top, side and front views. The hidden `References` collection contains packed image references, and a Blender text block contains viewing notes. Materials and references have no external file dependencies. The forward direction is -Y and up is +Z. Model units and relative ship scale are for review, not canonical measurements.

## What changed

Liberator now has a narrower pointed fuselage, broad sculpted forward pods with circular mechanical wells, and two open longitudinal channels with exposed actuators. The tall central fins and flat swept wings were replaced with small outboard rear stabilizers and layered pod shells. The supplied base picture controls the shape; a supplementary hangar picture confirms the arrangement.

The detail pass follows the visible assemblies in each reference:

| Ship | Revised details |
| --- | --- |
| Aegis | Exposed neck control blocks and hydraulic lines, engineering shell seams and access caps, emitter pins, lower service pods, green manipulator tips |
| Goliath | Ports along the curved arm flanks, fitted double edge strips, shoulder equipment racks and rear spine machinery |
| Bigboy | Open armor breaks along the flanks, exposed modules, dorsal equipment, articulated outrigger clamps and pistons |
| Defcom | Overlapping shoulder armor, radiator banks, curved wing seams and lower edges, aft mechanics |
| Leonov | Double fork rails, open-channel crossmembers, shoulder hatches and bridge instruments |
| Liberator | Rebuilt pod-and-channel arrangement, circular bearings and radial mechanisms, fitted shell seams, actuator sleeves and rear bridges |
| Nostromo | Layered nose cheeks, lateral equipment bays, segmented shoulder panels and turbine feeds |
| Phoenix | Capsule seams and silver-green framing, side radiator slots, sensor bezel and small pale hull markings |
| Piranha | Long shoulder rails, fine nose ribs, cockpit flank channels, wing-root vanes and aft supply cables |
| Spearhead | Exposed tower rack, braces, front instruments, copper feed pipes and upper service hatches |
| Vengeance | Vertical engine racks, stepped cheek details, cockpit-side ventilation and lower turbine plumbing |
| Yamato | Stepped cheek insets, aft flank machinery, engine yoke couplings and supply lines |

Each model separates editable hull plates, engine parts, cockpit frames and mechanical details. Curved shells use fitted mesh panels. Turbines now have interrupted curved cowl tiles, exposed joints, rear casing ties and top radiator ribs as well as hollow mouths, recessed wells and inner vanes. These details continue the existing modeling style; the small catalogue pictures do not establish every fastener or internal assembly.

Aegis now has a tall U-shaped engineering body with a closed upper deck, green armor, a separate top emitter assembly, a sloped graphite nose, an exposed inclined neck, small articulated forward tools and swept rear fins. Goliath has curved arms with changing width, thickness and elevation, individual silver armor shells, a recessed central beak, raised dorsal fins, swept winglets and separate aft engines. Fine channels, fasteners, cooling slots and service parts are modeled geometry. Materials add only subtle procedural metal grain.

These are individually authored reconstructions for visual review. The source pictures establish the visible silhouettes and major assemblies. They do not resolve exact panel depths, the underside, internal joints or many small details; those parts are inferred. The images also differ in era, paint and camera angle. These models are reconstructions, not extracted game assets or exact replicas. There are no cosmetic variants, rigs, collision meshes, LODs or game exports in this pass.

## References

The user's catalogue and downloaded family folders remain at `D:\Ship images`. Copies of the references used for this pass are in [references](references), with provenance in [sources.json](references/sources.json). The pictures depict Bigpoint's DarkOrbit ships.

- Aegis base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/aegis.png), from the [Aegis gallery](https://darkorbitwiki.com/ships/aegis/). Its green body determines the model's paint. The thin top antenna follows this base image; it is absent from the blue engineering illustration.
- Aegis geometry uses the two-angle engineering illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Aegis). The browser displayed a 960 x 450 source. The included 950 x 444 image is a crop of that browser display, not the original downloaded file. It depicts blue paint and provides useful views of the engineering body, front tools and fins. Only the geometry informs the green base model.
- Goliath base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/goliath.png), from the [Goliath gallery](https://darkorbitwiki.com/ships/goliath/). This 256 x 208 render is the primary silhouette and paint reference.
- Goliath's supplementary angle is the small `10_Goliath.jpg` illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Goliath), downloaded as its 180-pixel thumbnail. It supports the placement of the beak, arms and fins but supplies little fine detail.
- Liberator also uses the 276 x 264 hangar image on [DarkOrbit Wiki](https://darkorbit.fandom.com/wiki/Liberator), preserved as the browser-delivered WebP. It confirms the broad forward pods and open channels. The ship itself occupies only a small part of that image, so it does not establish fine mechanical construction.
- The ten additional ships use their supplied base catalogue PNGs from `D:\Ship images\<ship family>`. Copies are packed into each model and stored as `<ship>-base.png` under `references`. The provenance file records source galleries, local paths, native dimensions and SHA-256 hashes. Base hulls are modeled here; cosmetic designs and Plus variants are outside this request.

The unrelated black/orange spaceship in the catalogue's fan-made Goliath viewer is excluded. The small historical GIFs do not establish rotating views. Displaying a catalogue image larger on a comparison sheet does not recover detail. Comparison cameras approximate the source angles; the sheets are visual reviews, not calibrated overlays.

## Rebuilding and checks

Generated with Blender 5.2.1 LTS. From the repository root:

```powershell
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/build_models.py
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/validate_models.py
```

Append `-- Bigboy` to rebuild one ship, or list several names after `--`. Names are case-sensitive as listed in the table. With no names the builder regenerates all twelve, including the approved pair. Add `--draft` after `--` for smaller, quicker perspective and top renders. Draft builds overwrite that ship's model and previews; rebuild without `--draft` before delivery. `--gpu` enables OptiX rendering on a supported NVIDIA GPU. The sheet builder uses Pillow:

```powershell
rtk proxy C:/Users/TBerk/AppData/Local/Python/bin/python.exe art/ship-review/build_review_sheets.py
```

[build-stats.json](build-stats.json) records geometry counts. [validation.json](validation.json) records checks on the saved files, including evaluated geometry and packed references. The sheet builder also checks that no ship touches the render boundary. Five-view sheets and reference comparisons are used for visual inspection. Windows viewport interaction could not be checked because the computer-use native pipe was unavailable; saved files are reopened and checked through Blender's background mode. Gameplay checks do not apply to this isolated art pass; `art/.gdignore` excludes the collection from Godot imports.
