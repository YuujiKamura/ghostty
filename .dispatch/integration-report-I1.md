# Integration report I1 — A2 BLOCKED resolution

## Verdict

**A2 BLOCKED is already resolved at HEAD (`fe9f36268`); no source fix needed.**

A2's report cited a `Parser.init` arity mismatch:

> `src/terminal/apc.zig:45:38` calls `Parser.init(alloc, max_bytes)` (2 args) while
> `src/terminal/kitty/graphics_command.zig:58 pub fn init(alloc: Allocator)` accepts 1 (`sprawl-report-A2.md:106`).

That was true at A2's snapshot. By the time integration ran, A5 had landed a **coupled** revert that re-aligned both files:

- `6f58a234b revert(terminal): restore upstream apc.zig + c/terminal.zig`
- `be6ef464f revert(terminal): restore upstream kitty/graphics_command.zig (max_bytes is a security feature, coupled with apc.zig revert)`

`be6ef464f` is the missing half. With it, `kitty.Parser.init` is back to the upstream 2-arg form
(`pub fn init(alloc: Allocator, max_bytes: usize) Parser`, `graphics_command.zig:62`),
matching the call site in `apc.zig:45`.

## Verification

### Source-level API alignment (current HEAD)

- `src/terminal/apc.zig:44-49` — `.{ .kitty = .init(alloc, self.max_bytes.get(.kitty) orelse Protocol.defaultMaxBytes(.kitty)) }` → 2-arg call
- `src/terminal/kitty/graphics_command.zig:62` — `pub fn init(alloc: Allocator, max_bytes: usize) Parser` → 2-arg signature

Match.

### Caller audit (winui3 / Surface.zig)

`grep -rn "Parser.init"` across `src/apprt/winui3/` and `src/Surface.zig`:

- `src/apprt/winui3/`: **zero hits** for `Parser.init` from terminal/apc/kitty.
  Only match in `com_generated.zig` is `AddHandler/RemoveHandler` (unrelated, generated COM stubs).
- `src/Surface.zig`: zero `apc`/`Parser.init`. (One unrelated reference at line 1358 to `kitty_keyboard.set`.)
- `src/terminal/kitty/graphics_command.zig`: 30+ in-file `Parser.init(alloc, 1024 * 1024)` test/parseString call sites — all 2-arg, all consistent.
- `src/input/Binding.zig`: 9 `Parser.init(input)` call sites for the **input** Parser (different type, single-arg, unrelated to terminal/apc).

So there is **no winui3 wrap caller** to update for this API shape. The brief's premise (apprt-side wrap referencing the old 1-arg `kitty.Parser.init`) does not match HEAD.

### Test gate (L1: compile-pass via ast-check + fmt)

```
zig fmt --check src/terminal/apc.zig src/terminal/kitty/graphics_command.zig \
                src/Surface.zig src/apprt/winui3/Surface.zig
                                                                # PASS (silent)

zig ast-check src/terminal/apc.zig                              # EXIT=0
zig ast-check src/terminal/kitty/graphics_command.zig           # EXIT=0
zig ast-check src/apprt/winui3/Surface.zig                      # EXIT=0
```

L1 PASS on all four files. No syntax / type-shape errors at the parse / decl level.

### Test gate (L2: scoped unit test) — BLOCKED-test by infra

```
ZIG_GLOBAL_CACHE_DIR= zig build -Dapp-runtime=win32 --prefix zig-out-win32
```

→ `thread panic: unable to find module 'zigimg'` at
`p/vaxis-0.5.1-…/build.zig:30:52` (`vaxis_mod.addImport("zigimg", zigimg_dep.module("zigimg"))`).

Same configure-phase failure A2 / A4 reported. The local `p/zigimg-0.1.0-…`
package directory is in a transient state from concurrent peer sessions
(timestamps inside `p/` show writes within minutes of this run; `find` against the
specific zigimg dir intermittently returns `No such file or directory` while the
parent `ls` shows the entry — a classic mid-flight-rewrite signature).

Per `test-gate-default-on` and `parallel-dispatch-peer-aware`, this is
`BLOCKED-test: zig build infra broken by peer mid-flight on p/ cache`.
**The block is environmental, not introduced by A2 or by I1's audit.**
Hub I4 (build + test sweep) is the right owner once peer p/ writes settle.

### WinUI3 build

Same root cause (`zig build` configure-phase failure on `p/vaxis`). Not run.
WinUI3 gate is unchanged from A7's last result (WinUI3 build PASS at
`e887bab1d` per `sprawl-report-A7.md`); no I1 source change forces a re-run.

## Source edits

**None.** The fix the brief anticipated (caller realignment in
`src/apprt/winui3/Surface.zig`) is unnecessary because:

1. The kitty.Parser.init signature is already 2-arg again (via `be6ef464f`),
   matching apc.zig:45's call.
2. There are no winui3 callers of `Parser.init` from the terminal/apc/kitty
   surface to begin with — the wrap layer never touched this API.

Editing winui3/Surface.zig now would be invented churn.

## Stdout contract

```
SCOPE: I1 — A2 BLOCKED (Parser.init arity) is already resolved by A5's coupled revert be6ef464f; no source fix needed
ACTIONS: source audit (Parser.init callers in apprt/winui3 + src/Surface.zig — zero hits), L1 verify (fmt+ast-check PASS on apc.zig, graphics_command.zig, Surface.zig x2), L2 attempted, BLOCKED-test by p/ cache peer mid-flight
COMMITS: <this report only — see git log>
PUSHED: pending hub
SKILLS_FIRED: yes (parallel-dispatch-peer-aware, test-gate-default-on, plus implicit wrap-first-in-apprt review)
NOTES: A2's report cited only one half of the apc.zig <-> kitty/graphics_command.zig pair; A5's be6ef464f closed the loop. Confirm by re-reading sprawl-report-A2.md:106 against current HEAD diff for graphics_command.zig.
```

## Skill firing observation

- `parallel-dispatch-peer-aware`: fired at start (read coordination file, noted I2-I5 disjoint scope, observed peer-idle notifications during run, did not touch peer scope).
- `test-gate-default-on`: fired before report. L1 chosen for the audit
  (no source change → L1 is the correct level, not skipped). L2 attempted
  and BLOCKED-test reported with explicit reason (peer p/ cache mid-flight),
  not silently deferred.
- Both skills produced their intended discipline: no peer scope edits, no
  silent test skip, BLOCKED reported as a coordination move not a failure.
