# Overview assets

`hangar-background.png` is an empty hangar backdrop generated with the built-in
ImageGen tool from `docs/menu-design/main-menu-approved.png`. It contains no
interface or foreground ship. Labels, icons, navigation, live specifications
and Start are native Godot controls in `scripts/main_menu.gd`.

The twelve files in `ships/` are unchanged copies of the original 1600 × 1440
transparent model renders from `art/ship-review/previews/`. Overview crops their
transparent margins at runtime and selects the synchronized active hull. The
smaller existing shop/fitting thumbnails stay in `assets/ui/ships/`.

The SVG icons are original project-native geometric drawings. Rajdhani Bold and
SemiBold are bundled unchanged in `assets/ui/fonts/`, with their SIL Open Font
License in `OFL.txt`. Source: [Google Fonts' Rajdhani directory](https://github.com/google/fonts/tree/main/ofl/rajdhani).

## Background generation prompt

Built-in ImageGen, with the approved Overview PNG as the edit target:

> Use case: precise-object-edit. Asset type: production background for a native game menu. Edit target: the attached approved Dorbit overview mockup. Extract/reconstruct ONLY its atmospheric hangar environment into a full bleed landscape 16:9 image, filling the entire frame with the hangar. Remove ALL interface elements, panels, sidebars, borders, buttons, all typography and icons. Remove the spacecraft completely; reconstruct empty hangar floor behind it. Preserve dark graphite metal floor with perspective grid, subtle amber runway lights and diagonal floor markings, distant industrial hangar walls, and the planet and orbital station visible through a large opening at upper right. Keep the lower middle floor empty to accommodate an independently rendered ship. Cinematic realistic game art, subdued blue-gray steel and warm amber. No text, no ships in foreground, no UI, no watermark. Match the reference environment, camera angle and restrained lighting closely.
