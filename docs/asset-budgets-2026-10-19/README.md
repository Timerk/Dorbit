# Texture compression and LOD review, 19 October 2026

Measured from `origin/main` at `0afcaa83791fe2fdad679cf2a6b46bbb05fe76b0`,
then with this PR's PNG import settings. The fixture and model files were identical
in both runs. Godot 4.7.2 (`ed1daf0bf`), native Windows, OpenGL Compatibility,
AMD Radeon(TM) Graphics (driver 25.5.1.250226), 1440 × 900, 4× MSAA, VSync off,
60 FPS cap, one isolated APPDATA profile. This is a local visual/memory review,
not a frame-rate or multiplayer capacity benchmark on the reference PC.

## Memory monitors

Values are MiB (bytes / 1,048,576), read from `Performance.RENDER_TEXTURE_MEM_USED`
and `Performance.RENDER_VIDEO_MEM_USED` in the same camera/fixture sequence.
The latter counts Godot's textures plus buffers, not total driver/device VRAM.

| Resident workload | Texture before | Texture after | Video before | Video after |
| --- | ---: | ---: | ---: | ---: |
| Frozen M1, station far camera | 523.36 | 295.33 | 636.85 | 408.83 |
| Controlled busy lineup, far LOD | 699.36 | 471.33 | 842.13 | 614.11 |
| Same lineup, all 79 PNGs explicitly resident | 847.81 | 507.74 | 990.59 | 650.52 |

The controlled busy scene saves **228.02 MiB / 32.6% texture memory** and
27.1% tracked video memory. Its buffer memory is unchanged at 142.78 MiB.
The station sample saves 43.6% texture memory. The all-PNG sample saves
340.07 MiB / 40.1% texture memory, but includes normally on-demand menu art;
do not describe that as ordinary flight residency.

The imported image payload inventory falls from 374.74 to 107.77 MiB (71.2%).
This is `Image.get_data_size()`, not the GPU monitor: lossless RGB images can
occupy different storage on the GPU, so the two totals are deliberately separate.
All 19 external 3D PNGs now use compressed DXT1 or RGTC_RG with mipmaps; all 60
UI PNGs remain lossless. Three external normal maps explicitly enable normal-map
compression. Embedded ship/alien atlases were already compressed with mipmaps
(on this adapter: BPTC_RGBA color/ORM and RGTC_RG normals) and were not reencoded.
Original PNGs and GLBs retain their source bytes.

## Compatibility LOD check

The controlled busy lineup contains three actual gate meshes, ten playable hulls
(five Liberators and five Goliaths) and five M2 aliens (three Skirmishers and two
Raiders). Simulation, HUD and sector scenery are disabled for these samples.
All 150 surfaces remain visible at both cameras. The gates-only control keeps
the same three gates and all 15 surfaces visible. Camera FOV is 60°; near/far
distances along Z are 400 / 2,000 m. Values below are the median of 30 frames;
min and max equal the median in every controlled sample, before and after.

| Visible geometry | Near, threshold 1 | Far, threshold 1 | Same far camera, threshold 0 |
| --- | ---: | ---: | ---: |
| Busy lineup | 422,454 | 150,400 | 1,461,484 |
| Three gates only | 186,018 | 96,336 | 522,984 |

`RENDER_TOTAL_PRIMITIVES_IN_FRAME` drops by 89.7% in the far busy scene and
81.6% for the far gates relative to forced full detail. Identical draw-surface
counts rule out frustum culling as the explanation. Automatic LODs therefore
**do take effect in this Compatibility build**. Keep them enabled; no replacement
or decimated artwork is introduced. The far gates still cost about 32k primitives
each, above the new authoring target, so the budgets remain useful for future art.

