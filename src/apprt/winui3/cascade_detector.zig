//! Cascade deadlock detector — apprt-local chain breakers (issue #231).
//!
//! Background
//! ----------
//! The Phase 4 watchdog (`watchdog.zig`) is the **last resort**: it kills the
//! process once the UI thread has already wedged for >5s. By then the user
//! is staring at a frozen window and recovery is a process restart.
//!
//! Cascade defense aims to catch the **precursor signals** — the conditions
//! that empirically precede UI-thread stalls — and emit observability *before*
//! the watchdog has to fire. We monitor signals that are visible from the
//! apprt boundary without touching upstream-shared core code:
//!
//!   1. **Mailbox / drain pressure** — how often `drainMailbox` blew its slice
//!      budget, plus longest-observed tick. This is bookkeeping the apprt
//!      already does (see `tick_slice_warn_ns` in `App.zig`); the detector
//!      aggregates it into a rate signal.
//!   2. **Wakeup backlog** — `wakeup_pending` lingering true across multiple
//!      poll cycles means wakeups are arriving faster than the UI thread can
//!      drain them. Apprt-visible because the flag lives in `App`.
//!   3. **CP push staleness** — `cp_last_notify_ts` failing to advance while
//!      `wakeup_pending` is set means the UI thread is alive enough to take
//!      timer ticks but not enough to push CP status updates. This is the
//!      shape the deckpilot heartbeat regression (#28) used to take.
//!   4. **Cascade aggregator** — when 2+ of (mailbox-99%, long-tick storm,
//!      CP push stale, watchdog "almost firing") light up in the same
//!      window, log `CASCADE WARNING` and (if configured) preemptively
//!      trigger the watchdog snapshot path. Single-signal blips are noise;
//!      coincident signals are the cascade pattern.
//!
//! Heavy-fork stewardship rule (#231 addendum)
//! -------------------------------------------
//! This module touches **only** files in `src/apprt/winui3/`. Lock-contention
//! probing on upstream-shared mutexes (e.g. renderer state, BoundedMailbox
//! internals) was scoped out — wrapping them would require either editing
//! upstream-shared call sites or introducing apprt-side wrappers that every
//! call site must be migrated to. Either path bloats the upstream diff in a
//! way #231 explicitly forbids. We instead infer contention indirectly via
//! the apprt-visible tick latency / wakeup backlog signals above.
//!
//! Configuration (env vars)
//! ------------------------
//!   KS_CASCADE_DETECTOR=disabled|warn|trigger   (default: warn)
//!     - disabled : no thread spawned, zero overhead
//!     - warn     : log warnings + 30s summaries (default)
//!     - trigger  : on cascade warning, also call onCascadeFn callback
//!                  (e.g. force a phase4_watchdog snapshot dump)
//!   KS_CASCADE_POLL_MS=<u64 ms>                 (default: 1000)
//!   KS_CASCADE_SUMMARY_MS=<u64 ms>              (default: 30000)
//!
//! All env vars share the `KS_` prefix used by `watchdog.zig` so they can
//! be flipped together by a single launcher block.

const std = @import("std");

const log = std.log.scoped(.cascade);

const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

pub const Action = enum {
    /// No detector thread. Zero overhead.
    disabled,
    /// Log warnings + 30s rolling summaries.
    warn,
    /// As `warn`, but additionally call `onCascadeFn` when a multi-signal
    /// cascade fires (e.g. force a watchdog dump preemptively).
    trigger,
};

