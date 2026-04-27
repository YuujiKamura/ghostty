# Mailbox Interface Design — 2026-04-27

Companion to `notes/2026-04-27_fork_isolation_audit.md` (audit P0 #1) and
issue #239. Replaces the naive "just relocate the file" plan that surfaced
during the first dispatch attempt: lint-passes-but-sprawls-anyway is the
failure shape this doc is written to prevent.

## Problem statement

Phase 2 (commits `4e661fcab` + `3ff0756d1`, landed 2026-04-27) introduced
`BoundedMailbox<T,N,timeout>` at `src/datastruct/bounded_mailbox.zig` and
migrated `renderer.Thread.Mailbox` to use it. The implementation is sound
(741 lines + 13 unit tests, kills `.forever` at the type level, fixes the
#218 hang shape), but it sprawled in three ways:

1. **STDLIB-WRAPPABLE violation**: the new type lives under `src/datastruct/`
   alongside upstream's `BlockingQueue`. Per the apprt contract (#238) it
   should live under `src/apprt/winui3/` because it is a fork-driven
   solution to a fork-driven problem (Win32 timing pushed UI-thread
   producers into `cond_not_full.wait`).
2. **CROSS-APPRT-CONTAMINATION**: `src/apprt/embedded.zig` was migrated to
   the new API. We do not build embedded apprt; the edit only buys a green
   build for code we never ship.
3. **Direct-import sprawl in upstream-shared core**: the type is referenced
   by name (`BoundedMailbox(...)`) inside `src/renderer/Thread.zig`, an
   upstream-shared file. Even after relocation, *the import stays in
   upstream-shared code*. That is sprawl-in-disguise: the lint script sees
   paths, not import structure, so a file move + UPSTREAM-SHARED-OK
   marker would technically pass — but every future contributor sees the
   `BoundedMailbox` name in upstream-shared core and concludes that's the
   pattern, perpetuating the sprawl.

The audit's "relocate" recommendation under-specified item 3. This doc
replaces it with structural enforcement: the *type name* `BoundedMailbox`
must not appear anywhere outside `src/apprt/winui3/`. Upstream-shared core
sees only an interface.

## Current state recap

```
src/datastruct/bounded_mailbox.zig       ← 741 lines, BoundedMailbox<T,N,t>
src/datastruct/main.zig                  ← re-exports BoundedMailbox, ShutdownToken,
                                           bounded_mailbox_never_signal
src/renderer/Thread.zig                  ← `pub const Mailbox = BoundedMailbox(rendererpkg.Message, 64, 0)`
                                           direct import + named reference
src/Surface.zig                          ← 13 callsites use `mailbox.push() == .ok`,
                                           `pushTimeout(., 5_000)`. PushResult enum
                                           is BoundedMailbox-specific.
src/termio/Termio.zig                    ← 2 callsites, same shape
src/termio/stream_handler.zig            ← 2 callsites, same shape
src/apprt/embedded.zig                   ← 1 callsite migrated (cross-apprt sprawl)
tests/repro_focus_mailbox_hang.zig       ← imports bounded_mailbox via -M flag
                                           (test build-system path; not source sprawl)
```

The renderer.Thread.Mailbox concrete type is defined at the
*upstream-shared boundary* (`src/renderer/Thread.zig`). Every consumer
reaches the type through `self.renderer_thread.mailbox` (a pointer-typed
field), so the *callsites* are already opaque w.r.t. the implementation.
What is NOT opaque:

- The PushResult/PopResult enum tags (`.ok`, `.full`, `.shutdown`,
  `.value`, `.empty`).
- The method names (`push`, `pushTimeout`, `pop`, `popOrNull`,
  `pushUntilShutdown`).
- The constructor (`Mailbox.create(alloc)` called from Thread.init).
- The type alias declaration in `Thread.zig` itself.

So the surface to abstract is:
- **Lifecycle**: `create(alloc) → *Self`, `destroy(*Self, alloc) void`.
- **Producer API**: `push(value) PushResult`,
  `pushTimeout(value, ms) PushResult`,
  `pushUntilShutdown(value, *ShutdownToken) PushResult`.
- **Consumer API**: `pop() PopResult`, `popOrNull() ?T`.
- **Shutdown**: `shutdown() void`.
- **Result enums**: `PushResult`, `PopResult`, `ShutdownToken`.

## Target architecture

### Interface shape: comptime-generic over impl + concrete `pub const Mailbox = ...` per apprt

After enumerating the four candidates (function pointer table, `anytype`
generic, comptime parameter, vtable struct), the right shape is **the
apprt module owns the concrete `Mailbox` type definition and exports it
under a stable name**. `renderer/Thread.zig` does not define `Mailbox`
at all; it imports it from the chosen apprt:

```zig
// src/renderer/Thread.zig (upstream-shared, no winui3 names)
const apprt = @import("../apprt.zig");
pub const Mailbox = apprt.runtime.RendererMailbox;
```

`apprt.runtime` is already comptime-resolved by `build_config.app_runtime`
(see `src/apprt.zig:44-53`). Each apprt module provides a
`pub const RendererMailbox = ...` that satisfies a documented duck-typed
interface (the surface listed above). winui3 binds it to BoundedMailbox;
gtk/macos/embedded bind it to upstream's BlockingQueue with a thin
adapter that maps the call shapes.

#### Why not function pointers / vtable struct?

- The renderer.Thread.Mailbox is allocated once per Surface and lives for
  the surface's lifetime. There is no need for runtime polymorphism — the
  apprt is fixed at compile time (`build_config.app_runtime` is comptime).
- Vtable dispatch costs an indirect call per `push`; on the hottest path
  (termio → renderer, every PTY read batch) this matters.
- Function pointers in Zig require explicit closure of `self`; the
  ergonomics are worse than method calls.

#### Why not `anytype` generic at every callsite?

- It works but pollutes every consumer signature. `pushTimeout(mailbox: anytype, ...)`
  is hostile to grep and to incremental migration.
- The interface contract is invisible — duck-typed `anytype` accepts any
  shape and fails late.

#### Why comptime-resolved concrete type per apprt?

- Same model upstream already uses for `apprt.App` and `apprt.Surface`
  (see `apprt.zig` `pub const runtime = switch ...`).
- Zero runtime dispatch cost (direct method call resolved at compile time).
- The interface is documented in one place (a comment block in
  `src/renderer/mailbox_interface.zig`, see below) and verified by a
  comptime check that asserts the chosen `apprt.runtime.RendererMailbox`
  exposes every required decl.
- Each apprt is free to choose its impl: winui3 uses the bounded type,
  gtk/macos/embedded keep BlockingQueue, future apprts add their own.

### Interface definition location

Two candidates:

1. `src/renderer/mailbox_interface.zig` — new file, contract-first.
2. Comment block at the top of `src/renderer/Thread.zig`.

**Pick #1.** The interface deserves its own file because it carries:
- The duck-typed signature documentation (what `push`, `pushTimeout`, etc.
  must look like).
- The result enum *shapes* (each apprt declares its own `PushResult` /
  `PopResult` enums but they must have the same tag set).
- A comptime `assertConformance(comptime Mailbox: type) void` helper that
  every apprt's `RendererMailbox` calls in a `comptime { _ = assertConformance(...) }`
  block, so non-conformance is a compile error at the apprt module's load
  time, not at the renderer's first call.

The new file is upstream-shared (`src/renderer/`), but it is *interface
only* — it contains no winui3 names, no Win32 calls, no platform-specific
behaviour. It is the same shape as `src/apprt/runtime.zig` (an interface
declaration in upstream-shared code that each apprt fulfils).

### apprt-side concrete impls

```
src/apprt/winui3/safe_mailbox.zig       NEW (was src/datastruct/bounded_mailbox.zig)
                                         exports BoundedMailbox<T,N,t>
src/apprt/winui3.zig                     adds: pub const RendererMailbox =
                                                   safe_mailbox.BoundedMailbox(
                                                       renderer.Message, 64, 0)
src/apprt/gtk.zig                        adds: pub const RendererMailbox =
                                                   datastruct.BlockingQueue(
                                                       renderer.Message, 64)
                                         (with a tiny adapter struct that
                                          maps `.push(v) .ok|.full|.shutdown`
                                          to BlockingQueue's
                                          `.push(v, .{ .instant = {} }) Size`
                                          return — see Migration §B for shape)
src/apprt/embedded.zig                   adds: pub const RendererMailbox = …
                                         same BlockingQueue adapter
src/apprt/win32.zig                      adds: pub const RendererMailbox = …
                                         (decision pending: BlockingQueue or
                                          BoundedMailbox? win32 has the same
                                          UI-thread blocking risk as winui3.
                                          Defer to win32 owner; default to
                                          BoundedMailbox to match winui3.)
src/apprt/none.zig                       adds: pub const RendererMailbox = …
                                         (test-only; pick BlockingQueue)
src/apprt/browser.zig                    adds: pub const RendererMailbox = …
                                         (wasm; pick BlockingQueue)
```

### Adapter shape for BlockingQueue-backed apprts

To keep upstream-shared callsites uniform, BlockingQueue-backed apprts
provide a tiny adapter that exposes the same surface as BoundedMailbox:

```zig
// src/apprt/gtk/blocking_renderer_mailbox.zig (new, ~80 lines)
pub fn BlockingRendererMailbox(comptime T: type, comptime N: usize) type {
    const BQ = datastruct.BlockingQueue(T, N);
    return struct {
        const Self = @This();
        inner: *BQ,

        pub const PushResult = enum { ok, full, shutdown };
        pub const PopResult = union(enum) { value: T, empty: void, shutdown: void };
        pub const ShutdownToken = struct { signaled: bool = false };

        pub fn create(alloc: std.mem.Allocator) !*Self { ... }
        pub fn destroy(self: *Self, alloc: std.mem.Allocator) void { ... }

        // Map `push(v) .ok|.full|.shutdown` to BQ's
        // `push(v, .{ .instant = {} }) Size` semantics. .shutdown is
        // unreachable on BQ unless we add the sister method (or just
        // never return .shutdown for the legacy adapter).
        pub fn push(self: *Self, v: T) PushResult { ... }
        pub fn pushTimeout(self: *Self, v: T, ms: u32) PushResult { ... }
        pub fn pushUntilShutdown(self: *Self, v: T, _: *ShutdownToken) PushResult { ... }
        pub fn pop(self: *Self) PopResult { ... }
        pub fn popOrNull(self: *Self) ?T { ... }
        pub fn shutdown(self: *Self) void { ... }
    };
}
```

This adapter makes upstream-shared callsites uniform without forcing
non-winui3 apprts to inherit BoundedMailbox's structural `.forever`
prevention (which they don't need — they were never affected by the
#218 hang shape).

### Injection point

No constructor injection is required. The apprt's `RendererMailbox` type
is comptime-resolved through `apprt.runtime`, the same way `App` and
`Surface` are. `renderer.Thread.init` calls `Mailbox.create(alloc)` and
gets back a pointer; that pointer's static type is `apprt.runtime.RendererMailbox`,
which is whichever concrete the apprt provides. No runtime hand-off, no
new Surface.init parameter.

The only Thread.zig change is the `pub const Mailbox` line:

```diff
- const datastruct = @import("../datastruct/main.zig");
- const BlockingQueue = datastruct.BlockingQueue;
- const BoundedMailbox = datastruct.BoundedMailbox;
- pub const Mailbox = BoundedMailbox(rendererpkg.Message, 64, 0);
+ const apprt = @import("../apprt.zig");
+ pub const Mailbox = apprt.runtime.RendererMailbox;
```

The `BlockingQueue` import is dead after the change (it was only used for
the `Mailbox` declaration). Remove it. No upstream-shared name leakage
remains.

## Migration plan

### Phase A — interface scaffolding (1 commit, scope `feat`)

1. Create `src/renderer/mailbox_interface.zig` with:
   - The interface contract documentation.
   - A `pub fn assertConformance(comptime M: type) void` comptime checker
     that asserts every required decl exists and matches signature.
2. No consumer changes yet. This phase is pure addition; nothing breaks.
3. Verify: `zig build -Dapp-runtime=winui3` PASS, no behaviour change.

### Phase B — apprt-side concrete bindings (1 commit, scope `feat`)

1. Add the BlockingQueue-backed adapter at
   `src/apprt/gtk/blocking_renderer_mailbox.zig` (or a shared place inside
   another apprt — gtk is the canonical "still uses BlockingQueue" apprt).
2. Add `pub const RendererMailbox` to each apprt module (winui3, gtk,
   macos, embedded, win32, none, browser, win32_replacement).
3. Each `RendererMailbox` declaration includes a
   `comptime { mailbox_interface.assertConformance(@This()); }` block.
4. winui3 binds to the *current* `src/datastruct/bounded_mailbox.zig`
   (relocation deferred to Phase C). This is fine because we're only
   adding declarations; nothing imports `RendererMailbox` yet.
5. Verify: build passes for `winui3`, `gtk`, `embedded` runtime selections
   (the latter two via `-Dapp-runtime=...` if available; otherwise just
   `zig build` which exercises lazy analysis).

### Phase C — switch consumers + relocate file (1 commit, scope `refactor`)

This is the load-bearing commit; it is the "before" → "after" transition
point.

1. Change `src/renderer/Thread.zig` to import `Mailbox` from
   `apprt.runtime.RendererMailbox`. Drop the direct `BoundedMailbox`
   import. Drop the now-dead `BlockingQueue` import if unused.
2. **Relocate** `src/datastruct/bounded_mailbox.zig` →
   `src/apprt/winui3/safe_mailbox.zig` (rename file + module header).
3. **Revert** `src/datastruct/main.zig` re-exports
   (`BoundedMailbox`, `ShutdownToken`, `bounded_mailbox_never_signal`).
4. Update `src/apprt/winui3.zig` `RendererMailbox` declaration to import
   from the new `safe_mailbox.zig` location.
5. Update `tests/repro_focus_mailbox_hang.zig` `-M` module flag in any
   driver script (run-script or `tests/winui3/run-all-tests.ps1`) to
   point at the new path. The test file's `@import("bounded_mailbox")`
   line stays unchanged because it's a named-module import; only the path
   passed at the `zig test` invocation changes.
6. Surface.zig / termio/* / stream_handler.zig callsites are *not touched*
   in this phase — they call methods on `self.renderer_thread.mailbox`,
   which has type `Mailbox` (still resolves to the same concrete via the
   new indirection). The methods (`push`, `pushTimeout`, etc.) and result
   tags (`.ok`, `.full`, `.shutdown`) are part of the interface, so they
   keep working unchanged.
7. Verify:
   - `zig build -Dapp-runtime=winui3` PASS.
   - `zig test src/apprt/winui3/safe_mailbox.zig` 13/13 PASS.
   - `zig test tests/repro_focus_mailbox_hang.zig` 7/7 PASS.
   - `bash tools/lint-fork-isolation.sh` against fork/main: NO violations
     in the changed files. The Thread.zig diff is the only remaining
     upstream-shared edit and it removes a winui3 name (cleanup), so the
     UPSTREAM-SHARED-OK marker for it explains "removing direct
     BoundedMailbox import; Mailbox now comes through apprt indirection
     per #239".
   - `bash tools/lint-deadlock.sh`: NO new violations.

### Phase D — revert cross-apprt contamination (1 commit, scope `refactor`)

1. Revert `src/apprt/embedded.zig` Phase 2.2 change. The display_id
   callsite returns to `.{ .instant = {} }) == 0` form. Embedded apprt's
   `RendererMailbox` is the BlockingQueue adapter declared in Phase B, so
   the call shape is `mailbox.push(v) PushResult` if we use the adapter
   API, OR `inner.push(v, .{ .instant = {} }) Size` if we expose the
   adapter's `inner` field for legacy-style callsites.
2. **Decision needed**: do legacy apprts call the adapter or call
   BlockingQueue directly?
   - *Option 1*: legacy apprts call the adapter API (`mailbox.push(v)
     == .ok`). This unifies callsites at the cost of one more
     wrapper method to write per platform.
   - *Option 2*: legacy apprts expose `inner: *BlockingQueue` and call
     legacy API. This keeps embedded.zig diff minimal but bifurcates the
     callsite vocabulary (`.ok` for winui3, `> 0` for legacy).
   - **Recommendation**: Option 1. Unifying the vocabulary is exactly
     what the interface buys us. Reverting embedded.zig means rewriting
     the callsite in interface terms, not in upstream-BlockingQueue
     terms. The "revert to upstream form" wording in the audit doc is
     misleading: what actually reverts is the *cross-apprt API
     dependency*, not the call form.
3. Verify:
   - Build still passes (winui3 + gtk smoke).
   - `git diff fork/main -- src/apprt/embedded.zig` shows ONLY the
     callsite change and any required UPSTREAM-SHARED-OK marker.

### Phase E — lock in (1 commit, scope `chore`)

1. Add a comptime forbidden-pattern check in `src/renderer/mailbox_interface.zig`
   that fails compilation if `BoundedMailbox` is named anywhere outside
   `src/apprt/winui3/`. Implementable via `@compileLog` + a
   `tools/lint-no-bounded-mailbox-leak.sh` script run in pre-push.
2. Update `tools/lint-fork-isolation.sh` documentation (the audit table
   in `notes/2026-04-27_fork_isolation_audit.md`) to record category
   moves: `src/datastruct/bounded_mailbox.zig` from MOVABLE to RELOCATED;
   `src/apprt/embedded.zig` from CROSS-APPRT-CONTAMINATION to RESOLVED.
3. Run audit again, expect MOVABLE 55 → 53 (or thereabouts).

## Risk assessment

### Zig generic / comptime concerns

- **Risk**: `apprt.runtime.RendererMailbox` is comptime-resolved through
  the same mechanism as `App` and `Surface`, but those are `struct`
  types whereas `RendererMailbox` is a *generic instantiation*
  (`BoundedMailbox(Message, 64, 0)`). Zig handles this fine — a generic
  return type IS a `type`-typed value — but the apprt module evaluates
  the instantiation at module load, which means the renderer's Message
  type must be in scope. Likely requires the apprt module to import
  `renderer.Message`, which it currently does not.
- **Mitigation**: import the message type in the apprt module. Cyclic
  imports between `apprt` and `renderer` are not introduced because the
  apprt only imports `renderer.Message` (a type), not `renderer.Thread`.
- **Fallback**: if the cycle bites, define `RendererMailbox` as a *generic
  fn* `fn (T: type, N: usize) type` and have Thread.zig instantiate it:
  `pub const Mailbox = apprt.runtime.RendererMailbox(rendererpkg.Message, 64);`.
  The default_timeout_ms parameter is awkward in this shape; we may need
  to encode it in the apprt's choice rather than at the call site.

### Performance concerns

- All dispatch is comptime-resolved; the generated code is identical to
  the current direct-call form. Zero runtime cost.
- The interface conformance check is `comptime { ... }` — it costs
  compile time, not runtime.
- The BlockingQueue adapter has one extra branch per `push` (mapping
  `Size` → `.ok | .full`), but this only fires for non-winui3 apprts
  which we don't profile.

### Renderer.Thread cycle

- `renderer.Thread` defines `Mailbox` as `apprt.runtime.RendererMailbox`.
  The apprt module defines `RendererMailbox` using a type that may
  reference `renderer.Message`. This forms a *type-only* cycle:
  `renderer/Thread.zig` → `apprt.runtime` → `renderer.Message`.
- Zig handles type-only cycles via lazy evaluation as long as no concrete
  function body in the cycle calls into the cycle synchronously at
  module-init time. The current code already has the cycle (Thread.zig
  imports apprt, apprt.zig imports each apprt module which may import
  renderer); we are not introducing a new edge, only a new field to an
  existing edge.
- **Mitigation**: if the cycle does bite, define `Message` in a separate
  `renderer/message.zig` file that has no other deps and import it from
  both `renderer.zig` and the apprt modules. This is a 30-minute
  refactor.

### Backwards compat for tests

- `tests/repro_focus_mailbox_hang.zig` imports `bounded_mailbox` via a
  named-module flag (`-Mbounded_mailbox=src/datastruct/bounded_mailbox.zig`).
  After Phase C the path becomes `src/apprt/winui3/safe_mailbox.zig`. The
  invocation script changes; the test source does not.
- `tests/repro_blocking_queue_consumer_death.zig` exercises BlockingQueue
  directly and is unaffected.

### Other apprts breaking

- gtk/macos/embedded RendererMailbox is the BlockingQueue adapter. We do
  not actively build these (per CLAUDE.md the fork ships winui3 only),
  but they should still compile. The adapter is small (~80 lines) and
  the conformance assertion catches missing/wrong signatures at compile
  time.

## Test plan

### Existing tests cover

- `src/apprt/winui3/safe_mailbox.zig` (formerly bounded_mailbox.zig):
  13 unit tests for the BoundedMailbox type itself. All pass after
  relocation (no semantic change).
- `tests/repro_focus_mailbox_hang.zig`: 7 tests, including 3 that assert
  `BoundedMailbox.PushResult` has no `.forever` variant (compile-time).
  Update -M flag to new path.
- `tests/repro_blocking_queue_consumer_death.zig`: unaffected.
- `tools/lint-deadlock.sh`: forbids `.forever` in mailbox push call sites.
  Should still find nothing after migration.

### New tests required

1. **Interface conformance test** (`src/renderer/mailbox_interface_test.zig`):
   for each apprt, instantiate the chosen `RendererMailbox` and run a
   minimal lifecycle (create → push → pop → destroy). Asserts the
   adapter (BlockingQueue-backed) exposes the same vocabulary as the
   native impl (BoundedMailbox-backed).

2. **No-leak lint** (`tools/lint-no-bounded-mailbox-leak.sh`):
   `git grep -n 'BoundedMailbox\b' src/ -- ':!src/apprt/winui3/'`
   must return zero hits. Wire into pre-push gate.

3. **Cross-apprt build smoke**: a CI-style script that runs
   `zig build -Dapp-runtime=gtk` (Linux-only, may skip on Windows host)
   and `zig build` (default) to catch adapter signature drift. Defer to
   the relocation PR's verification or a follow-up.

### Pre-push gate after Phase C

- `zig build -Dapp-runtime=winui3 -Drenderer=d3d11` PASS
- `zig test src/apprt/winui3/safe_mailbox.zig` PASS
- `zig test tests/repro_focus_mailbox_hang.zig` (with updated -M) PASS
- `zig test tests/repro_blocking_queue_consumer_death.zig` PASS
- `bash tools/lint-deadlock.sh` PASS
- `bash tools/lint-fork-isolation.sh` PASS (with markers / commit body)
- `bash tools/lint-no-bounded-mailbox-leak.sh` PASS (Phase E onwards)
- `pwsh -NoProfile -File tests/winui3/run-all-tests.ps1 -SkipBuild` PASS

## Maintainer self-check

> If upstream received `src/renderer/mailbox_interface.zig` as a PR,
> would they merge it?

**Probably yes.** The file is a 50-line interface declaration with no
platform names, no fork-specific behaviour, and a comptime conformance
check. It is the same shape as the existing `apprt.runtime` indirection.
Upstream may push back on the "do we even need this?" question, but the
answer ("we have one apprt that wants drop-on-full and structural
`.forever` prevention; rather than baking that into stdlib, we
parameterise the choice") is defensible.

> If upstream received `src/renderer/Thread.zig` (the `pub const Mailbox`
> indirection) as a PR, would they merge it?

**Probably yes.** It is a one-line change that swaps a direct
instantiation for an apprt-resolved one, mirroring `App` and `Surface`.

> If upstream received the BlockingQueue adapter as a PR, would they
> merge it?

**Probably no.** The adapter exists only to bridge legacy apprts to
the BoundedMailbox-shaped interface. Upstream would either reject it
("just keep using BlockingQueue directly") or counter-propose
collapsing the two types into one. Either way, the adapter is a
fork-internal cost, lives under `src/apprt/<platform>/`, and never
appears in upstream-shared core.

The interface design pays the maintainability cost (one indirection
file + one adapter per legacy apprt) in exchange for moving the
BoundedMailbox name entirely out of upstream-shared paths.

## Decision log

| Decision | Choice | Rationale |
|---|---|---|
| Interface shape | comptime-generic concrete per apprt | Zero runtime cost, matches existing `apprt.runtime` pattern |
| Interface location | `src/renderer/mailbox_interface.zig` (new) | Contract-first; avoids Thread.zig comment sprawl |
| Injection mechanism | comptime via `apprt.runtime` | No constructor parameter; mirrors App/Surface |
| Legacy apprt strategy | BlockingQueue adapter under `src/apprt/<platform>/` | Keeps callsite vocabulary uniform |
| Win32 apprt impl | BoundedMailbox (default) | Same UI-thread blocking risk as winui3; defer to win32 owner |
| Phase ordering | A→B→C→D→E (interface first, relocate last) | Each phase is independently revertable; Phase C is the only "load-bearing" transition |
| `BoundedMailbox` leak prevention | Comptime `@compileError` + grep lint | Defence-in-depth against future sprawl |

## Open questions for review

1. **Win32 apprt mailbox choice** — does win32 owner want BoundedMailbox
   semantics (drop on full, no `.forever`) or BlockingQueue legacy? Defer
   to owner; default to BoundedMailbox to match winui3.
2. **Adapter location** — put `BlockingRendererMailbox` under
   `src/apprt/gtk/` (canonical legacy apprt) or under a new shared path
   like `src/apprt/_legacy/blocking_renderer_mailbox.zig`? The latter
   acknowledges that multiple apprts share the adapter; the former
   accepts duplication if other apprts need divergent shapes.
3. **`Message` cycle** — extract `renderer.Message` to its own file
   pre-emptively, or wait for the cycle to actually bite? Pre-emptive
   extraction is ~30min and removes an entire risk class.
4. **Phase E forbidden-pattern check** — implement as a comptime
   `@compileError` (Zig-level) or a shell script (CI-level)? The shell
   script is faster to write and easier to skip in emergencies; the
   `@compileError` is unbypassable. Recommend: shell script first, escalate
   to comptime if a future commit slips past it.

## Estimate

- Phase A: 1-2h (interface file + conformance helper + smoke build)
- Phase B: 3-4h (5 apprt module updates + adapter + tests)
- Phase C: 2-3h (relocate + Thread.zig switch + verify all gates)
- Phase D: 1h (embedded.zig revert)
- Phase E: 1h (lint + audit doc update)
- **Total: 8-11h**, vs. the 4-6h naive relocate estimate. The extra
  effort buys structural enforcement; the naive plan only buys a green
  lint until the next refactor re-introduces the same sprawl.

## References

- Audit: `notes/2026-04-27_fork_isolation_audit.md` (P0 #1)
- Contract: `docs/apprt-contract.md` (#238)
- Lint: `tools/lint-fork-isolation.sh`
- Phase 2 commits: `4e661fcab`, `3ff0756d1`
- Issue: #239 (mailbox interface refactor)
- Pattern reference: `src/apprt/runtime.zig`, `src/apprt/surface.zig:135` (existing apprt-typed Mailbox)