The base meshes have 174,328 triangles / five materials per gate, 36,556–98,228
triangles / 8–12 materials per playable hull, and 116,064 triangles / eight
materials for the station. New-asset targets are in [PERFORMANCE.md](../../PERFORMANCE.md#client-asset-budgets).

## Paired visual inspection

Left is before; right is after. These WebP sheets are lossless. Overview frames
are reduced to 720 × 450 for review; the detail sheets preserve native pixels.
Original 1440 × 900 PNG captures remain under `build/asset-review/{before,after}`.

- [Station and gate, near/far](station-gate.webp), [station native crops](station-native.webp), [gate native crops](gate-native.webp).
- [All twelve ships, near/far](ships.webp), [ship native crops](ships-native.webp).
- [M1 planet](planet-1.webp), [M2 planet](planet-2.webp), [M3 planet](planet-3.webp), [M4 planet](planet-4.webp), each near/far.
- [Quickslot bar at native resolution](quickslots-native.webp).
- [Busy lineup with near LOD, far LOD and far full detail](lod.webp).

Inspected armor edges, metallic highlights, recessed panels, normal-map lighting,
planet terrain/gradients, alpha edges and ammunition/rocket detail. No objectionable
block artifacts, broken normal lighting or visible loss of icon readability was
seen at these camera distances. Mipmaps smooth high-frequency station and distant
terrain detail. Ship texture content is unchanged. The animated gate vortex and
other shader TIME effects differ between captures; frozen HUD layout can settle
differently after loading. These images do not prove temporal shimmer is eliminated
or cover every graphics scale, close-up angle or target GPU. User art acceptance
and representative hardware playtesting remain applicable.

## Reproduction and raw evidence

Run `tools/asset_review.gd` as described in [PERFORMANCE.md](../../PERFORMANCE.md#client-asset-budgets).
Capture baseline first, change the imports, run a headless editor import, then
capture again with the same profile. An all-PNG residency pass holds strong
references to every image to prevent on-demand loading from changing the comparison.

[before.json](before.json) and [after.json](after.json) contain byte-valued monitors,
camera positions, primitive ranges, PNG dimensions/formats/mipmap flags and model
texture/geometry inventories. The full scene/HUD samples are for memory and visual
inspection; use the controlled lineup to assess LODs.

## Initial correctness validation

Ran the complete Windows suite with
`rtk proxy python tools/check-game.py .tools/godot/Godot_v4.7.2-stable_win64_console.exe --suite windows --workers 2`.
It completed 57 test commands in 432.72 seconds: 55 passed initially;
`hunting_contracts_test` and `equipment_test` exited early without an assertion
report. Both passed isolated fresh-profile/port reruns (62 and 160 assertions,
respectively). The initial exit cause was not established. The new import-budget
suite passed all 357 checks. [validation.json](validation.json) preserves the
first-run and retry summary instead of hiding the transient failures.

Headless editor reimport, fixture parse checks, local document links, unchanged
source PNG/GLB verification and `git diff --check` also passed. Native rendered
captures and monitor samples completed successfully before and after. The Linux
correctness suite, export builds and representative multiplayer GPU performance
were not run for this client-asset change.

## CI follow-up

The [initial CI run](https://github.com/Timerk/Dorbit/actions/runs/39238183654)
passed the Windows source suite and the checked Linux server package. Windows
export validation failed because `menu_assets_test.gd` still required 1024px item
images. It now requires the budgeted 512 × 512 size, lossless pixel data, mipmaps,
nonempty artwork and transparent padding for resource, rocket and collector-robot
images. Full-page Skylab artwork retains its larger requirement.

The report directory now has `.gdignore`, and the packaged menu test verifies
that it is absent from the client pack. This keeps the review screenshots out of
runtime imports and exports. No runtime textures or gameplay changed in this fix.

`rtk proxy powershell -NoProfile -File tools/dev.ps1 build` passed locally after
the fix, including source/export protocol matching, packaged ships, station,
aliens, menus, offline launch/return, HUD shortcuts and notices. The final export
log contains no report-directory resources. Updated CI results belong to the PR;
the original memory and screenshot measurements above remain unchanged.