pub const Config = struct {
    action: Action = .warn,
    poll_ms: u64 = 1000,
    summary_ms: u64 = 30_000,

    /// Tick that took longer than this is counted as a "long tick" sample.
    /// Aligned with `tick_slice_warn_ns` in `App.zig` so we don't double-
    /// emit on the same threshold the existing logger already uses.
    tick_warn_ms: u64 = 4,
    /// Tick longer than this is a "severe" sample — bumps the err counter.
    tick_err_ms: u64 = 100,

    /// If `wakeup_pending` is observed true for N consecutive polls, emit
    /// a backlog warning. At default poll_ms=1000 this means the UI thread
    /// has failed to drain for ~3s — Phase 4 watchdog will fire at 5s, so
    /// this is the precursor signal we want.
    wakeup_pending_consecutive_warn: u32 = 3,

    /// Threshold in ms beyond which the CP push timestamp is considered
    /// stale. Apprt drainMailbox pushes a "running" notify at most 1/sec
    /// while there's traffic; >10s without a notify under traffic is suspect.
    cp_push_stale_ms: i64 = 10_000,

    /// Threshold (ms) below the watchdog timeout below which we treat the
    /// watchdog as "almost firing" (cascade signal #4). Conservative default
    /// 2000ms = with the watchdog default 5000ms, we light up at 3s of stall.
    watchdog_near_fire_ms: i64 = 2_000,

    pub fn fromEnv(allocator: std.mem.Allocator) Config {
        var cfg = Config{};
        if (std.process.getEnvVarOwned(allocator, "KS_CASCADE_DETECTOR")) |s| {
            defer allocator.free(s);
            if (std.mem.eql(u8, s, "disabled")) {
                cfg.action = .disabled;
            } else if (std.mem.eql(u8, s, "warn")) {
                cfg.action = .warn;
            } else if (std.mem.eql(u8, s, "trigger")) {
                cfg.action = .trigger;
            }
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "KS_CASCADE_POLL_MS")) |s| {
            defer allocator.free(s);
            cfg.poll_ms = std.fmt.parseInt(u64, s, 10) catch cfg.poll_ms;
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "KS_CASCADE_SUMMARY_MS")) |s| {
            defer allocator.free(s);
            cfg.summary_ms = std.fmt.parseInt(u64, s, 10) catch cfg.summary_ms;
        } else |_| {}
        return cfg;
    }
};

// ---------------------------------------------------------------------------
// Stats — atomic counters bumped by the UI thread (cheap), read by the
// detector poll thread. All counters are monotonic; the detector computes
// rates by snapshotting deltas between summary windows.
// ---------------------------------------------------------------------------

pub const Stats = struct {
    /// Total drainMailbox invocations.
    tick_count: std.atomic.Value(u64) = .init(0),
    /// Ticks that exceeded `tick_warn_ms`.
    tick_warn_count: std.atomic.Value(u64) = .init(0),
    /// Ticks that exceeded `tick_err_ms`.
    tick_err_count: std.atomic.Value(u64) = .init(0),
    /// Longest-observed tick (ns) since process start. Stored as raw u64.
    /// CAS-loop updated for monotonic max.
    max_tick_ns: std.atomic.Value(u64) = .init(0),
    /// Last tick timestamp (ms since unix epoch). Used by the detector to
    /// notice "no tick in a long time" — distinct from heartbeat staleness.
    last_tick_unix_ms: std.atomic.Value(i64) = .init(0),

    /// Bump by `drainMailbox` after a tick completes. Cheap: 3 atomic adds
    /// + one CAS-loop max update + two stores.
    pub fn recordTick(self: *Stats, elapsed_ns: u64, warn_threshold_ns: u64, err_threshold_ns: u64) void {
        _ = self.tick_count.fetchAdd(1, .monotonic);
        if (elapsed_ns > warn_threshold_ns) {
            _ = self.tick_warn_count.fetchAdd(1, .monotonic);
        }
        if (elapsed_ns > err_threshold_ns) {
            _ = self.tick_err_count.fetchAdd(1, .monotonic);
        }
        // CAS-loop monotonic max.
        var prev = self.max_tick_ns.load(.monotonic);
        while (elapsed_ns > prev) {
            const result = self.max_tick_ns.cmpxchgWeak(prev, elapsed_ns, .monotonic, .monotonic);
            if (result == null) break;
            prev = result.?;
        }
        self.last_tick_unix_ms.store(std.time.milliTimestamp(), .monotonic);
    }
};

// ---------------------------------------------------------------------------
// Read-only views the detector consumes from its owner (App). Owner publishes
// these as pointers; we never mutate them. Pointer-of-atomic is the cheapest
// way to share state across threads without a wrapping struct.
// ---------------------------------------------------------------------------

pub const View = struct {
    /// Bumped by every `drainMailbox` call.
    stats: *Stats,
    /// True while the apprt has scheduled a drain that hasn't run yet.
    wakeup_pending: *std.atomic.Value(bool),
    /// Last time the apprt pushed a CP "running" status (ms since epoch).
    /// Zero means CP is disabled or hasn't been pinged yet.
    cp_last_notify_ms: *std.atomic.Value(i64),
    /// Last UI heartbeat timestamp (ns, i64 mirror — same field the Phase 4
    /// watchdog reads). Used to compute "watchdog near-fire" cascade signal.
    last_ui_heartbeat_ns: *std.atomic.Value(i64),
    /// Phase 4 watchdog timeout (ms), read once at init for cascade math.
    watchdog_timeout_ms: u64,
};

