const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");
const os = @import("os.zig");
const bootstrap = @import("bootstrap.zig");
const com_aggregation = @import("com_aggregation.zig");

const log = std.log.scoped(.basal_test);

pub fn main() !void {
    try bootstrap.init();
    defer bootstrap.deinit();

    try winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED));
    defer winrt.RoUninitialize();

    const dq_opts = winrt.DispatcherQueueOptions{};
    _ = try winrt.createDispatcherQueueController(&dq_opts);

    const app_class = try winrt.hstring("Microsoft.UI.Xaml.Application");
    defer winrt.deleteHString(app_class);
    const statics = try winrt.getActivationFactory(com.IApplicationStatics, app_class);
    defer statics.release();

    var app_state = BasalApp{};
    var callback = com_aggregation.InitCallback(BasalApp).create(&app_state);

    std.debug.print("--- BASAL TEST: Launching minimal WinUI 3 Window ---\n", .{});
    try statics.start(callback.comPtr());
    std.debug.print("--- BASAL TEST: Finished ---\n", .{});
}

const BasalApp = struct {
    window: ?*com.IWindow = null,

    pub fn initXaml(self: *BasalApp) !void {
        std.debug.print("initXaml (BasalApp): Creating window...\n", .{});
        const window_class = try winrt.hstring("Microsoft.UI.Xaml.Window");
        defer winrt.deleteHString(window_class);
        
        const window_inspectable = try winrt.activateInstance(window_class);
        self.window = try window_inspectable.queryInterface(com.IWindow);
        
        if (self.window) |win| {
            const title = try winrt.hstring("Ghostty Basal Infrastructure Test");
            defer winrt.deleteHString(title);
            try win.SetTitle(title);
            try win.activate();
            std.debug.print("SUCCESS: Minimal Window Activated!\n", .{});
            
            _ = os.SetTimer(null, 0, 3000, timerCallback);
        }
    }
};

fn timerCallback(_: os.HWND, _: os.UINT, _: os.UINT_PTR, _: os.DWORD) callconv(.winapi) void {
    std.debug.print("Timer fired: Exiting basal test...\n", .{});
    os.ExitProcess(0);
}
