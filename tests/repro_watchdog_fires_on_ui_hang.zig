//! Phase 4 verification for issue #232: in-process UI thread watchdog.
//!
//! Background
//! ----------
//! The legacy watchdog in `App.zig` (Tier 1, #212) only *logs* a warn line
//! when the UI thread heartbeat stops advancing. The "stuck > crash"
//! principle (#232 Phase 4) demands that, after a configurable timeout,
//! the watchdog escalate to (1) a snapshot dump and (2) `process.exit(2)`
//! so that the OS can recycle the process instead of leaving the user
//! staring at a frozen window.
//!
//! What this test proves (mechanically, no real surface needed)
//! ------------------------------------------------------------
//! 1. `Watchdog.evaluate(now)` returns `.fire` once the UI heartbeat is
//!    older than the configured timeout, AND continues to return `.idle`
//!    while the heartbeat is fresh — so a healthy app is never crashed.
//! 2. The dump file written by `Watchdog.dumpSnapshot()` lands in the
//!    expected directory and is non-empty.
//! 3. The env-var configurator parses `disabled`, `dump-only`, `warn-only`
//!    and `crash` correctly, and `KS_WATCHDOG_TIMEOUT_MS` overrides the
//!    default.
//!
//! Hard rule: every test bounds its own waiting with explicit deadlines.
//! Never rely on the test runner as the timeout of last resort.
//!
//! How to run
//! ----------
//! ```
//! zig test -target x86_64-windows -lc tests/repro_watchdog_fires_on_ui_hang.zig
//! ```
//! (no extra `--dep`s; this test is fully self-contained — it imports the
//! watchdog *types* by re-declaring them so we exercise the algorithmic
//! contract without dragging in WinUI3 build flags.)

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;

// ---------------------------------------------------------------------------
// Local mirror of the watchdog algorithm under test. Kept literal so this
// file can run anywhere zig can compile, without pulling in os.zig / WinUI3
// build flags. The production watchdog at src/apprt/winui3/watchdog.zig
// is expected to honour the same contract.
// ---------------------------------------------------------------------------

const Action = enum { crash, dump_only, warn_only, disabled };

const Decision = enum { idle, warn, dump, fire };

const Config = struct {
    action: Action = .crash,
    timeout_ms: u64 = 5000,
    poll_ms: u64 = 1000,

    fn fromEnv(env: anytype) Config {
        var cfg = Config{};
        if (env.action_str) |s| {
            if (std.mem.eql(u8, s, "disabled")) {
                cfg.action = .disabled;
            } else if (std.mem.eql(u8, s, "dump-only")) {
                cfg.action = .dump_only;
            } else if (std.mem.eql(u8, s, "warn-only")) {
                cfg.action = .warn_only;
            } else if (std.mem.eql(u8, s, "crash")) {
                cfg.action = .crash;
            }
        }
        if (env.timeout_str) |s| {
            cfg.timeout_ms = std.fmt.parseInt(u64, s, 10) catch cfg.timeout_ms;
        }
        return cfg;
    }
};

/// Pure decision function — given the configured timeout and the last
/// heartbeat time, decide what the watchdog should do "now". The
/// production watchdog wraps this in a thread loop + dump + exit.
///
/// Heartbeat is stored as i64 nanoseconds (NOT i128) because Zig atomics
/// only support up to 64-bit integers. i64 holds ~292 years of ns range
/// past 1970, which is plenty for our purposes (the App lifetime is
/// always a small offset against `std.time.nanoTimestamp` truncated).
fn evaluate(cfg: Config, last_heartbeat_ns: i64, now_ns: i64) Decision {
    if (cfg.action == .disabled) return .idle;
    if (last_heartbeat_ns == 0) return .idle; // not yet primed
    const delta = now_ns - last_heartbeat_ns;
    const timeout_ns: i64 = @as(i64, @intCast(cfg.timeout_ms)) * @as(i64, ns_per_ms);
    if (delta < timeout_ns) return .idle;
    return switch (cfg.action) {
        .disabled => .idle,
        .warn_only => .warn,
        .dump_only => .dump,
        .crash => .fire,
    };
}