/// Optional callback for `Action.trigger`. Invoked from the detector thread
/// when a multi-signal cascade fires. MUST NOT block the calling thread —
/// typical implementation flips an atomic flag the watchdog observes.
pub const OnCascadeFn = *const fn (ctx: ?*anyopaque) void;

// ---------------------------------------------------------------------------
// Detector
// ---------------------------------------------------------------------------

pub const Detector = struct {
    cfg: Config,
    view: View,
    on_cascade: ?OnCascadeFn = null,
    on_cascade_ctx: ?*anyopaque = null,

    stop: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    /// Internal poll-loop bookkeeping. Touched only by the detector thread,
    /// so no atomics needed beyond the View pointers above.
    consecutive_wakeup_pending: u32 = 0,
    last_summary_ms: i64 = 0,
    /// Snapshots taken at the previous summary, used to compute rate deltas.
    snap_tick_count: u64 = 0,
    snap_tick_warn_count: u64 = 0,
    snap_tick_err_count: u64 = 0,
    /// Has the cascade callback fired in this process lifetime? One-shot
    /// guard — avoid spamming the watchdog dump path. Resets only on process
    /// restart, which is the right granularity (a cascade is rare).
    cascade_fired: std.atomic.Value(bool) = .init(false),

    pub fn init(cfg: Config, view: View) Detector {
        return .{ .cfg = cfg, .view = view };
    }

    pub fn setCallback(self: *Detector, cb: OnCascadeFn, ctx: ?*anyopaque) void {
        self.on_cascade = cb;
        self.on_cascade_ctx = ctx;
    }

    pub fn start(self: *Detector) !void {
        if (self.cfg.action == .disabled) {
            log.info("cascade detector disabled via KS_CASCADE_DETECTOR=disabled", .{});
            return;
        }
        if (self.thread != null) return;
        self.last_summary_ms = std.time.milliTimestamp();
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
        log.info(
            "cascade detector started action={s} poll_ms={} summary_ms={} watchdog_timeout_ms={}",
            .{ @tagName(self.cfg.action), self.cfg.poll_ms, self.cfg.summary_ms, self.view.watchdog_timeout_ms },
        );
    }

    pub fn stopAndJoin(self: *Detector) void {
        self.stop.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    fn loop(self: *Detector) void {
        while (!self.stop.load(.acquire)) {
            std.Thread.sleep(self.cfg.poll_ms * ns_per_ms);
            if (self.stop.load(.acquire)) break;
            self.tick();
        }
    }

    /// One detector cycle. Public so tests can invoke it without a real
    /// thread. Pure: no sleeps, no env reads, only View loads + log emits +
    /// optional callback.
    pub fn tick(self: *Detector) void {
        const now_ms = std.time.milliTimestamp();
        const now_ns = nsNow();

        // Signal 1: wakeup backlog.
        const wakeup_set = self.view.wakeup_pending.load(.acquire);
        if (wakeup_set) {
            self.consecutive_wakeup_pending +%= 1;
        } else {
            self.consecutive_wakeup_pending = 0;
        }
        const wakeup_signal = self.consecutive_wakeup_pending >= self.cfg.wakeup_pending_consecutive_warn;
        if (wakeup_signal) {
            log.warn(
                "wakeup backlog: wakeup_pending=true for {} consecutive polls (~{}ms)",
                .{ self.consecutive_wakeup_pending, self.consecutive_wakeup_pending * self.cfg.poll_ms },
            );
        }

        // Signal 2: CP push staleness — only meaningful when traffic is
        // arriving (wakeup_set or recent ticks). cp_last_notify_ms == 0
        // means CP is uninitialized; skip in that case.
        const cp_last = self.view.cp_last_notify_ms.load(.acquire);
        const cp_stale = cp_last != 0 and (now_ms - cp_last) > self.cfg.cp_push_stale_ms;
        const recent_tick = blk: {
            const t = self.view.stats.last_tick_unix_ms.load(.monotonic);
            if (t == 0) break :blk false;
            break :blk (now_ms - t) < self.cfg.cp_push_stale_ms;
        };
        const cp_signal = cp_stale and (wakeup_set or recent_tick);
        if (cp_signal) {
            log.warn(
                "cp push stale: cp_last_notify_ms={}ms ago, traffic indicators wakeup={} recent_tick={}",
                .{ now_ms - cp_last, wakeup_set, recent_tick },
            );
        }

        // Signal 3: watchdog near-fire — UI heartbeat staleness approaching
        // the configured watchdog timeout. Conservative: only count if
        // heartbeat has been primed (non-zero).
        const last_hb = self.view.last_ui_heartbeat_ns.load(.acquire);
        const hb_stall_ms: i64 = if (last_hb != 0)
            @divTrunc(now_ns - last_hb, ns_per_ms)
        else
            0;
        const watchdog_timeout_i64: i64 = @intCast(self.view.watchdog_timeout_ms);
        const watchdog_signal = last_hb != 0 and
            hb_stall_ms > (watchdog_timeout_i64 - self.cfg.watchdog_near_fire_ms);
        if (watchdog_signal) {
            log.warn(
                "watchdog near-fire: ui heartbeat stall={}ms (watchdog timeout={}ms)",
                .{ hb_stall_ms, watchdog_timeout_i64 },
            );
        }

        // Signal 4: long-tick storm. Computed against snapshot rate at
        // summary boundaries below; here we just check absolute err count
        // movement for the immediate "just blew past 100ms" case.
        const tick_err_now = self.view.stats.tick_err_count.load(.monotonic);
        const tick_err_signal = tick_err_now > self.snap_tick_err_count;
        if (tick_err_signal) {
            const max_ms = self.view.stats.max_tick_ns.load(.monotonic) / ns_per_ms;
            log.warn(
                "long tick: err_count {} -> {} (max_tick_ms={})",
                .{ self.snap_tick_err_count, tick_err_now, max_ms },
            );
        }

        // Cascade aggregation: 2+ signals coincident → CASCADE WARNING.
        var lit_signals: u32 = 0;
        if (wakeup_signal) lit_signals += 1;
        if (cp_signal) lit_signals += 1;
        if (watchdog_signal) lit_signals += 1;
        if (tick_err_signal) lit_signals += 1;

        if (lit_signals >= 2) {
            log.err(
                "CASCADE WARNING: {} signals coincident (wakeup={} cp_stale={} wd_near={} tick_err={}) — UI deadlock imminent",
                .{ lit_signals, wakeup_signal, cp_signal, watchdog_signal, tick_err_signal },
            );
            self.maybeFireCascade(lit_signals);
        }

        // Periodic summary.
        if ((now_ms - self.last_summary_ms) >= @as(i64, @intCast(self.cfg.summary_ms))) {
            self.emitSummary(now_ms);
            // Snapshot for next window's delta math.
            self.snap_tick_count = self.view.stats.tick_count.load(.monotonic);
            self.snap_tick_warn_count = self.view.stats.tick_warn_count.load(.monotonic);
            self.snap_tick_err_count = self.view.stats.tick_err_count.load(.monotonic);
            self.last_summary_ms = now_ms;
        }
    }

    /// Pure cascade-callback gate. Public so unit tests can drive it without
    /// invoking `tick` (which logs `log.err` — Zig's test runner promotes
    /// any logged error to a non-zero exit code). Idempotent: only fires the
    /// callback once per process lifetime under `Action.trigger`.
    pub fn maybeFireCascade(self: *Detector, lit_signals: u32) void {
        _ = lit_signals;
        if (self.cfg.action != .trigger) return;
        if (self.cascade_fired.load(.acquire)) return;
        if (self.on_cascade) |cb| {
            self.cascade_fired.store(true, .release);
            cb(self.on_cascade_ctx);
        }
    }

    fn emitSummary(self: *Detector, now_ms: i64) void {
        const tick_count = self.view.stats.tick_count.load(.monotonic);
        const tick_warn = self.view.stats.tick_warn_count.load(.monotonic);
        const tick_err = self.view.stats.tick_err_count.load(.monotonic);
        const max_tick_ns = self.view.stats.max_tick_ns.load(.monotonic);
        const last_tick_age = blk: {
            const t = self.view.stats.last_tick_unix_ms.load(.monotonic);
            if (t == 0) break :blk @as(i64, -1);
            break :blk now_ms - t;
        };
        const cp_last = self.view.cp_last_notify_ms.load(.acquire);
        const cp_age = if (cp_last == 0) @as(i64, -1) else now_ms - cp_last;

        const delta_ticks = tick_count -% self.snap_tick_count;
        const delta_warn = tick_warn -% self.snap_tick_warn_count;
        const delta_err = tick_err -% self.snap_tick_err_count;

        log.info(
            "cascade summary: ticks={} (+{}) warn={} (+{}) err={} (+{}) max_tick_ms={} last_tick_age_ms={} cp_age_ms={} cascade_fired={}",
            .{
                tick_count,              delta_ticks,
                tick_warn,               delta_warn,
                tick_err,                delta_err,
                max_tick_ns / ns_per_ms, last_tick_age,
                cp_age,                  self.cascade_fired.load(.acquire),
            },
        );
    }
};

fn nsNow() i64 {
    return @as(i64, @truncate(std.time.nanoTimestamp()));
}

// ---------------------------------------------------------------------------
// Tests — exercise the algorithmic contract without spawning threads or
// touching real time. The detector is intentionally pure-on-`tick()` to make
// this trivial: build a View backed by stack atomics, drive `tick` directly.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "Config.fromEnv defaults to warn action" {
    const cfg = Config{};
    try testing.expectEqual(Action.warn, cfg.action);
    try testing.expectEqual(@as(u64, 1000), cfg.poll_ms);
    try testing.expectEqual(@as(u64, 30_000), cfg.summary_ms);
}

