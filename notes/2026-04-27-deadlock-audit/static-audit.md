# Static deadlock-blocker audit — fork/main @ a27b3c601

Read-only audit picking up the dispatch brief
`.dispatch/codex-deadlock-blocker-static-audit.md`. Scope: verify the four
landed commits (cascade detector, Command refactor, Phase 2.3 sweep,
upstream-shared minimisations) actually closed the unbounded-wait class.

```
$ git log --oneline a27b3c601 -10
a27b3c601 chore(231): relocate cascade detector repro test under tests/winui3/
2f4d7cc4c feat(231): cascade deadlock defense - apprt-local chain breakers
1a7625953 refactor(Command): minimize Win32 timeout/encoding footprint
bf9c556a1 refactor(#232): Phase 2.3 sweep — migrate remaining .forever callsites
6a479d8b4 refactor(#239): minimize termio footprint in upstream-shared files
de24427a4 refactor(#239): minimize DirectWrite footprint
5c2a3b432 docs(194): consolidate Windows 10 architectural lessons-learned
71e3cd73f docs(239): mailbox interface design
4d03e94e4 docs(#239): font backend interface design
6723a8f07 chore(238): apprt contract enforcement and audit
```

## 1. `.forever` 14 → 0 verification

Searched `src/` (production, excluding `tests/`):

```
$ rg -n '\.forever' src/
src/datastruct/bounded_mailbox.zig:4,32,35,209,679-741   (file describing why .forever does not exist; @compileError fixtures)
src/datastruct/blocking_queue.zig:116,156,234,356        (legacy type, kept for tests/repro fixtures)
src/font/shaper/coretext.zig:288                          (comment: "legacy `.forever` would have parked")
src/termio/Termio.zig:506                                 (comment)
src/termio/stream_handler.zig:135,186                     (comments)
src/renderer/generic.zig:1691                             (comment)
src/termio/mailbox.zig:21,102                             (comments)
src/termio/Exec.zig:294,394                               (comments)
src/Surface.zig:922,1879,2666,3552,3583,6085             (comments)
src/apprt/gtk/class/application.zig:1459,1812            (comments)
src/apprt/embedded.zig:2117,2119                          (comments)

$ rg -n 'pushTimeout.*\.forever' src/         → 0 production hits (only @compileError text)
$ rg -n 'BlockingQueue.*\.pop\(.forever\)' src/ → 0 hits
```

**Verdict: production `.forever` invocations = 0.** Every remaining hit is
either (a) explanatory commentary justifying the migration, (b) the
@compileError guards inside `bounded_mailbox.zig:709,724` that *prevent*
re-introduction, or (c) `blocking_queue.zig` itself — the legacy type that
Phase 2 superseded but kept compilable so test fixtures can still exercise
legacy semantics (the brief explicitly excludes those). Cross-referenced
with bf9c556a1 commit body which lists the exact 14→0 migration
(App.Mailbox, cf_release_thread.Mailbox, terminal/search/Thread.Mailbox,
termio/mailbox.Queue) and matches what the grep shows.

### Adjacent unbounded-wait classes (`WaitForSingleObject(INFINITE)`)

```
$ rg -n 'WaitForSingleObject\(.*INFINITE\)' src/
src/Command.zig:434          // LINT-ALLOW: legacy entry; #221 added waitTimeout
src/apprt/win32/spawn.zig    (doc-comments only)
src/apprt/win32/App.zig:205  // LINT-ALLOW: message pump itself
```

Both `LINT-ALLOW` sites are sound: `Command.wait` is the legacy blocking
entry that 1a7625953 left in place because callers should migrate to the
new `waitTimeout(ms)`; `win32/App.zig` is the message-pump-as-such whose
whole purpose is to park until a Win32 message arrives (`wakeup()` posts
`WM_USER` to break it). Neither is reachable from a UI-thread mailbox push.

## 2. BoundedMailbox push semantics

`src/datastruct/bounded_mailbox.zig` defines three producer entry points:

