# Ghostty Windows Port - WinRT/COM Binding Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the compilation errors in Ghostty Windows port by aligning COM interface definitions with the WinMD metadata and resolving module duplication issues.

**Architecture:** Use the generated `com_new.zig` as the source of truth for VTable layouts. Manually add typed wrapper functions to `com.zig`. Resolve module duplication by using correct import paths and build options.

**Tech Stack:** Zig 0.15.2, Windows Metadata (WinMD), COM/WinRT.

---

### Task 1: Comprehensive `com.zig` Update

**Files:**
- Modify: `src/apprt/winui3/com.zig`
- Reference: `src/apprt/winui3/com_new.zig`

**Step 1: Replace interface definitions**
Update `IWindow`, `ITabView`, `IPanel`, `IFrameworkElement` in `com.zig` with the exact VTable layout from `com_new.zig`.

**Step 2: Add typed wrapper functions**
Ensure all members used in `App.zig` and `Surface.zig` have typed function pointers in VTable instead of `VtblPlaceholder`.
- `ITabView.put_CanReorderTabs`
- `IPanel.get_Children`
- `IPanel.put_Background`
- `IFrameworkElement.add_SizeChanged`
- `IFrameworkElement.remove_SizeChanged`
- `IFrameworkElement.get_ActualWidth`
- `IFrameworkElement.get_ActualHeight`

**Step 3: Define Event Handler IIDs**
- Add `IID_SizeChangedEventHandler`.

### Task 2: Fix `OpenGL.zig` and Module Duplication

**Files:**
- Modify: `src/renderer/OpenGL.zig`
- Modify: `src/build_config.zig`

**Step 1: Import `build_config` in `OpenGL.zig`**
Add `const build_config = @import("../build_config.zig");` to `OpenGL.zig`.

**Step 2: Use `build_config.app_runtime`**
Correct the switch statement in `OpenGL.zig` to use the value `app_runtime`.

### Task 3: Verification

**Step 1: Run build**
Run: `zig build -Dtarget=x86_64-windows -Dapp-runtime=winui3`
Expected: Compilation succeeds (or moves to linking phase).

**Step 2: Run basal-test**
Run: `zig build basal-test -Dtarget=x86_64-windows -Dapp-runtime=winui3`
Expected: `basal_test.exe` is produced.
