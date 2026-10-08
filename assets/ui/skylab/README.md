# Skylab station artwork

`station.png` is an original production illustration derived from the user-approved
[station concept](../../../docs/menu-design/skylab-station-concept.png) with the
built-in ImageGen tool. [Exact prompt](../../../docs/menu-design/skylab-station-runtime-prompt.txt).

The illustration contains scenery only. Stock, levels, module labels, leader lines,
selection, controls and windows are live Godot UI. Normalized module anchors are
in `scripts/skylab_preview.gd`; labels are in `scripts/skylab_menu.gd`.
The static canvas requires no extra 3D viewport or continuous station rendering.

`robot-standard.png` and `robot-advanced.png` are original transparent robot renders
made with built-in ImageGen for the collector Productivity cards. Standard has
silver panels and blue sensors; Advanced has graphite armor and amber lighting.
Their [exact prompts](../../../docs/menu-design/skylab-robot-generation-prompts.txt)
are saved with the project. Artwork is displayed in its original colors.