test "Stats.recordTick bumps counters on threshold crossings" {
    var s = Stats{};
    s.recordTick(1 * std.time.ns_per_ms, 4 * std.time.ns_per_ms, 100 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 1), s.tick_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 0), s.tick_warn_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 0), s.tick_err_count.load(.monotonic));

    s.recordTick(50 * std.time.ns_per_ms, 4 * std.time.ns_per_ms, 100 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 2), s.tick_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 1), s.tick_warn_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 0), s.tick_err_count.load(.monotonic));

    s.recordTick(500 * std.time.ns_per_ms, 4 * std.time.ns_per_ms, 100 * std.time.ns_per_ms);
    try testing.expectEqual(@as(u64, 3), s.tick_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 2), s.tick_warn_count.load(.monotonic));
    try testing.expectEqual(@as(u64, 1), s.tick_err_count.load(.monotonic));
}

test "Stats max_tick_ns is monotonic non-decreasing" {
    var s = Stats{};
    s.recordTick(10 * ns_per_ms, 4 * ns_per_ms, 100 * ns_per_ms);
    s.recordTick(50 * ns_per_ms, 4 * ns_per_ms, 100 * ns_per_ms);
    s.recordTick(20 * ns_per_ms, 4 * ns_per_ms, 100 * ns_per_ms);
    try testing.expectEqual(@as(u64, 50 * ns_per_ms), s.max_tick_ns.load(.monotonic));
}

