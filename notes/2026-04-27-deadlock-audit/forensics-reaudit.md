# Forensics Re-audit — independent review of the panic-in-panic claim

Scope: validate or refute `README.md` root-cause claim that the 12:59:14
deaths of PIDs 37564 + 42852 were caused by a Zig `writeStackTraceWindows`
panic-in-panic chain. Read-only against `src/`. All offsets use the
worktree binary referenced by the dump
(`.claude/worktrees/agent-a1a0b111b3bbd1f21/zig-out-winui3/bin/ghostty.exe`,
PE preferred base `0x140000000`, Timestamp `Mon Apr 27 12:36:59 2026`).

## 1. The dump is not evidence for 12:59:14

`ghostty.exe.68932.dmp` was written at **`Mon Apr 27 12:37:43 2026`**
(cdb `Debug session time`) with `Process Uptime: 0 days 0:00:28.000`. PID
68932 is **not** 37564 or 42852, and its lifetime ended 22 minutes
before the user-reported event. The dump is from a short-lived crash
during the *audit warmup*, not from the simultaneous-death window.

WER tells the same story:

```
Application log, ghostty.exe APPCRASH events:
  12:30:01, 12:31:23, 12:37:06, 12:37:24, 12:37:43  ← last
```

There is **no APPCRASH, no Application Error 1000, no WER bucket** in
the Application log between 12:50:00 and 13:05:00 (PowerShell
`Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime='12:50';
EndTime='13:05'}` returns zero ghostty rows). The System log in the
12:55–13:05 window contains only an unrelated DaemonUpdateAssistantService
event at 13:00:07. No watchdog snapshot dir exists at
`%USERPROFILE%\.ghostty-win\crash\` (path not present).

So the draft's headline "WER recorded 21 ghostty crashes in 2 hours,
**all** at the same offset `0x248b4e`" silently extrapolates the 12:37
dump signature onto the 12:59:14 deaths. **It is not the same event.**

## 2. The "13-frame chain" is partly real, partly stack scraping

cdb `.ecxr; kn 200` against the dump produces only 8 frames before the
walker fails:

```
00 ghostty+0x248b4e         abort                        rip
01 0x00000092e65fd2f0       (data ptr)
02 0x01007ff61ff28e4f       (corrupt return addr, top byte 01)
03 ghostty+0x373bd30        (not in .text — heap pointer)
04 0xaaaaaaaaaaaaaaaa       0xAA poison
05 0x00000092e65fd2f0
06 0x00000092e65fd260
07 ghostty+0x4d1fe4
08 (end)
```

The "13 frames" the draft prints is reconstructed from raw `dps @rsp`
values, symbolized in isolation. Symbolizing each address against the
PDB at preferred VA `0x140000000`:

| ghostty offset | symbol                     | source           |
|---------------:|----------------------------|------------------|
| `0x248b4e`     | `abort`                    | posix.zig:687    |
| `0x269945`     | `OpenFile`                 | windows.zig:130  |
| `0x24e6e4`     | `openFileW`                | Dir.zig:945      |
| `0x232324`     | `printLineFromFileAnyOs`   | debug.zig:1185   |
| `0x23dfe1`     | `printLineInfo__anon_…`    | debug.zig:1176   |
| `0x23f72e`     | `printSourceAtAddress`     | debug.zig:1123   |
| `0x2479f0`     | `writeStackTraceWindows`   | debug.zig:1076   |
| `0x247df3`     | `handleSegfaultWindows`    | debug.zig:1544   |
| `0x46b99a`     | `handleSegfaultWindowsExtra` | debug.zig:1560 |
| `0x4d1fe4`     | `handleSegfaultWindowsExtra` (alt) | debug.zig:1560 |
| `0x373bd30`    | not in `.text`             | (data/heap)      |
| `0x322d420`    | not in `.text`             | (data/heap)      |

So the draft's chain is real for the panic-handler half. But none of
the addresses on the captured stack point into `apprt/winui3/*`,
`Surface.zig`, `renderer/*`, or any application code. The draft's
hypothesis that there is an "unrelated original panic" is consistent
with the evidence, but **the original panic is not identifiable from
this dump** — its frames live above `0x92e65fd400`, outside the captured
mini-dump range. The draft does not name the original panic, and this
audit cannot either.

Critical correction to the draft's narrative: the entry point is
`handleSegfaultWindows` (debug.zig:1544), which only handles
`ACCESS_VIOLATION`, `DATATYPE_MISALIGNMENT`, `ILLEGAL_INSTRUCTION`,
`STACK_OVERFLOW` (debug.zig:1530-1543). It is **not** the path Zig
takes for `@panic("...")` calls, which go through `defaultPanic` not
the VEH. So the original event was a **segfault**, not a panic. The
draft's phrase "an unrelated original panic" mis-frames the trigger.

## 3. The "original panic" question

Searching the captured dump pages for `panic`/`segfault`/`unreachable`
strings (`s -a 0x00000092e65f0000 L?20000`) returns **zero matches**.
The panic-message buffer is not in this dump's captured pages. The
original failure is therefore **named by category only**: the VEH
entry condition limits it to ACCESS_VIOLATION (most likely),
ILLEGAL_INSTRUCTION, DATATYPE_MISALIGNMENT, or STACK_OVERFLOW. Given
`Process Uptime: 28s` and the appearance of `0xAA` poison bytes mid-stack,
ACCESS_VIOLATION dereferencing uninitialized memory is the simplest fit.

## 4. 0xAA interpretation

`feedback_zig_releasesafe_0xaa_poison` calls `0xAA` a UAF signature.
That is wrong for this build. Per the daemon log search and per Zig
0.15.2 std semantics: in **Debug** and **ReleaseSafe**, Zig fills *all*
freshly allocated stack slots with `0xAA` as the **undefined-value
sentinel** (`std.mem.undefined_byte_pattern`). It marks "uninitialized"
just as much as it marks "freed-then-used". Without an additional
allocator that explicitly poisons on free, `0xAA` does not distinguish
UAF from uninit. The draft's "strong UAF signature" claim is unjustified.
On Debug builds it is most often **stack-frame init pattern** —
literally, "this stack slot was allocated but never assigned before the
walker tried to read it." That can absolutely happen if `printLineInfo`
walks past the `DebugInfo` cache miss into a code path that did not run
to its assignment, which is consistent with the symptom but does not
require a use-after-free.

## 5. "Did the deadlock blockers prevent anything?"

The draft's claim that the static blockers *worked* and only the
"panic recovery path" failed has two cracks.

(a) Phase 4 watchdog never fired: directory `.ghostty-win/crash/` does
not exist, and `process.exit(2)` would not produce a WER entry
either way. So Phase 4's silence is **uninformative** — it is
consistent with "watchdog never armed", "watchdog armed but
threshold never crossed", "process died before watchdog tick".
Cannot be used to claim the blockers worked.

(b) The `last_renderer_locked` BUSY signal climbed monotonically on
PID 42852 (lines 57, 495, 506, 573, 611, 652, 753 in
`evidence/daemon-37564-42852-full.log`: 8 BUSY events in 6m22s,
seven on 42852). The CP-pipe server **was** returning BUSY rather
than blocking, which is what the BoundedMailbox/CP backpressure
work was supposed to deliver. So *that* layer demonstrably did its
job. But neither watchdog nor cascade detector fired (no snapshot
file, no escalation log line in the daemon log surrounding 12:59).
The conservative reading is "the bounded-wait code worked; the
mid-tier observation/throttle was not present and is what's missing."
The draft's phrasing — "blockers worked, deaths are unrelated" —
is the same statement minus the qualifier.

## 6. Counter-hypotheses

| # | Hypothesis | Score | Evidence |
|---|---|---|---|
| H1 | Panic-in-panic in `writeStackTraceWindows` (draft) | **Possible**, not proven | Dump is from 12:37, not 12:59. The chain *exists* in the 12:37 dump, but extrapolation to 12:59 is inferential |
| H2 | WinUI 3 / Windows App SDK runtime DLL fault | **Possible** | Both processes loaded identical, separately-mapped WinAppSDK DLLs (dir listing of `agent-a1a0b111b3bbd1f21/zig-out-winui3/bin`). Could explain coincident timing if a shared DLL path (e.g. `Microsoft.ui.xaml.dll` global state) is involved. Not ruled out |
| H3 | TerminateProcess from external (deckpilot, OS, user) | **Ruled out** for deckpilot — daemon log shows no TERMINATE/SIGNAL command between 12:55 and 12:59:13. **Possible** for user (Task Manager kill of both windows). **Ruled out** for OS LowMemoryKiller — no System log resource event |
| H4 | Phase 4 watchdog (`process.exit(2)`) | **Possible** | Would produce no WER, no Event Log row, no crash dump — exactly matches observed silence. Snapshot file absent, but draft's own forensics admits the snapshot path is best-effort and can fail under page-allocator pressure |
| H5 | Resource exhaustion (handle leak, named-pipe limit, working set) | **Possible**, low | No System log warnings; named pipes are per-PID-keyed so two unrelated PIDs hitting the same limit simultaneously is unlikely |
| H6 | Original panic in app code → real panic-in-panic at 12:59 | **Possible** | The 12:37 dump shows the chain *can* fire. If the root original panic is some app-thread invariant (e.g. unwrap on a stale Surface ptr after CP-pipe race), 12:59 may be the same recipe under a different agent payload |

## 7. Verdict

**The draft is partially valid as a description of the 12:37 dump and
unsubstantiated as a description of the 12:59:14 deaths.** Specifically:

- The panic-in-panic chain is *real* in PID 68932 at 12:37:43 — symbol
  resolution against the worktree PDB confirms each frame the draft
  lists down to `OpenFile`. The `0xAA` interpretation is wrong (uninit,
  not UAF) but the chain itself is genuine.
- The leap from "dump A at 12:37 shows X" to "12:59 deaths were X" is
  unjustified. The 12:59 PIDs **left no dump, no Event Log entry, no
  snapshot file**. This signature pattern (silent exit, no WER) is
  more consistent with **`process.exit(2)` from Phase 4 watchdog**
  (H4) or **clean termination** (H3 user kill) than with a
  STATUS_BREAKPOINT crash that would have produced a WER report like
  the 12:37 one did.
- The likeliest single root cause for 12:59:14, given the evidence
  available, is **H4: Phase 4 watchdog firing**. To confirm, the user
  must check whether the watchdog actually creates the
  `%USERPROFILE%\.ghostty-win\crash\` directory on first arm
  (`watchdog.zig:46, 287-318`); if `createFile` is the first time the
  parent dir is needed and the open fails, no snapshot lands and the
  process still exits silently — exactly the observed pattern.

**Recommended next step (out of scope for this audit):** instrument
`watchdog.zig` `writeSnapshot` with `std.fs.cwd().makePath("%USERPROFILE%/.ghostty-win/crash")`
and a `stderr` print on entry, then re-run the validation workload to
distinguish H1 (chain at 12:59) from H4 (watchdog kill).
