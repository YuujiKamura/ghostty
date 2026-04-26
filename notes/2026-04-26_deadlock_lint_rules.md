# `tools/lint-deadlock.sh` rule rationale (2026-04-26)

This script greps the tree for the four code shapes that produced the
2026-04-26 issue cluster (#218, #219, #220, #221, #222, #223). Every issue
in that cluster reduced to the same root pattern: **a thread that must
remain responsive performs an unbounded wait with no escape hatch**. The
specific Win32 / mailbox API differs per issue, but the failure mode is
identical (UI hangs forever, `IsHungAppWindow == TRUE`, the only recovery
is process kill).

The lint is intentionally narrow: it does not try to model thread
ownership. Instead it draws a perimeter around the files where unbounded
waits are *known* to be reachable on the apprt UI thread (via the
`forever_push_audit` cross-reference) and refuses any new ones inside that
perimeter. Anything outside the perimeter (renderer thread, termio thread,
xev callbacks) is out of scope and untouched.

## Rules

| Rule id            | Severity | What it forbids | Recommended fix |
|--------------------|----------|-----------------|-----------------|
| `forever-ok`       | error    | `BlockingQueue.push(.., .{ .forever = {} })` reachable on the UI thread (see scope below) | `.{ .instant = {} }` and drop+log on full, or a bounded `.{ .ns = N * std.time.ns_per_ms }` with retry |
| `infinite-wait`    | error    | `WaitForSingleObject` / `MsgWaitForMultipleObjectsEx` / similar with `INFINITE` | finite ms; treat `WAIT_TIMEOUT` as an escalation event |
| `overlapped-bwait` | error    | `GetOverlappedResult(.., bWait=TRUE)` in CP pipe code | `bWait=FALSE` polling + `WaitForSingleObject(event, finite_ms)` + `CancelIoEx` on timeout |
| `sendmessagew`     | warn     | `SendMessageW(...)` callsites | `SendMessageTimeoutW(.., SMTO_ABORTIFHUNG, ms, ..)` or `PostMessageW` if fire-and-forget |

### Per-rule context

#### `forever-ok` (issues #218, #219, #220)

`#218` was the canonical hang: `Surface.focusCallback` ran on the apprt
WinUI3 UI thread, called `mailbox.push(.{ .focus = focused }, .{ .forever
= {} })`, and waited indefinitely whenever the renderer thread was already
saturated. Six sibling sites with the same hang shape were enumerated in
[`notes/2026-04-26_forever_push_audit.md`](2026-04-26_forever_push_audit.md);
each is a separate issue but they all match this rule.

`#220` added the matching `BlockingQueue.shutdown()` so consumer death
breaks the wait deterministically; that fix is necessary but not
sufficient — the UI-thread producer must still avoid `.forever` for
correctness during normal operation.

Scope (matches the audit's UI-thread reach analysis):

- `src/Surface.zig`
- `src/apprt/winui3/`
- `src/apprt/win32/`
- `src/apprt/embedded.zig` (host UI thread enters via exported C
  functions)
- `src/apprt/gtk/class/application.zig` (gtk activation signal)

Worker-thread `.forever` calls (renderer / termio / coretext) are
deliberately out of scope. They are summarised in §"Sites NOT on the UI
thread" of the audit.

#### `infinite-wait` (issue #221)

`Command.wait` on Windows used `WaitForSingleObject(child, INFINITE)`. A
suspended / kernel-frozen child wedges this forever. The fix replaces
INFINITE with a polling loop that escalates after a budget; the lint
prevents the regression.

The Win32 message pump in `src/apprt/win32/App.zig:204-205` deliberately
uses `MsgWaitForMultipleObjectsEx(.., INFINITE, ..)` because the message
pump is the thread's reason for existing — there is no "responsiveness"
to preserve, the function *is* the responsiveness. That site is
allowlisted in the source itself (see §"Allowlist marker" below).

Scope: `src/Command.zig`, `src/apprt/winui3/`, `src/apprt/win32/`. The
`pub const INFINITE` definitions in the `os.zig` files are not callsites
and are filtered out automatically (the regex requires `(...INFINITE`).

#### `overlapped-bwait` (issue #222)

`vendor/zig-control-plane` previously used `GetOverlappedResult(handle,
&overlapped, &bytes, TRUE)` for writeAll on slow clients. When the client
dropped between `WriteFile` and `GetOverlappedResult`, the call hung
forever with no escape. The fix switched to `bWait=FALSE` polling +
`CancelIoEx` on timeout.

Scope: `vendor/zig-control-plane/src`, `src/apprt/winui3/`,
`src/apprt/win32/`. Currently zero hits — the rule exists to prevent the
regression.

#### `sendmessagew` (issues #169, #223)

`SendMessageW` is synchronous and inherits the destination thread's
responsiveness. When the destination is hung (which it tends to be in
exactly the conditions that motivate cross-thread messaging), the caller
hangs too. `#169` resolved one site by switching to `SendMessageTimeoutW`
with `SMTO_ABORTIFHUNG`; `#223` repeated the same fix for the drag bar.

This rule emits a warning (not an error) because intra-process
NCHITTEST/NC mouse forwarding inside `nonclient_island_window.zig` is
sometimes safe (the destination *is* the UI thread, and the thread is
already in WndProc handling that very message). Each site needs a
case-by-case decision: switch to `SendMessageTimeoutW` if the destination
could be a different thread or if the message could trigger user code,
or add `LINT-ALLOW: sendmessagew (reason)` if the synchronous semantics
are required.

Scope: `src/apprt/winui3/`, `src/apprt/win32/`. The `extern fn
SendMessageW(...)` declaration in `os.zig` is filtered out automatically.

## Allowlist marker

When a site genuinely needs the unbounded behaviour (debug-only crash
binding, self-pumping message loop, intentional NCHITTEST forwarding),
append the marker to the same line:

```zig
_ = mailbox.push(.{ .crash = {} }, .{ .forever = {} }); // LINT-ALLOW: forever-ok (debug-only crash trigger, never reached in release)
```

Format requirements:

- Marker must be on the same physical line as the offending construct.
  Multi-line statements should put the marker on the line that contains
  the literal pattern (`.forever = {}`, `INFINITE`, etc.).
- Rule id is mandatory and must match exactly (`forever-ok`,
  `infinite-wait`, `overlapped-bwait`, `sendmessagew`).
- Reason in parentheses is mandatory and must be non-empty. An empty
  `()` is rejected by the matcher.
- The reason should reference an issue number when one exists, or
  explain the thread-ownership invariant that makes the call safe.

The matcher regex is literally `LINT-ALLOW: <rule-id> \([^)]+\)`. If you
need the marker to span multiple lines, split the statement so the
literal sits on a single line.

## Existing violations snapshot (2026-04-26 main @ 31a0b70f5, before any allowlists land)

This snapshot is taken after the #218, #219, #220, #221, #222, #223
merge train. The Surface.zig forever-push family is already gone (#218
and #219 collectively fixed all 7 sites that the
`forever_push_audit.md` enumerated under "Sites called from the UI
thread"); the remaining violations are the cross-platform sibling sites
that the audit also called out plus the `Command.wait` legacy entry
that #221 deliberately left for the next pass.

```
== forever-ok (error) ==                                            2 hits
src/apprt/embedded.zig:2119                macos_display_id push (host UI thread)
src/apprt/gtk/class/application.zig:1462   gtk activate new_window push

== infinite-wait (error) ==                                         2 hits
src/Command.zig:476                Command.wait WaitForSingleObject (legacy entry; #221 added waitTimeout, callers should migrate)
src/apprt/win32/App.zig:205        message pump wait (intentional; should land allowlist marker)

== overlapped-bwait (error) ==                                      0 hits
(rule exists to prevent regression; #222 already fixed)

== sendmessagew (warn) ==                                           4 hits
src/apprt/winui3/nonclient_island_window.zig:531/540/551/573  NC hit-test forwarding to parent

Total: 4 violation(s), 4 warning(s)
```

The expected fate of each entry:

- `embedded.zig:2119` and `application.zig:1462` need separate audits;
  they are reached only via the macOS embedded apprt and the GTK
  apprt respectively, so the regression cost on Windows is currently
  zero but the structural pattern is identical to #218 and a future
  cross-platform fix should remove them. Until then the lint forces
  any new addition through an explicit allowlist + reason.
- `Command.zig:476` is the legacy `wait()` entry. #221 introduced
  `waitTimeout(ms)` as the safe replacement; remaining callers of
  `wait()` should be migrated and this site removed. Until then the
  lint correctly flags it as a hang risk.
- `apprt/win32/App.zig:205` is the message pump itself; it should land
  an allowlist marker (`// LINT-ALLOW: infinite-wait (message pump,
  responsiveness IS the wait)`) once the lint becomes blocking.
- The four `nonclient_island_window.zig` `SendMessageW` sites are
  intra-process NCHITTEST forwarding; the Windows Terminal codebase
  uses the same pattern. Each should either pick up
  `SendMessageTimeoutW` or land an allowlist marker after a
  thread-ownership review.

## What to do when the lint trips

1. **Default**: open an issue mirroring the #218..#223 pattern, link to
   this document, and fix at the source. The recommended fix is in the
   error message and in the table above.
2. **If the unbounded wait is intentional**: append `// LINT-ALLOW:
   <rule-id> (<reason>)` on the offending line. The reason should
   reference an issue number or explain the invariant.
3. **If the lint is wrong**: edit `tools/lint-deadlock.sh` and update
   this document in the same commit. Do not silence the lint by
   removing files from the scope without a paired audit update.

## Running the lint

```bash
# default (writes summary to stdout, exits 1 on violation)
./tools/lint-deadlock.sh

# verbose (also reports allowlist hits and skip decisions)
./tools/lint-deadlock.sh --verbose

# quiet (suppress headings; only violations + summary)
./tools/lint-deadlock.sh --quiet
```

## CI integration

- `lefthook.yml` runs the lint as a `pre-push` hook so violations are
  caught before they reach `fork`.
- `.github/workflows/deadlock-lint.yml` runs the lint on every push and
  PR that touches the in-scope paths.

Both entry points use the same script, so behaviour is identical between
local and CI runs.
