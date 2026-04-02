# Ghostty apprt Interface Specification

## Overview

The `apprt` (Application Runtime) is a compile-time abstract interface that allows Ghostty's core logic to remain platform-agnostic. Different implementations (GTK, Win32, browser, etc.) provide their own `App` and `Surface` structs that conform to this interface.

This document specifies the EXACT interface required for any new apprt implementation.

---

## App Interface

### Struct Definition

```zig
pub const App = @This();
```

The App struct represents the entire application runtime. It owns the application lifecycle, event loop, and window management.

### Required Public Constants

```zig
/// Platform-specific, optional. If false, rendering can happen from any thread.
/// GTK requires true because GLArea doesn't support multi-threaded drawing.
pub const must_draw_from_app_thread: bool = false; // or true

/// Platform-specific, optional. Used for platform-specific initialization (e.g., Flatpak).
pub const application_id: []const u8 = "com.example.app";

/// Platform-specific, optional. Used for platform-specific initialization.
pub const object_path: []const u8 = "/com/example/app";
```

These constants are OPTIONAL - only define them if your platform requires them.

### Required Public Methods

#### init()

**Signature:**
```zig
pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void
```

**Parameters:**
- `self: *App` - Pointer to the uninitialized App struct
- `core_app: *CoreApp` - Pointer to the core Ghostty App (`src/App.zig`)
- `opts: struct {}` - Empty options struct (reserved for future use)

**Returns:** `!void` - Can return errors

**Called from:** `main_ghostty.zig` during application startup

**Purpose:** Initialize the runtime App. Called ONCE at application startup.

---

#### run()

**Signature:**
```zig
pub fn run(self: *App) !void
```

**Returns:** `!void`

**Called from:** `main_ghostty.zig` after init()

**Purpose:** Start the application event loop. This should block until the application terminates. Returns when the app should exit.

---

#### terminate()

**Signature:**
```zig
pub fn terminate(self: *App) void
```

**Called from:** `main_ghostty.zig` during cleanup

**Purpose:** Shut down the runtime application gracefully. No error handling.

---

#### wakeup()

**Signature:**
```zig
pub fn wakeup(self: *App) void
```

**Called from:** `App.Mailbox.push()` (in `src/App.zig`), when other threads need to wake the main event loop

**Purpose:** Wake the event loop from sleep/blocking operations. This should cause the event loop to check the mailbox and process pending messages. MUST be thread-safe.

---

#### performAction()

**Signature:**
```zig
pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool
```

**Parameters:**
- `target: apprt.Target` - Either `.app` or `.{ .surface = *CoreSurface }`
- `action: apprt.Action.Key` - Comptime enum value from `apprt.Action` (e.g., `.quit`, `.new_window`, `.toggle_fullscreen`)
- `value` - Type depends on action; use `apprt.Action.Value(action)` to get the correct type

**Returns:** `!bool` - true if action was handled, false otherwise. Can return errors.

**Called from:** Core App (`src/App.zig`), Surface (`src/Surface.zig`), main event loop

**Purpose:** Execute an action triggered by keybindings, timers, or other events. The action enum key determines which action is being requested. Return false if the action cannot be performed.

**Action Examples:**
- `.quit` → `value: void`
- `.new_window` → `value: void`
- `.new_tab` → `value: void`
- `.toggle_fullscreen` → `value: apprt.action.Fullscreen`
- `.config_change` → `value: struct { config: *const Config }`

See `src/apprt/action.zig` for the complete list of actions and their value types.

---

#### performIpc() [OPTIONAL - Static Method]

**Signature:**
```zig
pub fn performIpc(
    alloc: Allocator,
    target: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    value: apprt.ipc.Action.Value(action),
) !bool
```

**Note:** This is a STATIC function (no `self` parameter).

**Purpose:** Execute IPC (inter-process communication) actions from external processes (e.g., CLI tools). NOT called for the main application.

**Currently supported actions:**
- `.new_window` - Open a new window from a CLI call

---

#### redrawInspector() [OPTIONAL]

**Signature:**
```zig
pub fn redrawInspector(self: *App, surface: *Surface) void
```

**Purpose:** Redraw the inspector UI for a specific surface. Only needed if inspector support is implemented.

---

#### startQuitTimer() [OPTIONAL - Conditional]

**Signature:**
```zig
pub fn startQuitTimer(self: *App) void
```

**Called:** Only if `@hasDecl(apprt.App, "startQuitTimer")` is true (checked at compile time)

**Purpose:** Start a timer to quit the app if no surfaces exist. Used for apps that auto-quit when all windows close. Optional.

---

## Surface Interface

### Struct Definition

```zig
const Self = @This();
```

The Surface struct represents a single terminal surface (window/tab/pane). It handles rendering, input events, and clipboard operations for that surface.

### Required Public Methods

#### deinit()

**Signature:**
```zig
pub fn deinit(self: *Self) void
```

**Called from:** Core cleanup code

