/// Surface binding for winui3 — WT-style Clear+Append tab content switching.
/// Mirrors Windows Terminal's TerminalPage::_UpdatedSelectedTab() pattern.
const std = @import("std");
const App = @import("App.zig");
const Surface = @import("Surface.zig").Surface(App);
const com = @import("com.zig");
const winrt = @import("winrt.zig");
const os = @import("os.zig");
const util = @import("util.zig");
const split_view = @import("split_view.zig");

const log = std.log.scoped(.winui3);

pub fn setTabItemContent(tvi_insp: *winrt.IInspectable, content: ?*winrt.IInspectable) !void {
    var cc_guard = winrt.ComRef(com.IContentControl).init(try tvi_insp.queryInterface(com.IContentControl));
    defer cc_guard.deinit();
    const cc = cc_guard.get();
    if (content) |c| {
        try cc.SetContent(c);
    } else {
        try cc.SetContent(@as(?*anyopaque, null));
    }
}

/// WT-style tab content switch: Clear tab_content_grid children, then Append the active tab's panel
/// (or every tab, up to split_view.MAX_PANES, when split_mode != .none).
pub fn updateSelectedTab(self: anytype, idx: usize) void {
    const count = self.countSurfaces();
    if (idx >= count) return;
    const tab_content = self.tab_content_grid orelse return;

    const content_panel = tab_content.queryInterface(com.IPanel) catch |err| {
        log.warn("updateSelectedTab: QI IPanel failed: {}", .{err});
        return;
    };
    defer content_panel.release();
    const children_raw = content_panel.Children() catch |err| {
        log.warn("updateSelectedTab: Children() failed: {}", .{err});
        return;
    };
    // Same @ptrCast as App.zig initXaml step 8 — proven to work for append/clear.
    const children: *com.IVector = @ptrCast(@alignCast(children_raw));
    defer children.release();

    // Clear children first so we can cleanly re-configure Grid rows/columns.
    children.clear() catch |err| {
        log.warn("updateSelectedTab: clear() failed: {}", .{err});
        return;
    };

    const grid_opt = tab_content.queryInterface(com.IGrid) catch null;
    defer if (grid_opt) |g| g.release();

    if (grid_opt) |grid| {
        if (grid.ColumnDefinitions()) |col_defs_raw| {
            const col_defs: *com.IVector = @ptrCast(@alignCast(col_defs_raw));
            defer col_defs.release();
            col_defs.clear() catch {};
        } else |_| {}
        if (grid.RowDefinitions()) |row_defs_raw| {
            const row_defs: *com.IVector = @ptrCast(@alignCast(row_defs_raw));
            defer row_defs.release();
            row_defs.clear() catch {};
        } else |_| {}
        grid.SetColumnSpacing(0.0) catch {};
        grid.SetRowSpacing(0.0) catch {};
    }

    const use_split = self.split_mode != .none and count >= 2;

    if (use_split) {
        if (attachSplitPanels(self, grid_opt, children)) {
            return;
        }
        // Fallback to single panel if Grid setup failed.
    }

    const surface = self.getSurface(idx) orelse {
        log.warn("updateSelectedTab: idx={} has no panel", .{idx});
        return;
    };
    const panel: *winrt.IInspectable = surface.surface_grid orelse surface.swap_chain_panel orelse {
        log.warn("updateSelectedTab: idx={} has no panel", .{idx});
        return;
    };

    if (winrt.hstring("Microsoft.UI.Xaml.Controls.Grid")) |grid_class| {
        defer winrt.deleteHString(grid_class);
        if (winrt.getActivationFactory(com.IGridStatics, grid_class)) |grid_statics| {
            defer grid_statics.release();
            setGridCell(grid_statics, panel, .{ .row = 0, .col = 0 }) catch {};
        } else |_| {}
    } else |_| {}

    children.append(@ptrCast(panel)) catch |err| {
        log.warn("updateSelectedTab: append() failed: {}", .{err});
        return;
    };

    // Re-bind swap chain — entering the visual tree may require compositor re-attachment.
    surface.rebindSwapChain();

    log.info("updateSelectedTab: idx={} panel=0x{x}", .{ idx, @intFromPtr(panel) });
}

/// Grid.SetRow/SetColumn take a FrameworkElement ABI pointer, not the
/// IInspectable we hold. Passing the IInspectable makes XAML call through
/// the wrong vtable (access violation in Microsoft.UI.Xaml.dll at startup).
fn setGridCell(grid_statics: *com.IGridStatics, elem: *winrt.IInspectable, cell: split_view.Cell) !void {
    const fe = try elem.queryInterface(com.IFrameworkElement);
    defer fe.release();
    try grid_statics.SetRow(@ptrCast(fe), cell.row);
    try grid_statics.SetColumn(@ptrCast(fe), cell.col);
    try grid_statics.SetColumnSpan(@ptrCast(fe), cell.col_span);
}

fn appendTracks(vec_raw: anytype, comptime class_name: []const u8, tracks: []const split_view.Track, comptime is_row: bool) bool {
    const defs: *com.IVector = @ptrCast(@alignCast(vec_raw));
    defer defs.release();
    const class = winrt.hstring(class_name) catch return false;
    defer winrt.deleteHString(class);
    for (tracks) |t| {
        const insp = winrt.activateInstance(class) catch return false;
        defer _ = insp.release();
        const len: com.GridLength = switch (t) {
            .auto => .{ .Value = 1.0, .GridUnitType = com.GridUnitType.Auto },
            .star => .{ .Value = 1.0, .GridUnitType = com.GridUnitType.Star },
        };
        if (is_row) {
            const def = insp.queryInterface(com.IRowDefinition) catch return false;
            defer def.release();
            def.SetHeight(len) catch {};
        } else {
            const def = insp.queryInterface(com.IColumnDefinition) catch return false;
            defer def.release();
            def.SetWidth(len) catch {};
        }
        defs.append(@ptrCast(insp)) catch return false;
    }
    return true;
}

