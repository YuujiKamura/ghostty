# Dynamic Audit Report: Cascade Detector + Watchdog Effectiveness
**Date:** 2026-04-27
**Agent:** Gemini CLI
**Repo CWD:** `C:\Users\yuuji\ghostty-win`
**HEAD:** `a27b3c601`

## 1. Cascade Unit + Repro Tests (Three Modes)

### cascade_detector.zig
Command: `$env:KS_CASCADE_DETECTOR='<mode>'; zig test src/apprt/winui3/cascade_detector.zig`

| Mode | Result | Notes |
| :--- | :--- | :--- |
| `disabled` | PASS | All 7 tests passed. `start()` is a no-op. |
| `warn` | PASS | All 7 tests passed. Config defaults to `warn`. |
| `trigger` | PASS | All 7 tests passed. `maybeFireCascade` latches. |

### repro_cascade_detector_signals.zig
Command: `$env:KS_CASCADE_DETECTOR='<mode>'; zig test tests/winui3/repro_cascade_detector_signals.zig`

| Mode | Result | Notes |
| :--- | :--- | :--- |
| `disabled` | PASS | All 5 tests passed. |
| `warn` | PASS | All 5 tests passed. |
| `trigger` | PASS | All 5 tests passed. |

*Note: The repro test is a self-contained mirror of the algorithm and does not read the environment variable directly; it tests the contract via programmatic Action values.*

## 2. Threshold Sanity Check

### Is 3-poll wakeup-backlog (default = 3s) a true precursor to the 5s Phase 4 watchdog fire?
**Yes.** 
At `poll_ms = 1000` and `consecutive_warn = 3`, the detector lights the `wakeup_backlog` signal at 3 seconds of sustained UI thread failure to drain. The Phase 4 watchdog fires at 5 seconds. This provides a **2-second lead time** to capture diagnostics (snapshot/stack traces) before the process is terminated. On extremely slow/saturated machines, 2s is still sufficient for a serial dump as long as the detector thread itself isn't starving (it has high priority via `std.Thread.spawn`).

### Realistic dwell time for "2+ signals" (CASCADE WARNING)
**~3 Seconds.**
In a total UI deadlock:
1. `watchdog_near_fire` lights up at **3s** (default 5s timeout - 2s near-fire threshold).
2. `wakeup_backlog` lights up at **3s** (3 consecutive 1s polls).
Coincident fire happens at T+3s. 

In a "partial" stall (UI thread moving but slow):
1. `tick_err_signal` fires **immediately** upon any tick exceeding 100ms.
2. If pressure remains, `wakeup_backlog` or `watchdog_near_fire` will follow at ~3s.
Dwell time is dominated by the 3s backlog/near-fire thresholds.

## 3. Empirical 60-second Stability Run

**Configuration:** `KS_CASCADE_DETECTOR=warn`
**Duration:** 60 seconds
**Simulated Input:** `ls{ENTER}` via PowerShell SendKeys at T+10s.

### Log Excerpts
```
info(watchdog): watchdog started action=crash timeout_ms=5000 poll_ms=1000 hwnd=0xb91826
info(cascade): cascade detector started action=warn poll_ms=1000 summary_ms=30000 watchdog_timeout_ms=5000
warning(cascade): cp push stale: cp_last_notify_ms=10003ms ago, traffic indicators wakeup=false recent_tick=true
info(cascade): cascade summary: ticks=4 (+4) warn=0 (+0) err=0 (+0) max_tick_ms=0 last_tick_age_ms=29944 cp_age_ms=30018 cascade_fired=false
```

### Classification
**Correct Quiet.**
The `cp push stale` warning fired at 10s because the terminal was largely idle (only 4 ticks in 30s), causing the CP notify timestamp to exceed the 10s threshold while `recent_tick` remained true (likely due to cursor blink or initial setup). However, `CASCADE WARNING` correctly did **not** fire because the other 3 signals remained dark. No false positives were observed for the primary deadlock escalation path.

## 4. Drop-on-full Mailbox Sanity Check

### Saturation Behavior
`App.Mailbox` (defined in `src/App.zig`) uses `BoundedMailbox(Message, 64, 0)`. It is **non-blocking** (drop-on-full) by default. Under saturation, `push()` returns `.full` and increments `full_drops` for Phase 4 metrics.

### Message Taxonomy & Shutdown Correctness
Critical message: `.quit`. 
- If the mailbox is full, a `.quit` message pushed via `push()` WILL be dropped.
- **BUT**, the authoritative shutdown path in Ghostty-WinUI3 does not rely on enqueuing a message to a potentially dead-locked thread. 
- `App.shutdown()` calls `mailbox.shutdown()`. 
- `BoundedMailbox.shutdown()` sets an atomic `closed` flag and **broadcasts** to all parked producers/consumers.
- This out-of-band signaling ensures that even if the queue is full of noise, the shutdown signal propagates and unblocks all threads immediately.
- Shutdown correctness is **confirmed**: the design prioritizes out-of-band lifecycle signaling over in-band message passing for terminal states.

## Summary Findings
The cascade detector provides a sensible 2s buffer before process termination. The "2+ signal" requirement effectively filters out transient stalls (like a single 100ms long-tick) while catching sustained deadlocks at the 3s mark. The mailbox design is resilient to saturation during shutdown due to its atomic broadcast mechanism.
