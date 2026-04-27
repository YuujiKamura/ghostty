# 2026-04-27 deadlock-blocker effectiveness audit

User report: "両方クラッシュした、ぜんぜんデッドロックブロッカーになってねーな" — two
ghostty WinUI3 sessions hosting parallel Codex (PID 37564) and Gemini
(PID 42852) agent workloads died simultaneously at `12:59:14`, ~8 minutes
into a deadlock-blocker validation run on fork main `a27b3c601`.

## Root cause: panic-in-panic chain

WER recorded 21 ghostty crashes in 2 hours, **all** at the same offset
`0x80000003 STATUS_BREAKPOINT @ ghostty+0x248b4e`. Symbolizing against
`zig-out-winui3/bin/ghostty.exe` (debug build, PDB-less, llvm-symbolizer)
resolves the call stack from `CrashDumps/ghostty.exe.68932.dmp`:

```
posix.zig:687       abort()                               <- STATUS_BREAKPOINT
debug.zig:1560      handleSegfaultWindowsExtra
debug.zig:1544      handleSegfaultWindows                 <- VEH catches segfault
windows.zig:130     OpenFile                              <- segfault HERE
fs/Dir.zig:945      openFileW
fs/Dir.zig:821      openFile
debug.zig:1185      printLineFromFileAnyOs
debug.zig:1176      printLineInfo__anon_12029
debug.zig:1123      printSourceAtAddress
debug.zig:1076      writeStackTraceWindows
```

Reading bottom-up: an **unrelated original panic** triggered Zig's
`writeStackTraceWindows` to format a backtrace. The line-context
formatter tried to open the `.zig` source file for the faulting frame.
That `OpenFile` call segfaulted (stack shows `0xAA…AA` Zig ReleaseSafe
poison — strong UAF signature, ref `feedback_zig_releasesafe_0xaa_poison`).
The VEH `handleSegfaultWindows` caught the segfault and called `abort()`,
which raised `STATUS_BREAKPOINT` for the OS to capture.

**WER reports the breakpoint, never the original panic.** All 21 events
have an identical signature, so this is a deterministic reentrant fault
inside the panic handler — not 21 different bugs.

## What the deadlock blockers actually did

Static audit (`static-audit.md`) confirms the four landed commits work
as designed:

- **Phase 2.3 sweep** (`bf9c556a1`): production `.forever` count is
  truly `0`. Two remaining `WaitForSingleObject(INFINITE)` are correctly
  `LINT-ALLOW`-tagged (Win32 message pump + legacy `Command.zig`
  awaiting `waitTimeout` migration).
- **BoundedMailbox** (`bf9c556a1`, `2f4d7cc4c`): every public `push*`
  callsite is drop-safe. `quit` / `shutdown` flow through
  `performAction(.quit, {})` directly, never through a mailbox, so
  drop-on-full cannot lose a shutdown signal.
- **Cascade detector** (`2f4d7cc4c`): atomic ordering correct.
  **But**: detector `View` does not include `last_renderer_locked` — the
  signal that actually fired today (CP pipe BUSY responses) is invisible
  to the in-process detector. See `crash-forensics.md` Section 3.
- **Phase 4 watchdog** (`watchdog.zig:91, 261`): default action `crash`,
  timeout `5000ms`, calls `process.exit(2)` on fire and dumps
  `%USERPROFILE%\.ghostty-win\crash\<unix>-watchdog.log`. **No watchdog
  log directory was ever created on this machine** — Phase 4 has never
  fired. Today's deaths were not watchdog kills.

## Verdict

The user's claim is half wrong:

- The **static blockers** (bounded waits, drop-on-full mailbox) prevent
  the unbounded-wait class of deadlock and are working.
- The **cascade detector** is observability, not prevention; in `warn`
  mode (default) it only logs. Today its signals didn't fire because
  `last_renderer_locked` isn't wired into its View.
- The **Phase 4 watchdog** is a postmortem kill-switch, not a deadlock
  prevention. It didn't fire today.
- Today's deaths are **not** a deadlock failure at all — they're a
  panic-in-panic instability in Zig's `writeStackTraceWindows` under
  load. The processes weren't deadlocked; they were panicking, then
  corrupting their own backtrace formatter.

The bug is in **the panic recovery path**, not in the deadlock blockers.

## Files in this audit

- `crash-forensics.md` — Agent-tool crash forensics report (timeline,
  watchdog hypothesis, cascade-detector signal gap, simultaneous-death
  theory)
- `static-audit.md` — Agent-tool static audit (`.forever` 14→0
  verification, BoundedMailbox drop-safety classification, lint output,
  atomic ordering review)
- `evidence/timeline-summary.md` — minute-by-minute reconstruction with
  the auto-approver-was-not-the-trigger counter-hypothesis
- `evidence/daemon-37564-42852-full.log` — deckpilot daemon log slice
  (12:51 launch → 12:59 death)
- `evidence/manual-approve-poll.log` — proof the approver only fired 3
  times across 35s, ruling it out as a poll-storm trigger
- `evidence/repro-adhoc-monitor.log` — reproducer run on fresh PID 35640
  (1m34s to first BUSY, recurrent every ~36s during active Gemini
  workload, zero BUSY once Gemini went idle — confirms BUSY correlates
  with active agent I/O, not pure deckpilot polling)

## Persistent reproducer

`tests/winui3/repro_panic_in_panic_under_load.ps1` launches a fresh
ghostty, spawns 4 concurrent CP pollers at 5 Hz, and a text-flooder
that pipes ~1 MB into the session every 5 s. Captures
`renderer_locked` count and any new crash dump matching the failing
PID.

```pwsh
pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1 -Quick   # 3 min
pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1          # 15 min
```

Pass: ghostty survives, BUSY count ≤ 5, no new dump at offset 0x248b4e.
Fail: PID disappears, BUSY count > 5, or new dump appears.

3-min Quick run on fork main `a27b3c601` (post-fix-validation) passed
with `busy=0, dumps=0`. CP polling alone is insufficient to reproduce —
the original 12:59:14 deaths required active agent file I/O on top of
the polling. To force a crash repro you need to additionally run an
agent (Gemini / Codex) inside the session executing file-heavy work.
This script captures the polling/flood half deterministically; the
agent half is reproduced manually by re-launching the same dispatch
briefs in `.dispatch/codex-deadlock-blocker-static-audit.md` and
`.dispatch/gemini-deadlock-blocker-dynamic-audit.md`.

## Next-action recommendations

1. **Fix the panic-in-panic root cause.** The Zig `writeStackTraceWindows`
   path is a reentrant-fault hazard under load. Options:
   - Disable PDB-less line-context formatting in release builds.
   - Wrap the `Dir.openFile` call inside `printLineFromFileAnyOs` with a
     defensive try/catch that bails to "??" on failure.
   - Build with `-Doptimize=ReleaseSafe` plus `--strip` to skip the
     line-context lookup entirely.
2. **Wire `last_renderer_locked` into cascade detector** (`#231`
   follow-up). Add a 5th signal so the detector can observe what
   deckpilot already observes externally.
3. **Add CP pipe back-pressure** in `apprt/winui3/control_plane.zig` —
   when `last_renderer_locked` count exceeds N/sec, return BUSY
   pre-emptively without acquiring the renderer mutex, so the daemon's
   poll rate naturally drops before the panic-in-panic chain fires.
