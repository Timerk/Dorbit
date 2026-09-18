# DarkOrbit ship model review

Twelve editable base-ship Blender models built around the supplied DarkOrbit image catalogue. Aegis is the user's accepted quality benchmark and its model and renders are preserved. This revision corrects the other eleven ships' proportions, colors, glazing and assemblies after a close comparison with each supplied base image. Nothing is connected to gameplay.

[Overview of all twelve ships and their source pictures](previews/additional-ships-overview.jpg)

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

The review used Aegis's separation of painted armor, dark structure and exposed mechanisms as the finish benchmark. It also identified larger discrepancies that adding fasteners could not fix. The following table records the visible reference cues and resulting changes.

| Ship | Reference comparison and correction |
| --- | --- |
| Aegis | Accepted benchmark. The saved model, materials and all five renders remain unchanged. |
| Goliath | The arms read as thinner blades with darker inset crowns. Reduced arm thickness and fin height; added curved, fitted crown insets while retaining silver edges and flank ports. |
| Bigboy | The olive bridge is a small raised command unit under an aft overhang. Replaced the large flat windshield with a compact curved bridge, reshaped the overhang, shortened the aft drives, and deepened the blue paint. |
| Defcom | The green wings and central shell are curved. Rebuilt the scythes and carapace as curved shells with fitted glazing, rounded shoulders and shorter rear fins. |
| Leonov | The two forks dominate the front silhouette around a narrow center. Narrowed the central spine, replaced the tall block cockpit with a small curved bridge, and added open equipment wells on the aft rails. |
| Liberator | The central blue cockpit is raised and curved above the needle nose. Added a fitted fairing and glazing, dark equipment cells inside the engine channels, copper markings and pod armor divisions. |
| Nostromo | The turbines sit low against the dark aft body. Lowered and shortened them, removed the tall supports, narrowed the smoked cockpit and darkened the hull and exposed metal. |
| Phoenix | The capsule is broader, with silver-green canopy trim. Widened and lowered the body, fitted broad metal strips to the glazing, revised the red paint and silvery canopy, and inset the underlying chassis to prevent it breaking through the curved armor. |
| Piranha | The bridge and tail fins are small relative to the long nose rails. Replaced the large windshield with a narrow curved bridge, lowered the fins and added blue longitudinal fairings. |
| Spearhead | The upper blue pod rests on exposed dark machinery. Replaced the broad tower slab with a narrow spine and instruments, reduced the cockpit and outriggers, and added the blue nose strips. |
| Vengeance | A compact heavy fighter with stepped engine blocks and dark cheek apertures. Shortened the hull, rebuilt all four drives with bell intakes and exposed waists, reduced the canopy and replaced the broad engine braces. |
| Yamato | The cockpit is visibly stepped and the drives have separate blue-banded sections. Replaced the long windshield with three mounted panes and rebuilt both sizes of drive pod. |

Painted blue and green surfaces now have separate darker palettes instead of sharing the same bright metal finish. Glass is less reflective, metal grain is finer, and engine lenses are less luminous. Studio lighting is retained for inspection; it does not reproduce the source images' lighting. Most comparison cameras show more of the side to approach the catalogue angle. Aegis's camera remains unchanged.

Each model separates editable hull plates, engine parts, cockpit frames and mechanical details. Curved shells use fitted mesh panels. Vengeance and Yamato use short stepped drive assemblies; the other cylindrical engines retain their segmented cowls and radiator ribs. Glazing replaces selected curved shell panels on Defcom, Leonov and Liberator, avoiding overlapping glass and armor. Fasteners in reshaped assemblies move with their parent geometry.

Aegis retains its U-shaped engineering body, green armor, top emitter, sloped graphite nose, exposed inclined neck, articulated forward tools and swept rear fins. Its layered construction is the benchmark for this collection. Fine channels, fasteners, cooling slots and service parts are modeled geometry. Materials add only subtle procedural metal grain.

These are individually authored reconstructions for visual review. The source pictures establish the visible silhouettes and major assemblies. They do not resolve exact panel depths, the underside, internal joints or many small details; those parts are inferred. The images also differ in era, paint and camera angle. These models are reconstructions, not extracted game assets or exact replicas. There are no cosmetic variants, rigs, collision meshes, LODs or game exports in this pass.

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

Generated with Blender 5.2.1 LTS. From the repository root:

```powershell
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/build_models.py
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/validate_models.py
```

Append `-- Bigboy` to rebuild one ship, or list several names after `--`. Names are case-sensitive as listed in the table. With no names the builder regenerates all twelve, including Aegis; list the other names explicitly to preserve its accepted files. Add `--draft` after `--` for smaller, quicker perspective and top renders. Draft builds overwrite that ship's model and previews; rebuild without `--draft` before delivery. `--gpu` enables OptiX rendering on a supported NVIDIA GPU. The sheet builder uses Pillow:

```powershell
rtk proxy C:/Users/TBerk/AppData/Local/Python/bin/python.exe art/ship-review/build_review_sheets.py
```

[build-stats.json](build-stats.json) records geometry counts. [validation.json](validation.json) records checks on the saved files, including evaluated geometry and packed references. The sheet builder also checks that no ship touches the render boundary. Five-view sheets and reference comparisons are used for visual inspection. Windows viewport interaction could not be checked because the computer-use native pipe was unavailable; saved files are reopened and checked through Blender's background mode. Gameplay checks do not apply to this isolated art pass; `art/.gdignore` excludes the collection from Godot imports.
