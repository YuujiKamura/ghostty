// WinUI 3 application runtime for Ghostty on Windows.
// This implements the apprt interface using WinUI 3 via pure Zig WinRT COM vtable calls.
// No C/C++ code required — all WinRT interfaces are defined as Zig extern structs.
pub const App = @import("winui3/App.zig");
pub const Surface = @import("winui3/Surface.zig");

const internal_os = @import("../os/main.zig");
pub const resourcesDir = internal_os.resourcesDir;

test {
    _ = @import("winui3/Config.zig");
    _ = @import("winui3/version_compat.zig");
    _ = @import("winui3/settings_compat.zig");
    _ = @import("winui3/actions_compat.zig");
    _ = @import("winui3/slice_compat.zig");
    _ = @import("winui3/util.zig");
    _ = @import("winui3/WeakRef.zig");
    _ = @import("winui3/key.zig");
    _ = @import("winui3/App.zig");
    _ = @import("winui3/Surface.zig");
    _ = @import("winui3/input_overlay.zig");
    _ = @import("winui3/debug_harness.zig");
    _ = @import("winui3/hacks.zig");
    _ = @import("winui3/com_runtime.zig");
    @import("std").testing.refAllDecls(@This());
}