fn attachSplitPanels(self: anytype, grid_opt: ?*com.IGrid, children: *com.IVector) bool {
    const grid = grid_opt orelse return false;
    const count = self.countSurfaces();
    const n = split_view.paneCount(count);
    self.split_start = split_view.windowStart(self.split_start, count, self.active_surface_idx);
    const layout = split_view.layoutFor(self.split_mode, n) orelse return false;
    var surfaces: [split_view.MAX_PANES]*Surface = undefined;
    var panels: [split_view.MAX_PANES]*winrt.IInspectable = undefined;
    for (0..n) |k| {
        surfaces[k] = self.getSurface(self.split_start + k) orelse return false;
        panels[k] = surfaces[k].surface_grid orelse surfaces[k].swap_chain_panel orelse return false;
    }

    const grid_class = winrt.hstring("Microsoft.UI.Xaml.Controls.Grid") catch return false;
    defer winrt.deleteHString(grid_class);
    const grid_statics = winrt.getActivationFactory(com.IGridStatics, grid_class) catch return false;
    defer grid_statics.release();

    if (!appendTracks(grid.RowDefinitions() catch return false, "Microsoft.UI.Xaml.Controls.RowDefinition", layout.rows(), true)) return false;
    if (!appendTracks(grid.ColumnDefinitions() catch return false, "Microsoft.UI.Xaml.Controls.ColumnDefinition", layout.cols(), false)) return false;
    // A 2px gap between side-by-side panes; stacked panes are separated by
    // the header rows.
    if (layout.n_cols > 1) grid.SetColumnSpacing(2.0) catch {};

    for (0..n) |k| {
        if (self.ensureSplitHeader(k)) |h| {
            setGridCell(grid_statics, h.root, layout.header[k]) catch {};
            children.append(@ptrCast(h.root)) catch {};
        }
        setGridCell(grid_statics, panels[k], layout.pane[k]) catch return false;
        children.append(@ptrCast(panels[k])) catch return false;
    }

    for (surfaces[0..n]) |s| s.rebindSwapChain();
    refreshSplitHeaders(self);

    log.info("updateSelectedTab (split {s}): tabs {}..{} of {}", .{ @tagName(self.split_mode), self.split_start + 1, self.split_start + n, count });
    return true;
}

const header_active_bg = com.Color{ .A = 0xFF, .R = 0x2F, .G = 0x5F, .B = 0xC8 };
const header_active_fg = com.Color{ .A = 0xFF, .R = 0xFF, .G = 0xFF, .B = 0xFF };
const header_idle_bg = com.Color{ .A = 0xFF, .R = 0x2A, .G = 0x2A, .B = 0x2A };
const header_idle_fg = com.Color{ .A = 0xFF, .R = 0x9A, .G = 0x9A, .B = 0x9A };

/// Update split header text ("2  title") and highlight the focused pane.
/// No-op outside split view. Safe to call on every title change.
pub fn refreshSplitHeaders(self: anytype) void {
    if (self.split_mode == .none) return;
    const n = split_view.paneCount(self.countSurfaces());
    for (0..n) |k| {
        const idx = self.split_start + k;
        const h = self.split_headers[k] orelse continue;
        const surface = self.getSurface(idx) orelse continue;
        const active = idx == self.active_surface_idx;

        var buf: [256]u8 = undefined;
        const text = split_view.headerText(&buf, idx, if (surface.getTitle()) |t| t[0..t.len] else null);
        var wbuf: [256]u16 = undefined;
        const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch continue;
        if (winrt.createHString(wbuf[0..wlen])) |hs| {
            defer winrt.deleteHString(hs);
            if (util.boxString(hs)) |boxed| {
                defer _ = boxed.release();
                h.label.SetContent(@ptrCast(boxed)) catch {};
            } else |_| {}
        } else |_| {}

        if (App.solidBrush(if (active) header_active_bg else header_idle_bg)) |b| {
            defer b.release();
            h.panel.SetBackground(@ptrCast(b)) catch {};
        } else |_| {}
        if (App.solidBrush(if (active) header_active_fg else header_idle_fg)) |b| {
            defer b.release();
            h.label_control.SetForeground(@ptrCast(b)) catch {};
        } else |_| {}
    }
}

/// Is surface `s` one of the tabs shown in split view?
pub fn isSplitMember(self: anytype, s: *Surface) bool {
    if (self.split_mode == .none) return false;
    const n = split_view.paneCount(self.countSurfaces());
    for (0..n) |k| {
        if (self.getSurface(self.split_start + k)) |shown| {
            if (shown == s) return true;
        }
    }
    return false;
}

/// Ensure the currently active surface's panel is displayed.
/// Called from Surface.onLoaded() when a SwapChainPanel enters the visual tree.
pub fn ensureVisibleSurfaceAttached(self: anytype, surface: *Surface) void {
    if (self.tab_view == null) return;
    const tab_count = self.countSurfaces();
    var i: usize = 0;
    while (i < tab_count) : (i += 1) {
        if (self.getSurface(i)) |s| {
            if (s == surface and i == self.active_surface_idx) {
                updateSelectedTab(self, i);
                return;
            }
        }
    }
}
