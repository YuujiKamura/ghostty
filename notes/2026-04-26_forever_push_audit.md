# `.forever = {}` push audit (2026-04-26)

Scope: `src/**/*.zig`. Triggered by issue #218 (UI thread hung indefinitely on
`Surface.focusCallback -> mailbox.push(.{ .focus = focused }, .{ .forever = {} })`).
This audit classifies every remaining `.forever` push by whether it can run on
the UI thread (= the apprt thread that pumps window messages). Any UI-thread
producer of `.forever` is a potential `IsHungAppWindow` trigger.

The fix landed in this branch (`fix-218-focus-mailbox-drop`) only addresses
`Surface.zig:3382` (`focusCallback`). The other UI-thread call sites listed
below should be tracked as separate issues — they all carry the same hang
pattern and each needs its own correctness review (drop vs bounded wait vs
deferred dispatch).

## Methodology

1. `grep -rn '\.forever = \{\}' src/` enumerates 17 sites (1 of which is the
   focus push being fixed in this PR; 1 is the cdb-evidenced site for #218).
2. For each site, walked back the function definition and confirmed callers
   via `grep` (apprt-side `focusCallback` / `occlusionCallback` /
   `setFontSize` / `updateConfig` etc. directly invoke surface methods on the
   UI thread).
3. UI-thread classification rules:
   - **UI thread**: callsite reachable via apprt callback (`focusCallback`,
     `occlusionCallback`, XAML event handlers, GTK signal handlers, embedded
     `ghostty_surface_*` exported C functions invoked by host UI threads).
   - **Worker thread**: callsite reachable only from `renderer_thread`,
     `termio_thread`, `xev` event-loop callbacks, or `cf_release_thread`.
   - **Either**: ambiguous — caller graph contains both worker- and UI-thread
     reach paths.

## Sites called from the UI thread (HANG RISK — file follow-up issues)

| File | Line | Push | Caller chain (UI thread reach) | Risk |
|------|------|------|--------------------------------|------|
| `src/Surface.zig` | 3384 (was 3382) | `.{ .focus = focused }` | `Surface.focusCallback` ← apprt focus events (winui3 `onXamlGotFocus` etc., gtk `notify-has-focus`, embedded `ghostty_surface_focus`) | **FIXED** in this branch |
| `src/Surface.zig` | 3364 | `.{ .visible = visible }` | `Surface.occlusionCallback` ← apprt visibility (winui3, gtk visibility, embedded `ghostty_surface_set_occlusion`) | HIGH — same pattern as #218, fires on every show/hide. Recommend `.instant` drop + log. |
| `src/Surface.zig` | 921 | `.{ .inspector = true }` | `Surface.activateInspector` ← apprt inspector toggle (gtk `inspector_widget`, embedded `ghostty_inspector_*`) | MEDIUM — user-driven, low frequency, but UI thread is the producer. Recommend bounded `.{ .ns = 100 * ns_per_ms }` wait. |
| `src/Surface.zig` | 938 | `.{ .inspector = false }` | `Surface.deactivateInspector` ← same as above | MEDIUM — same as activate. |
| `src/Surface.zig` | 1805 | `rendererpkg.Message.initChangeConfig(...)` | `Surface.updateConfig` ← `core_app.updateConfig` ← apprt config reload (winui3 `App.zig:1727`, gtk `application.zig:2462`, embedded `ghostty_app_update_config`) | HIGH — config reload is user-driven; if renderer is mid-frame and mailbox saturated, UI hangs until renderer drains. Recommend bounded wait + error path that retries on renderer wakeup. |
| `src/Surface.zig` | 2499 | `.{ .font_grid = ... }` | `Surface.setFontSize` ← apprt font size change (embedded `ghostty_surface_set_font_size` via `embedded.zig:591`, also internal triggers from `keyCallback` on `font_size` actions) | HIGH — interactively triggered by Ctrl+= / Ctrl+-, runs on UI thread. |
| `src/Surface.zig` | 5876 | `.{ .crash = {} }` | `keyCallback` → action `.crash = .render` | LOW — debug-only crash binding; intentional. Leave as-is, possibly drop on full and log. |
| `src/apprt/embedded.zig` | 2119 | `.{ .macos_display_id = ... }` | exported `ghostty_surface_set_display_id` ← host (macOS embedder UI thread) | MEDIUM — host calls on display change, UI thread. Bounded wait or drop. |
| `src/apprt/gtk/class/application.zig` | 1462 | `.{ .new_window = ... }` | `Application.activate` ← gtk activation signal (UI thread) | MEDIUM — fires once per activation, but blocks UI if app mailbox is full (unlikely in practice, but a hang here is fatal at startup). |

## Sites NOT on the UI thread (no #218 risk)

| File | Line | Caller | Thread |
|------|------|--------|--------|
| `src/termio/Termio.zig` | 501 | `Termio.resize` | termio thread (resize comes via termio mailbox) |
| `src/termio/stream_handler.zig` | 134 | `surfaceMessageWriter` (fallback after `.instant`) | termio thread |
| `src/termio/stream_handler.zig` | 172 | `rendererMessageWriter` (fallback after `.instant`) | termio thread |
| `src/termio/mailbox.zig` | 92 | `Mailbox.send` (writer-thread fallback) | renderer/termio thread |
| `src/termio/Exec.zig` | 299 | `processExitCommon` | termio thread (xev process callback) |
| `src/termio/Exec.zig` | 391 | `termiosTimer` callback | termio thread (xev timer) |
| `src/font/shaper/coretext.zig` | 288 | `releaseRefs` | renderer thread (font shaping) |
| `src/renderer/generic.zig` | 1688 | render path → surface_mailbox | renderer thread |

The non-UI sites already have either explicit `.instant` first-attempt with a
`.forever` fallback (the stream_handler/mailbox pattern), or run on dedicated
worker threads where blocking is bounded by the consumer being separate from
any windowing message pump. They are not #218 candidates but should still be
reviewed as part of any general "no `.forever` on cross-thread queues" cleanup.

## Recommended follow-ups

1. **Open separate issues** for each HIGH/MEDIUM UI-thread site above so each
   can be triaged on its own merits (drop semantics differ — `.visible` and
   `.font_grid` cannot be silently dropped without correctness fallout, while
   `.focus` is best-effort).
2. **Consider a lint** (`zig build` step or grep CI check) that flags any new
   `.forever` push from a function whose name matches the apprt-callback
   surface (`*Callback`, `update*`, `activate*`, `deactivate*`).
3. **Long-term**: add a `pushOrDispatch` helper that schedules retry via
   `queueRender()` on full instead of blocking the producer. This would
   collapse the option-A vs option-B trade-off into a single safe primitive.

## Evidence reference

- cdb attach on PID 39796 (issue #218 body) confirms the focusCallback site
  is the one actively biting under sustained CP polling.
- Six independent hang dumps from 2026-04-26 sessions all show the same
  `Condition.wait → blocking_queue.push → focusCallback` stack.
