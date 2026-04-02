# Non-Negotiables

These rules are mandatory for `ghostty-win` WinUI3 work.

## Acceptance

- Do not declare WinUI3 work complete unless `pwsh -File .\scripts\winui3-contract-check.ps1 -Build` passes.
- For cross-repo or generator-facing changes, also require `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`.
- For ScrollBar/layout work, use `pwsh -File .\scripts\winui3-scrollbar-smoke.ps1 -NoBuild` as supporting evidence, not UIA alone.

## Parallel Work

- One file, one writer.
- `src/apprt/winui3/com.zig`, `com_native.zig`, and generated COM files must have a single owner during a task.
- If generator and consumer both need changes, serialize or use separate worktrees.

## Test Integrity

- Do not replace build-backed checks with TODO/`exit 0`.
- Do not keep stale verification steps in docs after the underlying script is removed.
- Do not treat chat memory as the primary source of WinUI3 operational truth; promote durable findings into docs/tests/issues.

## Hygiene

- Screenshots, temp scripts, `.bak`, and debug dumps are untracked by default and must not be mixed into functional commits unless explicitly requested.
- GitHub issue and PR operations must target forks, not upstream repos.
