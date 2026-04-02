# WinUI3 Prebuilt Assets

This directory contains pre-compiled XAML Binary Format (`.xbf`) and Package Resource Index (`.pri`) files.

## Purpose
These assets allow building Ghostty with WinUI3 support without requiring a full Visual Studio/MSBuild toolchain. This is particularly useful for:
- CI environments.
- Contributors who only want to work on the Zig codebase.
- Quick builds where XAML changes are not needed.

## Usage
The `build-winui3.sh` script automatically uses these assets as a fallback if MSBuild is not found or if `GHOSTTY_WINUI3_PREBUILT_ONLY=1` is set.

## Updating Assets
When you modify `.xaml` files in the `xaml/` directory, you should update these prebuilt assets so others can benefit from your changes without needing to rebuild XAML themselves.

To update:
1. Ensure you have Visual Studio 2022 with WinUI3 workloads installed.
2. Run the build with the `--update-prebuilt` flag:
   ```bash
   ./build-winui3.sh --release --update-prebuilt
   ```
3. Commit the updated files in this directory.

## Files
- `*.xbf`: Compiled XAML files.
- `ghostty.pri`: Compiled resource index.
- `runtime/x64/`: Essential Windows App SDK (WinUI 3) runtime DLLs.
  - This allows the app to run on machines where the Windows App SDK Runtime is not installed.
  - `Microsoft.WindowsAppRuntime.pri` is the framework's resource index, renamed to avoid collision with the app's `resources.pri`.
