# Equipment art

`equipment-atlas.png` was generated with the built-in ImageGen tool for the station shop and ship equipment UI. `StationUi.texture()` selects one of its four equal quadrants without modifying the source image.

| Quadrant | Use |
| --- | --- |
| Top left | Pulse laser |
| Top right | Shield generator |
| Bottom left | Ion engine |
| Bottom right | Temporary Pathfinder ship preview |

The preview is an inventory illustration, not a playable ship model. Replace its texture when final ship art is integrated.

`rocket-preview.svg` is an original vector illustration for the Refining Update tab's unavailable rocket category. It is presentation only; rocket combat and resource consumption remain disabled.

Final generation prompt:

```text
Use case: stylized-concept
Asset type: game equipment icon atlas for a native space game's inventory
Primary request: Create one square 1024x1024 image divided into four equal square quadrants, each with one separate centered object on an identical plain very dark navy background. Top-left: silver twin-barrel pulse laser module with amber glowing emitter tips. Top-right: compact cylindrical shield generator with cyan luminous coils. Bottom-left: compact ion engine thruster with blue exhaust and silver casing. Bottom-right: top-down placeholder scout spaceship, nose pointing up, silver angular hull, cyan engine lights, two swept wings. Style: polished readable science fiction 3D game item renders, consistent materials, high contrast silhouettes visible at tiny icon sizes. Composition: each object fully contained within its own 512x512 quadrant, generous 15 percent empty padding, no overlap between quadrants. No labels, no text, no borders, no watermark, no UI. Background uniform #091522.
```
