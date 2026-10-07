# Dorbit ship design references

[Overview of all twelve concept turnarounds](overview.jpg)

These twelve generated concept turnarounds use the user's Liberator main-menu
image as the finish reference and the existing ship catalogue as the silhouette
reference. They were created with the built-in image generation tool on
7 October 2026. The exact prompts are saved in [prompts.json](prompts.json).
[Provenance](provenance.json) records the input roles and image hashes; the
original [catalogue roster](catalogue-roster-reference.jpg) is preserved separately
from the newly rendered model overview.
The supplied screenshot is preserved as
[liberator-style-reference.png](liberator-style-reference.png).

Each sheet requests perspective, top, side, front, rear, underside and rear
three-quarter views. The primary reference for modeling is the large perspective
view. Generated views sometimes disagree about panel placement, engine details
or projection; they are concepts, not calibrated engineering drawings. Resolve
those ambiguities in the single editable Blender mesh, then use its six rendered
views as the consistent construction reference. Do not trace each angle as a
different ship, infer physical dimensions, or use the sheet as a runtime texture.

| Ship | Concept turnaround | Editable model | Consistent mesh views |
| --- | --- | --- | --- |
| Aegis | [Concept](aegis.png) | [Blender](../models/aegis.blend) | [Views](../previews/aegis-views.jpg) |
| Bigboy | [Concept](bigboy.png) | [Blender](../models/bigboy.blend) | [Views](../previews/bigboy-views.jpg) |
| Defcom | [Concept](defcom.png) | [Blender](../models/defcom.blend) | [Views](../previews/defcom-views.jpg) |
| Goliath | [Concept](goliath.png) | [Blender](../models/goliath.blend) | [Views](../previews/goliath-views.jpg) |
| Leonov | [Concept](leonov.png) | [Blender](../models/leonov.blend) | [Views](../previews/leonov-views.jpg) |
| Liberator | [Concept](liberator.png) | [Blender](../models/liberator.blend) | [Views](../previews/liberator-views.jpg) |
| Nostromo | [Concept](nostromo.png) | [Blender](../models/nostromo.blend) | [Views](../previews/nostromo-views.jpg) |
| Phoenix | [Concept](phoenix.png) | [Blender](../models/phoenix.blend) | [Views](../previews/phoenix-views.jpg) |
| Piranha | [Concept](piranha.png) | [Blender](../models/piranha.blend) | [Views](../previews/piranha-views.jpg) |
| Spearhead | [Concept](spearhead.png) | [Blender](../models/spearhead.blend) | [Views](../previews/spearhead-views.jpg) |
| Vengeance | [Concept](vengeance.png) | [Blender](../models/vengeance.blend) | [Views](../previews/vengeance-views.jpg) |
| Yamato | [Concept](yamato.png) | [Blender](../models/yamato.blend) | [Views](../previews/yamato-views.jpg) |

The common direction is fitted painted armor over graphite structure, readable
mechanical bays, clean chamfers, darker glazing, machined silver trim and small
copper service markings. Each ship retains its recognizable base silhouette and
dominant colors. The revised meshes are an authored interpretation of these
concepts; the images contain more surface detail than the game geometry.

The concept, original catalogue references and finish screenshot are packed into
each `.blend` under the hidden References collection. Enable that collection to
inspect them. Select the named perspective, top, side, front, rear or underside
camera for consistent views of the actual geometry.

See [the model workflow](../README.md) for rebuild and export commands and
[playable ships](../../../docs/ships.md) for game integration. Generated concepts
remain under `art/.gdignore`; game meshes and shop previews are exported separately.
