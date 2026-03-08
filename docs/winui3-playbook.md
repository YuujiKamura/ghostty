# WinUI3 Playbook

This playbook is the repo-local operating guide for WinUI3 work in `ghostty-win`.

It exists because WinUI3 in this project is not a normal C#/MSBuild environment:

- Zig is the primary implementation language
- Win32, WinRT, XAML, and COM interop overlap
- some facts are easy to forget and expensive to rediscover

Use this file as the first stop before ad-hoc WinUI3 exploration.

## Acceptance First

Do not treat app build alone as success.

Current acceptance line:

1. `zig build -Dapp-runtime=winui3 -Drenderer=d3d11`
2. `pwsh -File .\scripts\winui3-contract-check.ps1 -Build`
3. `pwsh -File ..\win-zig-core\scripts\winui3-verify-all.ps1`

For ScrollBar-specific visual acceptance:

4. `pwsh -File .\scripts\winui3-scrollbar-smoke.ps1 -NoBuild`

`winui3-contract-check.ps1` is the local gate. `winui3-verify-all.ps1` is the cross-repo gate.

## Architecture Boundaries

The WinUI3 stack here is split into three layers.

### 1. XAML / visual tree layer

Owned primarily by:

- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig)

Current rules:

- layout-only visual composition may use `XamlReader.Load()`
- runtime event hookup stays in Zig
- `surface_grid` is the visual container for `SwapChainPanel + ScrollBar`

Evidence:

- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):177
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):199
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):235

### 2. Input / focus ownership layer

Owned primarily by:

- [input_runtime.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\input_runtime.zig)
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig)
- [ime.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\ime.zig)
- [event_handlers.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\event_handlers.zig)

Current rules:

- normal keyboard input belongs to XAML `SwapChainPanel`
- IME composition uses `input_hwnd`
- `input_hwnd` is not the default keyboard owner
- focus must return to the XAML surface after IME activity

Evidence:

- [input_runtime.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\input_runtime.zig):32
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):889
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):914
- [ime.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\ime.zig):124

### 3. COM / interop boundary

Owned primarily by:

- [com_generated.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\com_generated.zig)
- [com_native.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\com_native.zig)
- [native_interop.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\native_interop.zig)

Current rules:

- `com_generated.zig` is generator-facing
- `com_native.zig` is consumer rescue/native glue, not bindgen truth
- `native_interop.zig` contains interfaces outside ordinary WinMD-covered bindgen scope
- generator truth is tracked in `win-zig-bindgen` manifests/issues, not here

Related issues:

- `win-zig-bindgen #112-#117`
- [ghostty #59](https://github.com/YuujiKamura/ghostty/issues/59)

## What Goes Where

### Prefer XAML when

- the problem is pure layout or visual composition
- the control is a built-in WinUI control
- no code-behind or package compiler output is needed

Current known-good example:

- `surface_grid` via `XamlReader.Load()`

### Prefer Zig-side event hookup when

- the handler must call into terminal/runtime logic
- handler ownership and token cleanup must stay explicit
- you need compile-visible control over the delegate wiring

Evidence:

- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):295
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):304

### Keep native interop when

- the interface is outside ordinary WinMD-covered bindgen scope
- the bindgen-side exception manifest still classifies it as an exception

Do not remove such entries optimistically.

## Known-Good Facts

### `XamlReader.Load()` is usable here

This repo can build layout-only XAML at runtime without XBF/PRI/compiler tooling for the current `surface_grid` use case.

Evidence:

- [com_native.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\com_native.zig):487
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):177
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):199

Scope limit:

- this is for built-in controls and layout-only composition
- it does not imply that full XBF/PRI/tooling is unnecessary for every future XAML scenario

### ScrollBar rendering is real even when UIA lies

For the current ScrollBar implementation:

- runtime metrics and pixel-diff are more trustworthy than UIA bounding rectangles

Evidence:

- [winui3-scrollbar-smoke.ps1](C:\Users\yuuji\ghostty-win\scripts\winui3-scrollbar-smoke.ps1)
- [ghostty #57](https://github.com/YuujiKamura/ghostty/issues/57)

### Input routing is intentionally split

This repo uses:

- XAML events for normal keyboard input
- `input_hwnd` for IME handling

That split is acceptable only if focus ownership is explicit and reversible.

## Known Failure Patterns

### 1. Build passes but input does not work

Likely causes:

- `input_hwnd` stole focus in the normal input path
- XAML surface no longer owns keyboard focus

Check:

- [input_runtime.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\input_runtime.zig)
- [Surface.zig](C:\Users\yuuji\ghostty-win\src\apprt\winui3\Surface.zig):889

### 2. UIA says a control is offscreen, but visuals look correct

Likely cause:

- UI Automation peer limitation, not layout failure

Check:

- smoke pixel-diff
- runtime metrics
- issue [#57](https://github.com/YuujiKamura/ghostty/issues/57)

### 3. Random crash or unrelated COM failure after interface edits

Likely cause:

- vtable slot drift or bad manual interop boundary

Check:

- generator truth in `win-zig-bindgen`
- exception boundary before editing `com_native.zig`

## Working Rules For Future Agents

1. Read this playbook first for WinUI3 work.
2. Do not use chat memory as the primary source of truth.
3. New facts must land in one of:
   - docs
   - smoke tests
   - manifests
   - issue comments with code/test references
4. Do not treat `com_native.zig` as bindgen truth.
5. Prefer acceptance-backed evidence over architectural guesses.
