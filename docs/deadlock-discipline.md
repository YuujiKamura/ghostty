# Deadlock discipline

Design rules for blocking calls in `ghostty-win`. Required reading for any
change touching the mailbox, BlockingQueue, Win32 wait APIs, named pipes,
or `SendMessage*`.

This document is the human-side companion to
[`tools/lint-deadlock.sh`](../tools/lint-deadlock.sh): the lint catches the
mechanical shapes, this doc covers the intent.

## The pattern

On 2026-04-26 a single root cause — **"a thread that must remain
responsive performs an unbounded wait with no escape valve"** — was
independently re-implemented across at least eight call sites in five
different layers (Zig stdlib `BlockingQueue`, mailbox queue, Win32
process wait, Win32 overlapped pipe IO, WinRT `SendMessageW`). Every
case hung the UI thread until process kill (`IsHungAppWindow == TRUE`,
no recovery).

Sites fixed in the #218–#224 cluster:

- `src/Surface.zig:3384` — `focusCallback` mailbox `.forever` push (#218 root cause)
- `src/Surface.zig:3364, 921, 938, 1805, 2499` — sibling `.forever` pushes from `occlusionCallback` / inspector / `updateConfig` / `setFontSize` (#219, the seven sibling sites)
- Stdlib `BlockingQueue` had no `shutdown()` method, so consumer death = permanent producer hang (#220)
- `src/Command.zig:476` — `Command.wait` used `WaitForSingleObject(child, INFINITE)`, which never returns when the child is kernel-frozen or suspended (#221)
- `vendor/zig-control-plane/src` — `GetOverlappedResult(handle, &ov, &bytes, TRUE)` wedged forever when the peer dropped between `WriteFile` and the result query (#222)
- `src/apprt/winui3/nonclient_island_window.zig` (drag bar WndProc) — `SendMessageW(parent, ...)` with no timeout; UI hang in the parent propagates to the titlebar (#169, #223)
- `src/apprt/embedded.zig:2119`, `src/apprt/gtk/class/application.zig:1462` — platform-specific `.forever` pushes on macOS / GTK UI threads (#224)
- Earlier instance: `#207` — control-plane hang under concurrent STATE/TAIL/INPUT load, same root pattern in pipe IO

The full audit is in
[`notes/2026-04-26_forever_push_audit.md`](../notes/2026-04-26_forever_push_audit.md)
and the lint rationale in
[`notes/2026-04-26_deadlock_lint_rules.md`](../notes/2026-04-26_deadlock_lint_rules.md).

## Layered ban list

Any of the following is a code smell. On the UI thread perimeter
(`src/Surface.zig`, `src/apprt/winui3/`, `src/apprt/win32/`,
`src/apprt/embedded.zig`, `src/apprt/gtk/class/application.zig`) it is
forbidden outright unless the call has an explicit escape valve and a
`LINT-ALLOW: <rule-id> (reason)` marker that a reviewer can re-evaluate.

| Construct | Why it bites | Lint rule |
|-----------|--------------|-----------|
| `BlockingQueue.push(.., .{ .forever = {} })` | producer blocks until consumer drains; consumer death or saturation = hang | `forever-ok` |
| `WaitForSingleObject(.., INFINITE)` | child / handle never signals = hang | `infinite-wait` |
| `WaitForMultipleObjects[Ex](.., INFINITE)` | same as above | `infinite-wait` |
| `MsgWaitForMultipleObjectsEx(.., INFINITE)` | safe **only** in the dedicated message pump; everywhere else = hang | `infinite-wait` |
| `GetOverlappedResult(.., bWait=TRUE)` | peer drops between IO start and query = hang | `overlapped-bwait` |
| `SendMessageW(...)` (and friends without `*Timeout*`) | inherits destination thread's responsiveness = chained hang | `sendmessagew` (warn) |
| `ReadFile` / `WriteFile` on a pipe handle without overlapped + cancel | peer death = hang | (no lint yet — review by hand) |
| `WaitForSingleObject` on any thread join without budget | thread stuck in WndProc = hang | covered by `infinite-wait` |

## Escape valve options

When a blocking call is genuinely needed, every site MUST pick one of these:

1. **Bounded timeout** (preferred for Win32). Pass a finite ms budget
   (e.g. 5000), and treat `WAIT_TIMEOUT` as an escalation event — log
   it, fail the operation, surface it to the caller. Do not retry in a
   tight loop without backoff.
2. **Cancellation token / atomic flag.** The blocking call polls an
   atomic `should_exit` between attempts. The owner sets the flag on
   shutdown. Pair with a short timeout per attempt so the flag is
   actually checked.
3. **Shutdown signal on the queue itself.** `BlockingQueue.shutdown()`
   (added in #220) wakes every producer with `error.Shutdown` so they
   can exit cleanly. Use this whenever the queue's lifetime is shorter
   than the producer's.
4. **Drop on full** (`.{ .instant = {} }` for the mailbox). The
   producer attempts to push; if the queue is full it logs and returns
   without blocking. Correct for "best-effort" signals like focus and
   visibility transitions where a stale value is harmless. Wrong for
   correctness-critical messages like `change_config` or `font_grid`
   without a separate retry path.
5. **Explicit cap with `.{ .ns = N * std.time.ns_per_ms }` + log warn.**
   Bounded wait, then fall back to drop+log or to a deferred dispatch
   via `queueRender()`. Preferred when the message must arrive
   eventually but immediate delivery is not required.

## UI thread special case

The UI thread (anything reachable from a WinUI3 / Win32 / GTK callback,
including focus, occlusion, key, mouse, NCHITTEST, COM vtable entries,
and exported `ghostty_*` C functions invoked by the host) is **never
allowed to block indefinitely**. Period.

- Cross-process Win32 messaging: use
  `SendMessageTimeoutW(.., SMTO_ABORTIFHUNG, ms, ..)` with a small ms
  (50–500). `SMTO_ABORTIFHUNG` makes the call return immediately if the
  destination is already hung, which is exactly the failure mode that
  motivated the rule.
- In-process mailbox: use `.{ .instant = {} }` and `log.warn` on full.
  If correctness requires the message to arrive, add a deferred retry
  via `queueRender()` or an atomic flag the consumer polls — do **not**
  block the UI thread waiting for the renderer to drain.
- Win32 message pump itself (`src/apprt/win32/App.zig:205`) is the one
  exception: `MsgWaitForMultipleObjectsEx(.., INFINITE, ..)` is what the
  message pump *is*. That site carries an explicit
  `LINT-ALLOW: infinite-wait (message pump, responsiveness IS the wait)`
  marker.

## Why memory-based discipline fails

The 2026-04-26 cluster was not a single bug. Five independent layers
authored the same construction in five different idioms over the
project's lifetime. No reviewer caught it because reviewers were
looking at the local code, not at "what happens if this thread is the
UI thread and the consumer died."

Memory cannot hold that invariant across years of contributors. Two
durable defenses are needed:

- **Type-level prevention.** Where possible, remove the dangerous shape
  from the type system. Example: a hypothetical
  `BoundedMailbox<T, N, timeout_ms>` with no `.forever` constructor
  cannot express the bug. Pursue this opportunistically — refactors
  here pay back across the entire codebase.
- **Mechanical lint enforcement.** `tools/lint-deadlock.sh` greps for
  the four shapes that produced the cluster. CI (`.github/workflows/
  deadlock-lint.yml`) and `lefthook.yml` pre-push both run it. The lint
  is intentionally narrow — it covers the perimeter of files where
  `forever_push_audit.md` confirmed UI-thread reachability. Anything
  outside the perimeter is reviewed by hand.

Neither defense is sufficient alone. The lint catches what it can
phrase as a regex; everything else (pipe IO without timeout, custom
synchronization primitives, new third-party blocking APIs) requires the
PR template checklist + this document.

## Audit cadence

Every 6 months, file a tracking issue and:

1. Run `bash tools/lint-deadlock.sh --verbose` and resolve any new
   violations or warnings (fix, or add a `LINT-ALLOW` marker with an
   issue-referenced reason).
2. Manually review every existing `LINT-ALLOW` marker. If the cited
   issue / invariant no longer applies, remove the marker and let the
   lint re-evaluate.
3. Sweep new blocking call sites that the lint cannot catch (pipe IO,
   thread joins, custom sync primitives) with the PR template
   checklist as a guide.
4. Update [`notes/2026-04-26_forever_push_audit.md`](../notes/2026-04-26_forever_push_audit.md)
   if the perimeter has shifted (new apprt thread, new callback shape).

## What this document does NOT promise

The lint catches four mechanical shapes. The checklist catches what a
human reviewer remembers to look for. Together they make the 2026-04-26
class of bug expensive to re-introduce — they do **not** make all
deadlocks impossible. Lock-order inversions, priority inversions, and
async cancellation races are out of scope here; they require their own
analysis.

## References

- [`tools/lint-deadlock.sh`](../tools/lint-deadlock.sh) — the lint script
- [`notes/2026-04-26_deadlock_lint_rules.md`](../notes/2026-04-26_deadlock_lint_rules.md) — per-rule rationale
- [`notes/2026-04-26_forever_push_audit.md`](../notes/2026-04-26_forever_push_audit.md) — original 17-site audit
- Issues: #207, #169, #195, #218, #219, #220, #221, #222, #223, #224, #227 (this discipline meta)
