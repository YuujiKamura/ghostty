//! Split view: show every tab of the window at once, pure layout logic.
//!
//! Modes: all tabs stacked top-to-bottom, side by side left-to-right, or in
//! a grid (2x2 for four tabs, ...). Each pane gets a one-line header with
//! the tab number and title; the tab strip itself is unchanged.
//!
//! Everything here is free of COM / XAML so it can be tested exhaustively.
//! `surface_binding.zig` turns a `Layout` into Grid rows/columns.
const std = @import("std");

pub const Mode = enum { none, top_bottom, left_right, grid };

/// At most this many tabs are shown at once (more panes get too small to
/// read). Other tabs stay reachable through the tab strip.
pub const MAX_PANES = 4;

/// Parse the `KS_SPLIT_VIEW` launch env var. Used by the UIA suite to start
/// in split mode without sending keys to whatever window is in front.
pub fn parseMode(raw: []const u8) Mode {
    if (std.ascii.eqlIgnoreCase(raw, "top_bottom") or
        std.ascii.eqlIgnoreCase(raw, "topbottom") or
        std.ascii.eqlIgnoreCase(raw, "vertical") or
        std.ascii.eqlIgnoreCase(raw, "1"))
        return .top_bottom;
    if (std.ascii.eqlIgnoreCase(raw, "left_right") or
        std.ascii.eqlIgnoreCase(raw, "leftright") or
        std.ascii.eqlIgnoreCase(raw, "horizontal"))
        return .left_right;
    if (std.ascii.eqlIgnoreCase(raw, "grid") or
        std.ascii.eqlIgnoreCase(raw, "quad"))
        return .grid;
    return .none;
}

/// Split button cycle: off -> top/bottom -> left/right -> grid -> off.
pub fn nextMode(mode: Mode) Mode {
    return switch (mode) {
        .none => .top_bottom,
        .top_bottom => .left_right,
        .left_right => .grid,
        .grid => .none,
    };
}

/// Ctrl+Shift+E / O: pressing the shortcut for the current mode turns it off.
pub fn toggleMode(current: Mode, requested: Mode) Mode {
    return if (current == requested) .none else requested;
}

/// Number of panes for `count` tabs.
pub fn paneCount(count: usize) usize {
    return @min(count, MAX_PANES);
}

