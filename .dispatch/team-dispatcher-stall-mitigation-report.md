# Team Dispatcher-Stall-Mitigation — Report (WIP)

Branch: `p1-task-214-dispatcher-stall-mitigation` (off `e4d99ae8b`, pushed to `fork`)
Discipline: `hypothesis-log-reproduce-verify` (8 steps, hsylife/Zenn). No fix before repro + root cause pin-down.
Scope separation: **runtime Dispatcher queue stall under Claude thinking burst**, NOT the spawn-time CP pipe init race (Team CP-Race-Fix, separate worker).

---

## Step 1 — Symptom (frozen in one sentence)

> ghostty-winui3 session (HEAD `e4d99ae8b`, `optimize=ReleaseFast`) で Claude CLI に xhigh-effort の長文 reasoning を流している間、Win32 message pump は生きたまま (window drag / resize が応答する) だが、XAML `DispatcherQueue` 経由で流れる `drainMailbox` / CP-pipe 応答 / XAML text update がまとまって秒〜数十秒遅延し、`deckpilot send <sess> ping` が `text_not_visible|phase1_timeout` を返す、または 1 秒以内に戻るべき応答が 5s を超える。

Expected: `deckpilot send` round-trip p95 < 500ms during any load.
Actual (2026-04-20 23:40, main-thread observation): p95 >> 500ms during multi-minute Claude reasoning bursts; `drainMailbox` logs gap open even while `WM_NCHITTEST` keeps firing for mouse drag.

---

## Step 2 — Hypotheses (≥3, each with a distinct observable)

Numbered so repro/log analysis can cite **H1 supported / H2 refuted** etc. without ambiguity.

### H1 — Wakeup flood without coalescing

Claim: PTY byte stream from a thinking Claude causes `core_app` → `rt_app.wakeup()` to fire at 100s-1000s Hz. Each call issues `DispatcherQueue.TryEnqueue(&WakeupHandler)` (App.zig:1572–1581), which **never coalesces** — the MSAL `DispatcherQueue` happily stacks N identical handler instances. Every drained callback then runs `drainMailbox → core_app.tick`, which in the vast majority of cases finds the mailbox already empty (work drained by the first callback) but still pays pump + mutex + log cost. Under sustained burst the Dispatcher queue backlog grows O(byte_rate), starving the 100 ms `HEARTBEAT_TIMER_ID` and any CP-pipe-thread → UI-thread `PostMessageW(WM_APP_CONTROL_ACTION)` from interleaving.

Observable predictions (to look for in diagnostic log):
- `wakeup_calls/sec` ≥ 200 during burst (idle baseline < 5/sec).
- `drainMailbox` tick count per second ≈ `wakeup_calls/sec` (no coalescing).
- `drainMailbox: tick done` pairs appear in bursts; median *useful* tick work per call → near zero (empty mailbox).
- `hb_age_ms` (Tier 1 heartbeat age) drifts > 100 ms well before `UI_STALL_THRESHOLD_NS` (3 s) — so `ui_stall detected` may not fire, but `deckpilot send` still times out.

Refutation: `wakeup_calls/sec` stays flat or `drainMailbox` count << wakeup count (coalescing actually happens), or useful tick work is non-trivial on every call.

### H2 — `core_app.tick` slice blowout

Claim: Even with the P1 #1 slice bound (`tick_slice_warn_ns = 4 ms`, App.zig:2313), under storm a single tick drains hundreds of `performAction` messages (title change, cursor, dirty flush, etc.). The bound only *warns* + re-posts `WM_USER` — it does **not** abort the tick. So a long tick keeps running, and the re-posted `WM_USER` guarantees another full tick follows without yielding. The yield is cosmetic because the next message in the pump is the same `WM_USER` we just posted.

Observable predictions:
- `"ui tick long_ms=X"` log line fires frequently during burst with X growing (e.g., 10–50 ms).
- Interleaved `WM_TIMER` (HEARTBEAT) callbacks appear with increasing gaps (hb_age creeps up).
- CPU on UI thread ~100% during burst.

Refutation: `long_ms` warnings rare or X always small, AND heartbeat age stays <100 ms → tick is fine.

### H3 — Tier 1 heartbeat self-starvation (meta-bug)

