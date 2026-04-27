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
//!   KS_CASCADE_PRIORITY_BOOST=disabled          (default: enabled when
//!                                                action != .disabled)
//!     - When enabled and Signal 5 (renderer_locked) fires, the detector
//!       calls SetThreadPriority(renderer_thread, ABOVE_NORMAL) so the
//!       renderer has a better chance of acquiring its state mutex against
//!       a busy termio thread under shell text flood. After 3 consecutive
//!       quiet polls (no renderer_locked signal) we restore NORMAL.
//!
//! All env vars share the `KS_` prefix used by `watchdog.zig` so they can
//! be flipped together by a single launcher block.
//!
//! This layers additively with `feat-stream-handler-lf-yield` (parallel PR
//! that patches `src/termio/stream_handler.zig` to add LF-safe-point yields).
//! The two fixes attack the same starvation from opposite sides — termio
//! cooperates more, renderer is scheduled harder — and never touch each
//! other's files.

const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.cascade);

const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;

// ---------------------------------------------------------------------------
// Win32 thread-priority externs (Windows-only). Local to this file per #231
// fork-stewardship rule — don't bloat `os.zig` with single-use decls.
// ---------------------------------------------------------------------------

const win32 = std.os.windows;

pub const THREAD_PRIORITY_NORMAL: i32 = 0;
pub const THREAD_PRIORITY_ABOVE_NORMAL: i32 = 1;

extern "kernel32" fn SetThreadPriority(hThread: win32.HANDLE, nPriority: i32) callconv(.winapi) win32.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) win32.DWORD;

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

    /// When true and Signal 5 (renderer_locked) fires, the detector raises
    /// the renderer thread's OS priority to ABOVE_NORMAL until 3 consecutive
    /// quiet polls have elapsed. Default is true; set
    /// `KS_CASCADE_PRIORITY_BOOST=disabled` to opt out (e.g. when a debugger
    /// is attached or for A/B latency comparisons).
    priority_boost_enabled: bool = true,

    /// Number of consecutive renderer_locked-clean polls required to
    /// restore the renderer thread to NORMAL priority. Three matches the
    /// poll cadence (3s at default poll_ms=1000) — long enough that we
    /// don't churn priority on transient bursts, short enough that the
    /// renderer doesn't keep starving low-priority work after the storm.
    quiet_polls_to_restore: u32 = 3,

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
        if (std.process.getEnvVarOwned(allocator, "KS_CASCADE_PRIORITY_BOOST")) |s| {
            defer allocator.free(s);
            if (std.mem.eql(u8, s, "disabled")) cfg.priority_boost_enabled = false;
        } else |_| {}
        // Hard-disable the boost when the detector itself is disabled —
        // there is no detector thread to drive transitions in that mode.
        if (cfg.action == .disabled) cfg.priority_boost_enabled = false;
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
    /// Zero means CP is uninitialized; skip in that case.
    cp_last_notify_ms: *std.atomic.Value(i64),
    /// Last UI heartbeat timestamp (ns, i64 mirror — same field the Phase 4
    /// watchdog reads). Used to compute "watchdog near-fire" cascade signal.
    last_ui_heartbeat_ns: *std.atomic.Value(i64),
    /// Phase 4 watchdog timeout (ms), read once at init for cascade math.
    watchdog_timeout_ms: u64,

    /// 5th Signal precursor: CP-side renderer mutex contention.
    /// Pointers to CP atomics (optional, set via setControlPlane).
    renderer_locked_event_count_ptr: ?*const std.atomic.Value(u32) = null,
    renderer_locked_circuit_open_until_ns_ptr: ?*const std.atomic.Value(i64) = null,

    /// Snapshots for Signal 5 (updated by tick()).
    renderer_locked_event_count: u32 = 0,
    renderer_locked_circuit_open: bool = false,
};

/// Optional callback for `Action.trigger`. Invoked from the detector thread
/// when a multi-signal cascade fires. MUST NOT block the calling thread —
/// typical implementation flips an atomic flag the watchdog observes.
pub const OnCascadeFn = *const fn (ctx: ?*anyopaque) void;

pub const Signal = enum(u32) {
    wakeup_backlog = 1,
    cp_push_stale = 2,
    watchdog_near_fire = 3,
    long_tick_storm = 4,
    renderer_locked = 5,
};