/// First tab of the shown window of `paneCount(count)` consecutive tabs.
/// Moves as little as possible from `prev_start` so that `active` is
/// inside, and stays within the tab list (e.g. after tabs were closed).
pub fn windowStart(prev_start: usize, count: usize, active: usize) usize {
    const n = paneCount(count);
    if (n == 0) return 0;
    var start = @min(prev_start, count - n);
    if (active < count) {
        if (active < start) start = active;
        if (active >= start + n) start = active + 1 - n;
    }
    return start;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

pub const Track = enum { auto, star };

pub const Cell = struct { row: i32, col: i32, col_span: i32 = 1 };

/// Grid plan: header row (auto height) directly above each pane (star).
pub const Layout = struct {
    rows_buf: [2 * MAX_PANES]Track = undefined,
    cols_buf: [MAX_PANES]Track = undefined,
    n_rows: usize = 0,
    n_cols: usize = 0,
    header: [MAX_PANES]Cell = undefined,
    pane: [MAX_PANES]Cell = undefined,
    panes: usize = 0,

    pub fn rows(self: *const Layout) []const Track {
        return self.rows_buf[0..self.n_rows];
    }
    pub fn cols(self: *const Layout) []const Track {
        return self.cols_buf[0..self.n_cols];
    }
};

/// Columns of the grid mode for `n` panes: the smallest c with c*c >= n
/// (2 -> 2x1, 3/4 -> 2x2, 5/6 -> 3x2, 7..9 -> 3x3).
pub fn gridColumns(n: usize) usize {
    var c: usize = 1;
    while (c * c < n) c += 1;
    return c;
}

/// Layout for `n` panes (2..MAX_PANES) in `mode`; null for `.none` or n < 2.
pub fn layoutFor(mode: Mode, n: usize) ?Layout {
    if (mode == .none or n < 2 or n > MAX_PANES) return null;
    var l = Layout{ .panes = n };
    const c: usize = switch (mode) {
        .top_bottom => 1,
        .left_right => n,
        .grid => gridColumns(n),
        .none => unreachable,
    };
    const r = (n + c - 1) / c;
    l.n_cols = c;
    for (0..c) |i| l.cols_buf[i] = .star;
    l.n_rows = 2 * r;
    for (0..r) |i| {
        l.rows_buf[2 * i] = .auto;
        l.rows_buf[2 * i + 1] = .star;
    }
    for (0..n) |i| {
        const row: i32 = @intCast(i / c);
        const col: i32 = @intCast(i % c);
        // The last pane stretches over any empty cells left in its row.
        const span: i32 = if (i == n - 1) @as(i32, @intCast(c)) - col else 1;
        l.header[i] = .{ .row = 2 * row, .col = col, .col_span = span };
        l.pane[i] = .{ .row = 2 * row + 1, .col = col, .col_span = span };
    }
    return l;
}

// ---------------------------------------------------------------------------
// Header text
// ---------------------------------------------------------------------------

/// "2  title" — tab number (1-based, as in the tab strip) and its title.
/// Falls back to "2  Tab 2" when the tab has no title yet. Output is
/// truncated to fit `buf` (never splitting a UTF-8 sequence).
pub fn headerText(buf: []u8, tab_idx: usize, title: ?[]const u8) []const u8 {
    const n = tab_idx + 1;
    const t = title orelse "";
    const s = if (t.len == 0)
        std.fmt.bufPrint(buf, "{d}  Tab {d}", .{ n, n })
    else
        std.fmt.bufPrint(buf, "{d}  {s}", .{ n, t });
    if (s) |ok| return ok else |_| {}
    // Too long: write what fits, then back off to a UTF-8 boundary.
    var w = std.io.fixedBufferStream(buf);
    w.writer().print("{d}  {s}", .{ n, t }) catch {};
    var end = w.pos;
    while (end > 0 and end < buf.len and (buf[end] & 0xC0) == 0x80) end -= 1;
    if (end == buf.len) {
        // Buffer filled exactly; make sure the final byte ends a code point.
        var i = end;
        while (i > 0 and (buf[i - 1] & 0xC0) == 0x80) i -= 1;
        if (i > 0) {
            const lead = buf[i - 1];
            const need: usize = if (lead < 0x80) 1 else if (lead >> 5 == 0b110) 2 else if (lead >> 4 == 0b1110) 3 else 4;
            if (end - (i - 1) < need) end = i - 1;
        }
    }
    return buf[0..end];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "parseMode: aliases and fallback" {
    try testing.expectEqual(Mode.top_bottom, parseMode("top_bottom"));
    try testing.expectEqual(Mode.top_bottom, parseMode("TOP_BOTTOM"));
    try testing.expectEqual(Mode.top_bottom, parseMode("vertical"));
    try testing.expectEqual(Mode.top_bottom, parseMode("1"));
    try testing.expectEqual(Mode.left_right, parseMode("left_right"));
    try testing.expectEqual(Mode.left_right, parseMode("Horizontal"));
    try testing.expectEqual(Mode.grid, parseMode("grid"));
    try testing.expectEqual(Mode.grid, parseMode("QUAD"));
    try testing.expectEqual(Mode.none, parseMode(""));
    try testing.expectEqual(Mode.none, parseMode("0"));
    try testing.expectEqual(Mode.none, parseMode("bogus"));
}

test "nextMode cycles through every mode once; toggleMode all combinations" {
    var m: Mode = .none;
    var seen = std.EnumSet(Mode).initEmpty();
    for (0..std.enums.values(Mode).len) |_| {
        try testing.expect(!seen.contains(m));
        seen.insert(m);
        m = nextMode(m);
    }
    try testing.expectEqual(Mode.none, m);
    for (std.enums.values(Mode)) |cur| {
        for (std.enums.values(Mode)) |req| {
            const got = toggleMode(cur, req);
            if (cur == req) try testing.expectEqual(Mode.none, got) else try testing.expectEqual(req, got);
        }
    }
}

test "windowStart: active always shown, window inside the list, minimal moves" {
    var count: usize = 1;
    while (count <= 9) : (count += 1) {
        const n = paneCount(count);
        try testing.expectEqual(@min(count, MAX_PANES), n);
        var prev: usize = 0;
        while (prev <= count + 2) : (prev += 1) {
            for (0..count) |active| {
                const s = windowStart(prev, count, active);
                try testing.expect(s + n <= count);
                try testing.expect(active >= s and active < s + n);
                // Unmoved when the active tab was already inside the (clamped) old window.
                const old = @min(prev, count - n);
                if (active >= old and active < old + n) try testing.expectEqual(old, s);
            }
        }
    }
    try testing.expectEqual(@as(usize, 0), windowStart(0, 0, 0));
}

fn checkLayout(mode: Mode, n: usize) !void {
    const l = layoutFor(mode, n).?;
    try testing.expectEqual(n, l.panes);
    const R: i32 = @intCast(l.n_rows);
    const C: i32 = @intCast(l.n_cols);
    // Every cell of the grid is covered by exactly one header or pane.
    var used = [_][MAX_PANES]bool{[_]bool{false} ** MAX_PANES} ** (2 * MAX_PANES);
    for (0..n) |i| {
        for ([_]Cell{ l.header[i], l.pane[i] }) |cell| {
            try testing.expect(cell.row >= 0 and cell.row < R);
            try testing.expect(cell.col >= 0 and cell.col_span >= 1 and cell.col + cell.col_span <= C);
            var c = cell.col;
            while (c < cell.col + cell.col_span) : (c += 1) {
                const r: usize = @intCast(cell.row);
                const cc: usize = @intCast(c);
                try testing.expect(!used[r][cc]);
                used[r][cc] = true;
            }
        }
        // Header directly above its pane, same width.
        try testing.expectEqual(l.header[i].col, l.pane[i].col);
        try testing.expectEqual(l.header[i].col_span, l.pane[i].col_span);
        try testing.expectEqual(l.header[i].row + 1, l.pane[i].row);
        try testing.expectEqual(Track.auto, l.rows()[@intCast(l.header[i].row)]);
        try testing.expectEqual(Track.star, l.rows()[@intCast(l.pane[i].row)]);
    }
    for (0..l.n_rows) |r| for (0..l.n_cols) |c| try testing.expect(used[r][c]);
    // Reading order: tab order goes left-to-right, then top-to-bottom.
    for (1..n) |i| {
        const a = l.pane[i - 1];
        const b = l.pane[i];
        try testing.expect(b.row > a.row or (b.row == a.row and b.col > a.col));
    }
    switch (mode) {
        .top_bottom => try testing.expectEqual(@as(usize, 1), l.n_cols),
        .left_right => try testing.expectEqual(@as(usize, 2), l.n_rows),
        .grid => {
            // Never more columns than rows+1 and no empty grid row.
            try testing.expect(l.n_cols * l.n_cols >= n);
            try testing.expect((l.n_rows / 2 - 1) * l.n_cols < n);
        },
        .none => unreachable,
    }
}

test "layoutFor: every split mode x pane count fills the grid exactly" {
    for ([_]Mode{ .top_bottom, .left_right, .grid }) |mode| {
        try testing.expect(layoutFor(mode, 0) == null);
        try testing.expect(layoutFor(mode, 1) == null);
        try testing.expect(layoutFor(mode, MAX_PANES + 1) == null);
        var n: usize = 2;
        while (n <= MAX_PANES) : (n += 1) try checkLayout(mode, n);
    }
    for (0..MAX_PANES + 2) |n| try testing.expect(layoutFor(.none, n) == null);
    // Grid shapes the user sees.
    try testing.expectEqual(@as(usize, 2), layoutFor(.grid, 4).?.n_cols); // 2x2
    try testing.expectEqual(@as(i32, 2), layoutFor(.grid, 3).?.pane[2].col_span); // 3rd spans the bottom row
}

test "headerText: number + title, fallback, truncation keeps valid UTF-8" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("1  pwsh", headerText(&buf, 0, "pwsh"));
    try testing.expectEqualStrings("3  Tab 3", headerText(&buf, 2, null));
    try testing.expectEqualStrings("3  Tab 3", headerText(&buf, 2, ""));
    const title = "ゴーストティ分割表示テスト";
    var full_buf: [128]u8 = undefined;
    const full = headerText(&full_buf, 1, title);
    var size: usize = 1;
    while (size <= full.len + 2) : (size += 1) {
        var small: [128]u8 = undefined;
        const out = headerText(small[0..size], 1, title);
        try testing.expect(std.unicode.utf8ValidateSlice(out));
        try testing.expect(std.mem.startsWith(u8, full, out));
        try testing.expect(out.len <= size);
    }
}