Claim: `HEARTBEAT_TIMER_ID` (WM_TIMER, 100 ms, App.zig:88) and the background `watchdogLoop` (1 s sleep, atomic load) share the same pump as everything else. Under H1/H2 load, `WM_TIMER` is a low-priority synthesized message — it only fires when `GetMessage` has no other queued messages. So the heartbeat becomes late *because* the queue is full, which means the watchdog's own signal is the victim, not the cause. We may be misinterpreting `ui_stall detected stall_ms=...` as "UI is hung" when it actually means "Dispatcher is busy but WM_TIMER lost priority".

Observable predictions:
- `ui_stall detected` fires, but `drainMailbox: tick done` log lines continue flowing (UI thread IS running).
- `hb_age_ms` monotonically grows, then snaps back to 0 as soon as burst ends.

Refutation: `ui_stall detected` fires AND `drainMailbox` log lines also gap during the same interval (UI thread truly frozen → different class of bug, back to investigation).

### H4 — CP pipe mutation path synchronously blocked on UI thread

Claim: Per control_plane.zig:57–58 the design is "reads lock-free/mutex, mutations PostMessageW async". But `deckpilot send` with an `INPUT` or similar command hits the mutation path, which posts `WM_APP_CONTROL_ACTION` to the UI thread. If the UI thread is busy (H1/H2), the CP **response** to deckpilot has to wait for the UI thread to complete the action (at least for the commands that return a status after performing the action). That would surface as `phase1_timeout` even though the pipe itself is healthy.

Observable predictions:
- `deckpilot send` latency distribution has a bimodal peak: fast (< 50 ms, pipe round-trip only) vs slow (matching `drainMailbox` gaps).
- Commands that the pipe server can answer without UI thread round-trip (e.g., `CAPABILITIES`, `STATE`) stay fast during burst; `INPUT` / `NEW_TAB` slow.

Refutation: all CP commands, including pure reads, gap simultaneously → not a CP-specific mutation-path issue; H1 is dominant.

### H5 — `log.info` flood on stderr inside `drainMailbox`

Claim: App.zig:2316 and :2322 emit unconditional `log.info("drainMailbox: tick...")` / `"drainMailbox: tick done"` every call. Release-build log level is `.info` (`src/main_ghostty.zig:179–182`), so **these lines are emitted in release**. Under H1 flood at e.g. 1000 wakeups/sec we emit 2000 log lines/sec from the UI thread. Each one calls the Zig `logFn` (synchronous write to stderr or log sink); if stderr is a pipe or file handle with bounded buffer, writes block the UI thread.

Observable predictions:
- Disabling those two log lines (or gating to `.debug`) eliminates the stall independently of H1's no-coalescing fix.
- stderr is a file/pipe (not `CONOUT$`) in the process that exhibits the stall (deckpilot-launched ghostty runs detached).

Refutation: log sink is lock-free / async, or removing the log lines does not change latency distribution.

---

## Step 3 — Minimal log design

For each hypothesis, the *single* observation that flips the judgment:

| Hyp | Minimal log | Emitted from | Cadence |
|-----|-------------|--------------|---------|
| H1 | `wakeup_calls` counter, sampled 1 Hz | `wakeup()` (App.zig:1572) | atomic `fetchAdd(1)` per call; 1 Hz timer emits snapshot |
| H1 | `drain_ticks` counter, sampled 1 Hz | `drainMailbox` entry | same atomic scheme |
| H2 | `long_tick_count` + max elapsed | existing `long_ms` warn site (App.zig:2331) | already logged — keep |
| H3 | `hb_age_ms` sample at `PULSE` cadence | existing Team-G watchdog log (NOT in HEAD) — **fold forward** | already designed |
| H4 | `cp_ui_queue_depth` (count of pending `WM_APP_CONTROL_ACTION` posted vs processed) | CP pipe handler + WM handler | atomic inc/dec, sample 1 Hz |
| H5 | `log_rate_drainmailbox` = drain_ticks × 2 (both lines); derived, no new counter | N/A | computed in report |

All counters gated on env var `GHOSTTY_WINUI3_DISPATCHER_DIAG=1`. When off, zero overhead (atomic loads only compiled into `if (flag) { ... }` branch that the optimizer lifts out — we use `std.atomic.Value(u64)` accessed from the UI thread only, so relaxed ordering suffices).

**Sink**: append lines to `%LOCALAPPDATA%\ghostty\dispatcher-stall-diag-<pid>.log` at 1 Hz:
```
DIAG t_ms=<unix_ms> pid=<pid> wakeups=<delta_1s> drains=<delta_1s> long_ticks=<delta_1s> max_long_ms=<last_1s> cp_q_depth=<current>
```

