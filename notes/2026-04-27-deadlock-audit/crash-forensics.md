# Crash Forensics — 2026-04-27 12:59:14 simultaneous death of PIDs 37564 + 42852

Verdict on the user's claim "deadlock blockers failed": **partially correct** but the framing is wrong. The blockers landed today are *postmortem* mechanisms (snapshot + exit, observability), not *prevention*. Real prevention surface is small and external pressure (CP pipe BUSY) is invisible to it.

## 1. Timeline (from `daemon-log-evidence.txt`)

| Time     | Event | Line |
|----------|-------|------|
| 12:51:02 | session 37564 launch, hwnd=1906944 | L13–14 |
| 12:51:04 | session 42852 launch, hwnd=727832 | L15–16 |
| 12:51:35 | callback wiring 37564→42852 | L17–18 |
| 12:51:45 | 37564 first transient pipe error ("No process on the other end") | L20–21 |
| 12:52:05 | 37564 second transient pipe error, recovers | L22–23 |
| 12:52:38 | **42852 first `server: BUSY|renderer_locked`** | L27 |
| 12:54:34 | 37564 first `server: BUSY|renderer_locked` | L29 |
| 12:57:10 | 42852 BUSY|renderer_locked (#2) | L33 |
| 12:57:16 | 42852 BUSY|renderer_locked (#3) | L35 |
| 12:57:56 | 42852 BUSY|renderer_locked (#4) | L41 |
| 12:58:07 | 42852 BUSY|renderer_locked (#5) | L44 |
| 12:58:22 | 42852 BUSY|renderer_locked (#6) | L46 |
| 12:58:58 | 42852 BUSY|renderer_locked (#7), 16s before death | L48 |
| 12:59:13 | **both pipes vanish simultaneously** (dial: file not found) | L50–51 |
| 12:59:14 | both marked dead. 37564 uptime=8m12s, 42852 uptime=8m10s | L55–61 |

Pre-death pattern: 7 BUSY|renderer_locked on 42852 in 6m22s, 1 on 37564. **42852 was the primary stress carrier**; 37564 died alongside it without escalating BUSY rate. lastPollOK on both = 12:59:12 — pipes disappeared in the same 1–2s window.

## 2. Did Phase 4 watchdog fire?

Watchdog config: default `action=.crash`, `timeout_ms=5000`, `poll_ms=1000` (`watchdog.zig:71-104`). On fire it calls `writeSnapshot` then `std.process.exit(2)` (`watchdog.zig:250-262`).

`std.process.exit(2)` does **not** trigger Windows Error Reporting / WER crash dumps (it is `ExitProcess(2)`). The user's `%LOCALAPPDATA%\CrashDumps` being empty after 12:37 is **consistent with watchdog-initiated exit**. A snapshot file would land at `%USERPROFILE%\.ghostty-win\crash\<unix>-watchdog.log` (`watchdog.zig:46, 287-318`) — the user should check this directory before treating watchdog as silent.

Critical gap: writeSnapshot uses an `ArenaAllocator` of `page_allocator` plus `std.fs.cwd().createFile` (`watchdog.zig:288, 305`). If the *loader lock* is the wedge cause, page allocation could itself block. The dump-then-exit path is best-effort.

## 3. Did cascade detector fire?

Cascade detector watches **only apprt-internal signals** (`cascade_detector.zig:17-29, 174-187`):
1. `wakeup_pending` consecutive count
2. `cp_last_notify_ms` staleness
3. `last_ui_heartbeat_ns` near-fire (3s of stall)
4. `tick_err_count` delta (>100ms ticks)

It **does not observe `last_renderer_locked` nor pipe-server BUSY responses** — `control_plane.zig:128, 307` flips `last_renderer_locked` then drops the bit after returning the wire string; the cascade View has no pointer to it. The seven daemon-side `BUSY|renderer_locked` errors are an **external observation invisible to the in-process detector**. **This is a gap.** The detector would only fire if mailbox/heartbeat staleness *also* manifested. Snapshot files (`watchdog.zig:46`) and `cascade summary` log lines (`cascade_detector.zig:387-396`) would tell us — but the detector only escalates under `KS_CASCADE_DETECTOR=trigger`; default is `.warn` (`cascade_detector.zig:76`). On a default install, cascade fires **logs only**, no callback.

## 4. Why simultaneous death of two independent PIDs?

Each ghostty.exe owns its own watchdog thread, its own pipe (`control_plane.zig:218-222`: `\\.\pipe\ghostty-winui3-{session}-{pid}`), and its own App. There is no shared singleton in `App.zig` — `surfaces_mutex`, `cached_config`, `phase4_watchdog` are per-App.

Most likely explanation, ranked:

1. **Independent watchdogs both fired in the same 5s window on correlated load.** 42852 was already CP-locked 6+ times. 37564's renderer was sharing nothing in-process with 42852 but both were under deckpilot poll storm + idle-callback cross-traffic (L24, 31, 38: `caller=37564 target=42852` and vice versa amplifying each session's UI work). Coincident wedge → coincident `process.exit(2)`. The 1s precision of "both pipes gone at 12:59:13" is consistent with two independent 5s timeouts triggered by the same poll burst at ~12:59:08.
2. **WinUI3 / Windows App SDK runtime DLL fault** — possible but no shared loader DLL crash signature; both processes have separate DLL copies in their unpackaged manifest.
3. **Parent/child cascade** — rejected: pipes are independent; daemon log shows no IPC client disconnect *before* L50.

Note that `Command.zig:389` (`#221` minimize footprint) only affects child processes — not relevant to the parent ghostty.exe death.

## 5. Verdict — is anything *preventing* deadlocks?

Distinguish:
- **Real prevention (drop-on-full / bounded wait):** `BoundedMailbox` removed `.forever` (`bounded_mailbox.zig:4-35, 209-210, 679-709`). CP backpressure returns `ERR|BUSY|input_queue_full` / `data_lane_full` / `renderer_locked` instead of blocking (`control_plane.zig:271, 286, 309`). These are doing real work — daemon got 7 BUSY responses instead of an unrecoverable wedge for 6 minutes.
- **Postmortem (kill-switch):** Phase 4 watchdog is by its own docstring "the **last resort**" / "stuck > crash" (`cascade_detector.zig:6-8`, `watchdog.zig:1-9`). Cascade detector is **observability** by default (`cascade_detector.zig:76` action=.warn).

So: the prevention layer **did its job** (kept the process responding to CP polls with structured BUSY for 8 minutes). The postmortem layer **did its job** (process exited cleanly, no WER hang for the user). What's missing is a **mid-tier**: CP pipe-server BUSY rate is not fed back into either the cascade aggregator or any throttle. The user's 5h sessions die at 8m because BUSY|renderer_locked is observed only externally.

The user's claim is misframed: the blockers worked *as designed*. The design is incomplete.

## 6. Next-action recommendations

1. **Wire `last_renderer_locked` into cascade detector as Signal #5.** Add `cp_renderer_locked_count: *std.atomic.Value(u64)` to `View` in `cascade_detector.zig:174-187`; bump from `control_plane.zig:307`; rate threshold (e.g. >3/min) lights signal. *Rationale:* the only signal that fired today was invisible to the detector. **File:** `src/apprt/winui3/cascade_detector.zig` (View + tick) and `src/apprt/winui3/control_plane.zig:307`.

2. **Default `KS_CASCADE_DETECTOR=trigger` for production launches.** Currently `.warn` is default (`cascade_detector.zig:76, 109`); under `.warn` the detector only logs — no preemptive snapshot. For 5h-sessions the snapshot is what diagnoses *why* the watchdog had to fire. *Rationale:* postmortem evidence is the bottleneck, not detection cost. **File:** launcher / build-winui3.sh wrapper, plus `cascade_detector.zig:76` default flip.

3. **Add a CP-BUSY adaptive throttle: when `last_renderer_locked` rate >N/min, the pipe handler should sleep() before responding** (or return a synthetic 429-equivalent to make deckpilot back off its poll cadence). The current code (`control_plane.zig:300-310`) flips a flag and immediately returns; deckpilot keeps polling at full rate, which is exactly what kept 42852 in the BUSY loop for 6 minutes. *Rationale:* turn an observation into a control loop. **File:** `src/apprt/winui3/control_plane.zig` `handleRequestWith` + a new rate counter on `ControlPlane`.
