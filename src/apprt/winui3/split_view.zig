//! Two-pane split view: pure state/layout logic.
//!
//! The split view shows two tabs of the same window at once (top/bottom or
//! left/right). Each pane gets a one-line header with the tab number and
//! title so the user can tell which two tabs are on screen. The tab strip
//! itself is unchanged.
//!
//! Everything here is free of COM / XAML so it can be tested exhaustively.
//! `surface_binding.zig` turns a `Layout` into Grid rows/columns.
const std = @import("std");

pub const Mode = enum { none, top_bottom, left_right };

/// Indices (into the tab list) of the two tabs shown. `first` is the
/// top / left pane, and always `first < second`.
pub const Pair = struct { first: usize, second: usize };

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
    return .none;
}

/// Button / Ctrl+Shift+E cycle: off → top/bottom → left/right → off.
pub fn nextMode(mode: Mode) Mode {
    return switch (mode) {
        .none => .top_bottom,
        .top_bottom => .left_right,
        .left_right => .none,
    };
}

/// Ctrl+Shift+E / O: pressing the shortcut for the current mode turns it off.
pub fn toggleMode(current: Mode, requested: Mode) Mode {
    return if (current == requested) .none else requested;
}

fn ordered(a: usize, b: usize) Pair {
    return .{ .first = @min(a, b), .second = @max(a, b) };
}

/// Pair chosen when split view is switched on: the active tab plus the one
/// used just before it (else its neighbour). Requires `count >= 2`.
pub fn initialPair(active: usize, last_active: ?usize, count: usize) Pair {
    std.debug.assert(count >= 2);
    const primary = @min(active, count - 1);
    const partner = blk: {
        if (last_active) |last| {
            if (last < count and last != primary) break :blk last;
        }
        break :blk if (primary + 1 < count) primary + 1 else primary - 1;
    };
    return ordered(primary, partner);
}

/// True when the pair can be shown as-is for `count` tabs.
pub fn pairValid(p: Pair, count: usize) bool {
    return p.first < p.second and p.second < count;
}

/// A tab outside the pair was selected in the tab strip. It replaces the
/// pane that was NOT focused (`prev`), so the pane being worked in stays.
/// A tab already in the pair leaves the pair unchanged.
pub fn pairOnSelect(p: Pair, prev: usize, new: usize) Pair {
    if (new == p.first or new == p.second) return p;
    const keep = if (prev == p.second) p.second else p.first;
    return ordered(keep, new);
}

/// A new tab was opened (it is appended at `new_idx`) while `prev` was
/// focused: show prev + the new tab.
pub fn pairOnNewTab(prev: usize, new_idx: usize) Pair {
    std.debug.assert(new_idx >= 1);
    const keep = if (prev < new_idx) prev else new_idx - 1;
    return ordered(keep, new_idx);
}