**Purpose:** Clean up the Surface. Called when a surface is being destroyed. Does NOT need to call close().

---

#### gobj() [OPTIONAL - GTK-Specific]

**Signature:**
```zig
pub fn gobj(self: *Self) *GObjectSurface
```

**Purpose:** Return the platform-specific GObject surface (GTK only). For other platforms, this method shouldn't exist.

---

#### core()

**Signature:**
```zig
pub fn core(self: *Self) *CoreSurface
```

**Returns:** Pointer to the core Surface (`src/Surface.zig`)

**Purpose:** Return the core Ghostty Surface associated with this runtime surface.

---

#### rtApp()

**Signature:**
```zig
pub fn rtApp(self: *Self) *ApprtApp
```

**Returns:** Pointer to the runtime App

**Purpose:** Return the runtime App that owns this surface.

---

#### close()

**Signature:**
```zig
pub fn close(self: *Self, process_active: bool) void
```

**Parameters:**
- `process_active: bool` - True if the child process is still running

**Called from:** Core Surface close logic

**Purpose:** Close the surface/window. The process_active flag helps determine cleanup behavior.

---

#### cgroup() [OPTIONAL - Linux-Specific]

**Signature:**
```zig
pub fn cgroup(self: *Self) ?[]const u8
```

**Returns:** Cgroup path string if available, null otherwise

**Purpose:** Return the cgroup path for process isolation (Linux/GTK). Optional.

---

#### getTitle()

**Signature:**
```zig
pub fn getTitle(self: *Self) ?[:0]const u8
```

**Returns:** Null-terminated string if a title is set, null otherwise

**Purpose:** Get the current window/surface title.

---

#### getContentScale()

**Signature:**
```zig
pub fn getContentScale(self: *const Self) !apprt.ContentScale
```

**Returns:**
```zig
pub const ContentScale = struct {
    x: f32,  // DPI scale factor for X axis (e.g., 1.0, 1.5, 2.0)
    y: f32,  // DPI scale factor for Y axis
};
```

**Error:** Can return errors if scale cannot be determined

**Called from:** Surface init, rendering, font setup

**Purpose:** Return the DPI scale factor for the surface. This is used to scale fonts and UI elements appropriately for high-DPI displays.

---

#### getSize()

**Signature:**
```zig
pub fn getSize(self: *const Self) !apprt.SurfaceSize
```

**Returns:**
```zig
pub const SurfaceSize = struct {
    width: u32,   // Pixel width
    height: u32,  // Pixel height
};
```

**Error:** Can return errors if size cannot be determined

**Called from:** Surface init, resize handling

**Purpose:** Return the current pixel dimensions of the surface's drawable area.

---

#### getCursorPos()

**Signature:**
```zig
pub fn getCursorPos(self: *const Self) !apprt.CursorPos
```

**Returns:**
```zig
pub const CursorPos = struct {
    x: f64,  // X coordinate in pixels
    y: f64,  // Y coordinate in pixels
};
```

**Error:** Can return errors if cursor position cannot be determined

**Called from:** Mouse event handling, link detection

**Purpose:** Get the current mouse cursor position in screen/window coordinates.

---

#### supportsClipboard()

**Signature:**
```zig
pub fn supportsClipboard(
    self: *const Self,
    clipboard_type: apprt.Clipboard,
) bool
```

**Parameters:**
```zig
pub const Clipboard = enum {
    standard,    // Standard copy/paste clipboard
    selection,   // X11 selection (middle-click paste)
    primary,     // macOS pasteboard
};
```

**Returns:** true if this clipboard type is supported on this platform

**Purpose:** Check if a specific clipboard type is available. Used to determine what clipboard operations are possible.

---

#### clipboardRequest()

**Signature:**
```zig
pub fn clipboardRequest(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool
```

**Parameters:**
```zig
pub const ClipboardRequest = struct {
    request_type: ClipboardRequestType,
    response: *const fn ([]const u8) void,
};

pub const ClipboardRequestType = enum {
    read,   // Request clipboard contents
    write,  // Request to write to clipboard
};
```

**Returns:** `!bool` - true if the request was accepted, false if not possible, errors on failure

**Purpose:** Request clipboard data (read) or notify that the app is ready to provide clipboard data (write). The response callback will be called with the clipboard contents asynchronously.

---

#### setClipboard()

**Signature:**
```zig
pub fn setClipboard(
    self: *Self,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void
```

**Parameters:**
```zig
pub const ClipboardContent = struct {
    mime: []const u8,      // MIME type (e.g., "text/plain")
    data: []const u8,      // Data bytes
};
```
- `contents` - Array of mime type + data pairs
- `confirm` - If true, notify the user when paste is invoked

**Purpose:** Set clipboard contents. Can provide multiple MIME types (e.g., plain text and HTML).

---

#### defaultTermioEnv()

**Signature:**
```zig
pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap
```

**Returns:** `!std.process.EnvMap` - Environment variables for new child processes

