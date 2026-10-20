# Art storage with Git LFS

Install [Git LFS](https://git-lfs.com), then run these from the repository root
before editing art sources or running Blender/export/review tools:

```powershell
rtk proxy git lfs install
rtk proxy git lfs pull
```

Normal LFS-enabled clones download the current art automatically. Existing clones,
or clones made with smudging skipped, need `git lfs pull` after updating. A small
text file starting with `version https://git-lfs.github.com/spec/v1` is an LFS
pointer, not a usable model or image. Fetch its content before opening art tools.
Game-only clones can use `GIT_LFS_SKIP_SMUDGE=1` when cloning to avoid art downloads.

## Scope

`.gitattributes` tracks `*.blend` anywhere, and `.glb`, `.png`, `.jpg`, `.jpeg`
and `.exr` recursively under `art/`. Images use directory/type rules rather than
size thresholds so new large maps cannot silently enter regular Git. JPEG review
sheets are included for the same reason. There are currently no EXR/JPEG-extension
files; these rules cover future art. Text, scripts and manifests remain regular Git.

Keep runtime GLBs, textures and fonts in `assets/` and documentation images in
`docs/` in regular Git. Before moving any runtime dependency to LFS, update every
consuming CI checkout to fetch LFS and account for its download bandwidth.

`art/.gdignore` excludes the entire art tree from Godot import/export. The game
build/check entry points (`tools/dev.ps1`, `tools/server.sh`, `tools/check-game.py`
and `tools/deploy-server.sh`) do not invoke art authoring tools. Standalone Blender
builders/exporters and review renderers do read/write art and require full files.
The Linux packaging helper archives the source tree, but does not consume art
content; Godot ignores it. All Actions checkouts explicitly use `lfs: false`.

`tools/import-cache.py` enumerates only `assets/` and follows resource and glTF
dependencies from there. An audit of the current resolved inputs found 441 paths
and no `art/` dependencies. Grep of runtime scripts, scenes, project settings and
asset resources found no runtime art references. CI helper tests mention art paths
as fixtures for change classification; they do not read the real art files.

## Inventory and quota

Tracked blob sizes at baseline `cb8044b` (20 October 2026), decimal MB:

| Tree/type | Files | Total MB | Largest MB |
| --- | ---: | ---: | ---: |
| art: Blender | 25 | 557.952 | 56.685 |
| art: GLB | 9 | 488.884 | 56.637 |
| art: PNG | 209 | 742.510 | 21.146 |
| art: JPG | 54 | 18.121 | 1.092 |
| assets: GLB | 29 | 228.845 | 14.483 |
| assets: PNG | 90 | 124.200 | 4.321 |
| assets: fonts | 2 | 0.791 | 0.401 |
| docs: PNG | 147 | 80.913 | 2.277 |
| docs: JPG | 13 | 5.168 | 0.767 |
| docs: WebP | 11 | 10.750 | 2.395 |

All tracked files total 2,263.656 MB: art 1,810.018 MB, assets 354.084 MB,
docs 97.408 MB. The LFS patterns select 297 existing files totaling
1,807,466,699 bytes (1.683 GiB), before content deduplication. Runtime files remain
unchanged. The local Git pack was 2.46 GiB; LFS adoption does not shrink it.

The policy/documentation commit and current-file pointer conversion are separate.
The conversion uses `git add --renormalize` on explicitly selected paths; it does
not rewrite history. Dropping that conversion commit before pushing leaves old
blobs in the current tree until individually changed/re-added, while new additions
and edits follow the LFS rules. Older revisions always retain their regular blobs.

Pushing the conversion uploads roughly 1.683 GiB of unique content at most into
the owner's LFS storage. Full-art downloads consume bandwidth; each changed binary
version adds its full size to storage. Historical Git blobs also remain, so full
clones still download history plus LFS content. Dropping/reverting a conversion
after upload does not automatically recover the uploaded storage quota.

[GitHub's LFS billing documentation](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)
lists 10 GiB storage and 10 GiB download bandwidth for Free/Pro accounts, shared
across the account. Existing usage, budgets and available allowance must be checked
in the owner's billing settings. Both `gh api user` and `gh api users/Timerk`
returned no plan information with the available credentials; this is not evidence
of a free plan or unused quota. No history migration or force push is required.
