# Sprawl Report A5

**Tracking issue:** #263
**Scope:** cli + config + input + terminal + pty (16 files)
**Branch:** fork/main

## Per-file decisions

### src/cli/ (3)

| File | wrap-first answer | Decision | Rationale |
|---|---|---|---|
| `cli/list_fonts.zig` | No — bound to fork's `font.Discover.init()` (no-arg) API | KEEP-WITH-ANNOTATION | Fork's font module independently diverges from upstream's `font.Library`/`Discover` coupling. Annotation added. |
| `cli/ssh_cache.zig` | No — fork only removed dead branches | REVERT | Cosmetic cleanup; `CacheIsLocked` branch is unreachable on Windows but harmless. Restored upstream. |
| `cli/version.zig` | No — generic build info, not WinUI3-specific | KEEP-WITH-ANNOTATION | `build_timestamp` printout is broadly useful; annotation added. |

### src/config/ (2)

| File | wrap-first answer | Decision | Rationale |
|---|---|---|---|
| `config/CApi.zig` | No — cosmetic `String` import alias rename | REVERT | Pure naming churn; restored upstream. |
| `config/Config.zig` | Mixed | REFACTOR + KEEP-WITH-ANNOTATION | Reverted upstream-feature regressions (middle-click-action option/enum, keyEventIsBinding fn, arrow→page_up keybind & move_tab removal). Kept 3 irreducible comptime `build_config.app_runtime` switches with `UPSTREAM-SHARED-OK` annotations. Extracted Windows realpath path-normalization in 4 theme tests into a single `normalizePathForTest` helper with annotation. **229 → 104 lines diff vs upstream.** |

### src/input/ (1)

| File | wrap-first answer | Decision | Rationale |
|---|---|---|---|
| `input/Binding.zig` | No — getGObjectType comptime switch is irreducible | REVERT-DOC + KEEP-WITH-ANNOTATION | Reverted doc-comment drift in `getEvent`. Kept comptime switch with annotation; expanded `.win32` → `.win32, .winui3`. **25 → 4 lines diff.** |

### src/terminal/ (9)

| File | wrap-first answer | Decision | Rationale |
|---|---|---|---|
| `terminal/PageList.zig` | No — tests must live next to code under test | KEEP-WITH-ANNOTATION | #138 scrollback regression tests; upstream-PR candidates. Annotation added. |
| `terminal/Screen.zig` | No — defensive default + tests | KEEP-WITH-ANNOTATION | #138 `max_scrollback` default bump (0 → 10MB) and regression tests. Annotations added. |
| `terminal/apc.zig` | No — APC `max_bytes` is a security feature | REVERT | Restored upstream's `max_bytes` protection; coupled with `c/terminal.zig` and `kitty/graphics_command.zig`. |
| `terminal/c/terminal.zig` | No — `apc_max_bytes_*` C API options are upstream contract | REVERT | Coupled with apc.zig; restored upstream. |
| `terminal/kitty/graphics_command.zig` | No — `max_bytes` security guard | REVERT | Coupled with apc.zig revert; restored upstream. |
| `terminal/kitty/graphics_image.zig` | No — Android check + style is upstream concern | REVERT | Restored upstream's Android-aware `isPathInTempDir`. |
| `terminal/mouse.zig` | No — `Shape` enum is upstream-shared GObject | KEEP-WITH-ANNOTATION | comptime switch needs `.win32, .winui3 => void`; annotation added. |
| `terminal/render.zig` | No — tests must live next to RenderState code | KEEP-WITH-ANNOTATION | preedit/cursor dirty regression tests; upstream-PR candidates. Annotation added. |
| `terminal/search/Thread.zig` | No — Mailbox boundary crosses apprt+terminal layers | KEEP-WITH-ANNOTATION | `BoundedMailbox` (#232/#251) is intentional sprawl; `safe_mailbox` lives in `apprt/winui3/`. Existing comments upgraded with `UPSTREAM-SHARED-OK` marker. |

### src/pty.zig (1)

| File | wrap-first answer | Decision | Rationale |
|---|---|---|---|
| `pty.zig` | No diff vs upstream | NO-OP | File matches origin/main; nothing to do. |

## Skill firing log

`wrap-first-in-apprt` was invoked **before** the audit started and re-consulted before each per-file decision. The "can this go to apprt/winui3?" question was answered explicitly for every file. Three patterns emerged:

1. **Pure cosmetic / dead-code drift** → REVERT (ssh_cache.zig, CApi.zig, kitty/graphics_image.zig).
2. **Upstream-feature regressions** that the fork accidentally dropped during merges → REVERT (apc.zig, c/terminal.zig, kitty/graphics_command.zig, Config.zig middle-click-action / keyEventIsBinding / keybinds).
3. **Irreducible apprt-shared boundaries** (comptime build_config switches, regression tests for upstream-shared logic, intentional sprawl with #232/#251 issue tracking) → KEEP-WITH-ANNOTATION with explicit `UPSTREAM-SHARED-OK: <reason>` markers.

No file was a Pattern-1 (move to apprt/winui3) or Pattern-2 (delegation stub) candidate within A5 scope; the chunk was dominated by Pattern-3 (comptime injection / annotation) and revert decisions. This matches expectations: A5 is core terminal/config/CLI code, not apprt-coupled.

Skill firing was **consistent across all 16 files** — no silent skips.

## Test gate

Attempted `zig build test -Dapp-runtime=win32 -Dtest-filter="config"` and `-Dtest-filter="render"`. Both failed during build configuration with a pre-existing Zig build runner panic (`assertion failure ... !std.fs.path.isAbsolute(child_cwd_rel)` at `std/Build/Step/Run.zig:662`) and a vendored-deps issue (`unable to find module 'zigimg'` inside `vaxis`). These failures originate in the build infrastructure / dependency cache (`p/vaxis-...`, `.zig-cache/tmp/`), not in any A5-touched source file. They affect all `zig build *` invocations regardless of filter.

All A5 changes are either (a) literal reverts to upstream-known-good content or (b) additive annotations / single-helper-extraction with no semantic effect, so functional regression risk is minimal. Full module-level test gate to be re-run by the next session once the deps cache is repaired.

## Contract block

```
SCOPE: A5 cli/config/input/terminal/pty (16 files)
DECISIONS: REVERT=7 WRAP=0 KEEP_ANNOT=8 NO_OP=1
COMMITS:
  5ac4d5c39 revert(cli): ssh_cache.zig
  756276ec3 chore(annotation): cli/list_fonts.zig + cli/version.zig
  08b5272d4 revert(config): CApi.zig
  2781e46a8 refactor(config): Config.zig (revert + annotate, 229→104 lines)
  0dc60f82c refactor(input): Binding.zig (revert doc + annotate switch, 25→4 lines)
  6f58a234b revert(terminal): apc.zig + c/terminal.zig
  cd7935404 chore(annotation): terminal/mouse.zig
  1e0546237 revert(terminal): kitty/graphics_image.zig
  df22f18dc chore(annotation): terminal/search/Thread.zig (#232/#251)
  64a8f9685 chore(annotation): terminal/PageList.zig (#138 tests)
  be6ef464f revert(terminal): kitty/graphics_command.zig
  c474c6cdd chore(annotation): terminal/Screen.zig (#138)
  ebb25a5d2 chore(annotation): terminal/render.zig (preedit tests)
ISSUES_FILED: -
PUSHED: pending
SKILLS_FIRED: yes
NOTES: Diff to upstream reduced from ~1100 lines across 16 files to ~700 lines across 9 files. Test gate blocked by pre-existing zig build runner / vaxis deps panic; deferred to next session with clean cache.
```
