//! Windows Terminal-style caption buttons (minimize, maximize, close).
//!
//! Registers Tapped + PointerEntered/Exited handlers on Border elements
//! defined in TabViewRoot.xaml (Column 2 of the titlebar Grid).
//! Close button gets red hover (#C42B1C), others get subtle white overlay.
//
// Ref: microsoft/terminal src/cascadia/TerminalApp/MinMaxCloseControl.xaml @ e4e3f08efca9 — XAML-rendered Min/Max/Close in the titlebar Grid (DWM cannot draw caption buttons after WM_NCCALCSIZE removes the NC area), with #C42B1C red hover on Close
// Ref: microsoft/terminal src/cascadia/TerminalApp/MinMaxCloseControl.cpp#_OnMinimizeClick @ e4e3f08efca9 — post WM_SYSCOMMAND SC_MINIMIZE / SC_MAXIMIZE / SC_RESTORE / SC_CLOSE to the host HWND from the XAML click handler

const std = @import("std");
const com = @import("com.zig");
const os = @import("os.zig");
const winrt = @import("winrt.zig");
const gen = @import("com_generated.zig");

const log = std.log.scoped(.winui3_caption);

fn postMessageWarn(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, msg_name: []const u8) bool {
    const result = os.PostMessageW(hwnd, msg, wparam, lparam);
    if (result == 0) {
        log.warn("PostMessageW failed msg={s} err={}", .{ msg_name, os.GetLastError() });
        return false;
    }
    return true;
}

var g_hwnd: ?os.HWND = null;

const ButtonKind = enum { minimize, maximize, close };

const ButtonCtx = struct {
    kind: ButtonKind,
    panel: ?*gen.IPanel = null, // Grid → IPanel for SetBackground
};

var ctx_minimize = ButtonCtx{ .kind = .minimize };
var ctx_maximize = ButtonCtx{ .kind = .maximize };
var ctx_close = ButtonCtx{ .kind = .close };

// --- Tapped handler ---

const TappedDelegate = gen.TappedEventHandlerImpl(ButtonCtx, *const fn (*ButtonCtx, ?*anyopaque, ?*anyopaque) void);

fn onTapped(ctx: *ButtonCtx, _: ?*anyopaque, _: ?*anyopaque) void {
    const hwnd = g_hwnd orelse return;
    switch (ctx.kind) {
        .minimize => {
            _ = postMessageWarn(hwnd, os.WM_SYSCOMMAND, os.SC_MINIMIZE, 0, "SC_MINIMIZE");
        },
        .maximize => {
            const sc: usize = if (os.IsZoomed(hwnd) != 0) os.SC_RESTORE else os.SC_MAXIMIZE;
            _ = postMessageWarn(hwnd, os.WM_SYSCOMMAND, sc, 0, "SC_MAXIMIZE");
        },
        .close => {
            _ = postMessageWarn(hwnd, os.WM_SYSCOMMAND, os.SC_CLOSE, 0, "SC_CLOSE");
        },
    }
}

// --- PointerEntered/Exited handlers ---

const PointerDelegate = gen.PointerEventHandlerImpl(ButtonCtx, *const fn (*ButtonCtx, ?*anyopaque, ?*anyopaque) void);

fn onPointerEntered(ctx: *ButtonCtx, _: ?*anyopaque, _: ?*anyopaque) void {
    const panel = ctx.panel orelse return;
    const brush = createBrush(switch (ctx.kind) {
        .close => gen.Color{ .A = 255, .R = 0xC4, .G = 0x2B, .B = 0x1C }, // WT close red
        else => gen.Color{ .A = 30, .R = 255, .G = 255, .B = 255 }, // subtle white
    }) catch return;
    defer brush.release();
    panel.SetBackground(@ptrCast(brush)) catch {};
}

fn onPointerExited(ctx: *ButtonCtx, _: ?*anyopaque, _: ?*anyopaque) void {
    const panel = ctx.panel orelse return;
    panel.SetBackground(null) catch {};
}

fn createBrush(color: gen.Color) !*gen.ISolidColorBrush {
    const class = try winrt.hstring("Microsoft.UI.Xaml.Media.SolidColorBrush");
    defer winrt.deleteHString(class);
    const insp = try winrt.activateInstance(class);
    defer _ = insp.release();
    const brush = try insp.queryInterface(gen.ISolidColorBrush);
    try brush.SetColor(color);
    return brush;
}

// --- Install ---

pub fn install(root_grid: *winrt.IInspectable, hwnd: os.HWND) void {
    g_hwnd = hwnd;

    const fe = root_grid.queryInterface(com.IFrameworkElement) catch |err| {
        log.err("caption_buttons: QI IFrameworkElement failed: {}", .{@intFromError(err)});
        return;
    };
    defer fe.release();

    registerButton(fe, "MinimizeButton", &ctx_minimize);
    registerButton(fe, "MaximizeButton", &ctx_maximize);
    registerButton(fe, "CloseButton", &ctx_close);

    log.info("caption_buttons: installed with Tapped + hover handlers", .{});
}

fn registerButton(fe: *com.IFrameworkElement, comptime name: [:0]const u8, ctx: *ButtonCtx) void {
    const name_hs = winrt.hstring(name) catch return;
    defer winrt.deleteHString(name_hs);

    const child_insp = fe.FindName(name_hs) catch |err| {
        log.err("caption_buttons: FindName({s}) failed: {}", .{ name, @intFromError(err) });
        return;
    };
    defer _ = child_insp.release();

    const ui_elem = child_insp.queryInterface(com.IUIElement) catch |err| {
        log.err("caption_buttons: QI IUIElement for {s} failed: {}", .{ name, @intFromError(err) });
        return;
    };
    defer ui_elem.release();

    // Store IControl reference for SetBackground in hover handlers.
    ctx.panel = child_insp.queryInterface(gen.IPanel) catch null;

    const alloc = std.heap.page_allocator;

    // Tapped
    {
        const d = TappedDelegate.createWithIid(alloc, ctx, &onTapped, &com.IID_TappedEventHandler) catch return;
        defer d.release();
        _ = ui_elem.AddTapped(d.comPtr()) catch return;
    }

    // PointerEntered
    {
        const d = PointerDelegate.createWithIid(alloc, ctx, &onPointerEntered, &gen.IID_PointerEventHandler) catch return;
        defer d.release();
        _ = ui_elem.AddPointerEntered(d.comPtr()) catch return;
    }

    // PointerExited
    {
        const d = PointerDelegate.createWithIid(alloc, ctx, &onPointerExited, &gen.IID_PointerEventHandler) catch return;
        defer d.release();
        _ = ui_elem.AddPointerExited(d.comPtr()) catch return;
    }

    log.info("caption_buttons: {s} handlers registered", .{name});
}