Team-G's `watchdog.zig` already implements a similar log sink on `p1-task-214-dispatcher-watchdog`. We duplicate (disjoint branches) rather than cherry-pick — Team G's PR curator owns that merge; we keep our diagnostic strictly local under a distinct filename so it can coexist if the branches ever merge.

---

## Step 4 — Instrumentation plan (opt-in, removal mandatory after step 8)

Three small edits:

1. **App.zig**: five atomic counters on `App`, 1 Hz `WM_TIMER` slot (reuse or add) that writes the DIAG line if env var set.
2. **wakeup()**: `wakeup_calls.fetchAdd(1, .monotonic)` at entry.
3. **drainMailbox()**: `drain_ticks.fetchAdd(1, .monotonic)` at entry; `long_ticks.fetchAdd(1, ...)` inside the `elapsed_ns > tick_slice_warn_ns` branch.
4. **control_plane.zig**: CP mutation enqueue/handle → `cp_q_depth` inc/dec.

All three steps deleted in step 8.

---

## Step 5 — Manual repro script

File: `scripts/repro-dispatcher-stall.ps1` (to be written).

Pre-conditions:
- Binary: `zig-out-winui3/bin/ghostty.exe` rebuilt with DIAG counters (this branch).
- `GHOSTTY_WINUI3_DISPATCHER_DIAG=1` set.
- Max 3 live `ghostty.exe` processes total during the test (CLAUDE.md / brief constraint). Script asserts `Get-Process ghostty -EA SilentlyContinue` ≤ 2 before spawning a new one.

Steps (numbered, fixed):
1. Clean any stale `%LOCALAPPDATA%\ghostty\dispatcher-stall-diag-*.log`.
2. Spawn one ghostty via `Start-Process` with `GHOSTTY_CONTROL_PLANE=1`, `GHOSTTY_SESSION_NAME=stall-probe`, `GHOSTTY_WINUI3_DISPATCHER_DIAG=1`. Record PID.
3. Wait for pipe `\\.\pipe\ghostty-winui3-stall-probe-<pid>` to become connectable (poll with 100 ms interval, 5 s timeout).
4. Deterministic burst generator (no network, no API key): feed the ghostty session a command that writes ≥ 200 KB of text quickly. Use `SEND_KEYS` of a one-liner shell loop:
   `for /L %i in (1,1,20000) do @echo token %i`
   (cmd.exe inside ghostty — keeps PTY writer local, reproducible, no external dependency).
5. 50 ms after SEND_KEYS, start a tight probe loop: every 100 ms, `deckpilot send stall-probe "STATE"`, measure round-trip ms, log to CSV. Run for 15 s.
6. Collect DIAG log + probe CSV, compute p50 / p95 / p99 / max latency, count `wakeups/sec` peak, `drains/sec` peak.
7. Optional: repeat with `GHOSTTY_WINUI3_DISPATCHER_DIAG=0` to confirm counters add zero regression.
8. Terminate the spawned ghostty (`Stop-Process -Id <pid>`).

Pass criterion (pre-mitigation baseline expected to FAIL): probe p95 < 500 ms. Post-mitigation target: p95 < 500 ms. We record absolute numbers either way.

Output: `.dispatch/dispatcher-stall-measurements-<timestamp>.log` (raw CSV + summary).

---

## Step 6 — Judgment (split into 6a–6e, partial commits after each)

### 6a — Canonical repro run

Command:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/repro-dispatcher-stall.ps1 \
    -ProbeDurationSec 15 -BurstLines 10000 -Label pre
