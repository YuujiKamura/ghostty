# WinUI3 Known-Good APIs

This file records high-value WinUI3/WinRT APIs that are available and usable in this repo, but easy to forget or misjudge during debugging.

Every entry here should stay evidence-backed and repo-specific.

## `Microsoft.UI.Xaml.Markup.XamlReader.Load`

### Status

- known-good for the current layout-only `surface_grid` use case

### What it is used for here

- building the inner surface grid at runtime
- composing:
  - `Grid`
  - `SwapChainPanel`
  - `ScrollBar`

### Evidence

- [com_native.zig](../src/apprt/winui3/com_native.zig):487
- [Surface.zig](../src/apprt/winui3/Surface.zig):177
- [Surface.zig](../src/apprt/winui3/Surface.zig):199
- [ghostty #57](https://github.com/YuujiKamura/ghostty/issues/57)

### Known-good usage conditions

- built-in controls only
- layout composition only
- event hookup remains in Zig after loading

### Do not assume

- that this replaces all future XAML compiler/XBF/PRI needs
- that code-behind style usage is in scope

## `PreviewKeyDown` on the XAML surface

### Status

- known-good for normal key routing on the XAML-owned path

### What it is used for here

- navigation and non-text key interception before XAML consumes them
- IME switching trigger via `VK_PROCESSKEY`

### Evidence

- [Surface.zig](../src/apprt/winui3/Surface.zig):294
- [Surface.zig](../src/apprt/winui3/Surface.zig):889

### Known-good usage conditions

- XAML surface owns focus
- normal typing is not routed through `input_hwnd`

## `CharacterReceived` on the XAML surface

### Status

- known-good for text input on the normal keyboard path

### What it is used for here

- receiving text-producing input after key routing

### Evidence

- [Surface.zig](../src/apprt/winui3/Surface.zig):303
- [Surface.zig](../src/apprt/winui3/Surface.zig):914

### Known-good usage conditions

- XAML surface owns keyboard focus
- IME path is only active during composition windows

## `input_hwnd` IME path

### Status

- valid as an IME-only path

### What it is used for here

- IME messages
- commit text via `WM_CHAR`

### Evidence

- [input_overlay.zig](../src/apprt/winui3/input_overlay.zig):82
- [input_overlay.zig](../src/apprt/winui3/input_overlay.zig):92
- [input_runtime.zig](../src/apprt/winui3/input_runtime.zig):32

### Known-good usage conditions

- not the default focus target
- focus returns to XAML after IME activity

### Do not assume

- that it is safe to restore `input_hwnd` after every tab or startup transition

## Runtime metrics over UIA for ScrollBar acceptance

### Status

- preferred evidence source for current ScrollBar validation

### What it is used for here

- proving ScrollBar layout/update correctness when UIA reports bad bounding rectangles

### Evidence

- [winui3-scrollbar-smoke.ps1](../scripts/winui3-scrollbar-smoke.ps1)
- [ghostty #57](https://github.com/YuujiKamura/ghostty/issues/57)

### Known-good usage conditions

- combine:
  - `scrollbar_sync` metrics
  - right-band pixel diff
  - contract/build acceptance

### Do not assume

- that UIA `is_offscreen` means the control is not rendered
