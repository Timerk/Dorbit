# Menu design references

These raster concepts were generated with the built-in ImageGen tool. They guide
future native Godot UI work; they are not runtime UI assets or playable screens.

## Review status

| Screen | Image | Status |
| --- | --- | --- |
| Main menu opening screen | [main-menu-approved.png](main-menu-approved.png) | User approved, including far-right outpost status and credits |
| Hangar | [hangar-draft.png](hangar-draft.png) | Draft awaiting user review |

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

## Generation provenance

The main-menu image is the selected tactical-amber concept, simplified according
to the user's red-circle annotations, then edited to align the outpost and wallet
at the right edge. Its final edit prompt is in [main-menu-final-edit-prompt.txt](main-menu-final-edit-prompt.txt).

The hangar used the approved main menu as its visual reference and
[the existing hangar screenshot](../feedback/main-menu-hangar.png) as its functional
reference. The initial draft had one extra generator slot. A targeted edit removed
it; the saved draft shows the correct six. Exact prompts are in
[hangar-generation-prompt.txt](hangar-generation-prompt.txt) and
[hangar-correction-prompt.txt](hangar-correction-prompt.txt).

Validation: visually checked both saved images, the right-aligned header, minimal
copy and hangar slot counts. Documentation and diff checks apply; no gameplay
code changed. The directory is excluded from Godot imports with `.gdignore`.
