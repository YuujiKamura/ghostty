# LoadComponent URI Fix for Unpackaged WinUI 3

Modified `tabview_runtime.zig` and `Surface.zig` to use file-based URIs instead of `ms-appx:///` for loading XBF components. This ensures compatibility with unpackaged (non-AppX) builds.

## Changes

### 1. `src/apprt/winui3_islands/tabview_runtime.zig`
- Refactored `createRoot` to use `IApplicationStatics.LoadComponent`.
- Changed URI from `ms-appx:///TabViewRoot.xbf` to `TabViewRoot.xbf`.
- Added logic to find `TabView` and `TabContentGrid` elements by name from the loaded tree.

### 2. `src/apprt/winui3_islands/Surface.zig`
- Refactored `init` to use `IApplicationStatics.LoadComponent` instead of `XamlReader.Load`.
- Changed URI from `ms-appx:///Surface.xbf` to `Surface.xbf`.
- Added logic to find the `ScrollBar` element by name from the loaded tree.

### 3. `src/apprt/winui3/os.zig`
- Added missing `WM_APP_CLOSE_TAB` definition to fix build errors in `App.zig`.

## Verification Results

### Build
Successfully built with the following command:
```powershell
zig build -Dapp-runtime=winui3_islands -Drenderer=d3d11 --summary all
```

### Runtime Check
- `TabViewRoot.xbf` and `Surface.xbf` are confirmed to be generated in `zig-out-winui3-islands\bin\`.
- By using simple filenames in the URI, WinUI 3 correctly resolves them relative to the executable path in unpackaged mode.
