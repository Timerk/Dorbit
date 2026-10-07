# Approved UI design references

The menus and [flight HUD](../hud-design/README.md) share one approved visual
direction. Use these rules for future UI work. The generated images illustrate
layouts, not playable screens or current game data; [GAME_PLAN.md](../../GAME_PLAN.md)
and the implementation define ownership, prices and configured controls.

## Shared direction

- Graphite `#0c1217` surfaces, slate `#34434b` borders, amber `#ff880b` accents,
  muted `#93a5b5` labels and Rajdhani typography. Preserve semantic status colors.
- Keep short functional labels, necessary values, actions and contextual feedback.
  Omit slogans, clocks, decorative numbering, repeated headings and permanent
  preparation instructions.
- Menus use persistent left navigation and a top bar with credits and a small
  wallet icon at the far right. Omit the outpost/docked label and green status dot.
- Start appears only on the preflight Overview. Flight browsing uses Resume flight.
- Ship specifications appear only on Overview and Hangar. Hangar's strip spans
  the content width; every other page keeps only its relevant product, cargo or
  quest information.
- The flight HUD leaves the central view open, without the menu sidebar,
  full-width header or Start action. See its [layout and feedback requirements](../hud-design/README.md).
- Preserve existing functionality and accessible alternatives to dragging.
  Do not introduce equipment, settings or progression systems through mockups.

The original menu images retain an illustrative outpost header. The written
header and launch rules above take precedence over older images and prompts.

## Approved screens

| Screen | Reference |
| --- | --- |
| Overview | [main-menu-approved.png](main-menu-approved.png) |
| Hangar | [hangar-approved.png](hangar-approved.png) |
| Quests | [quests-approved.png](quests-approved.png) |
| Shop | [shop-approved.png](shop-approved.png) |
| Cargo Trade | [cargo-trade-approved.png](cargo-trade-approved.png) |
| Connection | [connection-approved.png](connection-approved.png) |
| Controls | [settings-controls-approved.png](settings-controls-approved.png) |
| Audio | [settings-audio-approved.png](settings-audio-approved.png) |
| Graphics | [settings-graphics-approved.png](settings-graphics-approved.png) |
| Skylab | [skylab-approved.png](skylab-approved.png) |
| Galaxy Gates | [galaxy-gates-approved.png](galaxy-gates-approved.png) |
| Flight HUD | [flight-hud-top-aligned.png](../hud-design/flight-hud-top-aligned.png) |

## Page requirements

- Hangar combines owned-ship selection, preview, real fitting slots and storage.
  Show current/proposed fitting values, activation and contextual removal.
  Fitting is immediate, without Save/Apply. Concept inventory is illustrative.
- Quests keeps existing offers, objectives, rewards, active progress and
  Accept/Abandon. Preview artwork does not replace gameplay models.
- Shop keeps categories, catalog selection, product stats, ownership, pricing
  and purchase validation. Cargo Trade keeps seven resource cards, quantities,
  per-resource Sell and Sell all. Example prices are not economy configuration.
- Controls, Audio and Graphics use one consistent settings container. Changes
  apply immediately; binding guidance and save failures appear contextually.
- Connection retains editable disconnected endpoints, locked connected fields,
  session status and Connect/Disconnect. Authentication uses operator credentials.
- Skylab and Galaxy Gates contain an icon and Coming soon, without new gameplay.

## Generation provenance

Built-in ImageGen produced the selected tactical-amber Overview and its
[final edit](main-menu-final-edit-prompt.txt). Hangar used that style and
[the existing fitting screen](../feedback/main-menu-hangar.png), with
[generation](hangar-generation-prompt.txt) and
[slot-correction](hangar-correction-prompt.txt) prompts.

The remaining concepts used Hangar as the style reference. Each exact
`<screen>-generation-prompt.txt` is saved beside its image. The
[Hangar footer edit](hangar-footer-edit-prompt.txt) and
[other-menu footer edit](other-menus-footer-edit-prompt.txt) supersede the original
shared-footer instructions, restricting Start to Overview and specifications to
Overview/Hangar. Final images preserve the approved page actions.

Reference directories are excluded from Godot imports with `.gdignore`.
