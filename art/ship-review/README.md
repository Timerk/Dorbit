# Aegis and Goliath model review

Two editable Blender models rebuilt around the supplied DarkOrbit image catalogue. The previous 82-model collection has been removed. This pass contains only the base Aegis and base Goliath. Nothing is connected to gameplay.

| Ship | Blender file | Reference comparison | Five-view sheet |
| --- | --- | --- | --- |
| Aegis | [aegis.blend](models/aegis.blend) | [Compare](previews/aegis-comparison.jpg) | [Views](previews/aegis-views.jpg) |
| Goliath | [goliath.blend](models/goliath.blend) | [Compare](previews/goliath-comparison.jpg) | [Views](previews/goliath-views.jpg) |

Open a `.blend` file in Blender. Middle-drag orbits; the wheel zooms. Numpad 7 shows the top, numpad 1 the front, and numpad 3 the side. Press Home to frame the visible ship. F12 renders the saved review camera.

The Outliner separates armor and mechanical assemblies. Five named cameras provide perspective, rear, top, side and front views. The hidden `References` collection contains packed image references, and a Blender text block contains viewing notes. Materials and references have no external file dependencies. The forward direction is -Y and up is +Z. Model units and relative ship scale are for review, not canonical measurements.

## What changed

Aegis now has a tall U-shaped engineering body with a closed upper deck, green armor, a separate top emitter assembly, a sloped graphite nose, an exposed inclined neck, small articulated forward tools and swept rear fins. Goliath has curved arms with changing width, thickness and elevation, individual silver armor shells, a recessed central beak, raised dorsal fins, swept winglets and separate aft engines. Fine channels, fasteners, cooling slots and service parts are modeled geometry. Materials add only subtle procedural metal grain.

These are individually authored reconstructions for visual review. The source pictures establish the visible silhouettes and major assemblies. They do not resolve exact panel depths, the underside, internal joints or many small details; those parts are inferred. The images also differ in era, paint and camera angle. Neither model is an extracted game asset or a claim of an exact replica. There are no cosmetic variants, rigs, collision meshes, LODs or game exports in this pass.

## References

The user's catalogue and downloaded family folders remain at `D:\Ship images`. Copies of the references used for this pass are in [references](references), with provenance in [sources.json](references/sources.json). The pictures depict Bigpoint's DarkOrbit ships.

- Aegis base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/aegis.png), from the [Aegis gallery](https://darkorbitwiki.com/ships/aegis/). Its green body determines the model's paint. The thin top antenna follows this base image; it is absent from the blue engineering illustration.
- Aegis geometry uses the two-angle engineering illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Aegis). The browser displayed a 960 x 450 source. The included 950 x 444 image is a crop of that browser display, not the original downloaded file. It depicts blue paint and provides useful views of the engineering body, front tools and fins. Only the geometry informs the green base model.
- Goliath base appearance comes from the supplied [catalogue PNG](https://darkorbitwiki.com/images/goliath.png), from the [Goliath gallery](https://darkorbitwiki.com/ships/goliath/). This 256 x 208 render is the primary silhouette and paint reference.
- Goliath's supplementary angle is the small `10_Goliath.jpg` illustration on [German Dark Orbit Wiki](https://darkorbit.fandom.com/de/wiki/Goliath), downloaded as its 180-pixel thumbnail. It supports the placement of the beak, arms and fins but supplies little fine detail.

The unrelated black/orange spaceship in the catalogue's fan-made Goliath viewer is excluded. The small historical GIFs do not establish rotating views. Displaying a catalogue image larger on a comparison sheet does not recover detail. Comparison cameras approximate the source angles; the sheets are visual reviews, not calibrated overlays.

## Rebuilding and checks

Generated with Blender 5.2.1 LTS. From the repository root:

```powershell
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/build_models.py
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/validate_models.py
```

Append `-- Aegis` or `-- Goliath` to rebuild one ship. Add `--draft` after `--` for smaller, quicker perspective and top renders. `--gpu` enables OptiX rendering on a supported NVIDIA GPU. The sheet builder uses Pillow:

```powershell
rtk proxy C:/Users/TBerk/AppData/Local/Python/bin/python.exe art/ship-review/build_review_sheets.py
```

[build-stats.json](build-stats.json) records geometry counts. [validation.json](validation.json) records checks on the saved files, including evaluated geometry and packed references. All ten final renders and both reference comparison sheets were inspected visually. Gameplay checks do not apply to this isolated art pass; `art/.gdignore` excludes the collection from Godot imports.
