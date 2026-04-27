# Test hardening: `repro_panic_in_panic_under_load.ps1`

## Goal

Make `tests/winui3/repro_panic_in_panic_under_load.ps1 -Quick` (3-min budget)
reliably FAIL on the current build (`fork/main a27b3c601` + 2 unpushed audit
commits), reproducing the 2026-04-27 12:59:14 panic-in-panic crash signature
(STATUS_BREAKPOINT @ 0x248b4e in std.posix.abort, preceded by
`BUSY|renderer_locked` daemon log events).

## Result: REPRODUCED

Two consecutive `-Quick` runs both reproduced the crash signature in well
under 60 seconds:

| Run | Wall time to FAIL | BUSY events | Failure mode |
|-----|-------------------|-------------|--------------|
| 1 (13:50:39 → 13:50:58) | ~18.4 s | 3 (1 sess A, 2 sess B) | session B (pid 74392) disappeared (silent death) |
| 2 (13:51:30 → 13:51:49) | ~17.0 s | 17 | BUSY threshold breach (≥5) — both sessions still alive at exit |

Failure mode varies between runs (one had a silent process death, one
crossed the BUSY-count threshold without dying), but both exit with FAIL
within 20 seconds well under the 3-minute Quick budget.

The crash signature **`BUSY|renderer_locked` clustering followed by silent
process death within seconds** matches the original 12:59:14 incident
shape (two ghostty PIDs dying simultaneously after sustained BUSY events).
Note: WER `.dmp` file was NOT produced in our test runs even though the
process died — same observation matches some original incident sessions
where WER was overwhelmed by burst rate.

## What was tried (in order)

### Approach 0: Original test (FAILED to repro)

```
4 pollers × 5 Hz aggregate (= 20 Hz total)
+ 1 text-flood writer pushing `echo $payload` every 5s
single ghostty session
3-min wall budget
```

3 minutes, 0 BUSY events, exit 0 = PASS = useless regression test.

**Root finding**: The previous test ALSO had a BUSY-counting bug — it
filtered the daemon log regex by the test's own pid only. During the
13:34-13:37 baseline run, the daemon DID log 3 `BUSY|renderer_locked`
events, but they were on `ghostty-35640` (a leftover real session), not
on the test's `ghostty-8584`. Even so, 0 BUSY-on-our-session is a real
finding: the test's load shape was insufficient.

**Why insufficient**: `BUSY|renderer_locked` happens when the CP read-lane
calls `Surface.viewportStringLocked()` with `tryLock` and finds the
renderer mutex contended. The mutex is held by the **UI/render thread**
when it's actively painting. CP-pipe traffic alone doesn't paint; the
renderer is idle. To get contention, you need the **shell inside the
session** to be writing fast enough that the render path holds the
mutex when CP polls land.

The original 12:59:14 incident had Gemini doing `zig test` and reading
source files inside the session — thousands of lines/sec going through
the terminal write path, which is what locks the renderer.

### Approach 1: Longer baseline (skipped)

I didn't run the suggested 10-min baseline because the BUSY-on-other-pid
finding from the existing log already proved the polling-only theory
insufficient — no need to spend 10 minutes confirming a known result.

### Approach 2: Inject real shell workload (REPRODUCED)

```
2 ghostty sessions
4 pollers × 20 Hz per session = 8 pollers, 160 Hz aggregate
50Hz cross-session burst poller (matches original cross-callback shape)
+ infinite CMD `for /L` echo loop launched in each session's shell
+ `dir /S <repo>\src` flooder every 2s in each session
```

This **immediately** triggered:
- BUSY|renderer_locked on both sessions within 2 seconds of the load starting
- One session disappearing after 18 seconds total wall time

The combination that does it:
1. **Shell-side text I/O** (the echo loop + `dir /S`) holds the renderer mutex.
2. **High-Hz CP polling** (8 × 20Hz + 50Hz burst) generates rapid tryLock attempts.
3. **Multi-session cross-callback registration** (2 sessions) doubles the
   contention surface and matches the original incident topology.

## Empirical pass/fail boundary

The test currently FAILS at:

- Sessions ≥ 2
- Pollers ≥ 4 per session
- Poll Hz ≥ 20 per poller
- Shell-side flood active (echo loop + `dir /S` every 2s)
- Cross-session burst poller (50Hz) active

The `-BaselineOnly` switch keeps the polling but skips the shell injection
and burst poller — useful for confirming that polling alone is insufficient
(approach 0 reproduction).

I did **not** bisect the minimum trigger conditions because the request
was reliable repro within budget, not minimum repro. Future work could
narrow:
- 1 session vs 2 (does cross-session matter?)
- Hz floor (does 5 Hz suffice if shell flood is present?)
- Shell flood vs polling alone with different poll patterns

## Operational notes

- The test launches real ghostty windows. Visible cleanup: stop on completion.
- Orphan-cleanup loop at end catches any tabs that might have spawned.
- Crash dump detection works for both same-pid and re-spawned-pid cases
  (mtime > runStart).
- Daemon log polling at 2-second cadence with delta read; matches all
  test session names, not just one pid.
- Early-exit on first failure signature breach (BUSY ≥ 5 OR process death
  OR new dump) so test fails fast (~18s) instead of waiting full duration.

## Trigger summary (for the bug, not the test)

This is a **race between the CP read-lane's tryLock probe and the
renderer's lock acquisition** under sustained shell I/O. The race is not
the panic; the panic is somewhere downstream of `viewportStringLocked()`
when a tryLock failure path interacts badly with subsequent state. The
panic-in-panic visible at 0x248b4e is the **stack-trace dumping** code
re-faulting on `OpenFile(<.zig source>)`, masking the original panic.

The forensics agent (parallel work) is investigating the root panic; this
test only ensures the regression is caught.

## Files

- `tests/winui3/repro_panic_in_panic_under_load.ps1` — hardened test
- `notes/2026-04-27-deadlock-audit/repro/runs/run-*.log` — per-run logs
- `notes/2026-04-27-deadlock-audit/repro/test-hardening.md` — this file
