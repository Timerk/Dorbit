# Approved UI design references

These raster concepts were generated with the built-in ImageGen tool. They guide
future native Godot UI work; they are not runtime UI assets or playable screens.

The menu and [flight HUD references](../hud-design/README.md) form one approved
graphite-and-amber visual direction. Use the shared rules below when adding new
menus. Native menu and HUD implementation remain separate feature PRs:
[PR 42](https://github.com/Timerk/Dorbit/pull/42) and
[PR 48](https://github.com/Timerk/Dorbit/pull/48).
Example values and controls can predate later gameplay changes; use GAME_PLAN.md
and the implementation for current prices, ownership and configured bindings.

## Review status

| Screen | Image | Status |
| --- | --- | --- |
| Main menu opening screen | [main-menu-approved.png](main-menu-approved.png) | User approved; header simplified during implementation review |
| Hangar | [hangar-approved.png](hangar-approved.png) | User approved |
| Quests | [quests-approved.png](quests-approved.png) | Accepted with footer revision |
| Shop | [shop-approved.png](shop-approved.png) | Accepted with footer revision |
| Cargo Trade | [cargo-trade-approved.png](cargo-trade-approved.png) | Accepted with footer revision |
| Connection | [connection-approved.png](connection-approved.png) | Accepted with footer revision |
| Settings / Controls | [settings-controls-approved.png](settings-controls-approved.png) | Accepted with footer revision |
| Settings / Audio | [settings-audio-approved.png](settings-audio-approved.png) | Accepted with footer revision |
| Settings / Graphics | [settings-graphics-approved.png](settings-graphics-approved.png) | Accepted with footer revision |
| Skylab | [skylab-approved.png](skylab-approved.png) | Coming-soon concept accepted with footer revision |
| Galaxy Gates | [galaxy-gates-approved.png](galaxy-gates-approved.png) | Coming-soon concept accepted with footer revision |
| Flight HUD | [flight-hud-top-aligned.png](../hud-design/flight-hud-top-aligned.png) | User approved, including header removal and shared top margin |

## Shared direction

- Graphite surfaces, restrained amber accents, clear typography and generous spacing.
- Use graphite `#0c1217` surfaces, slate `#34434b` borders, amber `#ff880b` accents and muted `#93a5b5` labels with Rajdhani typography. Preserve semantic shield, health and danger colors.
- Menus retain left navigation and a top bar with right-aligned credits and a small wallet icon. The outpost/docked label and green status dot were removed during implementation review.
- Start appears only on the preflight Overview. Ship specifications appear only on Overview and Hangar.
- The flight HUD uses the same colors and typography with an open central view, no menu sidebar, no full-width header and no Start action.
- Keep text to useful labels, values, actions and contextual feedback. Start minimal and add only what is needed.
- No slogans, fictional clocks/dates, decorative numbering, duplicate outpost headings, schematic callouts or flight-preparation panel.
- Preserve existing functionality. Do not invent equipment types, configurations or progression systems.

| Page | Ship-specifications strip | Start |
| --- | --- | --- |
| Overview | Visible | Visible before launch |
| Hangar | Visible, spanning the content width | Hidden |
| Every other page | Hidden | Hidden |

Launch requires returning to Overview. Cargo Trade keeps its own cargo usage/value
summary; Shop keeps product stats and pricing; Quests keeps objectives and rewards.
After launch, menu browsing uses the same style with Resume flight in place of
launch access. The earlier concept images retain their original illustrative
header; the current header and launch rules above take precedence.

## Hangar intent

Ship selection and preview sit beside equipment and storage inventory. The Liberator
has four laser slots, six shared shield/engine slots and two reserved extra slots.
The draft shows one installed LF-1, one SG3N-A01 and one original Ion engine.
Two stored LF-1s and one stored SG3N-A01 illustrate the inventory layout; this is
not a change to starter ownership. A selected installed item has a contextual
Remove action. Fitting remains immediate; no Save or Apply action is added.

Keep current and proposed fitting values, ship activation, accessible click/select
alternatives to dragging and blocked-action reasons available in implementation
when relevant. These static images show one state, not every interaction.

## Other menu concepts

Quests shows the existing Scout, Sentinel and Heavy offers, their objectives and
rewards, and a selected Scout offer with Accept. Active runs use the same layout
with progress and Abandon when appropriate. The concept ships are illustrative
previews, not replacements for the current alien models.

Shop shows the Weapons category and an LF-1 purchase. The other categories use
the same catalog/detail layout. LF-4 remains unavailable. Cargo Trade retains
the seven ore cards and per-resource quantities/Sell actions, plus Sell all.
Its example of ten units of each resource totals 70 / 400 cargo and 1,270 CR.

Settings covers all current Controls, Audio and Graphics options without adding
settings or Save/Apply actions. Binding-edit guidance and save failures can appear
contextually in implementation. The three images illustrate tab content, not
final panel sizing; implement one consistent tab container across all three.

Connection shows an already-connected client with locked address/port fields.
The example hostname is fictional. Connect is unavailable while connected;
Disconnect is available. A disconnected state must expose editable fields and
Connect while disabling unavailable station actions and Overview's launch. Authentication
continues through operator-provisioned credentials, not new login fields.

Skylab and Galaxy Gates contain only an icon and Coming soon. They add no gameplay.
The [flight HUD notes](../hud-design/README.md) extend this approved style to the
flight overlays, preserving radar, navigation, ship/target status and contextual
feedback. Sector map and in-flight pause overlays are outside this raster batch.

## Generation provenance

The main-menu image is the selected tactical-amber concept, simplified according
to the user's red-circle annotations, then edited to align the outpost and wallet
at the right edge. Its final edit prompt is in [main-menu-final-edit-prompt.txt](main-menu-final-edit-prompt.txt).

The hangar used the approved main menu as its visual reference and
[the existing hangar screenshot](../feedback/main-menu-hangar.png) as its functional
reference. The initial draft had one extra generator slot. A targeted edit removed
it; the approved image shows the correct six. Exact prompts are in
[hangar-generation-prompt.txt](hangar-generation-prompt.txt) and
[hangar-correction-prompt.txt](hangar-correction-prompt.txt).

The other nine concepts used the approved hangar as their style reference. Quests,
Shop and Cargo Trade also used the existing screenshots as functional references.
Their exact built-in ImageGen prompts are saved as `<screen>-generation-prompt.txt`
beside each image.

The user accepted those concepts with one shared revision: Start belongs only to
Overview, and the ship-specifications strip belongs only to Overview and Hangar.
The current images reflect that rule. The hangar strip expands into the former
Start-button space; other pages restore quiet hangar background in place of both
footer components. Exact built-in ImageGen edits are saved in
[hangar-footer-edit-prompt.txt](hangar-footer-edit-prompt.txt) and
[other-menus-footer-edit-prompt.txt](other-menus-footer-edit-prompt.txt).
Original generation prompts describe the earlier shared footer for provenance;
the visibility table and final edit prompts supersede that earlier instruction.

Validation: visually checked the saved concepts for minimal copy, existing menu
functionality, right-aligned header and relevant values. At the original concept
review, Controls matched the twelve bindings pictured; resource quantities/prices total 1,270 CR; the LF-1
purchase leaves 9,000 CR from 19,000 CR. Documentation and diff checks apply; no
gameplay code changed. The directory is excluded from Godot imports with `.gdignore`.
The revised images were also checked for footer visibility, preserved page actions
and Hangar's unchanged four laser, six generator and two extra slots.
