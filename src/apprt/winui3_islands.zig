// WinUI 3 XAML Islands application runtime for Ghostty on Windows.
// Uses CreateWindowEx + DesktopWindowXamlSource for custom titlebar support
// (Windows Terminal architecture). Shared COM/WinRT/OS code is imported from winui3/.
//
// App.zig: islands-specific AppHost using NonClientIslandWindow (Task 5).
// Surface.zig: islands-local copy with import paths adjusted to shared modules.
pub const App = @import("winui3_islands/App.zig");
pub const Surface = @import("winui3_islands/Surface.zig").Surface;

const internal_os = @import("../os/main.zig");
pub const resourcesDir = internal_os.resourcesDir;

test {
    @import("std").testing.refAllDecls(@This());
}