/// Tab `removed` was closed; `new_len` tabs remain (>= 2) and `active` is
/// the already-adjusted focused index. Surviving pair members keep showing
/// (indices shifted); a closed member is replaced by the active tab, or by
/// the lowest index not already shown.
pub fn pairOnRemove(p: Pair, removed: usize, new_len: usize, active: usize) Pair {
    std.debug.assert(new_len >= 2);
    std.debug.assert(active < new_len);
    const shift = struct {
        fn f(i: usize, r: usize) ?usize {
            if (i == r) return null;
            return if (i > r) i - 1 else i;
        }
    }.f;
    var a = shift(p.first, removed);
    var b = shift(p.second, removed);
    if (a == null and b == null) {
        // Cannot happen (pair members are distinct), but stay total.
        return initialPair(active, null, new_len);
    }
    const survivor = (a orelse b).?;
    const replacement: usize = if (active != survivor) active else if (survivor == 0) 1 else 0;
    if (a == null) a = replacement;
    if (b == null) b = replacement;
    return ordered(a.?, b.?);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

pub const Track = enum { auto, star };
pub const Cell = struct { row: i32, col: i32 };

pub const Layout = struct {
    rows: []const Track,
    cols: []const Track,
    /// [0] = first pane (top/left), [1] = second pane.
    header: [2]Cell,
    pane: [2]Cell,
};

const tb_rows = [_]Track{ .auto, .star, .auto, .star };
const tb_cols = [_]Track{.star};
const lr_rows = [_]Track{ .auto, .star };
const lr_cols = [_]Track{ .star, .star };

/// Grid plan for a split mode; null for `.none` (single pane, no headers).
/// Headers sit directly above their pane.
pub fn layoutFor(mode: Mode) ?Layout {
    return switch (mode) {
        .none => null,
        .top_bottom => .{
            .rows = &tb_rows,
            .cols = &tb_cols,
            .header = .{ .{ .row = 0, .col = 0 }, .{ .row = 2, .col = 0 } },
            .pane = .{ .{ .row = 1, .col = 0 }, .{ .row = 3, .col = 0 } },
        },
        .left_right => .{
            .rows = &lr_rows,
            .cols = &lr_cols,
            .header = .{ .{ .row = 0, .col = 0 }, .{ .row = 0, .col = 1 } },
            .pane = .{ .{ .row = 1, .col = 0 }, .{ .row = 1, .col = 1 } },
        },
    };
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
// Tests — every (count, pair, prev/removed/active) combination up to 6 tabs.
// ---------------------------------------------------------------------------

const testing = std.testing;
const MAX_TABS = 6;

test "parseMode: aliases and fallback" {
    try testing.expectEqual(Mode.top_bottom, parseMode("top_bottom"));
    try testing.expectEqual(Mode.top_bottom, parseMode("TOP_BOTTOM"));
    try testing.expectEqual(Mode.top_bottom, parseMode("vertical"));
    try testing.expectEqual(Mode.top_bottom, parseMode("1"));
    try testing.expectEqual(Mode.left_right, parseMode("left_right"));
    try testing.expectEqual(Mode.left_right, parseMode("Horizontal"));
    try testing.expectEqual(Mode.none, parseMode(""));
    try testing.expectEqual(Mode.none, parseMode("0"));
    try testing.expectEqual(Mode.none, parseMode("bogus"));
}

test "nextMode / toggleMode: all mode combinations" {
    try testing.expectEqual(Mode.top_bottom, nextMode(.none));
    try testing.expectEqual(Mode.left_right, nextMode(.top_bottom));
    try testing.expectEqual(Mode.none, nextMode(.left_right));
    for (std.enums.values(Mode)) |cur| {
        for (std.enums.values(Mode)) |req| {
            const got = toggleMode(cur, req);
            if (cur == req) try testing.expectEqual(Mode.none, got) else try testing.expectEqual(req, got);
        }
    }
}

test "initialPair: valid and contains active, all inputs" {
    var count: usize = 2;
    while (count <= MAX_TABS) : (count += 1) {
        for (0..count) |active| {
            // last_active: null, every index, and one out of range.
            var l: usize = 0;
            while (l <= count + 1) : (l += 1) {
                const last: ?usize = if (l == count + 1) null else l;
                const p = initialPair(active, last, count);
                try testing.expect(pairValid(p, count));
                try testing.expect(p.first == active or p.second == active);
                if (last) |li| {
                    if (li < count and li != active)
                        try testing.expect(p.first == li or p.second == li);
                }
            }
        }
    }
}

test "pairOnSelect: valid, keeps focused pane, shows new tab" {
    var count: usize = 2;
    while (count <= MAX_TABS) : (count += 1) {
        for (0..count) |f| {
            for (f + 1..count) |s| {
                const p = Pair{ .first = f, .second = s };
                // prev is always a pane of the pair (focus lives in one of them).
                for ([_]usize{ f, s }) |prev| {
                    for (0..count) |new| {
                        const q = pairOnSelect(p, prev, new);
                        try testing.expect(pairValid(q, count));
                        try testing.expect(q.first == new or q.second == new);
                        if (new == f or new == s) {
                            try testing.expectEqual(p, q);
                        } else {
                            try testing.expect(q.first == prev or q.second == prev);
                        }
                    }
                }
            }
        }
    }
}

test "pairOnNewTab: shows previous and the new tab" {
    var new_idx: usize = 1;
    while (new_idx < MAX_TABS) : (new_idx += 1) {
        var prev: usize = 0;
        while (prev <= new_idx) : (prev += 1) {
            const q = pairOnNewTab(prev, new_idx);
            try testing.expect(pairValid(q, new_idx + 1));
            try testing.expectEqual(new_idx, q.second);
            if (prev < new_idx) try testing.expectEqual(prev, q.first);
        }
    }
}

test "pairOnRemove: valid, survivors kept, active shown when replaced" {
    var old_len: usize = 3;
    while (old_len <= MAX_TABS + 1) : (old_len += 1) {
        const new_len = old_len - 1;
        for (0..old_len) |f| {
            for (f + 1..old_len) |s| {
                for (0..old_len) |removed| {
                    for (0..new_len) |active| try checkRemove(f, s, removed, new_len, active);
                }
            }
        }
    }
}

fn checkRemove(f: usize, s: usize, removed: usize, new_len: usize, active: usize) !void {
    {
        const q = pairOnRemove(.{ .first = f, .second = s }, removed, new_len, active);
        try testing.expect(pairValid(q, new_len));
        for ([_]usize{ f, s }) |m| {
            if (m == removed) continue;
            const shifted = if (m > removed) m - 1 else m;
            try testing.expect(q.first == shifted or q.second == shifted);
        }
        if (removed == f or removed == s) {
            const survivor_old = if (removed == f) s else f;
            const survivor = if (survivor_old > removed) survivor_old - 1 else survivor_old;
            if (active != survivor) try testing.expect(q.first == active or q.second == active);
        } else {
            // Neither shown tab closed: pair only shifts.
            const ef = if (f > removed) f - 1 else f;
            const es = if (s > removed) s - 1 else s;
            try testing.expectEqual(Pair{ .first = ef, .second = es }, q);
        }
    }
}

test "layoutFor: every split mode has distinct cells inside the grid, header above pane" {
    try testing.expect(layoutFor(.none) == null);
    for ([_]Mode{ .top_bottom, .left_right }) |mode| {
        const l = layoutFor(mode).?;
        const cells = [_]Cell{ l.header[0], l.pane[0], l.header[1], l.pane[1] };
        for (cells, 0..) |c, i| {
            try testing.expect(c.row >= 0 and c.row < l.rows.len);
            try testing.expect(c.col >= 0 and c.col < l.cols.len);
            for (cells[i + 1 ..]) |d| try testing.expect(!(c.row == d.row and c.col == d.col));
        }
        for (0..2) |k| {
            try testing.expectEqual(l.header[k].col, l.pane[k].col);
            try testing.expectEqual(l.header[k].row + 1, l.pane[k].row);
            try testing.expectEqual(Track.auto, l.rows[@intCast(l.header[k].row)]);
            try testing.expectEqual(Track.star, l.rows[@intCast(l.pane[k].row)]);
        }
        // Pane order: first is top (top_bottom) or left (left_right).
        switch (mode) {
            .top_bottom => try testing.expect(l.pane[0].row < l.pane[1].row),
            .left_right => try testing.expect(l.pane[0].col < l.pane[1].col),
            .none => unreachable,
        }
    }
}

test "headerText: number + title, fallback, truncation keeps valid UTF-8" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("1  pwsh", headerText(&buf, 0, "pwsh"));
    try testing.expectEqualStrings("3  Tab 3", headerText(&buf, 2, null));
    try testing.expectEqualStrings("3  Tab 3", headerText(&buf, 2, ""));
    // Japanese title truncated at every buffer size: always valid UTF-8 and a prefix.
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
