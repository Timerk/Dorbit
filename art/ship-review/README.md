# DarkOrbit ship model review

Twelve editable base-ship Blender models, now refined using the user's Liberator hangar image as a shared finish reference. [Generated concept turnarounds](concepts/README.md) cover the whole roster. The models use brighter separated PBR materials, ship-specific fitted service panels and mechanical assemblies, rebuilt Liberator turbine pods and drives, and revised Goliath crowns and inner-arm bays. Six actual mesh renders provide consistent views, including the underside. Derived gameplay exports live under `assets/ships`; see [playable ships](../../docs/ships.md).

[Overview of all twelve ships and their source pictures](previews/additional-ships-overview.jpg)

The Nostromo now has a longer forebody and a narrower, tapered bow following user
review. Length relative to wing span increases by about 30%; the old wide nose
cap becomes a small tip. Its plating, cockpit and cheek fittings follow the
revised hull; the paired rear turbines and swept wings retain their recognizable
arrangement.

All twelve ships now share the approved [Godot material finish](../../docs/ship-materials.md)
with per-component surface maps, distinct cockpit glass and a live hangar view.
The [Godot roster overview](../../docs/feedback/ship-materials-overview.jpg) and
per-ship six-view sheets in that material review show the actual game assets.
These runtime maps are authored from the saved model during export; the Blender
renders below continue to document the geometry and studio finish.

| Ship | Blender file | Catalogue comparison | Six-view sheet |
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

The Outliner separates armor and mechanical assemblies. Six named cameras provide perspective, rear, top, side, front and underside views. The hidden `References` collection contains the packed concept, supplied finish screenshot and catalogue references. A Blender text block contains viewing notes. Materials and references have no external file dependencies. Forward is -Y and up is +Z. Model units and relative ship scale are for review, not canonical measurements.

## Model construction

The original catalogue pictures establish the base silhouettes. The shared
Dorbit finish and fitted machinery are implemented in
[concept_refinement.py](concept_refinement.py), called by the builder.

Each model separates editable hull plates, engine parts, cockpit frames and mechanical details. Curved shells use fitted mesh panels. Vengeance and Yamato use short stepped drive assemblies; the other cylindrical engines retain their segmented cowls and radiator ribs. Glazing replaces selected curved shell panels on Defcom, Leonov and Liberator, avoiding overlapping glass and armor. Fasteners in reshaped assemblies move with their parent geometry.

Aegis retains its U-shaped engineering body, green armor, top emitter, sloped graphite nose, exposed inclined neck, articulated forward tools and swept rear fins. Fine channels, fasteners, cooling slots and service parts are modeled geometry. Blender materials add subtle procedural metal grain; export produces portable surface maps for Godot.

These are individually authored reconstructions for visual review. The source pictures establish the visible silhouettes and major assemblies. They do not resolve exact panel depths, the underside, internal joints or many small details; those parts are inferred. The images also differ in era, paint and camera angle. The saved studies contain no cosmetic variants, rigs or collision meshes; game exports and LODs are derived separately.

## References

The user's catalogue and downloaded family folders remain at `D:\Ship images`. Copies of the references used for this pass are in [references](references), with provenance in [sources.json](references/sources.json). The pictures depict Bigpoint's DarkOrbit ships.

- Aegis base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/aegis.png), from the [Aegis gallery](https://darkorbitwiki.com/ships/aegis/). Its green body determines the model's paint. The thin top antenna follows this base image; it is absent from the blue engineering illustration.
- Aegis geometry uses the two-angle engineering illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Aegis). The browser displayed a 960 x 450 source. The included 950 x 444 image is a crop of that browser display, not the original downloaded file. It depicts blue paint and provides useful views of the engineering body, front tools and fins. Only the geometry informs the green base model.
- Goliath base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/goliath.png), from the [Goliath gallery](https://darkorbitwiki.com/ships/goliath/). This 256 x 208 render is the primary silhouette and paint reference.
- Goliath's supplementary angle is the small `10_Goliath.jpg` illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Goliath), downloaded as its 180-pixel thumbnail. It supports the placement of the beak, arms and fins but supplies little fine detail.
- Liberator also uses the 276 x 264 hangar image on [DarkOrbit Wiki](https://darkorbit.fandom.com/wiki/Liberator), preserved as the browser-delivered WebP. It confirms the broad forward pods and open channels. The ship itself occupies only a small part of that image, so it does not establish fine mechanical construction.
- The ten additional ships use their supplied base catalogue PNGs from `D:\Ship images\<ship family>`. Copies are packed into each model and stored as `<ship>-base.png` under `references`. The provenance file records source galleries, local paths, native dimensions and SHA-256 hashes. Base hulls are modeled here; cosmetic designs and Plus variants are outside this request.

The unrelated black/orange spaceship in the catalogue's fan-made Goliath viewer is excluded. The small historical GIFs do not establish rotating views. Comparison sheets crop nearly transparent margins before enlarging the reference, so the ship fills its panel. This makes comparison easier but does not recover detail. Comparison cameras approximate the source angles; the sheets are visual reviews, not calibrated overlays.

## Rebuilding and checks

The current revision uses Blender 5.2.2 LTS. From the repository root (adjust the executable path for your installation):

```powershell
rtk proxy "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python art/ship-review/build_models.py
rtk proxy "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python art/ship-review/validate_models.py
rtk proxy "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python tools/export_ships.py
```

Append `-- Bigboy` to rebuild one ship, or list several names after `--`. Names are case-sensitive as listed in the table. With no names the builder regenerates all twelve. The default renderer is Eevee with ray tracing and ambient occlusion; `--cycles` selects Cycles and `--cycles --gpu` enables OptiX on a supported NVIDIA GPU. Add `--draft` for smaller perspective and top renders; rebuild without it before delivery. Do not run simultaneous builders against the same ship. The sheet builder uses Pillow:

```powershell
rtk proxy python art/ship-review/build_review_sheets.py
```

The builder creates individual angle PNGs locally before validation and sheet
composition. These intermediate renders are ignored by Git; comparison sheets,
six-view sheets and the overview are retained. Rebuild the models before running
the validator or sheet builder on a fresh checkout.

[build-stats.json](build-stats.json) records geometry counts. [validation.json](validation.json) records checks on reopened files, evaluated geometry, all six final renders and packed concepts. The sheet builder also checks that no ship touches a render boundary. Game exports use a 3.5 m bounding diameter for Phoenix and 7 m for the others, with shared orientation and one-mesh layout. `art/.gdignore` excludes the modeling collection and concept sheets from Godot imports. Art acceptance and representative-hardware performance remain user review tasks.
