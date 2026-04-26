# Phase 2: `BoundedMailbox<T, capacity, default_timeout_ms>` design

Issue: YuujiKamura/ghostty#232 — meta: responsibility allocation + boundary
guards. This document is **design only**; no implementation lands in this
branch. The goal is to make `.forever = {}` *type-level impossible* so that
no future contributor can write the failure mode that produced the
2026-04-26 deadlock cluster (#218–#225, #207).

Phase 1 (responsibility doc) is out of scope here. Phase 3 (unified
shutdown bus) and Phase 4 (runtime defense layer) are referenced where they
intersect this design but are not designed in this document.

---

## 1. Problem restatement

`BlockingQueue(T, N).push(value, timeout: Timeout)` accepts a runtime tagged
union:

```zig
pub const Timeout = union(enum) {
    instant: void,   // non-blocking, drop on full
    forever: void,   // park forever (or until shutdown)
    ns: u64,         // park at most N ns
};
```

The `.forever` arm is the architectural defect. It is correct *in isolation*
on a worker thread whose consumer is liveness-guaranteed within the same App
lifecycle, but the type system makes it equally easy to write on the UI
thread, where it is fatal:

- #218: `Surface.focusCallback` → `mailbox.push(.{ .focus }, .forever)` from
  the UI thread → renderer mailbox saturated by CP polling →
  `cond_not_full.wait` indefinitely → `IsHungAppWindow=true` → message pump
  stops → window cannot be closed.
- #219: same shape, `occlusionCallback`.
- #220: `BlockingQueue.shutdown()` was missing entirely; producers parked
  on `.forever` survived consumer death.

`tools/lint-deadlock.sh` was landed as a stop-gap *grep* defence ("don't
write `.forever` from a function whose name matches `*Callback`"). That is
runtime-textual, not compile-time-structural; a renamed function or a new
indirection escapes it. Per #232 we want the contract enforced at the
**type system layer**.

The structural answer: **remove the `.forever` variant from the type**.
A producer that wants infinite-blocking semantics must spell that intent in
a different name (`pushTimeout(value, very_long_ms)` or
`pushUntilShutdown(value, shutdown_token)`) and that spelling must be
visibly different in code review. The default `push()` becomes always
bounded, with the bound either type-baked or call-supplied.

---

## 2. Type sketch — `src/datastruct/bounded_mailbox.zig`

Skeleton only. No `pub fn ... { ... }` bodies; signatures plus doc
comments. Naming follows the existing `BlockingQueue` style for symmetry.

```zig
//! Bounded mailbox for cross-thread message passing.
//!
//! Successor to `BlockingQueue` (see #232). The defining difference is that
//! the `.forever` timeout variant *does not exist*. Callers that need to
//! wait indefinitely must opt in via `pushUntilShutdown`, which requires a
//! shutdown token, making the lifecycle dependency explicit.
//!
//! Type parameters
//! ---------------
//!   T                    — message payload type
//!   capacity             — fixed ring-buffer slot count (compile-time)
//!   default_timeout_ms   — `?u32`. If non-null, `push` uses this as its
//!                          default bound; if null, `push` is a compile-
//!                          error and callers must use `pushTimeout`.
//!
//! `default_timeout_ms` lets each mailbox encode its own SLO at the type:
//!
//!   * UI → renderer mailbox  : `default_timeout_ms = 0`  (drop on full,
//!                              same semantics as today's `.instant`)
//!   * termio → renderer      : `default_timeout_ms = 5000`
//!   * worker → worker        : `default_timeout_ms = null`  (caller must
//!                              spell its own bound)
//!
//! Lifecycle
//! ---------
//! `shutdown()` inherits the semantics landed in #220: idempotent broadcast
//! that wakes every parked producer/consumer; subsequent operations
//! short-circuit with `.shutdown`.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PushResult = enum {
    /// Value was enqueued.
    ok,
    /// Queue was full at the bound; value was *not* enqueued.
    full,
    /// `shutdown()` has been called; value was *not* enqueued.
    shutdown,
};

pub const PopResult = union(enum) {
    /// A value was dequeued.
    value: anytype, // see implementation: actually `T`
    /// Queue was empty at the bound; no value.
    empty: void,
    /// `shutdown()` has been called; no value (drain remaining first).
    shutdown: void,
};

/// Opaque token broadcast by an `App`-scoped shutdown bus (Phase 3).
/// In Phase 2, callers may pass a `.never_signal` token to obtain
/// "wait until queue not full" with no external cancellation; this is
/// explicitly named so it shows up in code review.
pub const ShutdownToken = opaque {};

pub fn BoundedMailbox(
    comptime T: type,
    comptime capacity: usize,
    comptime default_timeout_ms: ?u32,
) type {
    return struct {
        const Self = @This();

        pub const Size = u32;
        pub const Capacity: Size = @intCast(capacity);
        pub const DefaultTimeoutMs: ?u32 = default_timeout_ms;
        pub const Payload = T;

        // --- lifecycle -------------------------------------------------

        /// Heap-allocate. Mirrors `BlockingQueue.create`.
        pub fn create(alloc: Allocator) Allocator.Error!*Self;

        /// Free. All producers/consumers must have exited (or `shutdown()`
        /// been called and observed) before this is called.
        pub fn destroy(self: *Self, alloc: Allocator) void;

        /// Idempotent. Wakes every parked producer/consumer; subsequent
        /// `push*` returns `.shutdown`, subsequent `pop*` drains remaining
        /// items then returns `.shutdown`.
        ///
        /// Inherits the contract from `BlockingQueue.shutdown()` (#220):
        /// the orchestrator that *knows* the consumer is gone calls this,
        /// freeing every parked producer.
        pub fn shutdown(self: *Self) void;

        /// Lock-free check.
        pub fn isClosed(self: *const Self) bool;

        // --- producer side --------------------------------------------

        /// Push using the type-baked default timeout.
        ///
        /// **Compile error** if `default_timeout_ms == null`. This forces
        /// the mailbox author to either bake the SLO into the type or
        /// require every callsite to spell its bound (`pushTimeout`).
        ///
        /// Behaviour for `default_timeout_ms == 0`: identical to today's
        /// `.instant` — non-blocking, returns `.full` on saturation. Use
        /// this for UI-thread → worker mailboxes (the #218 contract).
        ///
        /// Behaviour for `default_timeout_ms > 0`: bounded park on the
        /// not-full condvar; returns `.full` on timeout, `.shutdown` if
        /// the queue closes during the wait.
        pub fn push(self: *Self, value: T) PushResult;

        /// Push with an explicit per-call bound. Always available regardless
        /// of `default_timeout_ms`.
        ///
        /// `timeout_ms == 0` is non-blocking. `std.math.maxInt(u32)` ms
        /// is the longest legal wait (~49 days), which is finite and
        /// observable — i.e. not `.forever`. If you find yourself wanting
        /// "forever", reach for `pushUntilShutdown`.
        pub fn pushTimeout(self: *Self, value: T, timeout_ms: u32) PushResult;

        /// Push, parking until either (a) capacity frees, (b) `shutdown()`
        /// is called on this mailbox, or (c) the supplied shutdown token
        /// is signaled by an external authority.
        ///
        /// This is the *only* way to wait without a numeric bound, and the
        /// shutdown-token argument makes the lifecycle dependency
        /// syntactically obvious in code review.
        ///
        /// Recommended for: same-App-lifecycle worker→worker pushes where
        /// the consumer's death would already imply the producer's death,
        /// AND there is an App-scoped shutdown bus the token comes from.
        ///
        /// Forbidden by convention for: any function in the apprt callback
        /// surface (`*Callback`, `update*`, `activate*`, `deactivate*`).
        /// The lint introduced in Phase 2.4 enforces this.
        pub fn pushUntilShutdown(
            self: *Self,
            value: T,
            token: *const ShutdownToken,
        ) PushResult;

        // --- consumer side --------------------------------------------

        /// Non-blocking pop. Returns `.empty`, `.value{...}`, or
        /// `.shutdown` (only after the queue has drained).
        pub fn pop(self: *Self) PopResult;

        /// Bounded blocking pop. Symmetric with `pushTimeout`.
        pub fn popTimeout(self: *Self, timeout_ms: u32) PopResult;

        /// Bulk drain. Same semantics as `BlockingQueue.drain` — held
        /// mutex until the iterator's `deinit` is called.
        pub fn drain(self: *Self) DrainIterator;

        pub const DrainIterator = struct {
            // identical to BlockingQueue's
            pub fn next(self: *DrainIterator) ?T;
            pub fn deinit(self: *DrainIterator) void;
        };

        // --- introspection (for Phase 4 metrics) ----------------------

        /// Current depth. Lock-free best-effort.
        pub fn lenApprox(self: *const Self) Size;

        /// Total push attempts that hit `.full`. Useful for the contention
        /// metric Phase 4 will collect.
        pub fn fullDropCount(self: *const Self) u64;
    };
}
```

### Key non-obvious design choices

1. **`PushResult` is a 3-state enum, not `Size`.** `BlockingQueue.push`
   returns `Size` (queue depth after push, 0 = failure). That overloads
   "depth" with "did it succeed", and forces every callsite to either
   `_ = ...` or compare against zero. `PushResult` makes the three outcomes
   distinct names and forces callers to handle them via `switch` (Zig
   exhaustive-enum-switch is a real win here — see #224, where the
   platform mailbox needed an explicit drop-on-full path).

2. **`default_timeout_ms == null` is a compile error on `push`.** This is
   the structural lever. A mailbox author who genuinely wants every callsite
   to spell its own bound declares the type with `null`; nobody can later
   sneak in a one-arg `push()`. A mailbox author who knows the SLO bakes it
   in once and `push()` enforces it everywhere.

3. **`pushUntilShutdown` instead of `.forever`.** The semantics most
   `.forever` callsites *want* is "wait until either capacity frees or the
   consumer is provably gone". The current `.forever` provides this only via
   the `shutdown()` escape hatch landed in #220, but the type doesn't force
   the producer to acknowledge that escape hatch exists. `pushUntilShutdown`
   takes a `*const ShutdownToken` argument; you literally cannot call it
   without naming a shutdown source. In Phase 2 we accept a sentinel
   `.never_signal` token (well-named so it stands out in review); in Phase 3
   the App-scoped bus replaces it.

4. **Comptime SLO encoding.** Per-instance `default_timeout_ms` lets
   different mailbox sites declare different SLOs at the type:
   `BoundedMailbox(rendererpkg.Message, 64, 0)` for UI→renderer (drop on
   full), `BoundedMailbox(termio.Message, 64, 5000)` for termio→worker
   (5s bounded park), `BoundedMailbox(WorkerMessage, 64, null)` for
   anything where the call site is the right place to decide.

5. **Capacity stays comptime.** Same as `BlockingQueue` — supports
   stack-friendly fixed arrays and lets the compiler unroll bounds checks.

---

## 3. Existing `BlockingQueue` callsite census

Generated from `grep -rn 'BlockingQueue\|\.forever\|\.instant\|\.{ \.ns'
src/`. 7 files declare or import `BlockingQueue`; 13 distinct mailbox-style
sites use `.forever`. Roles below classify each producer thread and the
proposed `BoundedMailbox` type-parameter triple.

### 3.1 Mailbox declarations (5 distinct queues)

| File | Queue type | Capacity | Producers | Consumer |
|------|-----------|----------|-----------|----------|
| `src/App.zig:581` | `Mailbox.Queue = BlockingQueue(Message, 64)` | 64 | apprt UI threads, renderer thread (`redraw_surface`) | App thread (`drainMailbox`) |
| `src/renderer/Thread.zig:35` | `Mailbox = BlockingQueue(rendererpkg.Message, 64)` | 64 | UI thread (Surface callbacks), termio thread (resize, stream messages), search thread | renderer thread (`drainMailbox`) |
| `src/termio/mailbox.zig:14` | `Queue = BlockingQueue(termio.Message, 64)` | 64 | UI thread (some Surface paths), App thread, stream_handler (renderer thread for vt path) | termio thread (xev loop) |
| `src/terminal/search/Thread.zig:450` | `Mailbox = BlockingQueue(Message, 64)` | 64 | UI thread (search input), Surface (event handler) | search thread |
| `src/os/cf_release_thread.zig:30` | `Mailbox = BlockingQueue(Message, 64)` | 64 | renderer thread (font shaper) | cf_release thread (macOS only) |

### 3.2 `.forever` push sites (13 total, classified per the 2026-04-26 audit)

Reproduced and re-tagged from `notes/2026-04-26_forever_push_audit.md`.

**UI thread producers (#218-class, all proposed `default_timeout_ms = 0`
mailboxes):**

| File:Line | Push payload | Caller | Proposed migration |
|-----------|--------------|--------|--------------------|
| `Surface.zig:1465` | `search_viewport_matches` | search event handler (UI thread) | `push()` on `Mailbox<.., 64, 0>` → `.full` logged |
| `Surface.zig:1483` | `search_selected_match` | same | same |
| `Surface.zig:1492` | `search_selected` (surface mb) | same | `.full` logged + queueRender |
| `Surface.zig:1498` | `search_selected_match = null` | same | same |
| `Surface.zig:1504` | `search_selected = null` | same | same |
| `Surface.zig:1514` | `search_total` | same | same |
| `Surface.zig:1522,1526` | search-quit reset | same | same |
| `Surface.zig:1536,1540` | search-quit reset (surface mb) | same | same |
| `Surface.zig:5423,5435` | (app mailbox) | embedded host UI | `.full` logged |
| `apprt/embedded.zig:2117` | `macos_display_id` | host (macOS UI) | `.full` logged |
| `apprt/gtk/class/application.zig:1808` | `open_config` | gtk activation (UI) | `pushTimeout(.., 1000)` then log |
| `apprt/gtk/class/application.zig:1840` | (app mailbox) | gtk action (UI) | same |

**Worker thread producers (legitimate "consumer is same-App-lifecycle"
case, proposed `pushUntilShutdown` with App shutdown token):**

| File:Line | Push payload | Caller thread | Proposed migration |
|-----------|--------------|---------------|--------------------|
| `termio/Termio.zig:501` | `resize` | termio thread | `pushUntilShutdown(.., app_shutdown)` |
| `termio/stream_handler.zig:134` | fallback after `.instant` | termio thread (vt) | `pushTimeout(.., 5000)` — bounded; fallback on `.full` is to drop+log |
| `termio/stream_handler.zig:172` | fallback after `.instant` | termio thread (vt) | same |
| `termio/mailbox.zig:92` | fallback after `.instant` | renderer/termio | same |
| `termio/Exec.zig:299` | `child_exited` | termio (xev process cb) | `pushUntilShutdown(.., app_shutdown)` |
| `termio/Exec.zig:391` | termios timer | termio (xev timer) | same |
| `font/shaper/coretext.zig:288` | `release` | renderer thread | `pushUntilShutdown(.., app_shutdown)` |
| `renderer/generic.zig:1688` | (surface mailbox from renderer) | renderer thread | `pushTimeout(.., 5000)` |
| `terminal/search/Thread.zig:880` | test-only `.forever` | test fixture | leave; tests can use `pushTimeout(.., maxInt(u32))` |

### 3.3 Existing `.instant` sites (already correct, just need type renaming)

| File:Line | Notes |
|-----------|-------|
| `Surface.zig:928, 953` | inspector toggle, drop-on-full + queueRender |
| `Surface.zig:1833, 2621, 3504, 3538` | font_grid, occlusion (#219 fix), focus (#218 fix) |
| `Surface.zig:6028` | crash binding |
| `renderer/Thread.zig:514` | `redraw_surface` from renderer→app |
| `termio/mailbox.zig:70` | first-attempt before fallback |
| `termio/stream_handler.zig:131, 154` | first-attempt before fallback |

These map cleanly to `push()` on a `default_timeout_ms = 0` mailbox; no
behaviour change, just stronger types at the declaration site.

### 3.4 `.ns` sites

None at the moment; the audit found zero. (One test in
`blocking_queue.zig` itself uses `.{ .ns = 1000 }` as a fixture.) This
confirms the binary `.instant` / `.forever` polarisation that motivates the
phase-2 redesign.

---

## 4. Migration plan

### Phase 2.1 — Land `BoundedMailbox` alongside `BlockingQueue`

**Scope**

- Implement `src/datastruct/bounded_mailbox.zig` per §2.
- Re-export from `src/datastruct/main.zig`: `pub const BoundedMailbox = ...;`
- `BlockingQueue` stays. No callsite migration yet.

**Tests** (in `bounded_mailbox.zig`)

- `push() with default_timeout_ms = 0` returns `.ok` until full, then
  `.full`; never blocks. (Mirror of the `#218 drop contract` test in
  `blocking_queue.zig`.)
- `push() with default_timeout_ms == null` is a compile error (Zig
  `@compileError` test pattern; can be a `comptime if` skipped from the
  default test runner with a doc-test note).
- `pushTimeout(.., 0)` non-blocking equivalence to `default_timeout_ms = 0`.
- `pushTimeout(.., 100)` blocks at most 100ms then returns `.full`.
- `pushUntilShutdown(.., never_signal)` blocks until `shutdown()`, then
  returns `.shutdown`.
- `shutdown()` wakes every parked `pushTimeout` and `pushUntilShutdown`.
- `pop` / `popTimeout` symmetric tests.
- `PushResult` exhaustiveness test (a `switch` over all variants compiles).

**Exit criterion**: `BoundedMailbox` lands, all tests green, `BlockingQueue`
unchanged.

### Phase 2.2 — Pilot migration (1 callsite)

**Recommended pilot**: `src/renderer/Thread.zig:35` —
`pub const Mailbox = BlockingQueue(rendererpkg.Message, 64)`.

Rationale:

- Highest-traffic mailbox in the codebase (every Surface callback writes to
  it; the termio writer writes to it; the renderer drains every frame).
- All producers are well-classified (UI vs termio); Phase 1 responsibility
  doc work has already analysed this queue.
- Both `.instant` and `.forever` callsites coexist on it, so the migration
  exercises both `push()` (default_timeout_ms=0) and `pushTimeout`
  (worker→worker fallback).
- The #218 fix already replaced the most dangerous `.forever` site
  (`focusCallback`) with `.instant` — so type-renaming this queue makes the
  fix structural rather than reviewed-by-grep.

**Steps**

1. Replace declaration with
   `pub const Mailbox = BoundedMailbox(rendererpkg.Message, 64, 0);`
2. Convert UI-thread callsites (Surface.zig: focus, occlusion, font_grid,
   visibility, crash, inspector) from `.{ .instant = {} }` to `push()` —
   strip the timeout argument; handle `PushResult` via `switch`.
3. Convert worker-thread `.forever` callsites
   (`termio/stream_handler.zig:172`, `termio/Termio.zig:501`,
   `font/shaper/coretext.zig:288`, `renderer/generic.zig:1688`) to
   `pushTimeout(value, 5000)` with `.full` → log+drop fallback.
4. Audit each renamed callsite in PR review against the responsibility
   matrix (Phase 1).

**Tests**

- All existing `Surface` tests still pass.
- New regression test: under saturation, focus/occlusion drops, never
  blocks (existing #218 repro test in `blocking_queue.zig` ports over).
- New regression test: termio writer's bounded fallback returns `.full`
  after 5s if renderer is stalled (synthetic stall in test).

**Exit criterion**: `git grep '\.forever' src/renderer/ src/Surface.zig`
returns zero hits for renderer-mailbox pushes.

### Phase 2.3 — Remaining callsites

Migrate in order of risk surface:

1. `src/App.zig:581` (App mailbox) — `default_timeout_ms = 0` for UI
   producers. Worker fallback uses `pushTimeout(.., 1000)`.
2. `src/termio/mailbox.zig:14` — keep the existing `.instant`-then-fallback
   pattern; fallback becomes `pushTimeout(.., 5000)`.
3. `src/terminal/search/Thread.zig:450` — `default_timeout_ms = 0`.
   Test fixture at line 880 migrates to `pushTimeout(.., maxInt(u32))`.
4. `src/os/cf_release_thread.zig:30` — renderer→cf_release; both same App
   lifecycle. `pushUntilShutdown(.., app_shutdown)` once Phase 3 lands;
   until then, `pushTimeout(.., 5000)`.

**Tests per migration**

- Compile gate: every removed `.forever` reference is verified by
  `git grep '\.forever' src/` returning zero lines that aren't in
  `bounded_mailbox.zig` doc comments or in `blocking_queue.zig`.
- Behaviour gate: each migrated mailbox's existing tests still pass plus
  one new "saturation does not hang UI thread" test per UI-producer queue.

**Exit criterion**: `git grep 'BlockingQueue' src/` returns only
`src/datastruct/blocking_queue.zig` itself plus the deprecation re-export.

### Phase 2.4 — Deprecate / delete `BlockingQueue`

1. Mark `BlockingQueue` `pub` declarations with a `@compileError` shim if
   referenced from `src/` outside the file itself.
2. Update `tools/lint-deadlock.sh` to allowlist only `bounded_mailbox.zig`.
3. Delete `BlockingQueue` after one release cycle of green CI.

**Tests**

- CI lint: any new `import BlockingQueue` outside the deprecated file fails
  the build.
- Existing deadlock-lint allowlist shrinks to zero entries (the lint
  becomes obsolete; remove it in a follow-up).

**Exit criterion**: `BlockingQueue` deleted; `tools/lint-deadlock.sh`
either deleted or repurposed as a `.forever` keyword guard against
contributors importing it from a vendored copy.

---

## 5. Cases that resist clean migration

### 5.1 termio worker `.forever` push to renderer

Sites: `termio/Termio.zig:501` (`resize`),
`termio/stream_handler.zig:134, 172`, `termio/mailbox.zig:92`,
`termio/Exec.zig:299, 391`.

These run on the termio worker thread. The consumer (renderer) is bound to
the same `App` lifecycle: if the renderer dies, the App is in teardown and
the termio worker is being joined. A `.forever` push here will not produce
the #218 hang because the producer is not the message pump.

**Migration choices ranked**

1. **Preferred (Phase 3-aligned)**: `pushUntilShutdown(value,
   &app.shutdown_token)`. The shutdown bus broadcast on App teardown
   unblocks the producer; semantically identical to today's `.forever +
   queue.shutdown()` pattern landed in #220, but the lifecycle dependency
   is *visible at the callsite*.
2. **Bridge (Phase 2-only)**: `pushTimeout(value, 5_000)` with `.full` →
   log+drop. Adds a 5s ceiling on contention; under normal load the
   renderer drains in microseconds, so this should never trigger. If it
   does trigger we want to know — the warn log surfaces a real backpressure
   problem.
3. **Reject**: `pushTimeout(value, std.math.maxInt(u32))` — technically
   bounded (49 days) but semantically lying. Lint should flag this.

### 5.2 stream_handler `.instant`-then-`.forever` fallback

Pattern at `termio/stream_handler.zig:131-135` and `:154-172`: try
`.instant`, on failure release the renderer mutex, wake the renderer, then
`.forever` push.

The `.forever` here is not the failure mode #218 describes (it's a worker
thread, not UI). But it relies on the renderer eventually waking and
draining. With `BoundedMailbox`, this becomes:

```
push() → .full → unlock + wakeup + pushTimeout(value, 5_000)
                    → .ok | .full | .shutdown
```

If `pushTimeout` returns `.full` after 5s, the vt stream has *backpressure*
the renderer can't service. Today this is silently invisible. With the
bounded variant we surface it as a warn log and drop the message — a
*correctness regression* for vt output, but a *visibility win* on a real
problem. Phase 4's metrics layer turns this into a contention counter.

The legitimately load-bearing requirement is "never lose vt characters".
For that subset (raw stream bytes, not control messages), the long-term
right answer is a separate **byte-stream channel** with backpressure
propagated to `read()` on the pty, not a bounded mailbox at all. Out of
scope for Phase 2; flagged here as a known bridge limitation.

### 5.3 `cf_release_thread` (macOS)

`renderer → cf_release_thread` for `CFRelease`-on-worker semantics. Both
same App lifecycle. Migration target: `pushUntilShutdown` per §5.1 logic.
Until Phase 3, use `pushTimeout(.., 5000)` with `.full` → log; in steady
state this never triggers (cf_release drains as fast as the renderer pushes
font release ops).

### 5.4 Tests using `.forever`

`terminal/search/Thread.zig:880` and `blocking_queue.zig`'s own tests use
`.forever` as the natural way to say "wait for the worker to do its thing".
Replace with `pushTimeout(.., std.math.maxInt(u32))` and wrap the test
helper to make the intent clear, OR provide a test-only `pushBlocking`
helper inside the test module. No production exposure.

---

## 6. Alternative architectures considered

### 6.1 Go-style channels (MPSC / SPSC channel)

**Pros**

- Familiar mental model; producer/consumer asymmetry is type-encoded
  (`Sender<T>` vs `Receiver<T>`).
- `Sender::send` returns `Result`, naturally exhaustive.
- Multiple producers / multiple consumers expressible as type variants.

**Cons in Zig today**

- No language-level channel primitive; would need to be built atop
  `std.Thread.Mutex` and `std.Thread.Condition` exactly the way
  `BlockingQueue` is. Net structural change ≈ what `BoundedMailbox`
  already provides, with extra surface (Sender/Receiver halves) that
  doesn't pay rent for our use case (every queue in §3.1 is
  single-consumer, mostly single-producer).
- Doesn't solve the `.forever` problem on its own; a `Sender::send` that
  blocks forever is still the same bug.

**Verdict**: deferred. If we ever need MPMC routing the BoundedMailbox
abstraction can be reshaped into a Sender/Receiver pair without breaking
callsites that already use `push`/`pop`.

### 6.2 Erlang-style actor mailboxes

**Pros**

- Each thread *is* its mailbox; no separate type to wire up. Selective
  receive expresses "I'm waiting for message X" cleanly.
- Lifecycle and supervision tree formalised.

**Cons in Zig today**

- Requires runtime support for selective receive and pattern matching on
  message variants. Achievable manually but with significant overhead.
- Selective receive interacts badly with the existing `xev` event loop
  model; we'd be replacing the event loop, not augmenting it.
- Very large refactor — touches every thread entry point. Not aligned
  with #232's "bound the damage" framing.

**Verdict**: out of scope. The `pushUntilShutdown(token)` pattern borrows
the *good* part of actor model (explicit lifecycle dependency) without
forcing the runtime rewrite.

### 6.3 Async / await with cancellation tokens

**Pros**

- Cancellation-token shape is exactly what `pushUntilShutdown` needs.
- Future-proofs for Zig's evolving async story.
- `await mailbox.push(value, .{ .timeout = 5_000, .cancel = token })`
  reads naturally and is exhaustively typed via error union.

**Cons in Zig today**

- Zig's async support is in flux (post-0.11 reset). Building on it now
  risks stranding the design when the language semantics change again.
- The threads we have are OS threads bound to specific roles
  (renderer = GPU context owner, termio = pty owner, UI = HWND owner).
  Lifting them to async tasks doesn't match the underlying OS-resource
  affinity; we'd end up with `std.Thread.spawn` calling `await` against
  itself.
- Doesn't reduce the migration cost: every callsite still needs editing.

**Verdict**: design `BoundedMailbox` so the API is async-friendly (the
`PushResult` enum maps trivially to an async error union), but do not
require async to land it. Phase 5+ can lift to async if Zig's story
stabilises.

---

## 7. Open questions for Phase 3+

1. **App-scoped shutdown token shape**: opaque pointer vs atomic-bool
   vs std.Thread.ResetEvent. Phase 3 decision; Phase 2 punts via a
   `never_signal` sentinel.
2. **Per-mailbox SLO discovery**: should `default_timeout_ms` come from a
   single `App.config` rather than being a literal in the type
   declaration? Probably no — type-level is the *point*; runtime config
   would re-introduce the "I can change this from a far-away file" hazard.
3. **Lint repurposing**: once `tools/lint-deadlock.sh` becomes obsolete,
   does it morph into a "no `BlockingQueue` import" guard, or is the
   compile-error shim sufficient? Recommend compile-error shim only — fewer
   moving parts.

---

## 8. Summary

- New type `BoundedMailbox(T, capacity, default_timeout_ms)`, no
  `.forever` variant. The compiler refuses `default_timeout_ms = null`
  callers of bare `push()`; only `pushTimeout(value, ms)` and
  `pushUntilShutdown(value, token)` reach the runtime, and the latter
  *requires* a shutdown token argument by signature.
- 5 mailbox declarations and 13 `.forever` push sites to migrate. Pilot:
  `src/renderer/Thread.zig:35` (highest-impact, most scrutinised, both
  UI and worker producers).
- Worker-thread `.forever` sites (termio, cf_release, font shaper) move to
  `pushUntilShutdown` once Phase 3 lands the App-scoped shutdown bus;
  bridge with `pushTimeout(.., 5_000)` until then.
- Channel / actor / async alternatives evaluated; `BoundedMailbox` is the
  smallest delta that achieves the structural goal (`.forever` impossible
  to write).