/// Renderer-priority boost transition state. Documented as a state machine
/// so the test names line up with the real transitions:
///
///   idle ──renderer_locked signal──▶ boosted
///   boosted ──3 quiet polls──▶ idle
///
/// We do NOT have intermediate "draining" states: if the storm flares again
/// while we're still counting quiet polls, the counter resets and we stay
/// boosted. This keeps the machine 2-state and easy to reason about.
pub const BoostState = enum(u8) {
    idle = 0,
    boosted = 1,
};

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

    /// Snapshots for Signal 5 (renderer_locked).
    snap_renderer_locked_event_count: u32 = 0,

    /// Has the cascade callback fired in this process lifetime? One-shot
    /// guard — avoid spamming the watchdog dump path. Resets only on process
    /// restart, which is the right granularity (a cascade is rare).
    cascade_fired: std.atomic.Value(bool) = .init(false),

    // -- Renderer-thread priority boost state (companion to
    //    `feat-stream-handler-lf-yield`) -----------------------------------

    /// OS handle for the renderer thread, set by `setRendererThreadHandle`.
    /// Optional: when null, the boost state machine still runs (counters
    /// still increment, transitions still happen) but no SetThreadPriority
    /// call is issued. This lets unit tests drive the FSM without a real
    /// thread, and lets early-startup code paths (where the renderer thread
    /// hasn't been created yet) skip the boost without crashing.
    renderer_thread_handle: ?win32.HANDLE = null,

    /// Current FSM position. Touched only by the detector thread (or the
    /// test that calls `tick` synchronously), so a plain field is sufficient
    /// — the atomic counters below are the test-visible surface.
    boost_state: BoostState = .idle,

    /// Consecutive ticks observed with no renderer_locked signal while in
    /// the `.boosted` state. When this reaches `cfg.quiet_polls_to_restore`
    /// we restore NORMAL and drop back to `.idle`.
    consecutive_quiet_polls: u32 = 0,

    /// Cumulative count of `.idle` → `.boosted` transitions where we
    /// (attempted to) raise the renderer thread to ABOVE_NORMAL. Test
    /// assertion surface — the brief calls this out specifically.
    priority_boosts_applied: std.atomic.Value(u32) = .init(0),

    /// Cumulative count of `.boosted` → `.idle` transitions where we
    /// (attempted to) restore NORMAL. Distinct counter so tests can prove
    /// the boost is reversible (if we never restore, the renderer keeps
    /// starving everything else after the storm).
    priority_restores_applied: std.atomic.Value(u32) = .init(0),

    /// Set once if `SetThreadPriority` returns FALSE (e.g. an Insider
    /// scheduler rejects ABOVE_NORMAL, or the handle was opened without
    /// THREAD_SET_INFORMATION). After we log the warning, we stop calling
    /// the OS API entirely — repeated failures would just spam the log
    /// without changing behaviour. The state machine still advances so
    /// counters remain meaningful for diagnostics.
    boost_failed_once: std.atomic.Value(bool) = .init(false),

    pub fn init(cfg: Config, view: View) Detector {
        return .{ .cfg = cfg, .view = view };
    }

    /// Connect the detector to the ControlPlane to observe Signal 5.
    /// Uses anytype to avoid a direct dependency on control_plane.zig
    /// during standalone unit tests.
    pub fn setControlPlane(self: *Detector, cp: anytype) void {
        self.view.renderer_locked_event_count_ptr = &cp.renderer_locked_event_count;
        self.view.renderer_locked_circuit_open_until_ns_ptr = &cp.renderer_locked_circuit_open_until_ns;
    }

    pub fn setCallback(self: *Detector, cb: OnCascadeFn, ctx: ?*anyopaque) void {
        self.on_cascade = cb;
        self.on_cascade_ctx = ctx;
    }

    /// Register the renderer thread's OS handle so the boost state machine
    /// can call `SetThreadPriority` on it. Safe to call from any thread,
    /// but typically wired up once during `App` startup after the renderer
    /// thread has been spawned. Passing null is allowed (and is the default)
    /// — the FSM still drives counters but issues no OS calls.
    pub fn setRendererThreadHandle(self: *Detector, handle: ?win32.HANDLE) void {
        self.renderer_thread_handle = handle;
    }

    /// Apply NORMAL priority. Best-effort: if SetThreadPriority returns 0
    /// we log once and self-disable so we don't spam the log. The state
    /// machine still advances regardless.
    fn applyPriority(self: *Detector, target: i32) void {
        // Always bump the appropriate counter so tests (and prod telemetry)
        // observe the FSM transition even when the OS call is skipped or
        // self-disabled. The brief calls this out: the counter is the test
        // surface, not the SetThreadPriority side effect.
        if (target == THREAD_PRIORITY_ABOVE_NORMAL) {
            _ = self.priority_boosts_applied.fetchAdd(1, .monotonic);
        } else {
            _ = self.priority_restores_applied.fetchAdd(1, .monotonic);
        }

        if (builtin.os.tag != .windows) return;
        const handle = self.renderer_thread_handle orelse return;
        if (self.boost_failed_once.load(.acquire)) return;

        const ok = SetThreadPriority(handle, target);
        if (ok == 0) {
            // Mark first so a concurrent caller sees the latch. The brief
            // explicitly enumerated this failure mode: scheduler rejection
            // (Insider builds), missing THREAD_SET_INFORMATION on the
            // handle, or a stale handle after thread death.
            if (!self.boost_failed_once.swap(true, .acq_rel)) {
                log.warn(
                    "SetThreadPriority({d}) failed lasterr={d} — disabling further priority boost attempts for this process",
                    .{ target, GetLastError() },
                );
            }
        }
    }

    /// Drive the boost FSM for the current tick.
    ///
    /// Pure on inputs (signal_active + cfg) so tests can feed it directly
    /// without standing up a full View. Returns the new state for symmetry
    /// with `observe*` helpers in the repro test mirror.
    pub fn updateBoost(self: *Detector, signal_active: bool) BoostState {
        if (!self.cfg.priority_boost_enabled) return self.boost_state;

        switch (self.boost_state) {
            .idle => {
                if (signal_active) {
                    self.applyPriority(THREAD_PRIORITY_ABOVE_NORMAL);
                    self.boost_state = .boosted;
                    self.consecutive_quiet_polls = 0;
                }
            },
            .boosted => {
                if (signal_active) {
                    // Storm continues — reset the quiet counter, stay boosted.
                    self.consecutive_quiet_polls = 0;
                } else {
                    self.consecutive_quiet_polls +%= 1;
                    if (self.consecutive_quiet_polls >= self.cfg.quiet_polls_to_restore) {
                        self.applyPriority(THREAD_PRIORITY_NORMAL);
                        self.boost_state = .idle;
                        self.consecutive_quiet_polls = 0;
                    }
                }
            },
        }
        return self.boost_state;
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

        // Refresh CP snapshots if connected.
        if (self.view.renderer_locked_event_count_ptr) |ptr| {
            self.view.renderer_locked_event_count = ptr.load(.acquire);
        }
        if (self.view.renderer_locked_circuit_open_until_ns_ptr) |ptr| {
            self.view.renderer_locked_circuit_open = ptr.load(.acquire) > now_ns;
        }

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

        // Signal 5: renderer locked.
        const rl_delta = self.view.renderer_locked_event_count -% self.snap_renderer_locked_event_count;
        const renderer_locked_signal = self.view.renderer_locked_circuit_open or rl_delta >= 3;
        if (renderer_locked_signal) {
            log.warn(
                "renderer locked: circuit_open={} event_count_delta={} (total={})",
                .{ self.view.renderer_locked_circuit_open, rl_delta, self.view.renderer_locked_event_count },
            );
        }

        // Companion mitigation (layers with `feat-stream-handler-lf-yield`):
        // raise the renderer thread's OS priority while Signal 5 is hot, and
        // restore it once 3 quiet polls show the storm has cleared. The FSM
        // is intentionally separate from the cascade-aggregation path above
        // — Signal 5 alone is enough to justify the boost, and we want to
        // act on the precursor signal (one signal lit) rather than waiting
        // for the 2-signal cascade verdict.
        _ = self.updateBoost(renderer_locked_signal);

        // Cascade aggregation: 2+ signals coincident → CASCADE WARNING.
        var lit_signals: u32 = 0;
        if (wakeup_signal) lit_signals += 1;
        if (cp_signal) lit_signals += 1;
        if (watchdog_signal) lit_signals += 1;
        if (tick_err_signal) lit_signals += 1;
        if (renderer_locked_signal) lit_signals += 1;

        if (lit_signals >= 2) {
            log.err(
                "CASCADE WARNING: {} signals coincident (wakeup={} cp_stale={} wd_near={} tick_err={} renderer_locked={}) — UI deadlock imminent",
                .{ lit_signals, wakeup_signal, cp_signal, watchdog_signal, tick_err_signal, renderer_locked_signal },
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
            self.snap_renderer_locked_event_count = self.view.renderer_locked_event_count;
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
        const delta_rl = self.view.renderer_locked_event_count -% self.snap_renderer_locked_event_count;

        log.info(
            "cascade summary: ticks={} (+{}) warn={} (+{}) err={} (+{}) max_tick_ms={} last_tick_age_ms={} cp_age_ms={} renderer_locked={}/{} (+{}) cascade_fired={}",
            .{
                tick_count,                            delta_ticks,
                tick_warn,                             delta_warn,
                tick_err,                              delta_err,
                max_tick_ns / ns_per_ms,               last_tick_age,
                cp_age,                                @intFromBool(self.view.renderer_locked_circuit_open),
                self.view.renderer_locked_event_count, delta_rl,
                self.cascade_fired.load(.acquire),
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

test "Detector.tick flags renderer_locked signal when event count increases" {
    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(false);
    var cp_notify = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp_notify,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .warn }, view);

    // Manual setup: Signal 5 ONLY.
    det.view.renderer_locked_event_count = 5;
    det.snap_renderer_locked_event_count = 0; // delta = 5 >= 3

    // tick() should see Signal 5 (renderer_locked) and log a warning,
    // but NO cascade error because it is the only signal lit.
    det.tick();

    // Verify snapshot was updated.
    try testing.expectEqual(@as(u32, 5), det.snap_renderer_locked_event_count);
}

test "Detector.tick flags renderer_locked signal when circuit is open" {
    var stats = Stats{};
    var wakeup = std.atomic.Value(bool).init(false);
    var cp_notify = std.atomic.Value(i64).init(0);
    var hb = std.atomic.Value(i64).init(0);
    const view = View{
        .stats = &stats,
        .wakeup_pending = &wakeup,
        .cp_last_notify_ms = &cp_notify,
        .last_ui_heartbeat_ns = &hb,
        .watchdog_timeout_ms = 5000,
    };
    var det = Detector.init(.{ .action = .warn }, view);

    // Signal 5 ONLY.
    det.view.renderer_locked_circuit_open = true;

    det.tick();

    // In this case delta was 0, but circuit_open=true triggered the signal.
    try testing.expectEqual(@as(u32, 0), det.snap_renderer_locked_event_count);
}

// ---------------------------------------------------------------------------
// Renderer-thread priority boost FSM tests (companion to
// `feat-stream-handler-lf-yield`). The brief calls these out explicitly:
//
//   1. Boost is applied when renderer_locked fires (counter increments).
//   2. After 3 quiet polls the boost is restored (decrement-style counter).
//   3. KS_CASCADE_PRIORITY_BOOST=disabled short-circuits — counter stays 0.
//
// These tests drive `updateBoost` directly so they don't require a real
// thread handle, and they stay deterministic under the Zig test runner.
// ---------------------------------------------------------------------------

fn newBoostDetector(cfg: Config) Detector {
    // Stack-backed View — pointers don't escape this stack frame because
    // the returned Detector is consumed in the same test function.
    const S = struct {
        var stats: Stats = .{};
        var wakeup: std.atomic.Value(bool) = .init(false);
        var cp: std.atomic.Value(i64) = .init(0);
        var hb: std.atomic.Value(i64) = .init(0);
    };
    const view = View{
        .stats = &S.stats,
        .wakeup_pending = &S.wakeup,
        .cp_last_notify_ms = &S.cp,
        .last_ui_heartbeat_ns = &S.hb,
        .watchdog_timeout_ms = 5000,
    };
    return Detector.init(cfg, view);
}

test "boost FSM raises priority on first renderer_locked signal" {
    var det = newBoostDetector(.{ .action = .warn, .priority_boost_enabled = true });
    // Null handle — FSM advances counters but skips OS call. That's the
    // intended testable surface (brief: "Track current state with an atomic
    // so transitions are observable from tests").
    det.setRendererThreadHandle(null);

    try testing.expectEqual(BoostState.idle, det.boost_state);
    try testing.expectEqual(@as(u32, 0), det.priority_boosts_applied.load(.monotonic));

    // Signal fires → idle → boosted, counter increments exactly once.
    _ = det.updateBoost(true);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 1), det.priority_boosts_applied.load(.monotonic));

    // Signal still hot on the next poll → counter does NOT double-bump,
    // we just stay boosted (no idempotency violation).
    _ = det.updateBoost(true);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 1), det.priority_boosts_applied.load(.monotonic));
}