**Purpose:** Return the default environment for PTY child processes. Usually based on the parent environment plus any platform-specific variables.

---

#### redrawInspector() [OPTIONAL]

**Signature:**
```zig
pub fn redrawInspector(self: *Self) void
```

**Purpose:** Redraw the inspector UI for this surface. Only if inspector support is implemented.

---

## How Core Code Calls the Interface

### In main_ghostty.zig

```zig
// Create core app
const app: *App = try App.create(alloc);

// Create and initialize runtime app
var app_runtime: apprt.App = undefined;
try app_runtime.init(app, .{});

// Start the event loop
try app_runtime.run();
```

### In src/App.zig

```zig
// Tick is called repeatedly from the runtime's event loop
pub fn tick(self: *App, rt_app: *apprt.App) !void {
    try self.drainMailbox(rt_app);
}

// Perform actions
_ = try rt_app.performAction(.app, .quit, {});
_ = try rt_app.performAction(.{ .surface = surface }, .render, {});
```

### In src/Surface.zig

```zig
pub fn init(
    self: *Surface,
    alloc: Allocator,
    config_original: *const configpkg.Config,
    app: *App,
    rt_app: *apprt.runtime.App,
    rt_surface: *apprt.runtime.Surface,
) !void {
    // Call runtime surface methods
    const content_scale = try rt_surface.getContentScale();
    const surface_size = try rt_surface.getSize();
    // ...
}
```

---

## Implementation Checklist for Win32

### App Implementation (win32.zig/App.zig)

- [ ] `pub fn init(self: *App, core_app: *CoreApp, opts: struct {}) !void`
- [ ] `pub fn run(self: *App) !void` - Main event loop
- [ ] `pub fn terminate(self: *App) void`
- [ ] `pub fn wakeup(self: *App) void` - Thread-safe event loop wake
- [ ] `pub fn performAction(self: *App, target: apprt.Target, comptime action: apprt.Action.Key, value: apprt.Action.Value(action)) !bool`
- [ ] Optional: `pub const must_draw_from_app_thread: bool` (set to true for WGL)
- [ ] Optional: `pub fn performIpc(alloc: Allocator, target: apprt.ipc.Target, comptime action: apprt.ipc.Action.Key, value: apprt.ipc.Action.Value(action)) !bool`

### Surface Implementation (win32.zig/Surface.zig)

- [ ] `pub fn deinit(self: *Self) void`
- [ ] `pub fn core(self: *Self) *CoreSurface`
- [ ] `pub fn rtApp(self: *Self) *ApprtApp`
- [ ] `pub fn close(self: *Self, process_active: bool) void`
- [ ] `pub fn getTitle(self: *Self) ?[:0]const u8`
- [ ] `pub fn getContentScale(self: *const Self) !apprt.ContentScale`
- [ ] `pub fn getSize(self: *const Self) !apprt.SurfaceSize`
- [ ] `pub fn getCursorPos(self: *const Self) !apprt.CursorPos`
- [ ] `pub fn supportsClipboard(self: *const Self, clipboard_type: apprt.Clipboard) bool`
- [ ] `pub fn clipboardRequest(self: *Self, clipboard_type: apprt.Clipboard, state: apprt.ClipboardRequest) !bool`
- [ ] `pub fn setClipboard(self: *Self, clipboard_type: apprt.Clipboard, contents: []const apprt.ClipboardContent, confirm: bool) !void`
- [ ] `pub fn defaultTermioEnv(self: *Self) !std.process.EnvMap`

---

## Key Design Notes

1. **Comptime Action Dispatch**: The `performAction` method uses `comptime` parameters to dispatch actions. The compiler knows the exact action type at compile time, ensuring type safety. The value type is computed via `apprt.Action.Value(action)`.

2. **Thread Safety**:
   - Core App methods are called ONLY from the main/UI thread
   - `wakeup()` must be thread-safe as it's called from renderer and IO threads
   - Surface clipboard operations must be thread-safe

3. **Error Handling**: Methods can fail with errors. The core code handles errors appropriately.

4. **Nullable Returns**: Many methods return optional values (`?T`) which should be null if unavailable.

5. **Callback Pattern for Clipboard**: Clipboard reads are asynchronous - the request method should invoke a callback with the data.

6. **Init Signature**: Surface init is called by the runtime implementation (GTK's `class/surface.zig` or Win32's equivalent) and must store references to the core Surface and runtime App.

---

## Related Source Files

- `src/apprt.zig` - Main apprt module definition
- `src/apprt/action.zig` - Action enum and value types
- `src/apprt/structs.zig` - ContentScale, CursorPos, etc.
- `src/apprt/gtk/App.zig` - GTK reference implementation
- `src/apprt/gtk/Surface.zig` - GTK reference implementation
- `src/App.zig` - Core App (CoreApp) that calls apprt
- `src/Surface.zig` - Core Surface (CoreSurface) that calls apprt
- `src/main_ghostty.zig` - Application entry point
