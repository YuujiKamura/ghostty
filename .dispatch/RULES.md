# .dispatch/RULES.md — common rules every brief inherits

This file is the single source of truth for dispatch-time conventions. Each `.dispatch/*-brief.md` should reference it as `Follow .dispatch/RULES.md baseline rules` rather than restating these.

## Project rules (already in `CLAUDE.md`, `AGENTS.md`, `docs/apprt-contract.md`)

These are project rules. Read those files for full context. The brief-time conventions below are **layered on top**.

- Build: `./build-winui3.sh` for WinUI3, `zig build -Dapp-runtime=win32 --prefix zig-out-win32` for Win32. Never bare `zig build`.
- Push: only to `fork` (`YuujiKamura/ghostty`). Never to `origin` (= upstream `ghostty-org/ghostty`).
- Apprt contract: fork-driven changes belong in `src/apprt/winui3/` (or `src/apprt/win32/`). Don't modify upstream-shared core. See `docs/apprt-contract.md` for wrapper patterns and the audit backlog at `notes/2026-04-27_fork_isolation_audit.md`.
- Hardcoded paths forbidden: no drive letters, no user-profile paths in code.

## Brief-time conventions (recurring, layer this on top)

### Git
- **Explicit `git add <path>` always.** Never `git add .` / `git add -A`. Other sister sessions may have dirty files in the same working directory.
- **Commit gate bypass**: pre-commit lefthook has a known pre-existing vtable-manifest failure that is NOT yours. Use `LEFTHOOK=0 git commit -m "..."`. The Claude harness blocks `--no-verify`, so stick with `LEFTHOOK=0`.
- **Push gate bypass**: `LEFTHOOK=0 git push fork HEAD:main`.
- **Push race**: if you get non-fast-forward, sister session beat you. Resolve: `git fetch fork && git rebase fork/main && LEFTHOOK=0 git push fork HEAD:main`. Do NOT push-force.

### Tests
- Run: `ZIG_GLOBAL_CACHE_DIR= zig build test --summary all` (the empty env var dodges a Zig 0.15.2 abs-path bug).
- Filter: `ZIG_GLOBAL_CACHE_DIR= zig build test -Dtest-filter="<your_helper>" --summary all`.
- **Baseline**: 2745+ tests pass / 3 pre-existing `renderer.Overlay highlight*` failures. **Don't fix the 3 pre-existing.** Don't regress the rest.

### GUI changes
- **`test PASS` is not `ship-ready`** for any GUI behavior. After a GUI change, build and visually verify.
- SendKeys / SendInput must target a **fresh shell** in the test ghostty, not a window where Claude Code or other PTY child is consuming keys. See `feedback_test_keys_against_fresh_window`.

### Behavior
- **Single objective.** Do not expand scope. Do not refactor unrelated code while you're in the file.
- **Act fully autonomously.** Do not ask the hub for permission, do not pause for confirmation. Smallest patch that satisfies the brief.
- **Stop early on dead-end signals**: if your premise is invalidated by evidence (e.g. the bug doesn't exist, the fix shape is much bigger than the brief), reply `BLOCKED: <one-sentence>` and stop. The hub will decide.
- **No new `*.md`, README, planning, or scratch files** outside `.dispatch/`. Reply on stdout only.

### File scope
- Each brief specifies which files you may edit. **Do not edit anything else** even if the change "feels related". Sister sessions own other files; cross-overs cause merge pain.
- The dirty files visible in `git status` may belong to sister sessions. Don't `git add` them.

## Output contract (every brief expects this)

Every brief expects a final stdout block in the form:

```
HELPER_TARGETS / FILES_MOVED / etc: <what you delivered>
TESTS_ADDED: <N or "0 — no testable surface">
COMMIT_HASH: <hash>
PUSHED_TO_FORK: yes|no
ISSUE_<N>_CLOSED: yes|no  (if the brief targets a specific issue)
```

If blocked: `BLOCKED: <one-sentence>` and stop.

---

## Index of brief types (when to use which)

- **Helper extract + tests** (e.g. `team-tier2-K-pipeline.md`, `team-tier2-N-shouldRingBell.md`): pull pure mutation out of templated/coupled context, add table-driven tests. See skill `helper-extract-for-templated`.
- **Audit pass** (read-only): produce a punch list, no edits. See skill `audit-then-parallel-team`.
- **Issue resolve**: implement the issue spec, close with merge-attribution comment.
- **Apprt-contract cleanup**: relocate file out of upstream-shared core to `apprt/winui3/`, update callers (import path only, no logic change). See `docs/apprt-contract.md` and `notes/2026-04-27_fork_isolation_audit.md` for the backlog.

## When to escalate to hub

- Premise invalid (the bug doesn't exist as framed, or fix shape is 10x what the brief assumes).
- File scope conflict with sister session (their work breaks yours).
- Pre-existing failure not in the documented baseline.
- Build broken before your edits (rebase + retry, then escalate if persistent).
