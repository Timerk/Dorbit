# Menu design references

These raster concepts were generated with the built-in ImageGen tool. They guide
future native Godot UI work; they are not runtime UI assets or playable screens.

## Review status

| Screen | Image | Status |
| --- | --- | --- |
| Main menu opening screen | [main-menu-approved.png](main-menu-approved.png) | User approved, including far-right outpost status and credits |
| Hangar | [hangar-approved.png](hangar-approved.png) | User approved |
| Quests | [quests-draft.png](quests-draft.png) | Draft awaiting review |
| Shop | [shop-draft.png](shop-draft.png) | Draft awaiting review |
| Cargo Trade | [cargo-trade-draft.png](cargo-trade-draft.png) | Draft awaiting review |
| Connection | [connection-draft.png](connection-draft.png) | Draft awaiting review |
| Settings / Controls | [settings-controls-draft.png](settings-controls-draft.png) | Draft awaiting review |
| Settings / Audio | [settings-audio-draft.png](settings-audio-draft.png) | Draft awaiting review |
| Settings / Graphics | [settings-graphics-draft.png](settings-graphics-draft.png) | Draft awaiting review |
| Skylab | [skylab-draft.png](skylab-draft.png) | Coming-soon placeholder draft |
| Galaxy Gates | [galaxy-gates-draft.png](galaxy-gates-draft.png) | Coming-soon placeholder draft |

## Shared direction

- Graphite surfaces, restrained amber accents, clear typography and generous spacing.
- Persistent left navigation and top bar; outpost status and credits at the far right.
- Keep text to useful labels, values, actions and contextual feedback. Start minimal and add only what is needed.
- No slogans, fictional clocks/dates, decorative numbering, duplicate outpost headings, schematic callouts or flight-preparation panel.
- Preserve existing functionality. Do not invent equipment types, configurations or progression systems.

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

## Other menu drafts

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
Connect while disabling launch and unavailable station actions. Authentication
continues through operator-provisioned credentials, not new login fields.

Skylab and Galaxy Gates contain only an icon and Coming soon. They add no gameplay.
These drafts cover the docked main-menu destinations; flight HUD, sector map and
in-flight pause overlays are outside this concept batch.

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

The other nine drafts used the approved hangar as their style reference. Quests,
Shop and Cargo Trade also used the existing screenshots as functional references.
Their exact built-in ImageGen prompts are saved as `<screen>-generation-prompt.txt`
beside each image.

Validation: visually checked the saved concepts for minimal copy, existing menu
functionality, right-aligned header and relevant values. Controls matches all
twelve current bindings; resource quantities/prices total 1,270 CR; the LF-1
purchase leaves 9,000 CR from 19,000 CR. Documentation and diff checks apply; no
gameplay code changed. The directory is excluded from Godot imports with `.gdignore`.
