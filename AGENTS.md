# Development workflow

Read [GAME_PLAN.md](GAME_PLAN.md) before implementing gameplay, choosing architecture, or changing scope. It records agreed requirements and identifies settings that still need playtesting.

## Branches, commits, and pull requests

- Start each distinct task on a short-lived branch based on current `origin/main` by default. When work depends on an unmerged PR, branching from that PR's feature branch is allowed. Use descriptive names such as `feat/ship-flight`, `fix/target-selection`, or `docs/game-plan`.
- Keep `main` for merged work. Target pull requests at `main` by default. Use stacked PRs when dependencies make them useful: target the dependent PR at its prerequisite's feature branch so its diff shows only the new work, and state the dependency and intended merge order in the PR description. After the prerequisite merges, retarget the dependent PR to `main` and update its branch as needed to keep the diff focused.
- Group changes into focused commits that each serve one purpose. Use descriptive messages such as `feat: add ship movement` or `fix: clear destroyed targets`.
- Stage relevant files explicitly and inspect the staged diff before committing. Preserve unrelated local work.
- Push completed task branches and open or update a pull request. Describe the resulting behavior, relevant validation, and any remaining limitations. Use a draft PR when required work is incomplete.
- Leave merging to the user unless they request it. Include the branch and PR link in the handoff.

## Implementation and validation

- Keep changes within the current milestone. Update the game plan when the user agrees to a design change.
- Prefer changes to existing files and simple implementations. Use type information where the language supports it.
- Run checks appropriate to the change. For gameplay or visual changes, run the game and inspect the affected interaction when tools permit. Report checks that could not be completed.
- Add focused tests for meaningful behavior. Documentation-only changes need document and diff checks, not gameplay tests.
- Prefix shell commands with `rtk`. Use `rtk proxy <command>` when unfiltered output is needed.