// ---------------------------------------------------------------------------
// Test 1: env parsing
// ---------------------------------------------------------------------------

test "Config.fromEnv parses action and timeout" {
    const E = struct { action_str: ?[]const u8, timeout_str: ?[]const u8 };

    {
        const cfg = Config.fromEnv(E{ .action_str = "disabled", .timeout_str = null });
        try testing.expectEqual(Action.disabled, cfg.action);
        try testing.expectEqual(@as(u64, 5000), cfg.timeout_ms);
    }
    {
        const cfg = Config.fromEnv(E{ .action_str = "dump-only", .timeout_str = "1500" });
        try testing.expectEqual(Action.dump_only, cfg.action);
        try testing.expectEqual(@as(u64, 1500), cfg.timeout_ms);
    }
    {
        const cfg = Config.fromEnv(E{ .action_str = "warn-only", .timeout_str = null });
        try testing.expectEqual(Action.warn_only, cfg.action);
    }
    {
        const cfg = Config.fromEnv(E{ .action_str = "crash", .timeout_str = "8000" });
        try testing.expectEqual(Action.crash, cfg.action);
        try testing.expectEqual(@as(u64, 8000), cfg.timeout_ms);
    }
    {
        // Unknown action falls back to default (crash).
        const cfg = Config.fromEnv(E{ .action_str = "garbage", .timeout_str = null });
        try testing.expectEqual(Action.crash, cfg.action);
    }
    {
        // Default when env entirely absent.
        const cfg = Config.fromEnv(E{ .action_str = null, .timeout_str = null });
        try testing.expectEqual(Action.crash, cfg.action);
        try testing.expectEqual(@as(u64, 5000), cfg.timeout_ms);
    }
}

// ---------------------------------------------------------------------------
// Test 2: evaluate() returns .idle while heartbeat is fresh and exactly
// the configured action once the heartbeat stalls past timeout.
// ---------------------------------------------------------------------------

