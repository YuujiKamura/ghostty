# Font Backend Interface Design — 2026-04-27

Companion to `notes/2026-04-27_fork_isolation_audit.md` and the apprt
contract refactor (#238 / #239). This document is the **design spec** for
the font subsystem refactor; no code changes accompany it. A separate
implementation agent will execute the migration after this design is
reviewed.

## Why this document exists (not "just move the files")

The naive plan was to relocate the DirectWrite-related NEW files
(`src/font/directwrite.zig`, `src/font/dwrite_generated.zig`,
`src/fontconfig/windows/*`, `src/os/fontconfig_env.zig`) under
`src/apprt/winui3/font/` and slap `// UPSTREAM-SHARED-OK` markers on the
imports that survive in `src/font/discovery.zig` and
`src/font/DeferredFace.zig`.

That approach was tried in this branch's first attempt and rejected by
the coordinator. Reasons:

1. **Lint sees paths, not import structure.** A relocated file imported
   from upstream-shared code via a long relative path
   (`@import("../apprt/winui3/font/directwrite.zig")`) will satisfy the
   lint, but the structural coupling is unchanged: `src/font/discovery.zig`
   still names DirectWrite by symbol, still gets edited every time
   DirectWrite changes, still needs the marker. The contract is "fork-owned
   code does not leak into upstream-shared types," and a name-resolved
   import IS a type leak.
2. **Future agents will re-sprawl.** With the markers in place, the next
   bug fix that adds a sixth field to `DirectWriteFace` will quietly add
   a sixth conditional in `DeferredFace.zig` because the path is already
   greased. The contract erodes by precedent.
3. **Lint exists to force the conversation, not to make the decision.**
   `docs/apprt-contract.md` is explicit: judgment is human. The marker
   approach exports the conversation back to the lint, which can't have
   it.

The correct enforcement is structural: `src/font/discovery.zig` and
`src/font/DeferredFace.zig` reach the DirectWrite implementation only
through an interface that does not mention DirectWrite by name. apprt
provides the concrete impl via dependency injection.

## 1. Current state — what we added to upstream-shared paths

### NEW files (all introduced for the WinUI3 freetype-on-Windows path)

| Path | Lines | Purpose |
|---|---|---|
| `src/font/directwrite.zig` | 698 | Hand-written DirectWrite discovery + face wrapper. Exposes `init`, `deinit`, `discover`, `discoverFallback`, `DirectWriteFace { deinit, hasCodepoint, familyName, name, load }`, `DiscoverIterator`. |
| `src/font/dwrite_generated.zig` | 3192 | `win-zig-bindgen` output: COM vtables for IDWriteFactory/IDWriteFontCollection/IDWriteFontFace/etc. Pure data, no other-module imports. |
| `src/fontconfig/windows/fonts.conf` | 18 | Windows-runtime fontconfig defaults. |
| `src/fontconfig/windows/conf.d/60-cjk-prefer-japanese.conf` | 53 | CJK fallback ordering. |
| `src/fontconfig/windows/conf.d/README` | 2 | Notes. |
| `src/os/fontconfig_env.zig` | 111 | Resolves `FC_FILE` / `FONTCONFIG_PATH` env values for bundled config. Exposes `Resolved`, `EnvVars`, `resolve`, `buildEnvVars`. |

### MODIFIED upstream-shared files

| File | Hunks | What was added | Why |
|---|---|---|---|
| `src/font/discovery.zig` | +7/-1 | `pub const directwrite = @import("directwrite.zig")` (Windows only); `Discover = .freetype => DirectWrite on Windows`. | Made the upstream `freetype` discovery arm route to DirectWrite on Windows so callers (`SharedGridSet`, `CodepointResolver`, `cli/list_fonts`) get a real discoverer instead of `void`. |
| `src/font/DeferredFace.zig` | +40/-11 | New `dw: ?DirectWriteFace` field, gated on `has_directwrite` comptime; new arms in `deinit`/`familyName`/`name`/`load`/`hasCodepoint` switch statements that delegate to `dw` under `.freetype` backend on Windows. Renamed local `discovery` test variable to `disco` to avoid shadowing the new module-level import. | DeferredFace is upstream's per-face state container. Adding a peer field next to `fc`/`ct`/`wc` was the path of least resistance to add a fourth backend without rewriting the dispatch. |
| `src/font/face.zig` | +1/-1 | `.none, .win32 => void` instead of `.none => void` in the `getGObjectType` switch arm. | Declares that the win32 apprt also has no GObject type. Strictly an apprt declaration, not DirectWrite-specific. |
| `src/font/shaper/harfbuzz.zig` | +1/-0 | `@setRuntimeSafety(terminal.options.slow_runtime_safety)` inside the per-glyph loop in `Shaper.shape`. | Performance tweak for the hot loop. Not DirectWrite-specific; cross-cutting build-mode plumbing. |

`src/global.zig` also imports `os/fontconfig_env.zig` directly:
- `const fontconfig_env = @import("os/fontconfig_env.zig");`
- usage at `self.resources_dir.app() ... fontconfig_env.buildEnvVars(...)` to set `FC_FILE`/`FONTCONFIG_PATH` before fontconfig loads. Gated on `build_config.font_backend.hasFontconfig()`, which currently is `true` for any backend that links fontconfig — including builds where the freetype-on-Windows path actually wants different env handling than a Linux fontconfig build.

Note: `src/os/main.zig` re-exports `fontconfigEnv = fontconfig_env.resolve` and `FontconfigEnv = fontconfig_env.Resolved` but **nothing in the tree consumes those symbols today** (verified by grep). The re-exports are dead.

## 2. Current call structure

How a font lookup currently flows on Windows + freetype backend:

```
src/font/main.zig
  pub const Discover = discovery.Discover  ────────┐
                                                   │
src/font/discovery.zig                             │
  pub const directwrite = @import("directwrite.zig")
  pub const Discover = switch (backend) {
    .freetype => if (windows) DirectWrite else void,  ← directly named
    ...
  }                                                │
                                                   ▼
src/font/SharedGridSet.zig (and cli/list_fonts.zig, CodepointResolver.zig)
  var disco = font.Discover.init();
  var it = try disco.discover(alloc, descriptor);
  while (try it.next()) |def| { ... }              │
                                                   ▼
src/font/directwrite.zig                           │
  pub fn discover(...) -> DiscoverIterator         │
  pub const DiscoverIterator = struct {            │
    pub fn next() !?DeferredFace { ... fills .dw field ... }
  }                                                │
                                                   ▼
src/font/DeferredFace.zig                          │
  dw: ?discovery.directwrite.DirectWriteFace = null,  ← named again
  pub fn load(...) {                               │
    .freetype => if (has_directwrite) self.dw.?.load(...)
  }                                                │
  pub fn hasCodepoint, familyName, name, deinit — same shape
                                                   ▼
                              FreeType Face (rendering happens here)
```

The DirectWrite name appears twice in upstream-shared code:
1. `src/font/discovery.zig:17` (the import) — pulls in the module.
2. `src/font/DeferredFace.zig:34` (the field type) — fixes the field
   layout based on the imported type.

Every other reference is via comptime conditional on `has_directwrite`
or on the `discovery.directwrite.*` namespace, but those all transitively
depend on those two names.

The fontconfig env path is similar:
- `src/global.zig:6` — direct `@import("os/fontconfig_env.zig")`.
- `src/global.zig:180` — direct `fontconfig_env.buildEnvVars(...)` call
  inside `GlobalState.init`.

There is no apprt-level indirection; upstream-shared init code
literally calls into our fork-owned helpers.

## 3. Target architecture

### 3.1 Interface location

Add `src/font/Backend.zig` as the contract upstream-shared font code
talks to. The existing `src/font/discovery.zig` keeps its descriptor
types and the upstream `Fontconfig`/`CoreText` discoverers, but the
"native discoverer for the current target" is no longer a switch over
`backend` — it's a value that the apprt hands in.

### 3.2 Interface shape: function pointer table (vtable)

Two candidates:

a. **Comptime-parameterized `Discover(BackendImpl)`** — fits the existing
   pattern (most of `src/font/` is comptime-parametric on `options`). Zero
   runtime cost. Downside: `BackendImpl` must be reachable at comptime
   from every translation unit that touches a `Discover` value, which
   recreates the import-name leak problem in disguise (the comptime type
   has to come from somewhere).

b. **Runtime vtable: `pub const Backend = struct { ptr: *anyopaque, vtable: *const VTable }`** — apprt code constructs a concrete impl, packages it as a `Backend`, and hands it to upstream-shared font init. Upstream-shared code only ever sees the `Backend` type.

**Pick (b) — runtime vtable.** Rationale:

1. The font hot path is shaping (HarfBuzz), not discovery. Discovery
   happens at startup and on fallback misses; vtable cost is invisible.
2. (a) would leak the apprt-side type into every comptime-parametric
   call site (`SharedGridSet`, `CodepointResolver`, `list_fonts`),
   forcing them all to thread the type parameter. That is the bigger
   refactor.
3. (b) lets `src/font/Backend.zig` be 100% upstream-clean: it declares
   the vtable shape and the `DeferredFace.Native` opaque slot but does
   not name DirectWrite, CoreText, or fontconfig directly.

Sketch:

```zig
// src/font/Backend.zig — UPSTREAM-CLEAN, no apprt names
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (*anyopaque) void,
        discover: *const fn (*anyopaque, Allocator, Descriptor) Error!Iterator,
        discoverFallback: *const fn (*anyopaque, Allocator, Descriptor, *Collection) Error!Iterator,
    };

    pub const Iterator = struct {
        ptr: *anyopaque,
        vtable: *const IteratorVTable,
        // ...
    };

    pub const NativeFace = struct {
        // Opaque storage for the apprt-specific per-face state.
        // Sized to fit the largest known impl (currently DirectWriteFace
        // ~ 3 pointers). Asserted via comptime size check at impl-side.
        storage: [4 * @sizeOf(usize)]u8 align(@alignOf(usize)),
        vtable: *const FaceVTable,
    };

    pub const FaceVTable = struct {
        deinit: *const fn (*NativeFace) void,
        hasCodepoint: *const fn (*const NativeFace, u32) bool,
        familyName: *const fn (*const NativeFace, []u8) Error![]const u8,
        name: *const fn (*const NativeFace, []u8) Error![]const u8,
        load: *const fn (*NativeFace, Library, face.Options) Error!Face,
    };
};
```

`DeferredFace.zig` then has a single new field:

```zig
native: ?Backend.NativeFace = null,
```

instead of `fc`/`ct`/`wc`/`dw` peer fields. The dispatch in `deinit`,
`familyName`, `name`, `load`, `hasCodepoint` becomes a single
`if (self.native) |*n| return n.vtable.X(...)` and the existing
`fc`/`ct`/`wc` arms are subsumed (Phase B in §4 — we move CoreText and
fontconfig discoverers behind the same vtable).

Compromise: the per-face slot is `[4 * usize]` opaque storage. Using
`*anyopaque + alloc` would be cleaner but adds an allocation per
discovered face; inline storage matches today's perf characteristics.
A `comptime assert` at impl construction site catches overflow.

### 3.3 apprt-side concrete impl

```
src/apprt/winui3/font/
  directwrite.zig         ← relocated, implements Backend.VTable
  dwrite_generated.zig    ← relocated, leaf import (no upstream)
  fontconfig_env.zig      ← relocated
  fontconfig/
    fonts.conf
    conf.d/
      60-cjk-prefer-japanese.conf
      README
  backend.zig             ← NEW: wraps directwrite.zig as Backend
```

`src/apprt/winui3/font/backend.zig` exposes:

```zig
pub fn create(alloc: Allocator) !*Backend {
    // Allocate DirectWrite, wrap as Backend, return.
}
pub fn destroy(b: *Backend) void { ... }
```

Other apprts:

- **gtk**: `src/apprt/gtk/font/backend.zig` → wraps upstream's
  `discovery.Fontconfig`. Today gtk consumes `discovery.Fontconfig`
  directly; we re-route through the vtable.
- **macos / embedded with macos**: `src/apprt/macos/font/backend.zig` →
  wraps `discovery.CoreText`. Same shape.
- **none / web_canvas / non-discovery builds**: `Backend = null` is a
  valid state; upstream-shared code already handles
  `if (font.Discover == void)` today and would handle `if (backend ==
  null)` analogously.

### 3.4 Injection point

Today, font discovery is implicit: `font.Discover.init()` is called
ad-hoc from `SharedGridSet`, `CodepointResolver`, `cli/list_fonts`, and
`cli/show_face` — a static type lookup. After the refactor it must be
explicit data.

Recommended injection: **App init time, into a field on `App`**.

- `src/App.zig` already constructs `apprt.runtime`. Right after, ask
  the apprt for its font backend: `app.font_backend = try
  apprt.runtime.fontBackend(alloc);`
- Plumbing: `apprt.runtime` (currently a struct selected by
  `build_config.app_runtime`) gains a `pub fn fontBackend(alloc:
  Allocator) !?*font.Backend` method. Each apprt provides its own
  implementation; apprts that don't have a discoverer return `null`.
- Consumers: `SharedGridSet` already takes config + an allocator at
  construction; thread the backend in alongside. `CodepointResolver`
  is owned by `SharedGrid`; same. `cli/list_fonts` and `cli/show_face`
  build their own `App`-equivalent; they can ask the apprt directly.

This makes the dependency graph one-way: `apprt/winui3/` depends on
`font/Backend.zig`, never the reverse.

### 3.5 fontconfig env handling

`src/global.zig`'s call to `fontconfig_env.buildEnvVars` is
WinUI3-specific in practice (no other apprt ships bundled fontconfig
data and needs `FC_FILE`/`FONTCONFIG_PATH` set before fontconfig load).

Move the env-setup into the WinUI3 apprt's bootstrap path. A clean
location: `src/apprt/winui3/bootstrap.zig` already exists; have it call
into `apprt/winui3/font/fontconfig_env.zig` during early init, before
`global.zig` runs the fontconfig-dependent path.

If the timing is awkward (global init order vs apprt bootstrap),
fallback option: `src/global.zig` calls
`apprt.runtime.preFontconfigInit(alloc, resources_dir)` (a no-op for
non-WinUI3 apprts). This keeps the call site upstream-shared but the
DOING is apprt-side.

The dead `os.fontconfigEnv` / `os.FontconfigEnv` re-exports in
`src/os/main.zig` get reverted as part of this work (returns
`src/os/main.zig` to upstream-clean).

## 4. Migration plan

### Phase A — define interface (no behaviour change)

- Add `src/font/Backend.zig` with the vtable shape above.
- Add `src/apprt/winui3/font/backend.zig` that wraps the existing
  in-tree `src/font/directwrite.zig` (without moving it yet).
- `src/font/discovery.zig` keeps the current `directwrite` import; the
  vtable wrapper is additive.
- Add `apprt.runtime.fontBackend(alloc)` method; for now it returns
  `null` for every apprt (so consumers fall back to today's
  `font.Discover.init()` static path).
- Build, smoke test (no diff in behaviour).

Effort: 4-6h. Deliverable: new files only, zero modifications to existing
upstream-shared font code.

### Phase B — refactor consumers to use the interface

- `SharedGridSet` and `CodepointResolver` accept a `?*Backend` at
  construction. When non-null, use it; when null, fall through to
  current `font.Discover` path (still works during the transition).
- Switch `cli/list_fonts` and `cli/show_face` to ask the apprt.
- Switch `App.init` (or the apprt bootstrap) to construct the backend
  and pass it to grid construction.
- `apprt.runtime.fontBackend()` for winui3 now returns the wrapped
  DirectWrite; gtk/macos still return `null`.

Effort: 6-10h. Deliverable: WinUI3 builds run discovery through the
vtable path; other apprts unchanged.

### Phase C — relocate NEW files, eliminate upstream-shared imports

- `git mv src/font/directwrite.zig src/apprt/winui3/font/directwrite.zig`
- `git mv src/font/dwrite_generated.zig src/apprt/winui3/font/dwrite_generated.zig`
- `git mv src/fontconfig/windows/* src/apprt/winui3/font/fontconfig/`
- `git mv src/os/fontconfig_env.zig src/apprt/winui3/font/fontconfig_env.zig`
- Update `src/build/GhosttyResources.zig` to read fontconfig from the
  new path. (`GhosttyResources.zig` is itself
  upstream-shared but the audit notes legitimate apprt-extension
  edits are expected there; document with self-check, no marker.)
- Update `src/global.zig` to call apprt bootstrap instead of
  importing `os/fontconfig_env.zig` directly.
- Revert `src/os/main.zig` re-exports.
- Revert `src/font/discovery.zig` to upstream-clean — the
  `directwrite` import is gone.
- Revert `src/font/DeferredFace.zig` `.dw` field and the comptime
  branches in `deinit`/`load`/`familyName`/`name`/`hasCodepoint` —
  they are now subsumed by `native: ?Backend.NativeFace`.

Effort: 3-5h. **No `UPSTREAM-SHARED-OK` markers needed** because
upstream-shared font code no longer names DirectWrite at all.

### Phase D — port CoreText and Fontconfig discoverers behind the same vtable (optional, follow-up)

- `src/apprt/macos/font/backend.zig` wraps `discovery.CoreText`.
- `src/apprt/gtk/font/backend.zig` wraps `discovery.Fontconfig`.
- Eventually: `discovery.zig` no longer needs `Discover` at all; it
  becomes a pure container of `Descriptor` and shared types. The
  apprt-specific discoverers can move out of `src/font/` entirely.

This phase is BEYOND the audit's "MOVABLE" line item but is the natural
end state. Decoupled from this PR.

## 5. Risk assessment

### 5.1 HarfBuzz `@setRuntimeSafety`

The +1/-0 in `src/font/shaper/harfbuzz.zig` is `@setRuntimeSafety(
terminal.options.slow_runtime_safety)`. This is **not DirectWrite-related**;
it is a build-mode plumbing that uses an upstream comptime constant
(`terminal.options.slow_runtime_safety`) to gate runtime checks in a hot
loop. Genuinely cross-cutting. Two options:

- (a) Leave it with `// UPSTREAM-SHARED-OK: shaper hot-loop runtime-safety control is fork-policy until upstream accepts a slow_runtime_safety toggle PR (#239)`. Honest framing: we do not propose upstream PRs (`docs/apprt-contract.md`), so the marker is permanent.
- (b) Revert it and accept the perf cost in slow-safety builds. Measure impact first.

Recommendation: keep with marker. The change is one line, the
`terminal.options.slow_runtime_safety` flag is already upstream-defined,
and the only "edit" is opting one more loop into it. This is the kind of
genuinely-impossible-to-wrap modification the marker is meant for.

### 5.2 fontconfig_env reuse by other Windows apprts

`src/apprt/winui3/font/fontconfig_env.zig` is portable across any
Windows apprt that bundles fontconfig data (today: only WinUI3;
hypothetically: a future Win32 apprt with its own fontconfig path).

If a Win32 apprt grows the same need, it should depend on the WinUI3
location via a deliberate import (`@import("../winui3/font/fontconfig_env.zig")`)
or — cleaner — we extract a `src/apprt/win32_shared/font/fontconfig_env.zig`.
Defer until a second consumer exists; YAGNI.

### 5.3 Performance impact of vtable dispatch

The vtable adds one indirect call per `discover`, `discoverFallback`,
`hasCodepoint`, `familyName`, `name`, `load`. None of these are in the
glyph-rendering hot loop:

- `discover` / `discoverFallback`: at startup and on font fallback
  cache miss. Microseconds vs seconds.
- `hasCodepoint`: per fallback codepoint resolution, already behind a
  fallback cache.
- `load`: once per face lifetime.
- `familyName` / `name`: diagnostic, not on hot path.

Indirect call cost: ~1ns on modern x86 with branch prediction. Total
budget impact: undetectable. The hot loop (`harfbuzz.shape`) does not
touch the vtable.

### 5.4 face.zig `.win32` arm

The `+1/-1` in `src/font/face.zig` adds `.win32` to a `.none =>` arm in
`getGObjectType`. This is an apprt-declaration edit (we declared a
win32 apprt to upstream's switch table), not a font-specific
modification. It is the same shape as the dozens of expected
`apprt.zig` / `apprt/runtime.zig` etc. edits the audit lists under "apprt
interface adaptations" (P1, manual review).

Recommendation: leave as-is. It's a one-token addition to an enumeration
upstream owns; the only alternative would be a wrapper enum which is
worse. Marker not strictly required since the lint will treat this
file's modification under the "apprt extension" carve-out — but if lint
flags it, mark it `// UPSTREAM-SHARED-OK: win32 apprt declaration`.

## 6. Test plan

After Phase C lands, validate that the WinUI3 build still finds and
renders fonts correctly.

### Mechanical checks (must all pass)

1. `./build-winui3.sh` — clean compile.
2. `pwsh -NoProfile -File tests/winui3/run-all-tests.ps1 -SkipBuild`
   — full UIA smoke suite, currently 9/9 passing. The font subsystem
   participates in `phase1-ghost-demo-smoke` (D3D11 rendering active)
   and `phase3-japanese-input` (CJK code path).
3. `bash tools/lint-fork-isolation.sh --audit` — expect:
   - MOVABLE count drops by 5 (the 5 NEW files in src/font/, src/fontconfig/, src/os/ disappear).
   - `src/font/DeferredFace.zig`, `src/font/discovery.zig` should leave the audit's CORE-ADAPTATION list (they revert to upstream-clean modulo the `harfbuzz.zig` line which moves to MOVABLE-with-marker).
4. `bash tools/lint-fork-isolation.sh` (default lint mode against
   fork/main) on the migration branch — zero violations on Phase C
   commits because no upstream-shared file references DirectWrite by
   name anymore.

### Manual / visual checks

5. Launch ghostty, type some Japanese (e.g., `あいうえお` via clipboard
   paste — IME is gated by ConPTY codepage limitations per phase3
   skip note). Verify glyphs render, not tofu.
6. Launch ghostty with a config that requests a missing font; verify
   fallback path resolves through the WinUI3 backend and finds a CJK
   substitute (the `60-cjk-prefer-japanese.conf` ordering matters
   here).
7. `ghostty +list-fonts` (the CLI subcommand) — verify the discoverer
   enumerates installed Windows fonts, not an empty list.
8. Compare a screenshot of a known-good build vs the migrated build at
   the same config. No visible diff in the terminal renderer.

### Regression watch

9. The `dwrite_generated.zig` ABI is touchy (re: #193 vtable slot
   issue). Phase A/B/C should not modify the file content; if Zig
   compile errors hit during the move, suspect Zig version drift, not
   the binding.

## Out of scope for this design

- Phase D (CoreText/Fontconfig migration behind the same vtable) is
  noted but not specified in detail; that's a follow-up.
- Upstream PR proposal to accept the Backend interface — we don't
  propose to upstream (`docs/apprt-contract.md`).
- Performance microbenchmarks of vtable dispatch — qualitative
  assessment in §5.3 is sufficient unless a measurable regression
  appears in `phase1-ghost-demo-smoke` timing.
- Font cache invalidation across apprt switch — irrelevant; apprt is
  fixed at build time.

## Decision log (one-line summary for the implementation agent)

- **Interface shape**: runtime vtable (`src/font/Backend.zig`), opaque
  `[4*usize]` per-face storage. Not comptime — keeps upstream-shared
  call sites apprt-agnostic.
- **Injection point**: `apprt.runtime.fontBackend(alloc)`, called from
  `App.init`, threaded into `SharedGridSet`/`CodepointResolver`
  construction.
- **fontconfig_env**: moved into apprt; `global.zig` calls
  `apprt.runtime.preFontconfigInit(...)` instead of importing
  `os/fontconfig_env.zig` directly.
- **harfbuzz.zig +1**: keep with `UPSTREAM-SHARED-OK` marker — genuine
  cross-cutting build flag, not wrappable.
- **face.zig +1/-1**: keep as-is — apprt declaration edit, expected.
- **Markers needed in upstream-shared font code after Phase C**: zero
  (only `harfbuzz.zig` carries one, for the perf flag, not for
  DirectWrite).
- **Effort total**: 13-21h across Phases A/B/C; Phase D is open-ended.