```

Valid run (shell launched + burst executed): pid=29360, timestamp 20260420-235616.
Raw data: `.dispatch/dispatcher-stall-diag-pre-20260420-235616-pid29360.log` and
`.dispatch/dispatcher-stall-measurements-pre-20260420-235616.log`.

Other runs (pid=50868 `pre-heavy` 200K, pid=43248 `pre-50k`, pid=41476 `canonical`) repeatedly tripped a
separate `error starting IO thread: error.InvalidUtf8` shell init failure that left the session with no
PTY writer. Those sessions subsequently showed a full UI-thread freeze (`stalled=1`, hb_age_ms growing
monotonically past 40s, wakeups=0, drains=0) but that's an **init-time failure, not the runtime dispatcher
stall in scope**. Flagged as a separate finding in "Known gaps" below.

Probe summary for the valid run (pid=29360):
- `STATE` probes n=134, p50=1ms, p95=2ms, p99=4ms, max=4ms.
- `CAPABILITIES` probes n=134, p50=0ms, p95=1ms, p99=15ms, max=15ms.
- Probe loop never saw a CP pipe stall. **Under 10K-line cmd.exe echo burst alone, the issue is not reproduced end-to-end** (no p95 > 500ms, no client-visible failure).

### 6b — Canonical diag log (pid=29360, 1 Hz DIAG frames)

```
DIAG t_ms=1776696975506 pid=29360 hb_age_ms=19  stalled=0 wakeups=1800 drains=1799 long_ticks=0 tick_ns=16655700  avg_tick_us=9
DIAG t_ms=1776696976506 pid=29360 hb_age_ms=33  stalled=0 wakeups=8279 drains=8288 long_ticks=8 tick_ns=215487000 avg_tick_us=25
DIAG t_ms=1776696977507 pid=29360 hb_age_ms=45  stalled=0 wakeups=0    drains=0    long_ticks=0 tick_ns=0         avg_tick_us=0
DIAG t_ms=1776696978508 pid=29360 hb_age_ms=65  stalled=0 wakeups=0    drains=0    long_ticks=0 tick_ns=0         avg_tick_us=0
...
```
(log continues with idle frames through t_ms=1776696991516; max observed `hb_age_ms=106` on idle frames.)

| Sample window | Event | wakeups | drains | long_ticks | tick_ns | avg_tick_us | hb_age_ms |
|---------------|-------|---------|--------|------------|---------|-------------|-----------|
| +0 to +1s     | session startup (init + config cache load + XAML layout) | 1800 | 1799 | 0 | 16.7M | 9 | 19 |
| +1 to +2s     | cmd.exe executes 10K-line `for /L` echo burst | 8279 | 8288 | **8** | 215.5M | 25 | **33** |
| +2 to +15s    | idle (burst complete) | 0 | 0 | 0 | 0 | 0 | ≤ 106 |

### 6c — H1 (wakeup flood, no coalescing)

**Status: SUPPORTED by evidence.**

Facts (from +1→+2s DIAG frame):
- `wakeups=8279`, `drains=8288`. The 1:1 ratio (drains even slightly exceeds wakeups, modulo sample
  boundary) proves that `DispatcherQueue.TryEnqueue` does **not** coalesce identical handler instances.
  Each `wakeup()` call from termio/core produced exactly one scheduled `drainMailbox` invocation.
- `avg_tick_us=25` → each drain did only ~25µs of useful work. With 8288 drains × 25µs = 207ms of drain
  CPU per second (close to `tick_ns=215.5M`). 20% of the UI thread is spent on drain admin.
- Under a 10K-line cmd.exe burst the load saturated at 8.3 kHz drain rate; Claude xhigh thinking can
  plausibly push token stream rates 3–10× higher, which extrapolates to 25–80 kHz drain rate → 60–100%
  UI thread consumed by drain admin, at which point the symptom in the brief begins.

Inference (NOT fact): "At Claude xhigh token burst rate (observed main-thread, 2026-04-20 23:40), the
wakeup:drain 1:1 relationship multiplied by the actual per-byte PTY wakeup rate exceeds the UI thread's
admin capacity and starves other Dispatcher work". Needs direct measurement during real Claude burst —
deferred to post-mitigation re-measure.

### 6d — H2 (`core_app.tick` slice blowout)

**Status: PARTIALLY SUPPORTED — slice bound triggers but at low rate.**

Facts (from +1→+2s DIAG frame):
- `long_ticks=8` during the burst window (8 ticks exceeded the 4ms `tick_slice_warn_ns` threshold).
- `tick_ns=215.5M ÷ drains=8288 → avg_tick_us=25`. Most ticks are short; only 8 of 8288 blew past 4ms.
- No `long_ticks` counted outside the burst window.

Inference: Tick slice blowouts are a real phenomenon but rare (0.1% of drains). The existing P1 #1 fix
(8dc3fa343, "bound UI-thread tick slice") successfully re-posts `WM_USER` after a blowout, but since the
next pump turn is immediately another `WM_USER` (our own re-post), the "yield" is cosmetic. H2 is a
minor contributor, not the primary cause at the 10K burst level. At higher burst rates, the 8/sec
long-tick rate would rise and compound with H1.

### 6e — H3 / H4 / H5

**H3 (Tier 1 heartbeat self-starvation):**
**Status: REFUTED for this load.** Facts: `hb_age_ms=33` during the burst window (max `hb_age_ms=106`
anywhere in the log). The 3s `ui_stall detected` threshold was never tripped in the in-scope runs (only
tripped in the separate init-time freeze, which is H0-class / out of scope). Heartbeat timer was
serviced on every cadence, so the pump is not starving the heartbeat under this load.

**H4 (CP pipe mutation path synchronously blocked on UI thread):**
**Status: REFUTED for this load.** Facts: probe latencies p95(STATE)=2ms, p95(CAPABILITIES)=1ms
throughout the run. Both pure reads (lock-free/mutex, per control_plane.zig:57–58) stayed fast;
CAPABILITIES went as high as p99=15ms once, which is within normal noise. No bimodal latency
distribution (which H4 predicted). No pipe timeouts. At the 10K burst level, CP pipe path is not the
bottleneck.

**H5 (`log.info` flood on stderr inside `drainMailbox`):**
**Status: UNDETERMINED.** Facts: release-mode `log_level=.info` (main_ghostty.zig:179–182) confirms the
two `log.info("drainMailbox: tick...")` lines are emitted. At 8288 drains/sec that is 16576 stderr lines
per second. stderr in a GUI-launched ghostty is redirected to a temp log (os.attachDebugConsole, os.zig:
678–701), so each write hits disk I/O. We did not instrument per-line log latency; cannot isolate H5's
contribution from H1's raw enqueue/drain overhead without an additional run that gates those two log
lines behind `.debug`. **Deferred**: a follow-up A/B repro with the two `log.info` lines commented out
would decide H5. Not blocking H1 mitigation — if H1 fix reduces drain count, H5 amplitude drops
proportionally regardless.

### 6 — Summary

- **H1 is the dominant in-scope finding** (supported, wakeup:drain 1:1, 8.3 kHz rate at 10K burst).
- H2 is a minor contributor (supported at 0.1% rate).
- H3, H4 refuted at this load.
- H5 undetermined; would fall naturally with H1 fix.
- **A separate init-time UTF-8 shell-launch failure** was observed in 3 of 4 repro attempts and triggered
  a full UI-thread freeze. That symptom is **out of scope for this team** (brief §scope: runtime
  dispatcher stall, not init-time failures) and should be routed to a separate investigation. Captured
  diag logs at `.dispatch/dispatcher-stall-diag-{pre-heavy,pre-50k,canonical}-*.log` for that other team.


---

## Step 7 — Mitigation choice (pending step 6)

Brief offers:
- **(a) UI update coalescing** — reduces H1/H3 amplitude by folding redundant enqueues. Simplest: set a `wakeup_pending` atomic flag; `wakeup()` skips `TryEnqueue` if already set; `drainMailbox` clears it after the first tick. Side effect: if drainMailbox doesn't actually drain everything, a second wakeup might be missed — but since drain always calls `core_app.tick` which drains fully, this is safe.
- **(b) Priority lane** — split input/CP vs render, requires two DispatcherQueues or WM_APP priority slots. Bigger change.
- **(c) Stall-detect force-yield** — workaround.
- **(d) Circuit breaker** — workaround.

Hypothesis (to be confirmed by step 6): H1 is the primary cause, (a) is the minimal correct fix.

---

## Step 8 — Re-measure + remove diag (pending)

After mitigation:
- Repro script run, expect p95 drop.
- Remove diag counters (step 4 edits reverted or gated to Debug-only).
- Single mitigation commit + single diag-removal commit (or squash).
- `git push fork p1-task-214-dispatcher-stall-mitigation`. No PR — Team PR-Curator's responsibility.

---

## Known gaps / non-goals

1. Hard fixes (replacing DispatcherQueue, changing XAML render pipeline) are out of scope. If H1–H5 all refute and the stall persists, stop + report only.
2. We do not touch `src/apprt/winui3/control_plane.zig` pipe *init* code — that belongs to Team CP-Race-Fix.
3. Team G's `watchdog.zig` log sink is *not* imported into this branch to avoid cross-team merge noise. Duplicate counters with distinct filename.
4. 4+ session stress testing is prohibited. Max 3 ghostty processes at any time; the test subject is 1 of those, leaving room for the host session running this investigation plus a deckpilot daemon.

## Progress log

- 2026-04-20: brief received, branch `p1-task-214-dispatcher-stall-mitigation` created off `e4d99ae8b`. Steps 1–4 drafted in this report. Next: implement diag counters (step 4), write repro script (step 5).