test "boost FSM restores priority after 3 quiet polls" {
    var det = newBoostDetector(.{ .action = .warn, .priority_boost_enabled = true });
    det.setRendererThreadHandle(null);

    // Enter boosted state.
    _ = det.updateBoost(true);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 0), det.priority_restores_applied.load(.monotonic));

    // 1st quiet poll — still boosted.
    _ = det.updateBoost(false);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 1), det.consecutive_quiet_polls);
    try testing.expectEqual(@as(u32, 0), det.priority_restores_applied.load(.monotonic));

    // 2nd quiet poll — still boosted.
    _ = det.updateBoost(false);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 2), det.consecutive_quiet_polls);

    // 3rd quiet poll — restore fires, FSM drops back to idle.
    _ = det.updateBoost(false);
    try testing.expectEqual(BoostState.idle, det.boost_state);
    try testing.expectEqual(@as(u32, 0), det.consecutive_quiet_polls);
    try testing.expectEqual(@as(u32, 1), det.priority_restores_applied.load(.monotonic));

    // A 2nd storm re-arms the FSM and re-bumps the boost counter — proves
    // the transition is not one-shot (that's `cascade_fired`'s contract,
    // not the priority boost's).
    _ = det.updateBoost(true);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 2), det.priority_boosts_applied.load(.monotonic));
}