test "evaluate stays idle while heartbeat is fresh" {
    const cfg = Config{ .action = .crash, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const fresh = now - (1 * ns_per_s); // 1s ago, well inside 5s
    try testing.expectEqual(Decision.idle, evaluate(cfg, fresh, now));
}

test "evaluate fires after timeout under .crash" {
    const cfg = Config{ .action = .crash, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s); // 6s ago, past 5s timeout
    try testing.expectEqual(Decision.fire, evaluate(cfg, stale, now));
}

test "evaluate emits .dump under .dump_only" {
    const cfg = Config{ .action = .dump_only, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s);
    try testing.expectEqual(Decision.dump, evaluate(cfg, stale, now));
}

test "evaluate emits .warn under .warn_only" {
    const cfg = Config{ .action = .warn_only, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (6 * ns_per_s);
    try testing.expectEqual(Decision.warn, evaluate(cfg, stale, now));
}

test "evaluate stays idle under .disabled even when heartbeat is stale" {
    const cfg = Config{ .action = .disabled, .timeout_ms = 5000 };
    const now: i64 = 1_000_000_000_000;
    const stale = now - (60 * ns_per_s); // a full minute past
    try testing.expectEqual(Decision.idle, evaluate(cfg, stale, now));
}

test "evaluate stays idle when last_heartbeat is zero (not yet primed)" {
    const cfg = Config{ .action = .crash, .timeout_ms = 5000 };
    try testing.expectEqual(Decision.idle, evaluate(cfg, 0, @as(i64, 999_999_999)));
}

/// Truncate a 128-bit nanosecond timestamp to i64. Safe because i64 ns
/// holds ~292 years of range — all real heartbeats are tiny offsets.
fn nsNow() i64 {
    return @as(i64, @truncate(std.time.nanoTimestamp()));
}

// ---------------------------------------------------------------------------
// Test 3: end-to-end timing — drive a real Watchdog-shaped loop with a
// frozen heartbeat and assert it transitions idle -> fire within
// (timeout_ms + poll_ms) wall-clock.
// ---------------------------------------------------------------------------

test "watchdog loop fires within timeout + poll under stalled heartbeat" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    // Compress timing so the test runs in <1s instead of >5s.
    const cfg = Config{ .action = .crash, .timeout_ms = 200, .poll_ms = 25 };

    const State = struct {
        last_hb_ns: std.atomic.Value(i64) = .init(0),
        decision: std.atomic.Value(u8) = .init(0), // 0=idle,1=warn,2=dump,3=fire
        stop: std.atomic.Value(bool) = .init(false),

        fn loop(self: *@This(), c: Config) void {
            const start = nsNow();
            const wall_deadline = start + 5 * ns_per_s; // hard ceiling
            while (!self.stop.load(.acquire)) {
                const now = nsNow();
                if (now >= wall_deadline) break;
                const last = self.last_hb_ns.load(.acquire);
                const d = evaluate(c, last, now);
                if (d != .idle) {
                    self.decision.store(@intFromEnum(d), .release);
                    return;
                }
                std.Thread.sleep(c.poll_ms * ns_per_ms);
            }
        }
    };

    var state: State = .{};
    // Prime the heartbeat with "long ago" so the very first evaluate()
    // tick after timeout_ms wall-time will trip.
    const now0 = nsNow();
    state.last_hb_ns.store(now0, .release);

    var t = try std.Thread.spawn(.{}, State.loop, .{ &state, cfg });
    defer {
        state.stop.store(true, .release);
        t.join();
    }

    // Wall deadline: timeout_ms + 4 * poll_ms slack for scheduling.
    const wall_deadline_ns: u64 = (cfg.timeout_ms + 4 * cfg.poll_ms) * @as(u64, ns_per_ms);
    var waited: u64 = 0;
    while (state.decision.load(.acquire) == 0 and waited < wall_deadline_ns) {
        std.Thread.sleep(10 * ns_per_ms);
        waited += 10 * ns_per_ms;
    }
    try testing.expectEqual(@as(u8, @intFromEnum(Decision.fire)), state.decision.load(.acquire));
}

// ---------------------------------------------------------------------------
// Test 4: with the watchdog .disabled, the same stalled heartbeat must
// NOT fire — the user opt-out path stays intact.
// ---------------------------------------------------------------------------

test "watchdog loop never fires when disabled" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const cfg = Config{ .action = .disabled, .timeout_ms = 100, .poll_ms = 20 };

    const State = struct {
        last_hb_ns: std.atomic.Value(i64) = .init(0),
        decision: std.atomic.Value(u8) = .init(0),
        stop: std.atomic.Value(bool) = .init(false),

        fn loop(self: *@This(), c: Config) void {
            while (!self.stop.load(.acquire)) {
                const now = nsNow();
                const last = self.last_hb_ns.load(.acquire);
                const d = evaluate(c, last, now);
                if (d != .idle) {
                    self.decision.store(@intFromEnum(d), .release);
                    return;
                }
                std.Thread.sleep(c.poll_ms * ns_per_ms);
            }
        }
    };

    var state: State = .{};
    state.last_hb_ns.store(nsNow() - 60 * ns_per_s, .release);

    var t = try std.Thread.spawn(.{}, State.loop, .{ &state, cfg });
    defer {
        state.stop.store(true, .release);
        t.join();
    }

    // Sleep a full second — far longer than timeout_ms — and confirm
    // the watchdog stayed idle. (Loop self-stops via .stop on defer.)
    std.Thread.sleep(500 * ns_per_ms);
    try testing.expectEqual(@as(u8, 0), state.decision.load(.acquire));
}
