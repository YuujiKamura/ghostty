# Task — Static audit: deadlock blocker effectiveness on fork main

## Goal
Independently verify that the recently landed Phase 2.3 sweep + minimize-footprint
refactors actually closed the unbounded-wait class of deadlock risks. Produce a
machine-checkable report.

## Pre-state (already verified by hub)
- fork main HEAD: `a27b3c601`
- Phase 2.3 agent claimed: production `.forever` callsites went 14 → 0
- Phase 4 watchdog (`src/apprt/winui3/watchdog.zig`) lands UI-thread hang detection
- Cascade detector (`src/apprt/winui3/cascade_detector.zig`) lands precursor signals
- All hooks PASS (build-check, deadlock-lint, fork-isolation, uia-smoke, zig-fmt-check)
- Repo: `C:\Users\yuuji\ghostty-win`, branch: `fork/main`

## What to do (read-only audit, NO code changes)
1. **Verify the .forever 14→0 claim.**  Grep production `src/` (excluding `tests/`,
   `vendor/`, `.zig-cache/`) for: `\.forever`, `WaitForSingleObject\(.*INFINITE\)`,
   `BlockingQueue.*\.pop\(.forever\)`, `pushTimeout.*\.forever`. Cross-reference with
   the migration table in commit `bf9c556a1` body. Done when every remaining hit
   has a written justification (in-comment or in the report).
2. **Audit BoundedMailbox push semantics.** Read `src/datastruct/bounded_mailbox.zig`
   (the type added by Phase 2.1 / 2.2). Confirm: drop-on-full default does NOT silently
   discard messages required for shutdown correctness (e.g. quit signals). Done when
   every public `push*` callsite has been classified as `drop_safe` / `drop_unsafe`
   with reasoning.
3. **Cross-check apprt isolation.** Run `bash tools/lint-fork-isolation.sh` and report
   any new violations introduced by the 4 landed commits. Done when output is
   captured + diffed against the pre-Phase-2.3 baseline.
4. **Cascade detector signal completeness.** Read `cascade_detector.zig`. Confirm the
   4 chain breakers (mailbox/drain pressure, wakeup backlog, CP push staleness,
   cascade aggregator) have correct atomic ordering for cross-thread reads (check
   `.acquire` / `.release` on `std.atomic.Value`). Done when every atomic op is
   listed with its ordering and a one-line rationale.

## Deliverables (commit a single file)
- `notes/2026-04-27_deadlock_blocker_static_audit.md` — sections per the 4 audit
  steps above, each with grep evidence / line refs / verdict.
- Single commit on a fresh branch `audit/codex-deadlock-blocker-2026-04-27`.
- DO NOT push; the hub will review and push.

## Constraints
- `cwd` = `C:\Users\yuuji\ghostty-win`. Use git worktree if you need isolation.
- Read-only against `src/`. New file only under `notes/`.
- No upstream interaction (no `origin` push, no PR, no issue).
- This is an *audit*, not a fix. If you find a real bug, document it in the
  report — do not patch it.

## Out of scope (hard list)
- Modifying `src/`, `tests/`, `xaml/`.
- Running the UIA suite (already 9/9, hub re-verifies).
- Stress-testing or launching ghostty.
- Anything related to `src/apprt/embedded.zig` (cross-apprt contamination —
  hub explicitly accepted as revert candidate at next upstream merge).

## Verification commands (you run these and paste output into the report)
```
git -C C:/Users/yuuji/ghostty-win log --oneline a27b3c601 -10
git -C C:/Users/yuuji/ghostty-win grep -n '\.forever' -- src/ | grep -v test
bash C:/Users/yuuji/ghostty-win/tools/lint-fork-isolation.sh
bash C:/Users/yuuji/ghostty-win/tools/lint-deadlock.sh
```

Expected: report file exists with all 4 sections filled, evidence inline.
