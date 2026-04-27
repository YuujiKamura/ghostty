# 2026-04-27 deadlock-blocker effectiveness audit

User report: 「両方クラッシュした、ぜんぜんデッドロックブロッカーになってねーな」
— two ghostty WinUI3 sessions hosting parallel Codex (PID 37564) and Gemini
(PID 42852) agent workloads died simultaneously at `12:59:14`, ~8 minutes
into a deadlock-blocker validation run on fork main `a27b3c601`.

**This README is the synthesis after team re-audit. Earlier draft was
rejected on 4 of 5 root-cause claims; see `forensics-reaudit.md` for
the rejection.**

## What we actually know

### About the 12:59:14 deaths
- Both ghostty.exe processes disappeared at the same second.
- **No WER APPCRASH event in the Application log between 12:50:00 and
  13:05:00.** No new minidump in `%LOCALAPPDATA%\CrashDumps\` after 12:37.
  No watchdog crash log directory at `%USERPROFILE%\.ghostty-win\crash\`
  (path does not exist on this machine — see "Open question 1" below).
- daemon log shows a `BUSY|renderer_locked` cluster on 42852 starting at
  `12:52:38` and recurring every ~30 s while Gemini was active. Once
  Gemini went idle the BUSY events stopped.
- Process exit was **silent** — no error event logged anywhere on the
  system. This pattern is consistent with `process.exit(2)` (Phase 4
  watchdog) or external `TerminateProcess`, NOT with a STATUS_BREAKPOINT
  panic that WER would catch.

### About the 12:37:43 crash dump
- WER recorded **21 ghostty crashes between 11:29 and 12:37:43**, all at
  fault offset `0x248b4e` = `std.posix.abort` (`STATUS_BREAKPOINT`).
- The latest dump `CrashDumps/ghostty.exe.68932.dmp` shows a stack chain
  ending in `handleSegfaultWindows` (Zig's VEH for ACCESS_VIOLATION),
  i.e. **a real segfault — but** the deeper frames are not recoverable
  from this minidump (rsp walk fails after 8 frames; mid-stack frames
  are heap pointers and `0xAA` poison bytes).
- This dump is **NOT from the 12:59:14 deaths.** It's from a different,
  earlier short-lived crash (uptime 28 s, 22 minutes before the user's
  event). Earlier draft conflated them.

### About the deadlock blockers themselves
The static-audit + Gemini cascade-detector audit + reproducer all agree:

- **Phase 2.3 sweep** (`bf9c556a1`): production `.forever` count is `0`.
  Two remaining `WaitForSingleObject(INFINITE)` are correctly
  `LINT-ALLOW`-tagged.
- **BoundedMailbox** (`bf9c556a1`, `2f4d7cc4c`): every public `push*`
  callsite is drop-safe. `quit` flows out-of-band via
  `BoundedMailbox.shutdown()` atomic broadcast, not through a `push()`
  that could be dropped.
- **Cascade detector** (`2f4d7cc4c`): atomic ordering correct; 7+5
  unit/repro tests pass in all three modes (`disabled`, `warn`,
  `trigger`). **But the View has no `last_renderer_locked` signal**, so
  the actual signal that fired today (CP-side BUSY) was invisible to
  the in-process detector.
- **Phase 4 watchdog** (`watchdog.zig:91, 261`): default action `crash`,
  timeout `5000ms`, calls `process.exit(2)` and writes a snapshot to
  `%USERPROFILE%\.ghostty-win\crash\<unix>-watchdog.log`. **No watchdog
  log directory has ever been created on this machine.** Either the
  watchdog has never fired in `crash` mode, or the snapshot directory
  creation is silently failing.

### About reproducibility
The reproducer at `tests/winui3/repro_panic_in_panic_under_load.ps1`
**reliably triggers the failure shape in 18 seconds** when run with the
hardened defaults (`-Sessions 2`, multi-session SHELL flooders +
80 Hz/session pollers). 2/2 consecutive `-Quick` runs FAIL within
budget. Trigger summary:

> Pure CP-pipe traffic doesn't load the renderer mutex. **Shell-side
> text I/O inside the session** (`for /L echo` loop + `dir /S`
> flooder) holds `Surface.renderer_state.mutex` long enough that
> high-Hz `deckpilot show` calls into `viewportStringLocked()` with
> `tryLock` start failing with BUSY. Multi-session (2+) doubles the
> cross-callback contention surface. The original 12:59:14 incident
> matched this exact shape.

See `repro/test-hardening.md` for the empirical pass/fail boundary.

## Verdict

The user's claim 「ブロッカーになっていない」 is **half-right with a
twist**:

- The static prevention layer (bounded waits, drop-on-full mailbox,
  out-of-band shutdown) is correct and is preventing the
  unbounded-wait class of deadlock.
- The detection layer (cascade detector + Phase 4 watchdog) is **not
  observing the contention that actually fires under load**:
  `last_renderer_locked` is not a cascade signal, and the Phase 4
  snapshot path may be broken (directory never created).
- The **failure mode is not deadlock at all.** It's renderer-mutex
  contention that produces BUSY responses externally, eventually
  followed by a silent process death whose root cause we still cannot
  identify because:
  1. WER did not capture it (no APPCRASH event).
  2. The watchdog's snapshot path may have failed silently.
  3. The earlier crash dump (12:37) we initially leaned on is from a
     different incident and doesn't apply.

The reproducer fires the **first half** of the chain (BUSY clustering
+ session disappearance under load) deterministically. The **second
half** (what specifically kills the process — VEH abort vs.
`process.exit(2)` vs. external) remains open.

## Open questions for follow-up issues

1. **Why doesn't `%USERPROFILE%\.ghostty-win\crash\` exist?** Is Phase 4
   watchdog snapshot writing failing silently, or has it genuinely
   never fired in `crash` mode? Add a smoke test that forces a fake
   wedge under `KS_WATCHDOG_TIMEOUT_MS=1000` and checks the snapshot
   appears.

2. **Why was there no WER APPCRASH event for the 12:59:14 deaths?**
   `process.exit(2)` exits with code 2 silently — no WER. So either
   Phase 4 fired and we just have no log, or something else killed the
   process. Capture exit code reliably in the reproducer.

3. **Wire `last_renderer_locked` into the cascade detector View** as a
   5th signal. The CP layer already tracks it; the detector just
   doesn't poll it.

4. **Add CP-side back-pressure** in `apprt/winui3/control_plane.zig` —
   when `last_renderer_locked` exceeds N/sec, return BUSY pre-emptively
   without acquiring the renderer mutex, so the daemon's poll rate
   naturally drops before the failure cascade fires.

5. **Investigate the 21-crash burst at 11:29–12:37.** All at offset
   `0x248b4e` is too deterministic to ignore. Capture stderr/stdout of
   one of those processes (build-winui3 with `set KS_WATCHDOG=disabled`
   so panic prints to console), reproduce, get the *original* panic
   message. Open issue.

## Files

- `README.md` (this file) — corrected synthesis post re-audit.
- `forensics-reaudit.md` — independent re-audit that rejected the
  earlier draft.
- `crash-forensics.md` — earlier (now-superseded) forensics report.
  Kept for history; some claims rejected.
- `static-audit.md` — static blocker audit (claims still valid).
- `evidence/` — daemon log slice, manual-approve poll log, ad-hoc
  reproducer logs, timeline summary.
- `repro/` — ad-hoc reproducer + test-hardening notes.
- `tests/winui3/repro_panic_in_panic_under_load.ps1` — hardened
  regression reproducer (2/2 FAIL on current build).
- `.dispatch/codex-deadlock-blocker-static-audit.md`,
  `.dispatch/gemini-deadlock-blocker-dynamic-audit.md` — original
  briefs the codex/gemini sessions worked from before they died.

## Status

Local fork main is 2 commits ahead of remote `a27b3c601`:

- `3eedf4e2d` — Gemini's auto-committed dynamic audit notes
- `d76ad9386` — first audit pass (this README before correction +
  evidence + repro test)

Not yet pushed. Will be amended/replaced after issues are filed.