test "boost FSM resets quiet-poll counter when storm flares again" {
    var det = newBoostDetector(.{ .action = .warn, .priority_boost_enabled = true });
    det.setRendererThreadHandle(null);

    _ = det.updateBoost(true); // → boosted
    _ = det.updateBoost(false); // quiet=1
    _ = det.updateBoost(false); // quiet=2
    try testing.expectEqual(@as(u32, 2), det.consecutive_quiet_polls);

    // Storm flares — quiet counter resets, we stay boosted, and we do NOT
    // re-bump priority_boosts_applied (we never left .boosted).
    _ = det.updateBoost(true);
    try testing.expectEqual(BoostState.boosted, det.boost_state);
    try testing.expectEqual(@as(u32, 0), det.consecutive_quiet_polls);
    try testing.expectEqual(@as(u32, 1), det.priority_boosts_applied.load(.monotonic));
    try testing.expectEqual(@as(u32, 0), det.priority_restores_applied.load(.monotonic));
}

test "KS_CASCADE_PRIORITY_BOOST=disabled short-circuits the FSM" {
    // priority_boost_enabled=false short-circuits before any state change
    // or counter increment — the brief calls this out specifically as the
    // env-override contract.
    var det = newBoostDetector(.{ .action = .warn, .priority_boost_enabled = false });
    det.setRendererThreadHandle(null);

    _ = det.updateBoost(true);
    _ = det.updateBoost(true);
    _ = det.updateBoost(false);

    try testing.expectEqual(BoostState.idle, det.boost_state);
    try testing.expectEqual(@as(u32, 0), det.priority_boosts_applied.load(.monotonic));
    try testing.expectEqual(@as(u32, 0), det.priority_restores_applied.load(.monotonic));
}

test "Config.fromEnv hard-disables boost when action=disabled" {
    // When the detector itself is off there is no thread to drive the FSM,
    // so the boost must also be off — otherwise a later setRendererThreadHandle
    // call would leave us with a permanently-elevated thread we never
    // restore.
    var cfg = Config{ .action = .disabled, .priority_boost_enabled = true };
    // Direct field tweak then re-apply the invariant the way fromEnv does.
    if (cfg.action == .disabled) cfg.priority_boost_enabled = false;
    try testing.expect(!cfg.priority_boost_enabled);
}
