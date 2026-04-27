//! Cascade detector unit-contract test for issue #231.
//!
//! Mirrors the algorithmic contract of `src/apprt/winui3/cascade_detector.zig`
//! without dragging in WinUI3 build flags. Same pattern as
//! `repro_watchdog_fires_on_ui_hang.zig` — re-declare the algorithm in a
//! self-contained form so the test runs anywhere `zig test` works.
//!
//! What this test proves
//! ---------------------
//! 1. The wakeup-pending consecutive counter advances under sustained
//!    backpressure and resets when the flag clears — this is the precursor
//!    signal we want to catch *before* the Phase 4 watchdog fires.
//! 2. The cascade callback is one-shot per process: once it has fired under
//!    `Action.trigger`, additional coincident-signal observations do NOT
//!    re-fire the callback (avoids dump spam).
//! 3. The callback is silent under `Action.warn` no matter how many signals
//!    light up — `warn` is a logging-only mode.
//!
//! How to run
//! ----------
//!   zig test -target x86_64-windows -lc tests/repro_cascade_detector_signals.zig

const std = @import("std");
const testing = std.testing;

// -- Minimal mirror of cascade_detector.zig's contract. We don't `@import`
//    the production file because that would pull in the full apprt/winui3
//    transitive deps; this file is meant to be a free-standing reproducer.

const Action = enum { disabled, warn, trigger };

const Stats = struct {
    tick_count: std.atomic.Value(u64) = .init(0),
    tick_warn_count: std.atomic.Value(u64) = .init(0),
    tick_err_count: std.atomic.Value(u64) = .init(0),
};

const Detector = struct {
    action: Action,
    consecutive_wakeup_pending: u32 = 0,
    snap_renderer_locked_event_count: u32 = 0,
    fired: std.atomic.Value(bool) = .init(false),
    on_cascade: ?*const fn (ctx: ?*anyopaque) void = null,
    on_cascade_ctx: ?*anyopaque = null,

    const wakeup_warn_threshold: u32 = 3;

    fn observeWakeup(self: *Detector, pending: bool) bool {
        if (pending) {
            self.consecutive_wakeup_pending +%= 1;
        } else {
            self.consecutive_wakeup_pending = 0;
        }
        return self.consecutive_wakeup_pending >= wakeup_warn_threshold;
    }

    fn observeRendererLocked(self: *Detector, count: u32, circuit_open: bool) bool {
        const delta = count -% self.snap_renderer_locked_event_count;
        const signal = circuit_open or delta >= 3;
        self.snap_renderer_locked_event_count = count;
        return signal;
    }

    fn maybeFireCascade(self: *Detector, lit_signals: u32) void {
        if (lit_signals < 2) return;
        if (self.action != .trigger) return;
        if (self.fired.load(.acquire)) return;
        if (self.on_cascade) |cb| {
            self.fired.store(true, .release);
            cb(self.on_cascade_ctx);
        }
    }
};

test "wakeup-pending consecutive counter latches at threshold then resets" {
    var det = Detector{ .action = .warn };
    try testing.expect(!det.observeWakeup(true));
    try testing.expect(!det.observeWakeup(true));
    try testing.expect(det.observeWakeup(true)); // 3rd consecutive → signal
    try testing.expect(det.observeWakeup(true)); // stays signalled
    try testing.expect(!det.observeWakeup(false)); // resets
    try testing.expect(!det.observeWakeup(true)); // back to 1, no signal
}

test "renderer-locked signal flags on delta or circuit-open" {
    var det = Detector{ .action = .warn };

    // Case 1: Delta >= 3
    try testing.expect(det.observeRendererLocked(3, false));
    try testing.expect(!det.observeRendererLocked(4, false)); // delta 1
    try testing.expect(det.observeRendererLocked(7, false)); // delta 3

    // Case 2: Circuit open
    try testing.expect(det.observeRendererLocked(7, true));
}

test "cascade triggered by wakeup-backlog + renderer-locked" {
    const Counter = struct {
        n: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.n += 1;
        }
    };
    var c = Counter{};
    var det = Detector{ .action = .trigger, .on_cascade = Counter.cb, .on_cascade_ctx = &c };

    // Setup 1 signal: wakeup backlog
    _ = det.observeWakeup(true);
    _ = det.observeWakeup(true);
    const s1 = det.observeWakeup(true);
    try testing.expect(s1);

    // Setup 2nd signal: renderer locked delta
    const s2 = det.observeRendererLocked(3, false);
    try testing.expect(s2);

    // Fire cascade
    var lit: u32 = 0;
    if (s1) lit += 1;
    if (s2) lit += 1;
    det.maybeFireCascade(lit);

    try testing.expectEqual(@as(u32, 1), c.n);
}

test "cascade callback is one-shot under .trigger" {
    const Counter = struct {
        n: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.n += 1;
        }
    };
    var c = Counter{};
    var det = Detector{ .action = .trigger, .on_cascade = Counter.cb, .on_cascade_ctx = &c };
    det.maybeFireCascade(2);
    det.maybeFireCascade(3);
    det.maybeFireCascade(4);
    try testing.expectEqual(@as(u32, 1), c.n);
}

test "cascade callback never fires under .warn" {
    const Counter = struct {
        n: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.n += 1;
        }
    };
    var c = Counter{};
    var det = Detector{ .action = .warn, .on_cascade = Counter.cb, .on_cascade_ctx = &c };
    det.maybeFireCascade(2);
    det.maybeFireCascade(99);
    try testing.expectEqual(@as(u32, 0), c.n);
    try testing.expect(!det.fired.load(.acquire));
}

test "cascade callback never fires under .disabled" {
    const Counter = struct {
        n: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.n += 1;
        }
    };
    var c = Counter{};
    var det = Detector{ .action = .disabled, .on_cascade = Counter.cb, .on_cascade_ctx = &c };
    det.maybeFireCascade(2);
    try testing.expectEqual(@as(u32, 0), c.n);
}

test "cascade requires 2+ signals" {
    const Counter = struct {
        n: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.n += 1;
        }
    };
    var c = Counter{};
    var det = Detector{ .action = .trigger, .on_cascade = Counter.cb, .on_cascade_ctx = &c };
    det.maybeFireCascade(0);
    det.maybeFireCascade(1);
    try testing.expectEqual(@as(u32, 0), c.n);
    det.maybeFireCascade(2);
    try testing.expectEqual(@as(u32, 1), c.n);
}