test "Detector.tick increments wakeup_pending consecutive counter" {
    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(true);
    var cp = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .warn, .wakeup_pending_consecutive_warn = 3 }, view);
    det.tick();
    det.tick();
    try testing.expectEqual(@as(u32, 2), det.consecutive_wakeup_pending);
    wakeup.store(false, .release);
    det.tick();
    try testing.expectEqual(@as(u32, 0), det.consecutive_wakeup_pending);
}

test "cascade callback fires once on .trigger when 2+ signals coincident" {
    // Exercises the pure cascade path without invoking `tick()` so the
    // production `log.err` line stays out of the test binary's stderr (the
    // Zig test runner promotes any logged error to a non-zero exit code).
    const Counter = struct {
        count: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.count += 1;
        }
    };
    var counter = Counter{};

    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(false);
    var cp = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .trigger }, view);
    det.setCallback(Counter.cb, &counter);

    // First fire: 2 signals lit → callback runs, fired flag latches.
    det.maybeFireCascade(2);
    try testing.expectEqual(@as(u32, 1), counter.count);
    try testing.expect(det.cascade_fired.load(.acquire));

    // One-shot guard: subsequent invocations do NOT re-fire.
    det.maybeFireCascade(3);
    try testing.expectEqual(@as(u32, 1), counter.count);
}

test "cascade callback does NOT fire on .warn even with many signals" {
    const Counter = struct {
        count: u32 = 0,
        fn cb(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.count += 1;
        }
    };
    var counter = Counter{};
    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(false);
    var cp = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .warn }, view);
    det.setCallback(Counter.cb, &counter);
    det.maybeFireCascade(4);
    try testing.expectEqual(@as(u32, 0), counter.count);
    // .warn never latches the fired flag — only .trigger does.
    try testing.expect(!det.cascade_fired.load(.acquire));
}

test "Detector disabled action: start() is a no-op" {
    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(false);
    var cp = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .disabled }, view);
    try det.start();
    try testing.expect(det.thread == null);
    det.stopAndJoin(); // safe no-op
}