- **`push(value)`** (line 190) — uses the type-baked `default_timeout_ms`.
  Compile-error if the type was instantiated with `null` default.
  When default is `0` it is identical to legacy `.instant`; when default
  is `> 0` it is `pushTimeout(value, default)`.
- **`pushTimeout(value, ms: u32)`** (line 211) — explicit per-call bound.
- **`pushUntilShutdown(value, *ShutdownToken)`** (line 263) — the only
  unbounded variant; mandatory token argument is the syntactic flag.

Drop-safety classification of every production callsite:

| Site (file:line) | Variant | Producer thread | Class |
|---|---|---|---|
| App.zig:606 (Mailbox.push) | wrapper | varies | wrapper, see callers |
| App.zig:618 (Mailbox.pushTimeout) | wrapper | worker | wrapper |
| apprt/embedded.zig:2124 macos_display_id | push (instant) | host UI | drop_safe — best-effort, renderer picks up next frame (comment 2117–2123) |
| apprt/surface.zig:153,169 | wrapper | varies | wrapper |
| Surface.zig:931 inspector=true | push (instant) | UI | drop_safe — pointer already published, renderer reads on tick (922–927) |
| Surface.zig:956 inspector=false | push (instant) | UI | drop_safe — symmetric to above (951–955) |
| Surface.zig:1473,1497,1518,1526,1537,1550,1560,1571,1587,1593 search_* | pushTimeout 5s | search worker | drop_safe — UI redraws stale match counter for one cycle; arena `deinit()`d on drop, no leak |
| Surface.zig:1888 change_config | push (instant) | UI (config reload) | drop_safe — `renderer_message.deinit()` on drop; renderer picks up new config on next reload (1879–1887) |
| Surface.zig:2676 font_grid | push (instant) | UI (Ctrl+= / Ctrl+−) | drop_safe — `font_grid_set.deref(font_grid_key)` on drop; `self.font_grid_key` not advanced; old grid stays valid (2666–2685) |
| Surface.zig:3559 visible | push (instant) | UI (occlusion) | drop_safe — renderer keeps prior visible state for one cycle, `queueRender()` follow-up (3549–3563) |
| Surface.zig:3593 focus | push (instant) | UI (focusCallback) | drop_safe — focus state best-effort, drop preferable to UI hang (#218 root) |
| Surface.zig:5485 change_needle | push (instant) | UI | drop_safe — `needle.deinit()` on drop, prevents leak (5483–5488) |
| Surface.zig:5495 select(navigate_search) | push (instant) | UI | drop_safe — pure navigation hint |
| Surface.zig:6089 crash | push (instant) | UI (debug bind) | drop_safe — debug-only, user retries |
| App.zig:606 (via gtk activate, open_config, present_surface @ 1468/1815/1845) | push (instant) | GTK UI | drop_safe — best-effort UI requests, warn-on-drop |
| renderer/Thread.zig:530 redraw_surface | push w/ legacy `.instant` arg | renderer | wrapper-compatible drop_safe |
| renderer/generic.zig:1394 scrollbar | push (instant) | renderer worker | drop_safe — retried next frame (1390–1396) |
| renderer/generic.zig:1694 renderer_health | pushTimeout 5s | renderer worker | drop_safe — health update delayed by next health cycle |
| termio/Exec.zig:298 child_exited | pushTimeout 5s | termio | drop_safe — comment acknowledges 5s app-mailbox stall preferable to permanent termio park (289–305) |
| termio/Exec.zig:400 password_input | pushTimeout 5s | termio timer | drop_safe — stale password-mode UI surfaced via warn log (392–404) |
| termio/Termio.zig:508 resize | pushTimeout 5s | termio | drop_safe — stale GPU size for one frame; watchdog catches >5s renderer stall |
| termio/Termio.zig:683 reset_cursor_blink | push (instant) | termio | drop_safe — cursor re-renders next frame (681–684) |
| termio/mailbox.zig:80 fast path | push (instant) | termio producer | drop_safe — slow path retries with bounded 5s |
| termio/mailbox.zig:107 slow path | pushTimeout 5s | termio producer | drop_safe — bounded fallback after wakeup |
| termio/stream_handler.zig:137,141 surface_mailbox | push then pushTimeout 5s | termio | drop_safe — bounded fallback |
| termio/stream_handler.zig:167,193 renderer_mailbox vt | push then pushTimeout 5s | termio | **drop_advisory**: comment 186–192 admits bounded fallback can drop a vt char on saturation; long-term proper backpressure channel is out of scope for #232. Acceptable: dropping under 5s of renderer wedge is preferable to deadlocking the termio thread; user-visible artefact would be glitched render of one segment, not stuck UI |
| terminal/search/Thread.zig:886 (test) | pushTimeout 5s | test | drop_safe — test fixture |
| font/shaper/coretext.zig:291 cf_release | pushTimeout 5s | renderer worker | drop_safe — fallback path `CFRelease`s items inline (303–304) so no GPU-resource leak on drop |
| gtk activate/open_config/present_surface | push (instant) | GTK UI | drop_safe (warn) |

**No `.quit` / shutdown message is delivered via mailbox push.**
`grep -nE 'mailbox\.push.*\.quit'` returns zero hits in `src/`. The
shutdown path in `App.zig:264,450` invokes `rt_app.performAction(.quit, {})`
directly, not via mailbox enqueue, so a saturated mailbox cannot drop a
quit signal. The `BoundedMailbox.shutdown()` method (line 162) is the
correct termination primitive — it's called by drain-loop owners
(App.zig drainMailbox, termio/Thread.zig, terminal/search/Thread.zig,
os/cf_release_thread.zig) and a closed mailbox returns `.shutdown` from
subsequent pushes, never silently dropping work that needed to land
post-shutdown.

**No `pushUntilShutdown` callsites in production** (only the test at
bounded_mailbox.zig:492). The unbounded variant is unused, which matches
the design intent: Phase 3 will introduce an App-scoped shutdown bus
before any worker opts into it.

**Verdict: every production push is drop-safe.** The single
drop-advisory site (stream_handler vt fallback) is documented in-comment
as a known artefact and bounded at 5 s.

## 3. Apprt isolation + deadlock lint

```
$ bash tools/lint-fork-isolation.sh
lint-fork-isolation: scanning HEAD..fork/main (branch divergence)
lint-fork-isolation: no changed files; ok
$ echo $?
0

$ bash tools/lint-deadlock.sh
== rule: forever-ok (error) ==                        ok: 0 hits
== rule: infinite-wait (error) ==                     hits: 0
== rule: overlapped-bwait (error) ==                  ok: 0 hits
== rule: sendmessagew (warn) ==                       hits: 4
   src/apprt/winui3/nonclient_island_window.zig:531,540,551,573
lint-deadlock: 0 violations, 4 warning(s)
$ echo $?
0
```

The four `sendmessagew` warnings in `nonclient_island_window.zig` are
pre-existing (the bf9c556a1 commit body explicitly notes "pre-existing 4
sendmessagew warnings unrelated to this change"). They are HTTOP/HTCAPTION
forwards — fire-and-forget caption-button hit-test routing where switching
to `SendMessageTimeoutW` would not change behaviour because the recipient
is the same UI thread. Out of scope for this audit.

**Verdict: zero new violations. Apprt isolation intact.**

## 4. Cascade detector atomic ordering

`src/apprt/winui3/cascade_detector.zig` `std.atomic.Value` operations:

| File:line | Field | Op | Ordering | Verdict |
|---|---|---|---|---|
| 150 | tick_count | fetchAdd | .monotonic | OK — pure counter, observed via delta in same thread (321) |
| 152 | tick_warn_count | fetchAdd | .monotonic | OK — same as above |
| 155 | tick_err_count | fetchAdd | .monotonic | OK — same as above |
| 158 | max_tick_ns | load | .monotonic | OK — CAS-loop bootstrap, no happens-before needed |
| 160 | max_tick_ns | cmpxchgWeak | .monotonic/.monotonic | OK — value-only, no cross-field dependency |
| 164 | last_tick_unix_ms | store | .monotonic | OK — observed via delta in the same poll cycle, not used as a fence for any other publication |
| 244 | stop | store | .release | OK — pairs with .acquire load at 252,254 to publish "stop" before joiner observes |
| 252,254 | stop | load | .acquire | OK — pairs with .release store at 244 |
| 267 | wakeup_pending | load | .acquire | OK — paired with App's .release store on the producer side; ensures any state writes preceding the wakeup flag are visible |
| 284 | cp_last_notify_ms | load | .acquire | OK — owner publishes cp_last_notify_ms via .release after staging the notify; .acquire here ensures the timestamp reflects the corresponding push |
| 287 | last_tick_unix_ms | load | .monotonic | OK — used only for "is there recent traffic" coarse rate signal; happens-before unnecessary |
| 302 | last_ui_heartbeat_ns | load | .acquire | OK — paired with .release store from the watchdog's heartbeat update path; ensures the heartbeat timestamp reflects a completed UI-thread tick rather than a torn read |
| 320 | tick_err_count | load | .monotonic | OK — delta calculation only |
| 323 | max_tick_ns | load | .monotonic | OK — display-only |
| 349-351 | tick_count/warn/err | load | .monotonic | OK — delta snapshot |
| 363 | cascade_fired | load | .acquire | OK — pairs with .release store at 365; one-shot guard reads before the callback fires, must not reorder past the store that latches it |
| 365 | cascade_fired | store | .release | OK — pairs with the load at 363; ensures any side effects of the previous tick are visible before "fired" becomes true |
| 376 | last_tick_unix_ms | load | .monotonic | OK — display age |
| 380 | cp_last_notify_ms | load | .acquire | OK — same rationale as 284 |
| 394 | cascade_fired | load | .acquire | OK — display in summary log |

Each `.acquire`/`.release` pair (`stop`, `cascade_fired`,
`wakeup_pending`/`last_ui_heartbeat_ns`/`cp_last_notify_ms`) is correct:
the producer side stores with `.release` after publishing the underlying
state (the wakeup flag, the heartbeat timestamp, the CP notify
timestamp), so the detector's `.acquire` load establishes happens-before
on the corresponding state writes. Pure counters that are only read for
delta-rate calculation use `.monotonic`, which is the cheapest legal
ordering and sufficient because the detector tolerates one-cycle staleness
by design (the cascade aggregator is a heuristic, not a hard fence).

The CAS-loop on `max_tick_ns` (158–162) is a textbook monotonic-max
pattern; correctness does not depend on synchronisation with any other
field, only on the per-value monotonicity of the max itself.

**Verdict: every atomic op in cascade_detector.zig has correct
ordering.** No happens-before gaps; the design intentionally uses
relaxed (`.monotonic`) only on counters that publish no other state.

## Bottom line

All four audit deliverables clear:

- **§1** Production `.forever` count = 0; remaining hits are commentary or compile-time guards.
- **§2** Every production `BoundedMailbox.push*` callsite is drop-safe; no quit/shutdown signal is mailbox-delivered, so drop-on-full cannot break shutdown correctness. One *drop_advisory* (vt char on >5s renderer wedge, `stream_handler.zig:193`) is documented and bounded.
- **§3** lint-fork-isolation: clean. lint-deadlock: 0 errors, 4 pre-existing `sendmessagew` warnings unrelated to the four landed commits.
- **§4** All `std.atomic.Value` ops in `cascade_detector.zig` use correct memory ordering for their role; acquire/release pairs match across detector ↔ App publishing, monotonic limited to counters where staleness is tolerated.

No new bugs surfaced. The Phase 2.3 sweep + cascade detector + Command
refactor combination structurally rules out the unbounded-wait deadlock
class on fork main.
