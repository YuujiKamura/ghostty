//! Windows Terminal-style caption buttons (minimize, maximize, close).
//!
//! Creates a horizontal StackPanel with 3 Border+TextBlock glyphs using
//! XamlReader.Load(), then sets it as TabView.TabStripFooter.
//!
//! Uses Border+TextBlock instead of Button because Button requires
//! XamlControlsResources theme dictionary (XAML compiler + PRI).

const std = @import("std");
const com = @import("com.zig");
const os = @import("os.zig");
const winrt = @import("winrt.zig");
const gen = @import("com_generated.zig");

const log = std.log.scoped(.winui3_caption);

/// Module-level HWND for event callbacks.
var g_hwnd: ?os.HWND = null;

/// XAML string for the caption button panel.
/// Three TextBlocks inside Borders: minimize (E921), maximize (E922), close (E8BB).
/// Uses Segoe MDL2 Assets font, 46x40px per button (same as Windows Terminal).
const CAPTION_XAML =
    \\<StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    \\            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    \\            Orientation="Horizontal"
    \\            HorizontalAlignment="Right"
    \\            VerticalAlignment="Stretch"
    \\            Height="40">
    \\  <Border x:Name="MinimizeButton"
    \\          Width="46" Height="40"
    \\          Background="Transparent">
    \\    <TextBlock Text="&#xE921;"
    \\               FontFamily="Segoe MDL2 Assets" FontSize="10"
    \\               Foreground="White"
    \\               HorizontalAlignment="Center"
    \\               VerticalAlignment="Center"/>
    \\  </Border>
    \\  <Border x:Name="MaximizeButton"
    \\          Width="46" Height="40"
    \\          Background="Transparent">
    \\    <TextBlock Text="&#xE922;"
    \\               FontFamily="Segoe MDL2 Assets" FontSize="10"
    \\               Foreground="White"
    \\               HorizontalAlignment="Center"
    \\               VerticalAlignment="Center"/>
    \\  </Border>
    \\  <Border x:Name="CloseButton"
    \\          Width="46" Height="40"
    \\          Background="Transparent">
    \\    <TextBlock Text="&#xE8BB;"
    \\               FontFamily="Segoe MDL2 Assets" FontSize="10"
    \\               Foreground="White"
    \\               HorizontalAlignment="Center"
    \\               VerticalAlignment="Center"/>
    \\  </Border>
    \\</StackPanel>
;

/// Dummy context for Tapped event delegates (HWND stored in module global).
const CaptionContext = struct {
    action: Action,

    const Action = enum { minimize, maximize, close };
};

/// Static contexts — must live for the lifetime of the app.
var ctx_minimize = CaptionContext{ .action = .minimize };
var ctx_maximize = CaptionContext{ .action = .maximize };
var ctx_close = CaptionContext{ .action = .close };

const XamlDelegate = gen.TappedEventHandlerImpl(CaptionContext, *const fn (*CaptionContext, ?*anyopaque, ?*anyopaque) void);

fn onCaptionTapped(ctx: *CaptionContext, _: ?*anyopaque, _: ?*anyopaque) void {
    const App = @import("App.zig");
    const hwnd = g_hwnd orelse return;
    switch (ctx.action) {
        .minimize => {
            App.fileLog("caption: minimize clicked", .{});
            _ = os.PostMessageW(hwnd, os.WM_SYSCOMMAND, os.SC_MINIMIZE, 0);
        },
        .maximize => {
            const sc = if (os.IsZoomed(hwnd) != 0) os.SC_RESTORE else os.SC_MAXIMIZE;
            App.fileLog("caption: maximize/restore clicked (zoomed={})", .{os.IsZoomed(hwnd) != 0});
            _ = os.PostMessageW(hwnd, os.WM_SYSCOMMAND, sc, 0);
        },
        .close => {
            App.fileLog("caption: close clicked", .{});
            _ = os.PostMessageW(hwnd, os.WM_SYSCOMMAND, os.SC_CLOSE, 0);
        },
    }
}

/// Creates the caption button panel and attaches it to the TabView footer.
pub fn install(tab_view: *com.ITabView, hwnd: os.HWND) void {
    const App = @import("App.zig");
    g_hwnd = hwnd;

    const reader_class = winrt.hstring("Microsoft.UI.Xaml.Markup.XamlReader") catch |err| {
        App.fileLog("caption_buttons: hstring failed: {}", .{@intFromError(err)});
        return;
    };
    defer winrt.deleteHString(reader_class);
    const reader = winrt.getActivationFactory(com.IXamlReaderStatics, reader_class) catch |err| {
        App.fileLog("caption_buttons: getActivationFactory failed: {}", .{@intFromError(err)});
        return;
    };
    defer reader.release();

    const xaml_str = winrt.hstring(CAPTION_XAML) catch |err| {
        App.fileLog("caption_buttons: xaml hstring failed: {}", .{@intFromError(err)});
        return;
    };
    defer winrt.deleteHString(xaml_str);

    const panel_insp = reader.Load(xaml_str) catch |err| {
        App.fileLog("caption_buttons: XamlReader.Load FAILED: {}", .{@intFromError(err)});
        return;
    };
    defer _ = panel_insp.release(); // Release local ref; TabView holds its own.

    // Set as TabStripFooter.
    tab_view.SetTabStripFooter(@ptrCast(panel_insp)) catch |err| {
        App.fileLog("caption_buttons: SetTabStripFooter FAILED: {}", .{@intFromError(err)});
        return;
    };

    // Find named children and register Tapped handlers.
    const fe = panel_insp.queryInterface(com.IFrameworkElement) catch |err| {
        App.fileLog("caption_buttons: QI IFrameworkElement failed: {}", .{@intFromError(err)});
        return;
    };
    defer fe.release();

    registerTapped(fe, "MinimizeButton", &ctx_minimize, App);
    registerTapped(fe, "MaximizeButton", &ctx_maximize, App);
    registerTapped(fe, "CloseButton", &ctx_close, App);

    App.fileLog("caption_buttons: installed with click handlers", .{});
}

fn registerTapped(fe: *com.IFrameworkElement, comptime name: [:0]const u8, ctx: *CaptionContext, comptime App: type) void {
    const name_hs = winrt.hstring(name) catch return;
    defer winrt.deleteHString(name_hs);

    const child_insp = fe.FindName(name_hs) catch |err| {
        App.fileLog("caption_buttons: FindName({s}) failed: {}", .{ name, @intFromError(err) });
        return;
    };
    defer _ = child_insp.release();

    const ui_elem = child_insp.queryInterface(com.IUIElement) catch |err| {
        App.fileLog("caption_buttons: QI IUIElement for {s} failed: {}", .{ name, @intFromError(err) });
        return;
    };
    defer ui_elem.release();

    const alloc = std.heap.page_allocator;
    const delegate = XamlDelegate.createWithIid(alloc, ctx, &onCaptionTapped, &com.IID_TappedEventHandler) catch |err| {
        App.fileLog("caption_buttons: createDelegate for {s} failed: {}", .{ name, @intFromError(err) });
        return;
    };
    defer delegate.release();

    _ = ui_elem.AddTapped(delegate.comPtr()) catch |err| {
        App.fileLog("caption_buttons: AddTapped for {s} failed: {}", .{ name, @intFromError(err) });
        return;
    };

    App.fileLog("caption_buttons: {s} Tapped handler registered", .{name});
}
