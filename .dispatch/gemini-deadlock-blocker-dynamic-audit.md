# Task — Dynamic audit: cascade detector + watchdog effectiveness

## Goal
Verify that the cascade detector (`#231`) and Phase 4 watchdog (`#232`) actually
fire under simulated stall conditions, and that their warning thresholds make
sense. Produce a reproducible report.

## Pre-state (already verified by hub)
- fork main HEAD: `a27b3c601`
- Cascade detector lives at `src/apprt/winui3/cascade_detector.zig`, repro test at
  `tests/winui3/repro_cascade_detector_signals.zig` (5/5 PASS reported by agent).
- Phase 4 watchdog lives at `src/apprt/winui3/watchdog.zig`, fires at 5s.
- Cascade default poll = 1000ms, summary = 30000ms, mode = `warn`.
- UIA suite 9/9 PASS on default config; 9/9 PASS with `KS_CASCADE_DETECTOR=disabled`
  per the cascade agent's report.
- Repo: `C:\Users\yuuji\ghostty-win`, branch: `fork/main`.

## What to do (dynamic audit; NO production code changes)
1. **Re-run the cascade unit + repro tests under three modes** and capture output:
   - `KS_CASCADE_DETECTOR=disabled zig test src/apprt/winui3/cascade_detector.zig`
   - `KS_CASCADE_DETECTOR=warn zig test src/apprt/winui3/cascade_detector.zig`
   - `KS_CASCADE_DETECTOR=trigger zig test src/apprt/winui3/cascade_detector.zig`
   - same three modes for `tests/winui3/repro_cascade_detector_signals.zig`.
   Done when each mode's pass/fail + log excerpts are in the report.
2. **Threshold sanity check.** Read the detector source and answer in the report:
   - Is 3-poll wakeup-backlog (default = 3s) a true precursor to the 5s Phase 4
     watchdog fire, or is the gap too narrow on slow machines?
   - When the cascade aggregator demands "2+ signals," what is the realistic
     dwell time before it logs `CASCADE WARNING`? Walk through the worst case.
3. **Empirical 60-second stability run with cascade in `warn` mode.**
   - Build: `./build-winui3.sh` (already done by hub; just verify exit 0).
   - Launch: `KS_CASCADE_DETECTOR=warn ./zig-out-winui3/bin/ghostty.exe` in a
     separate ghostty session (NOT from your own session — this is the SUT).
   - For 60 seconds, type into the terminal, resize, switch tabs (if applicable),
     then close cleanly via Stop-Process.
   - Grep the captured log for `CASCADE`, `watchdog`, `tick_err_count`, and
     report whether any false positives fired during normal use.
   Done when the log excerpt + classification (false-positive / correct-quiet) is
   in the report.
4. **Drop-on-full mailbox sanity check.** Read `src/datastruct/bounded_mailbox.zig`
   and confirm: under saturation, drop-on-full on `App.Mailbox` does NOT silently
   discard a `quit` / `shutdown` message. Document the message taxonomy and
   confirm shutdown correctness in writing.

## Deliverables (commit a single file)
- `notes/2026-04-27_deadlock_blocker_dynamic_audit.md` — sections per the 4 steps
  above, with command output excerpted inline.
- Single commit on a fresh branch `audit/gemini-deadlock-blocker-dynamic-2026-04-27`.
- DO NOT push; the hub will review and push.

## Constraints
- `cwd` = `C:\Users\yuuji\ghostty-win`. Use git worktree if you need isolation.
- No edits to `src/`, `tests/`, `xaml/`. New file under `notes/` only.
- Auto-approvals via deckpilot are running — don't fight them.
- Don't launch more than one ghostty SUT instance at a time (kill before re-launch).
- 60s of typing into a SUT counts as "manual"; if you cannot drive interactive
  input, simulate via PowerShell `SendKeys` (NOT mouse) and document the limitation.

## Out of scope (hard list)
- Modifying production `src/` code.
- Running upstream `origin` (Microsoft / ghostty-org) — fork-only.
- Any deckpilot session creation beyond your own (already created by hub).
- 1+ hour soak test (hub will run that manually, not your concern).

## Verification commands (you run these and paste output into the report)
```
git -C C:/Users/yuuji/ghostty-win log --oneline -3 a27b3c601
ls C:/Users/yuuji/ghostty-win/zig-out-winui3/bin/ghostty.exe
zig test C:/Users/yuuji/ghostty-win/src/apprt/winui3/cascade_detector.zig
zig test C:/Users/yuuji/ghostty-win/tests/winui3/repro_cascade_detector_signals.zig
```

Expected: report file exists with all 4 sections filled, command output inline.
