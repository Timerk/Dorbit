# Customizable quickslots

The flight bar has ten mixed slots, bound to `1–0` by default. Its `+` button opens
Lasers, Rockets, Hellstorm and Extras. Click a picker item to use it directly.
Ammo items select ammo; rocket firing and Hellstorm load/fire are separate actions.
Space still toggles laser fire, and F/G retain the dedicated rocket commands.

Opening `+` also enables customization, without opening the HUD editor or stopping
flight and firing. Drag a picker item into a slot, or drag between slots to swap.
The pointer carries the complete tile, including its picture, count/status, title,
shortcut and background at the displayed scale. Clicking a slot then an item is
an alternative; assignment clears the selection so picker clicks resume normal
use. **Clear slot** removes the selected assignment. **Reset slots** restores the
defaults without changing orientation or placement. **Done**, **Close** or `+`
closes customization. Press Ctrl + Alt separately to edit HUD placement: dragging
the bar moves it as one instrument, with local flight input stopped as before.

Settings > Controls rebinds each slot using the existing conflict-swap behavior.
Keys belong to positions. The displayed key follows rebinding, and items can be
assigned multiple times. Hidden bars retain their keyboard shortcuts during flight.
Empty slots and unavailable actions do nothing. Menus, death and disconnection
block activation.

`user://quickslots.cfg` stores ten stable action IDs and orientation. The existing
`ammo` entry in `user://hud-layout.cfg` stores position, scale and visibility.
Resetting HUD layout does not clear assignments. Existing numeric flight bindings
are preserved on migration: the conflicting new slot receives the flight action's
former default binding. No server-save or protocol migration is added.

## Extras integration

The extras owner calls `sector.hud.ammo_bar.register_extra(id, state, command)`.
Use a stable lowercase ID such as `repair-cpu`. The state callable returns a
Dictionary with `name`, optional `icon` (Texture2D), `count` (String), `active`
(bool), `available` (bool), `color` (Color) and `tooltip` (String). Refresh state
from confirmed gameplay data. The command must invoke the extra's existing
server-validated request; the bar never applies equipment effects itself.

Call `unregister_extra(id)` when the action owner goes away. Saved `extra:<id>`
assignments remain disabled until registered again. Unavailable equipment should
return `available: false` and a helpful tooltip. Passive equipment needs no slot.
The Extras tab is empty until the separate extras feature registers usable actions.

## Validation

`tests/quickslots_test.gd` exercises actual GUI drag-and-drop, click assignment,
complete drag previews, direct `+` customization without pausing, key dispatch/rebinding,
HUD placement isolation, extras registration/removal, independent
resets, saved configuration, legacy binding migration and layout at 960×600,
1440×900 and 1920×1080. Run rendered to produce `build/validation/quickslots-*.png`.
The existing ammo/rocket network tests continue to exercise the same commands
through the default quickslots.

Reviewed native captures: [flight bar](feedback/quickslots-flight-1920.png),
[960-pixel picker](feedback/quickslots-editor-960.png),
[vertical picker](feedback/quickslots-vertical-1440.png), and
[complete drag preview](feedback/quickslots-drag-1440.png).
