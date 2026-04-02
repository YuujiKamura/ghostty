# WinUI3 Test Parity Map (GTK -> WinUI3)

This map tracks direct transcription/equivalent tests from `src/apprt/gtk` into `src/apprt/winui3`.

## 1:1 Mapped Tests

- `atLeast` (`gtk/gtk_version.zig`) -> `atLeast` (`winui3/version_compat.zig`)
- `runtimeUntil` (`gtk/gtk_version.zig`) -> `runtimeUntil` (`winui3/version_compat.zig`)
- `versionAtLeast` (`gtk/adw_version.zig`) -> `versionAtLeast` (`winui3/version_compat.zig`)
- `Key.Type returns correct types` (`gtk/gsettings.zig`) -> `Key.Type returns correct types` (`winui3/settings_compat.zig`)
- `Key.requiresAllocation identifies allocating types` (`gtk/gsettings.zig`) -> `Key.requiresAllocation identifies allocating types` (`winui3/settings_compat.zig`)
- `Key.GValueType returns correct GObject types` (`gtk/gsettings.zig`) -> `Key.GValueType returns correct GObject types` (`winui3/settings_compat.zig`)
- `@tagName returns correct GTK property names` (`gtk/gsettings.zig`) -> `@tagName returns correct GTK property names` (`winui3/settings_compat.zig`)
- `gActionNameIsValid` (`gtk/ext/actions.zig`) -> `gActionNameIsValid` (`winui3/actions_compat.zig`)
- `adding actions to an object` (`gtk/ext/actions.zig`) -> `adding actions to an object` (`winui3/actions_compat.zig`)
- `StringList create and destroy` (`gtk/ext/slice.zig`) -> `StringList create and destroy` (`winui3/slice_compat.zig`)
- `StringList create empty list` (`gtk/ext/slice.zig`) -> `StringList create empty list` (`winui3/slice_compat.zig`)
- `StringList boxedCopy and boxedFree` (`gtk/ext/slice.zig`) -> `StringList boxedCopy and boxedFree` (`winui3/slice_compat.zig`)
- `GhosttyConfig` (`gtk/class/config.zig`) -> `GhosttyConfig` (`winui3/Config.zig`)
- `computeFraction` (`gtk/class/surface.zig`) -> `computeFraction` (`winui3/Surface.zig`)
- `accelFromTrigger` (`gtk/key.zig`) -> `accelFromTrigger` (`winui3/key.zig`)
- `xdgShortcutFromTrigger` (`gtk/key.zig`) -> `xdgShortcutFromTrigger` (`winui3/key.zig`)
- `labelFromTrigger` (`gtk/key.zig`) -> `labelFromTrigger` (`winui3/key.zig`)

## WinUI3-only Additional Tests

- `COM infrastructure`
- `WinRT ABI critical IIDs are correct`
- `guidEql`
- `WinRT string boxing`
- `E2E-like: PropertyValue boxed string supports IPropertyValue QI`
- `WeakRef basic functionality`
- `imeUtf16ToUtf8 conversion`
- `IME composition source should not inject keyCallback directly`
- `vkToKey mapping`
- `vkToUnshiftedCodepoint resolution`
- `RuntimeDebugConfig load`
- `GhosttyConfig memory management`
