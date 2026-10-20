# DarkOrbit ship model review

Art sources and review images use [Git LFS](https://git-lfs.com). Before editing
art sources or running art tools, install Git LFS and run `git lfs install` and
`git lfs pull` from the repository root.

Twelve editable base-ship Blender models, now refined using the user's Liberator hangar image as a shared finish reference. [Generated concept turnarounds](concepts/README.md) cover the whole roster. The models use brighter separated PBR materials, ship-specific fitted service panels and mechanical assemblies, rebuilt Liberator turbine pods and drives, and revised Goliath crowns and inner-arm bays. Six actual mesh renders provide consistent views, including the underside. Derived gameplay exports live under `assets/ships`; see [playable ships](../../docs/ships.md).

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

| Ship | Blender file | Six-view sheet |
| --- | --- | --- |
| Aegis | [aegis.blend](models/aegis.blend) | [Views](previews/aegis-views.jpg) |
| Goliath | [goliath.blend](models/goliath.blend) | [Views](previews/goliath-views.jpg) |
| Bigboy | [bigboy.blend](models/bigboy.blend) | [Views](previews/bigboy-views.jpg) |
| Defcom | [defcom.blend](models/defcom.blend) | [Views](previews/defcom-views.jpg) |
| Leonov | [leonov.blend](models/leonov.blend) | [Views](previews/leonov-views.jpg) |
| Liberator | [liberator.blend](models/liberator.blend) | [Views](previews/liberator-views.jpg) |
| Nostromo | [nostromo.blend](models/nostromo.blend) | [Views](previews/nostromo-views.jpg) |
| Phoenix | [phoenix.blend](models/phoenix.blend) | [Views](previews/phoenix-views.jpg) |
| Piranha | [piranha.blend](models/piranha.blend) | [Views](previews/piranha-views.jpg) |
| Spearhead | [spearhead.blend](models/spearhead.blend) | [Views](previews/spearhead-views.jpg) |
| Vengeance | [vengeance.blend](models/vengeance.blend) | [Views](previews/vengeance-views.jpg) |
| Yamato | [yamato.blend](models/yamato.blend) | [Views](previews/yamato-views.jpg) |

Open a `.blend` file in Blender. Middle-drag orbits; the wheel zooms. Numpad 7 shows the top, numpad 1 the front, and numpad 3 the side. Press Home to frame the visible ship. F12 renders the saved review camera.

The Outliner separates armor and mechanical assemblies. Six named cameras provide perspective, rear, top, side, front and underside views. The hidden `References` collection contains only the packed generated concept and Dorbit finish image. A Blender text block contains viewing notes. Materials and references have no external file dependencies. Forward is -Y and up is +Z. Model units and relative ship scale are for review, not canonical measurements.

## Model construction

The original catalogue pictures establish the base silhouettes. The shared
Dorbit finish and fitted machinery are implemented in
[concept_refinement.py](concept_refinement.py), called by the builder.

Each model separates editable hull plates, engine parts, cockpit frames and mechanical details. Curved shells use fitted mesh panels. Vengeance and Yamato use short stepped drive assemblies; the other cylindrical engines retain their segmented cowls and radiator ribs. Glazing replaces selected curved shell panels on Defcom, Leonov and Liberator, avoiding overlapping glass and armor. Fasteners in reshaped assemblies move with their parent geometry.

Aegis retains its U-shaped engineering body, green armor, top emitter, sloped graphite nose, exposed inclined neck, articulated forward tools and swept rear fins. Fine channels, fasteners, cooling slots and service parts are modeled geometry. Blender materials add subtle procedural metal grain; export produces portable surface maps for Godot.

These are individually authored reconstructions for visual review. The source pictures establish the visible silhouettes and major assemblies. They do not resolve exact panel depths, the underside, internal joints or many small details; those parts are inferred. The images also differ in era, paint and camera angle. The saved studies contain no cosmetic variants, rigs or collision meshes; game exports and LODs are derived separately.

## References

Bigpoint catalogue images, comparison sheets containing them, and the catalogue
roster have been removed from the current tree. The saved Blender files contain
only generated Dorbit concept and finish images. [sources.json](references/sources.json)
retains historical provenance for the external images; the image files are absent.
Keep external references in private storage outside this repository. Git LFS
would still distribute them from a public repository.

The models still reconstruct DarkOrbit ship designs. Removing source images does
not make those designs original or resolve the public-release requirement in
[GAME_PLAN.md](../../GAME_PLAN.md#art-and-tools). Older Git commits still contain
the removed images and packed copies. Purging them requires a coordinated history
rewrite, including affected branches and tags; this cleanup does not rewrite history.

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
composition. These intermediate renders are ignored by Git; six-view sheets
and the generated concept overview are retained. Rebuild the models before running
the validator or sheet builder on a fresh checkout.

For model and packed-image checks without regenerating local renders, append
`-- --models-only` to the validator command. The report records that render
checks were skipped.

[build-stats.json](build-stats.json) records geometry counts. [validation.json](validation.json) records checks on reopened files, evaluated geometry and the generated-only packed images. Full validation also checks all six final renders; the current cleanup report uses `--models-only`. The sheet builder checks that no ship touches a render boundary. Game exports use a 3.5 m bounding diameter for Phoenix and 7 m for the others, with shared orientation and one-mesh layout. `art/.gdignore` excludes the modeling collection and concept sheets from Godot imports. Art acceptance and representative-hardware performance remain user review tasks.
