const std = @import("std");
const os = @import("os.zig");
const D3D11RenderPass = @import("../../renderer/d3d11/RenderPass.zig");

const zcp = @import("zig-control-plane");
const ControlPlaneLib = zcp.ControlPlane;
const Provider = zcp.Provider;
const PipeServer = zcp.pipe_server.PipeServer;

const windows = std.os.windows;
const Allocator = std.mem.Allocator;

extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;

const log = std.log.scoped(.winui3_control_plane);

fn postMessageWarn(hwnd: os.HWND, msg: os.UINT, wparam: os.WPARAM, lparam: os.LPARAM, msg_name: []const u8) bool {
    const result = os.PostMessageW(hwnd, msg, wparam, lparam);
    if (result == 0) {
        log.warn("PostMessageW failed msg={s} err={}", .{ msg_name, os.GetLastError() });
        return false;
    }
    return true;
}

const PendingInput = struct {
    from: []u8,
    text: []u8,
    raw: bool = false,
    cmd_id: u32 = 0,
};

const default_max_pending_inputs: usize = 128;
const default_max_inflight_data_requests: u32 = 1;

/// Circuit-breaker thresholds for the `renderer_locked` storm guard
/// (#242). Threshold = number of BUSY|renderer_locked emissions within
/// the rolling window that trips the breaker; once tripped, every
/// inbound request is short-circuited to BUSY for `open_ns`.
const renderer_locked_circuit_threshold: u32 = 5;
const renderer_locked_circuit_window_ns: i64 = 1 * std.time.ns_per_s;
const renderer_locked_circuit_open_ns: i64 = 100 * std.time.ns_per_ms;

// ── #269 observability: ring-buffered request samples + cadenced log ──
//
// We need numerical evidence that a forthcoming snapshot-cache fix actually
// moves the BUSY|renderer_locked rate. Per-request log lines would drown the
// signal, so we keep atomic counters + a 64-slot lossy ring of recent
// duration/outcome samples and emit one cp.stats line on a cadence. Lossy
// under contention is fine: this is observability, not source of truth.

/// Power of two so `idx % cp_recent_capacity` is a single AND.
const cp_recent_capacity: u32 = 64;

/// Outcome bucket recorded with each request sample. `error_other` covers
/// everything that wasn't BUSY (oom, internal_error, timeout).
const RingOutcome = enum(u8) { ok, busy, error_other };

/// Per-request observation. Fixed-size struct so the ring can live inline
/// in `ControlPlane`. `timestamp_ns` is wall-clock for cross-correlation
/// with external traces; `duration_ns` is monotonic-derived from a single
/// nanoTimestamp pair so it stays ≥0 even across CLOCK_REALTIME jumps.
const RingSample = struct {
    duration_ns: u64 = 0,
    outcome: RingOutcome = .ok,
    timestamp_ns: i128 = 0,
};

/// Emit a cp.stats line every `cp_log_interval_ns` of wall time OR every
/// time `busy_total` increments by `cp_log_busy_step` events, whichever
/// comes first. The dual trigger keeps idle sessions quiet but still
/// captures bursts that would otherwise span many quiet log windows.
const cp_log_interval_ns: i64 = 30 * std.time.ns_per_s;
const cp_log_busy_step: u64 = 100;

// ── UI-thread stall watchdog (#212) ──
//
// Two atomic timestamps that let an external observer (deckpilot daemon,
// test harness, etc.) detect "CP posted a WM_APP_CONTROL_INPUT but the UI
// thread never drained it" faster and more deterministically than
// IsHungAppWindow. Strictly observational: this module records timestamps
// and answers `isStalled(threshold_ns)`; it does NOT take any action on
// detection (kill / recover are explicitly out of scope per #212).
//
// Storage is i64 nanoseconds since the UNIX epoch (`std.time.nanoTimestamp`
// truncated to i64). i64 covers ~292 years from 1970, so safe through 2262.
// Sentinel value `0` means "never recorded".
//
// Memory ordering:
//   - Writers use `.release` so that any state mutated before the store is
//     visible to a reader that performs an `.acquire` load.
//   - Readers use `.acquire` for the same reason.
var pending_posted_at: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);
var last_drained_at: std.atomic.Value(i64) = std.atomic.Value(i64).init(0);

fn nowNs() i64 {
    return @as(i64, @intCast(std.time.nanoTimestamp()));
}

/// Record that a `WM_APP_CONTROL_INPUT` was just posted from the CP pipe
/// thread. Called immediately after `PostMessageW`.
fn recordPendingPost() void {
    pending_posted_at.store(nowNs(), .release);
}

/// Record that the UI thread just finished `drainPendingInputs`. Called at
/// the bottom of the drain handler.
fn recordDrain() void {
    last_drained_at.store(nowNs(), .release);
}

/// Pure stall predicate suitable for unit tests: takes the current
/// timestamp and threshold explicitly so synthetic clocks can be injected.
///
/// Stalled iff: (a) we've actually posted at least once, (b) more than
/// `threshold_ns` has elapsed since the most recent post, AND (c) no
/// drain has caught up to that post (`last_drained_at < pending_posted_at`).
///
/// The first clause matters: with both atomics at 0 (fresh boot), the
/// raw `(now - 0 > threshold) and (0 < 0)` would be `(true) and (false)`
/// = false anyway, but the explicit guard makes the intent obvious and
/// guards against future refactors that could change the sentinel.
pub fn isStalledAt(now_ns: i64, threshold_ns: i64) bool {
    const posted = pending_posted_at.load(.acquire);
    const drained = last_drained_at.load(.acquire);
    if (posted == 0) return false;
    return (now_ns - posted > threshold_ns) and (drained < posted);
}

/// Production stall predicate. Reads the monotonic wall clock and delegates
/// to `isStalledAt`. Daemon-side observers (deckpilot etc.) call this.
pub fn isStalled(threshold_ns: i64) bool {
    return isStalledAt(nowNs(), threshold_ns);
}

/// Snapshot of the watchdog atomics for the daemon-side observer. Both
/// fields are i64 nanoseconds since UNIX epoch; `0` means "never recorded".
pub const Observation = struct {
    pending_posted_at: i64,
    last_drained_at: i64,
};

pub fn lastObservation() Observation {
    return .{
        .pending_posted_at = pending_posted_at.load(.acquire),
        .last_drained_at = last_drained_at.load(.acquire),
    };
}

/// Test-only: reset both timestamps to 0. Lets each test start from a
/// known-clean state regardless of test ordering.
fn resetWatchdogForTest() void {
    pending_posted_at.store(0, .release);
    last_drained_at.store(0, .release);
}

const ResponseCache = struct {
    req: ?[]u8 = null,
    resp: ?[]u8 = null,
    ts_ns: i128 = 0,
    ttl_ns: i128 = 150 * std.time.ns_per_ms,

    fn clear(self: *ResponseCache, allocator: Allocator) void {
        if (self.req) |v| allocator.free(v);
        if (self.resp) |v| allocator.free(v);
        self.req = null;
        self.resp = null;
        self.ts_ns = 0;
    }
};

/// Zig-native control plane that replaces the Rust DLL.
///
/// Integrates the zig-control-plane library with the WinUI3 App runtime.
/// Thread-safe architecture:
/// - Mutations (newTab, closeTab, etc.) via PostMessageW (async) to UI thread.
/// - Reads (STATE, TAIL, etc.) use shared-memory snapshots (lock-free or mutex).
/// - No SendMessageW calls from CP thread to prevent UI-induced deadlocks.
pub const ControlPlane = struct {
    const BackendFn = *const fn (ctx: ?*anyopaque, request: []const u8, allocator: Allocator) anyerror![]const u8;
    /// Action codes posted via WM_APP_CONTROL_ACTION (wparam).
    /// Wire-compatible action codes used by ipc.zig PostMessageW dispatch.
    pub const Action = enum(usize) {
        new_tab = 1,
        close_tab = 2,
        switch_tab = 3,
        focus_window = 4,
    };

    // Capture function types for App.zig callbacks
    pub const StateSnapshot = struct {
        pwd: ?[]const u8 = null,
        title: ?[]const u8 = null,
        has_selection: bool = false,
        at_prompt: bool = false,
        tab_count: usize = 0,
        active_tab: usize = 0,
        pane_pid: u32 = 0,

        pub fn deinit(self: *StateSnapshot, allocator: Allocator) void {
            if (self.pwd) |pwd| allocator.free(pwd);
            if (self.title) |title| allocator.free(title);
            self.* = .{};
        }
    };

    pub const CaptureStateFn = *const fn (ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) anyerror!?StateSnapshot;
    pub const CaptureTailFn = *const fn (ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) anyerror!?[]u8;
    pub const CaptureHistoryFn = *const fn (ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) anyerror!?[]u8;
    pub const CaptureTabListFn = *const fn (ctx: *anyopaque, allocator: Allocator) anyerror!?[]u8;

    allocator: Allocator,
    hwnd: os.HWND,
    /// Session name (e.g. "ghostty-30052") — stored for window title display.
    session_name: ?[:0]const u8 = null,
    pending_inputs_lock: std.Thread.Mutex = .{},
    pending_inputs: std.ArrayListUnmanaged(PendingInput) = .{},
    /// Drained cmd_ids — set by drainPendingInputs, read by ACK_POLL.
    drained_lock: std.Thread.Mutex = .{},
    last_drained_cmd_id: u32 = 0,
    pending_ime_injects_lock: std.Thread.Mutex = .{},
    pending_ime_injects: std.ArrayListUnmanaged([]u8) = .{},
    callback_ctx: ?*anyopaque = null,

    // zig-control-plane library state
    cp: ?ControlPlaneLib = null,
    pipe_server: ?PipeServer = null,
    provider: ?Provider = null,

    cache_lock: std.Thread.Mutex = .{},
    cache: ResponseCache = .{},

    capture_state_fn: ?CaptureStateFn = null,
    capture_tail_fn: ?CaptureTailFn = null,
    capture_history_fn: ?CaptureHistoryFn = null,
    capture_tab_list_fn: ?CaptureTabListFn = null,
    max_pending_inputs: usize = default_max_pending_inputs,
    max_inflight_data_requests: u32 = default_max_inflight_data_requests,
    inflight_data_requests: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    last_provider_timeout: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Set by provCaptureSnapshot/provCaptureHistory when the App-side
    /// callback returns `error.RendererLocked` (i.e. the CP read-lane
    /// tryLock found `Surface.renderer_state.mutex` contended). The
    /// upper layer (handleRequestWith) consumes this flag and overrides
    /// the response with `ERR|BUSY|renderer_locked\n`.
    ///
    /// See `notes/2026-04-26_cp_stall_source_audit.md` cause (A) and
    /// the fix in `Surface.zig` `*Locked` variants.
    last_renderer_locked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Circuit breaker for renderer_locked storms (#242). When
    /// `renderer_locked_circuit_threshold` events occur within a
    /// `renderer_locked_circuit_window_ns` window, hold the circuit
    /// open for `renderer_locked_circuit_open_ns` and short-circuit
    /// inbound requests with `ERR|BUSY|renderer_locked` *without*
    /// dispatching to backend_fn — so clients back off and the
    /// `Surface.renderer_state.mutex` stops being further contended.
    /// Empirically (`tests/winui3/repro_panic_in_panic_under_load.ps1`)
    /// the unbounded retry pattern caused 17+ BUSY events in 4s and
    /// silent process death within ~18s under shell-flood load; the
    /// circuit breaker turns that into bounded retry pressure.
    renderer_locked_event_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    renderer_locked_window_start_ns: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    renderer_locked_circuit_open_until_ns: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    // ── #269 observability counters ──
    // Atomic counters bumped on every request entry/exit and BUSY emit.
    // `cp_inflight_max` is a high-water mark updated via CAS from the
    // success path of `recordRequestStart`. All counters are u64 except
    // `cp_inflight*` which are u32 — concurrent inflight CP requests will
    // not exceed `max_inflight_data_requests + control-lane`, comfortably
    // u32 and giving CAS a smaller footprint.
    cp_inflight: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    cp_inflight_max: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    cp_requests_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    cp_busy_total: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    cp_busy_renderer_locked: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    cp_busy_data_lane_full: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    cp_busy_input_queue_full: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    cp_circuit_open_emissions: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // Ring of recent request samples. `cp_recent_idx` is monotonic; the
    // physical slot is `idx % cp_recent_capacity`. We accept the data race
    // on the slot's struct contents (writer might be torn relative to a
    // concurrent reader) — readers tolerate junk samples and pdq-sort
    // small N anyway.
    cp_recent: [cp_recent_capacity]RingSample = [_]RingSample{.{}} ** cp_recent_capacity,
    cp_recent_idx: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    // Cadence state for `maybeLogStats`. `_at_ns` is wall-clock of last
    // emission; `_busy_at` is the busy_total value at last emission.
    cp_stats_last_log_at_ns: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),
    cp_stats_last_log_busy: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn isEnabled(allocator: Allocator) bool {
        return checkEnvFlag(allocator, "GHOSTTY_CONTROL_PLANE") or
            checkEnvFlag(allocator, "WINDOWS_TERMINAL_CONTROL_PLANE");
    }

    fn checkEnvFlag(allocator: Allocator, name: []const u8) bool {
        const value = std.process.getEnvVarOwned(allocator, name) catch return false;
        defer allocator.free(value);
        return std.mem.eql(u8, value, "1") or
            std.ascii.eqlIgnoreCase(value, "true") or
            std.ascii.eqlIgnoreCase(value, "yes");
    }

    pub fn create(
        allocator: Allocator,
        hwnd: os.HWND,
        callback_ctx: ?*anyopaque,
        capture_state_fn: ?CaptureStateFn,
        capture_tail_fn: ?CaptureTailFn,
        capture_history_fn: ?CaptureHistoryFn,
        capture_tab_list_fn: ?CaptureTabListFn,
    ) !*ControlPlane {
        const self = try allocator.create(ControlPlane);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .hwnd = hwnd,
            .callback_ctx = callback_ctx,
            .capture_state_fn = capture_state_fn,
            .capture_tail_fn = capture_tail_fn,
            .capture_history_fn = capture_history_fn,
            .capture_tab_list_fn = capture_tab_list_fn,
        };
        self.cache.ttl_ns = self.loadCacheTtlNs();
        self.max_pending_inputs = self.loadMaxPendingInputs();
        self.max_inflight_data_requests = self.loadMaxInflightDataRequests();

        // Initialize the Zig-native control plane
        self.initControlPlane() catch |err| {
            log.warn("control plane init failed: {} — control plane disabled", .{err});
            // Not fatal: control plane is simply disabled.
            return self;
        };

        return self;
    }

    fn initControlPlane(self: *ControlPlane) !void {
        const pid = GetCurrentProcessId();
        const session_name = loadSessionName(self.allocator, pid) catch |err| {
            log.warn("failed to load session name: {}", .{err});
            return error.SessionNameFailed;
        };
        defer self.allocator.free(session_name);

        // Keep a copy for window title display
        self.session_name = try self.allocator.dupeZ(u8, session_name);

        // Build the Provider vtable — callbacks bridge to self
        self.provider = .{
            .ctx = @ptrCast(self),
            .captureSnapshot = &provCaptureSnapshot,
            .captureHistory = &provCaptureHistory,
            .sendInput = &provSendInput,
            .ackPoll = &provAckPoll,
            .newTab = &provNewTab,
            .closeTab = &provCloseTab,
            .switchTab = &provSwitchTab,
            .focus = &provFocus,
            .hwnd = &provHwnd,
        };

        // Initialize ControlPlane library
        self.cp = try ControlPlaneLib.init(
            self.allocator,
            session_name,
            "ghostty-winui3",
            "ghostty-winui3",
            &self.provider.?,
        );

        // Start the session file
        try self.cp.?.start();

        // Build pipe name for the pipe server
        const safe_name = try zcp.session.sanitizeSessionName(self.allocator, session_name);
        defer self.allocator.free(safe_name);
        const pipe_name = try std.fmt.allocPrint(
            self.allocator,
            "\\\\.\\pipe\\ghostty-winui3-{s}-{d}",
            .{ safe_name, pid },
        );
        defer self.allocator.free(pipe_name);

        // Initialize and start the pipe server
        self.pipe_server = try PipeServer.init(self.allocator, pipe_name, &pipeHandler, @ptrCast(self));
        try self.pipe_server.?.start();

        log.info("control plane started (zig-native, pipe_prefix=ghostty-winui3, session={s})", .{session_name});
    }

    /// Pipe server handler — called from the pipe server thread.
    fn pipeHandler(request: []const u8, ctx: *anyopaque, allocator: Allocator) []const u8 {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        const req = std.mem.trim(u8, request, " \r\n\t");
        if (std.mem.indexOf(u8, req, "BGTRACE_STATE") != null) {
            const diag = D3D11RenderPass.traceDiagnostics();
            return std.fmt.allocPrint(
                allocator,
                "OK|enabled={d}|bind_counter={d}|sentinel={d}\n",
                .{
                    if (diag.enabled) @as(u8, 1) else @as(u8, 0),
                    diag.bind_counter,
                    if (diag.sentinel_emitted) @as(u8, 1) else @as(u8, 0),
                },
            ) catch return "ERR|oom\n";
        }
        if (self.cp) |*cp| {
            return self.handleRequestWith(request, allocator, cp, cpBackend);
        }
        return allocator.dupe(u8, "ERR|not_initialized\n") catch return "ERR|not_initialized\n";
    }

    fn handleRequestWith(
        self: *ControlPlane,
        request: []const u8,
        allocator: Allocator,
        backend_ctx: ?*anyopaque,
        backend_fn: BackendFn,
    ) []const u8 {
        const req = std.mem.trim(u8, request, " \r\n\t");
        const cmd = commandName(req);
        if (std.mem.eql(u8, cmd, "CAPABILITIES")) {
            return std.fmt.allocPrint(
                allocator,
                "OK|{s}|CAPABILITIES|transport=polling|reads=STATE,CAPTURE_PANE,TAIL,HISTORY,WAIT_FOR,PANE_PID,CURSOR_POS,PANE_TITLE,LIST_TABS|writes=INPUT,RAW_INPUT,PASTE,SEND_KEYS,ACK_POLL|control=NEW_TAB,CLOSE_TAB,SWITCH_TAB,FOCUS\n",
                .{self.session_name orelse "ghostty"},
            ) catch "ERR|oom\n";
        }
        // #269 observability: pair start/end so every served request lands
        // a sample in the ring, regardless of which return path fires.
        const obs_started_at = self.recordRequestStart();
        var obs_outcome: RingOutcome = .ok;
        defer {
            self.recordRequestEnd(obs_started_at, obs_outcome);
            self.maybeLogStats();
        }
        if (isBackpressureCommand(cmd) and self.pendingInputLen() >= self.max_pending_inputs) {
            self.recordBusy(.input_queue_full);
            obs_outcome = .busy;
            return allocator.dupe(u8, "ERR|BUSY|input_queue_full\n") catch "ERR|BUSY|input_queue_full\n";
        }
        // #242 circuit breaker: short-circuit during a renderer_locked
        // storm so we don't pile more tryLock attempts on the renderer
        // mutex. Open until is set on the cooldown path below.
        const cb_now_ns: i64 = @intCast(std.time.nanoTimestamp());
        if (cb_now_ns < self.renderer_locked_circuit_open_until_ns.load(.acquire)) {
            self.recordBusy(.circuit_open);
            obs_outcome = .busy;
            return allocator.dupe(u8, "ERR|BUSY|renderer_locked\n") catch "ERR|BUSY|renderer_locked\n";
        }
        if (isCacheableCommand(cmd)) {
            if (self.tryGetCachedResponse(req, allocator)) |cached| {
                return cached;
            }
        } else if (isMutatingCommand(cmd)) {
            self.clearResponseCache();
        }

        var data_lane_token = false;
        if (isDataLaneCommand(cmd)) {
            const prev = self.inflight_data_requests.fetchAdd(1, .acq_rel);
            if (prev >= self.max_inflight_data_requests) {
                _ = self.inflight_data_requests.fetchSub(1, .acq_rel);
                self.recordBusy(.data_lane_full);
                obs_outcome = .busy;
                return allocator.dupe(u8, "ERR|BUSY|data_lane_full\n") catch "ERR|BUSY|data_lane_full\n";
            }
            data_lane_token = true;
        }
        defer if (data_lane_token) {
            _ = self.inflight_data_requests.fetchSub(1, .acq_rel);
        };

        const resp = backend_fn(backend_ctx, request, allocator) catch |err| {
            log.warn("handleRequest error: {}", .{err});
            obs_outcome = .error_other;
            return allocator.dupe(u8, "ERR|internal_error\n") catch return "ERR|internal_error\n";
        };
        if (self.last_provider_timeout.swap(false, .acq_rel)) {
            allocator.free(resp);
            obs_outcome = .error_other;
            return allocator.dupe(u8, "ERR|TIMEOUT|ui_thread_busy\n") catch return "ERR|TIMEOUT|ui_thread_busy\n";
        }
        // Issue #207 hyp 1: CP read lane tryLock contended on
        // renderer_state.mutex → translate the generic SNAPSHOT_FAILED
        // (which the vendor lib emits when captureSnapshot returns false)
        // into a specific BUSY response so deckpilot can interpret it as
        // "skip this poll, retry later" rather than "session is dead".
        if (self.last_renderer_locked.swap(false, .acq_rel)) {
            allocator.free(resp);
            self.recordBusy(.renderer_locked);
            obs_outcome = .busy;
            // Track for #242 circuit breaker. Roll the window each
            // time it expires so a slow trickle of locks does not trip
            // the breaker, but a burst within window_ns will.
            const now_ns: i64 = @intCast(std.time.nanoTimestamp());
            const w_start = self.renderer_locked_window_start_ns.load(.acquire);
            if (w_start == 0 or now_ns - w_start > renderer_locked_circuit_window_ns) {
                self.renderer_locked_window_start_ns.store(now_ns, .release);
                self.renderer_locked_event_count.store(1, .release);
            } else {
                const cnt = self.renderer_locked_event_count.fetchAdd(1, .acq_rel) + 1;
                if (cnt >= renderer_locked_circuit_threshold) {
                    self.renderer_locked_circuit_open_until_ns.store(
                        now_ns + renderer_locked_circuit_open_ns,
                        .release,
                    );
                    log.warn("renderer_locked storm: {d} events in window — circuit open for {d}ms", .{
                        cnt, @divTrunc(renderer_locked_circuit_open_ns, std.time.ns_per_ms),
                    });
                }
            }
            return allocator.dupe(u8, "ERR|BUSY|renderer_locked\n") catch return "ERR|BUSY|renderer_locked\n";
        }
        if (isCacheableCommand(cmd) and !std.mem.startsWith(u8, std.mem.trim(u8, resp, " \r\n\t"), "ERR|")) {
            self.updateCachedResponse(req, resp);
        }
        return resp;
    }

    fn cpBackend(ctx: ?*anyopaque, request: []const u8, allocator: Allocator) ![]const u8 {
        _ = allocator;
        const cp: *ControlPlaneLib = @ptrCast(@alignCast(ctx orelse return error.InvalidContext));
        return cp.handleRequest(request);
    }

    pub fn destroy(self: *ControlPlane) void {
        // Stop the pipe server first
        if (self.pipe_server) |*ps| {
            ps.deinit();
            self.pipe_server = null;
        }

        // Stop and deinit the control plane library
        if (self.cp) |*cp| {
            cp.stop();
            cp.deinit();
            self.cp = null;
        }

        self.clearPendingInputs();
        self.clearResponseCache();
        if (self.session_name) |sn| {
            self.allocator.free(sn);
            self.session_name = null;
        }
        log.info("control plane stopped", .{});
        self.allocator.destroy(self);
    }

    fn clearPendingInputs(self: *ControlPlane) void {
        self.pending_inputs_lock.lock();
        defer self.pending_inputs_lock.unlock();

        for (self.pending_inputs.items) |entry| {
            self.allocator.free(entry.from);
            self.allocator.free(entry.text);
        }
        self.pending_inputs.deinit(self.allocator);
        self.pending_inputs = .{};

        self.pending_ime_injects_lock.lock();
        defer self.pending_ime_injects_lock.unlock();
        for (self.pending_ime_injects.items) |text| {
            self.allocator.free(text);
        }
        self.pending_ime_injects.deinit(self.allocator);
        self.pending_ime_injects = .{};
    }

    fn loadCacheTtlNs(self: *ControlPlane) i128 {
        const raw = std.process.getEnvVarOwned(self.allocator, "GHOSTTY_CP_CACHE_MS") catch return 150 * std.time.ns_per_ms;
        defer self.allocator.free(raw);
        const parsed = std.fmt.parseInt(u64, raw, 10) catch return 150 * std.time.ns_per_ms;
        if (parsed == 0) return 0;
        // Hard cap to keep staleness bounded.
        const bounded = @min(parsed, 2000);
        return @as(i128, @intCast(bounded)) * std.time.ns_per_ms;
    }

    fn loadMaxPendingInputs(self: *ControlPlane) usize {
        const raw = std.process.getEnvVarOwned(self.allocator, "GHOSTTY_CP_MAX_PENDING") catch return default_max_pending_inputs;
        defer self.allocator.free(raw);
        const parsed = std.fmt.parseInt(u32, raw, 10) catch return default_max_pending_inputs;
        if (parsed == 0) return default_max_pending_inputs;
        return @as(usize, @intCast(@min(parsed, 4096)));
    }

    fn loadMaxInflightDataRequests(self: *ControlPlane) u32 {
        const raw = std.process.getEnvVarOwned(self.allocator, "GHOSTTY_CP_MAX_INFLIGHT_DATA") catch return default_max_inflight_data_requests;
        defer self.allocator.free(raw);
        const parsed = std.fmt.parseInt(u32, raw, 10) catch return default_max_inflight_data_requests;
        if (parsed == 0) return default_max_inflight_data_requests;
        return @max(@as(u32, 1), @min(parsed, 1024));
    }

    fn clearResponseCache(self: *ControlPlane) void {
        self.cache_lock.lock();
        defer self.cache_lock.unlock();
        self.cache.clear(self.allocator);
    }

    fn tryGetCachedResponse(self: *ControlPlane, req: []const u8, allocator: Allocator) ?[]u8 {
        self.cache_lock.lock();
        defer self.cache_lock.unlock();
        if (self.cache.ttl_ns <= 0) return null;
        const cached_req = self.cache.req orelse return null;
        const cached_resp = self.cache.resp orelse return null;
        if (!std.mem.eql(u8, cached_req, req)) return null;
        const now = std.time.nanoTimestamp();
        if (now - self.cache.ts_ns > self.cache.ttl_ns) return null;
        return allocator.dupe(u8, cached_resp) catch null;
    }

    fn pendingInputLen(self: *ControlPlane) usize {
        self.pending_inputs_lock.lock();
        defer self.pending_inputs_lock.unlock();
        return self.pending_inputs.items.len;
    }

    fn updateCachedResponse(self: *ControlPlane, req: []const u8, resp: []const u8) void {
        const req_copy = self.allocator.dupe(u8, req) catch return;
        errdefer self.allocator.free(req_copy);
        const resp_copy = self.allocator.dupe(u8, resp) catch return;
        self.cache_lock.lock();
        defer self.cache_lock.unlock();
        if (self.cache.req) |old| self.allocator.free(old);
        if (self.cache.resp) |old| self.allocator.free(old);
        self.cache.req = req_copy;
        self.cache.resp = resp_copy;
        self.cache.ts_ns = std.time.nanoTimestamp();
    }

    fn enqueueInput(self: *ControlPlane, from: []const u8, text: []const u8, raw: bool, cmd_id: u32) bool {
        const owned_from = self.allocator.dupe(u8, from) catch return false;
        const owned_text = self.allocator.dupe(u8, text) catch {
            self.allocator.free(owned_from);
            return false;
        };

        self.pending_inputs_lock.lock();
        defer self.pending_inputs_lock.unlock();
        if (self.pending_inputs.items.len >= self.max_pending_inputs) {
            self.allocator.free(owned_from);
            self.allocator.free(owned_text);
            return false;
        }
        self.pending_inputs.append(self.allocator, .{
            .from = owned_from,
            .text = owned_text,
            .raw = raw,
            .cmd_id = cmd_id,
        }) catch {
            self.allocator.free(owned_from);
            self.allocator.free(owned_text);
            return false;
        };
        return true;
    }

    pub fn drainPendingInputs(self: *ControlPlane, surface: anytype) void {
        self.pending_inputs_lock.lock();
        var pending = self.pending_inputs;
        self.pending_inputs = .{};
        self.pending_inputs_lock.unlock();
        defer pending.deinit(self.allocator);

        log.info("drainPendingInputs: {} items", .{pending.items.len});

        const termio = @import("../../termio.zig");

        var max_cmd_id: u32 = 0;
        for (pending.items) |entry| {
            defer self.allocator.free(entry.from);
            defer self.allocator.free(entry.text);

            if (entry.cmd_id > max_cmd_id) max_cmd_id = entry.cmd_id;

            // Route ALL CP-originated text through queueIo, never textCallback.
            //
            // textCallback → completeClipboardPaste acquires renderer_state.mutex
            // on the UI thread. Under heavy CP input bursts (deckpilot send-text
            // storms) this serializes every keystroke through the renderer mutex,
            // letting a PTY-busy renderer stall the UI. queueIo hands the bytes
            // to termio's own queue, which drains off-UI.
            //
            // The CP protocol layer (vendor/zig-control-plane) already applies
            // bracketed-paste wrapping for .paste requests before they reach us,
            // so we never need to go through the clipboard-paste path here. Both
            // .input (raw=false) and .raw_input (raw=true) are written verbatim;
            // `entry.raw` is retained only for logging/symmetry. writeReq copies
            // the bytes (small-inline or alloc.dupe), so the `defer free` above
            // cleanly releases our owned buffer without double-free.
            _ = entry.raw;
            const msg = termio.Message.writeReq(self.allocator, entry.text) catch |err| {
                log.warn("failed to create cp write message: {}", .{err});
                continue;
            };
            surface.queueIo(msg, .unlocked);
        }

        // Update last drained cmd_id for ACK polling
        if (max_cmd_id > 0) {
            self.drained_lock.lock();
            defer self.drained_lock.unlock();
            if (max_cmd_id > self.last_drained_cmd_id) {
                self.last_drained_cmd_id = max_cmd_id;
                log.info("drainPendingInputs: ack cmd_id={}", .{max_cmd_id});
            }
        }

        // #212: stamp the drain timestamp unconditionally (even when the
        // pending list was empty) — a spurious WM_APP_CONTROL_INPUT that
        // finds nothing to drain is still a UI-thread liveness signal.
        recordDrain();
    }

    pub fn drainPendingImeInjects(self: *ControlPlane) ?[]u8 {
        self.pending_ime_injects_lock.lock();
        var pending = self.pending_ime_injects;
        self.pending_ime_injects = .{};
        self.pending_ime_injects_lock.unlock();

        if (pending.items.len == 0) {
            pending.deinit(self.allocator);
            return null;
        }

        var total_len: usize = 0;
        for (pending.items) |text| {
            total_len += text.len;
        }
        const result = self.allocator.alloc(u8, total_len) catch {
            for (pending.items) |text| self.allocator.free(text);
            pending.deinit(self.allocator);
            return null;
        };
        var offset: usize = 0;
        for (pending.items) |text| {
            @memcpy(result[offset..][0..text.len], text);
            offset += text.len;
            self.allocator.free(text);
        }
        pending.deinit(self.allocator);
        return result;
    }

    fn enqueueImeInject(self: *ControlPlane, text: []const u8) void {
        const owned = self.allocator.dupe(u8, text) catch return;
        self.pending_ime_injects_lock.lock();
        defer self.pending_ime_injects_lock.unlock();
        self.pending_ime_injects.append(self.allocator, owned) catch {
            self.allocator.free(owned);
        };
    }

    // ── #269 observability helpers ──
    // Helper-style instead of inline so the BUSY emission sites can stay
    // single-line edits — keeps the merge with the parallel snapshot-cache
    // branch mechanical.

    /// Aggregated observability snapshot consumed by external readers
    /// (cadenced log line, future `STATS` IPC verb). Caller owns no
    /// allocations; this is by-value on purpose.
    pub const Stats = struct {
        inflight: u32,
        inflight_max: u32,
        requests_total: u64,
        busy_total: u64,
        busy_renderer_locked: u64,
        busy_data_lane_full: u64,
        busy_input_queue_full: u64,
        circuit_open_emissions: u64,
        /// (busy_total * 1000) / max(requests_total, 1). "Per-mille"
        /// because BUSY rates are typically <1% and we want resolution.
        busy_rate_per_thousand: u32,
        recent_p50_ok_ns: u64,
        recent_p99_ok_ns: u64,
        recent_p50_busy_ns: u64,
        recent_p99_busy_ns: u64,
    };

    /// Bump cp_inflight + cp_inflight_max + cp_requests_total. Returns the
    /// monotonic start timestamp the caller stores until it pairs with
    /// `recordRequestEnd`.
    fn recordRequestStart(self: *ControlPlane) i128 {
        _ = self.cp_requests_total.fetchAdd(1, .monotonic);
        const after_add = self.cp_inflight.fetchAdd(1, .acq_rel) + 1;
        // CAS-loop high-water mark. Loops only when concurrent writers
        // race; trivially terminates because each retry observes a
        // strictly larger candidate or a race-winning new max.
        var observed = self.cp_inflight_max.load(.acquire);
        while (after_add > observed) {
            observed = self.cp_inflight_max.cmpxchgWeak(
                observed,
                after_add,
                .acq_rel,
                .acquire,
            ) orelse break;
        }
        return std.time.nanoTimestamp();
    }

    /// Pair with `recordRequestStart`. Decrements inflight and writes a
    /// sample into the ring under the given outcome.
    fn recordRequestEnd(self: *ControlPlane, started_at_ns: i128, outcome: RingOutcome) void {
        _ = self.cp_inflight.fetchSub(1, .acq_rel);
        const ended_at = std.time.nanoTimestamp();
        const delta = ended_at - started_at_ns;
        const duration_ns: u64 = if (delta < 0) 0 else @intCast(delta);
        const slot = self.cp_recent_idx.fetchAdd(1, .monotonic) % cp_recent_capacity;
        self.cp_recent[slot] = .{
            .duration_ns = duration_ns,
            .outcome = outcome,
            .timestamp_ns = ended_at,
        };
    }

    /// Bump the appropriate BUSY counter. Centralized so the BUSY emit
    /// sites in `handleRequestWith` stay single-line edits. `busy_total`
    /// is bumped exactly once per BUSY event, and the kind-specific
    /// counter is bumped exactly once — the kind enum prevents miscounts
    /// when multiple BUSY paths share a string.
    const BusyKind = enum { renderer_locked, data_lane_full, input_queue_full, circuit_open };
    fn recordBusy(self: *ControlPlane, kind: BusyKind) void {
        _ = self.cp_busy_total.fetchAdd(1, .monotonic);
        switch (kind) {
            .renderer_locked => _ = self.cp_busy_renderer_locked.fetchAdd(1, .monotonic),
            .data_lane_full => _ = self.cp_busy_data_lane_full.fetchAdd(1, .monotonic),
            .input_queue_full => _ = self.cp_busy_input_queue_full.fetchAdd(1, .monotonic),
            .circuit_open => {
                _ = self.cp_busy_renderer_locked.fetchAdd(1, .monotonic);
                _ = self.cp_circuit_open_emissions.fetchAdd(1, .monotonic);
            },
        }
    }

    /// Compute Stats by reading the atomics + sorting a snapshot of the
    /// ring. N=64 so a stack copy is fine; we never call this on the hot
    /// path. Pdq-sort is in-place on the local array.
    pub fn snapshotStats(self: *const ControlPlane) Stats {
        const reqs = self.cp_requests_total.load(.monotonic);
        const busy = self.cp_busy_total.load(.monotonic);
        // No requests yet → report 0 per-mille. We never want a
        // mathematically-defined-but-operationally-meaningless ratio
        // showing up in the log line during boot.
        const rate_pm: u32 = if (reqs == 0)
            0
        else
            @intCast(@min(@as(u64, std.math.maxInt(u32)), (busy * 1000) / reqs));

        var ok_buf: [cp_recent_capacity]u64 = undefined;
        var busy_buf: [cp_recent_capacity]u64 = undefined;
        var ok_n: usize = 0;
        var busy_n: usize = 0;
        // Snapshot ring contents. We don't atomic-load each slot — the
        // ring is intentionally lossy and small. A torn struct would at
        // worst skew one percentile sample.
        for (self.cp_recent) |sample| {
            // Skip the all-zero default rows (never written) so empty
            // ring → empty percentiles instead of a flood of 0s.
            if (sample.timestamp_ns == 0) continue;
            switch (sample.outcome) {
                .ok => {
                    ok_buf[ok_n] = sample.duration_ns;
                    ok_n += 1;
                },
                .busy => {
                    busy_buf[busy_n] = sample.duration_ns;
                    busy_n += 1;
                },
                .error_other => {},
            }
        }
        return .{
            .inflight = self.cp_inflight.load(.monotonic),
            .inflight_max = self.cp_inflight_max.load(.monotonic),
            .requests_total = reqs,
            .busy_total = busy,
            .busy_renderer_locked = self.cp_busy_renderer_locked.load(.monotonic),
            .busy_data_lane_full = self.cp_busy_data_lane_full.load(.monotonic),
            .busy_input_queue_full = self.cp_busy_input_queue_full.load(.monotonic),
            .circuit_open_emissions = self.cp_circuit_open_emissions.load(.monotonic),
            .busy_rate_per_thousand = rate_pm,
            .recent_p50_ok_ns = percentile(ok_buf[0..ok_n], 50),
            .recent_p99_ok_ns = percentile(ok_buf[0..ok_n], 99),
            .recent_p50_busy_ns = percentile(busy_buf[0..busy_n], 50),
            .recent_p99_busy_ns = percentile(busy_buf[0..busy_n], 99),
        };
    }

    /// Cadenced one-line emit. Called at the *end* of `handleRequestWith`
    /// after counters are settled. Cheap-fast-path: a single atomic load
    /// + integer compare returns false 99% of the time.
    fn maybeLogStats(self: *ControlPlane) void {
        const now_ns: i64 = @intCast(std.time.nanoTimestamp());
        const last_at = self.cp_stats_last_log_at_ns.load(.monotonic);
        const last_busy = self.cp_stats_last_log_busy.load(.monotonic);
        const busy_now = self.cp_busy_total.load(.monotonic);
        const time_due = (last_at == 0) or (now_ns - last_at >= cp_log_interval_ns);
        const busy_due = busy_now >= last_busy + cp_log_busy_step;
        if (!time_due and !busy_due) return;
        // CAS the timestamp so only one racing caller actually emits.
        // `last_at` may have changed under us; cmpxchg returns null on
        // win, the new observed value on loss → we just bail.
        if (self.cp_stats_last_log_at_ns.cmpxchgStrong(last_at, now_ns, .acq_rel, .acquire) != null) return;
        self.cp_stats_last_log_busy.store(busy_now, .release);
        const s = self.snapshotStats();
        log.info(
            "cp.stats inflight={d} inflight_max={d} req={d} busy={d} busy_rl={d} busy_dlf={d} busy_iqf={d} circuit={d} rate_pm={d} p50_ok={d} p99_ok={d} p50_busy={d} p99_busy={d}",
            .{
                s.inflight,              s.inflight_max,           s.requests_total,
                s.busy_total,            s.busy_renderer_locked,   s.busy_data_lane_full,
                s.busy_input_queue_full, s.circuit_open_emissions, s.busy_rate_per_thousand,
                s.recent_p50_ok_ns,      s.recent_p99_ok_ns,       s.recent_p50_busy_ns,
                s.recent_p99_busy_ns,
            },
        );
    }

    // ── Provider callbacks ──
    // Called from the pipe server thread. Read callbacks acquire
    // renderer_state.mutex directly (no SendMessageW round-trip).
    // Mutations use PostMessageW to the UI thread (async, no deadlock).

    /// Atomic cmd_id counter for ACK tracking.
    var next_cmd_id: u32 = 1;

    fn provSendInput(ctx: *anyopaque, text: []const u8, raw: bool, tab_index: ?usize) u32 {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = tab_index; // TODO: route to specific tab

        const cmd_id = @atomicRmw(u32, &next_cmd_id, .Add, 1, .monotonic);
        log.info("provSendInput hwnd=0x{x} len={} raw={} cmd_id={}", .{ @intFromPtr(self.hwnd), text.len, raw, cmd_id });

        // Special prefix "\x1b[TSF:" routes text through the TSF commit path
        const tsf_prefix = "\x1b[TSF:";
        if (text.len > tsf_prefix.len and std.mem.startsWith(u8, text, tsf_prefix)) {
            const payload = text[tsf_prefix.len..];
            self.enqueueImeInject(payload);
            const tsf_result = if (postMessageWarn(self.hwnd, os.WM_APP_TSF_INJECT, 0, 0, "WM_APP_TSF_INJECT")) @as(os.BOOL, 1) else 0;
            log.info("provSendInput PostMessageW(WM_APP_TSF_INJECT) result={}", .{tsf_result});
            return cmd_id;
        }

        if (!self.enqueueInput("zig-cp", text, raw, cmd_id)) {
            log.warn("provSendInput dropped input due to full queue (max={})", .{self.max_pending_inputs});
            return cmd_id;
        }
        const result = if (postMessageWarn(self.hwnd, os.WM_APP_CONTROL_INPUT, 0, 0, "WM_APP_CONTROL_INPUT")) @as(os.BOOL, 1) else 0;
        log.info("provSendInput PostMessageW(WM_APP_CONTROL_INPUT) result={}", .{result});
        if (result == 0) {
            return 0;
        }
        // #212: record post timestamp only after a successful PostMessageW.
        // A failed post leaves the prior `pending_posted_at` value in place,
        // which is correct: if an earlier post is still undrained, that
        // pending stall signal must continue to fire.
        recordPendingPost();
        return cmd_id;
    }

    fn provAckPoll(ctx: *anyopaque, cmd_id: u32) bool {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        self.drained_lock.lock();
        defer self.drained_lock.unlock();
        return cmd_id <= self.last_drained_cmd_id;
    }

    /// Issue #142: capture all tab state in a single SendMessageW round-trip.
    /// Called from zig-control-plane when captureSnapshot is wired into Provider.
    fn provCaptureSnapshot(ctx: *anyopaque, tab_index: usize, result: *zcp.CombinedSnapshot) bool {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        const callback_ctx = self.callback_ctx orelse return false;
        const capture_fn = self.capture_state_fn orelse return false;
        const capture_tail_fn = self.capture_tail_fn orelse return false;

        // 1. Capture basic state (pwd, etc.)
        var snapshot = (capture_fn(callback_ctx, self.allocator, tab_index) catch |err| {
            // Issue #207 hyp 1: signal renderer-locked so the upper
            // layer overrides SNAPSHOT_FAILED with ERR|BUSY|renderer_locked.
            if (err == error.RendererLocked) {
                self.last_renderer_locked.store(true, .release);
            }
            return false;
        }) orelse return false;
        defer snapshot.deinit(self.allocator);

        result.tab_count = snapshot.tab_count;
        result.active_tab = snapshot.active_tab;
        result.pane_pid = snapshot.pane_pid;
        result.has_selection = snapshot.has_selection;

        if (snapshot.pwd) |pwd| {
            const pwd_len = @min(pwd.len, result.pwd.len);
            @memcpy(result.pwd[0..pwd_len], pwd[0..pwd_len]);
            result.pwd_len = pwd_len;
        } else {
            result.pwd_len = 0;
        }

        if (snapshot.title) |title| {
            const title_len = @min(title.len, result.title.len);
            @memcpy(result.title[0..title_len], title[0..title_len]);
            result.title_len = title_len;
        } else {
            result.title_len = 0;
        }

        // 2. Capture viewport/tail
        const tail = (capture_tail_fn(callback_ctx, self.allocator, tab_index) catch |err| {
            if (err == error.RendererLocked) {
                self.last_renderer_locked.store(true, .release);
            }
            return false;
        }) orelse return false;
        defer self.allocator.free(tail);

        const tail_len = @min(tail.len, result.viewport.len);
        @memcpy(result.viewport[0..tail_len], tail[0..tail_len]);
        result.viewport_len = tail_len;

        return true;
    }

    /// Capture full scrollback history via SendMessageW round-trip.
    /// Same pattern as provCaptureSnapshot but uses capture_history QueryKind.
    fn provCaptureHistory(ctx: *anyopaque, tab_index: usize, result: *zcp.CombinedSnapshot) bool {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        const callback_ctx = self.callback_ctx orelse return false;
        const capture_fn = self.capture_state_fn orelse return false;
        const capture_history_fn = self.capture_history_fn orelse return false;

        // 1. Capture basic state (pwd, etc.)
        var snapshot = (capture_fn(callback_ctx, self.allocator, tab_index) catch |err| {
            if (err == error.RendererLocked) {
                self.last_renderer_locked.store(true, .release);
            }
            return false;
        }) orelse return false;
        defer snapshot.deinit(self.allocator);

        result.tab_count = snapshot.tab_count;
        result.active_tab = snapshot.active_tab;
        result.pane_pid = snapshot.pane_pid;
        result.has_selection = snapshot.has_selection;

        if (snapshot.pwd) |pwd| {
            const pwd_len = @min(pwd.len, result.pwd.len);
            @memcpy(result.pwd[0..pwd_len], pwd[0..pwd_len]);
            result.pwd_len = pwd_len;
        } else {
            result.pwd_len = 0;
        }

        if (snapshot.title) |title| {
            const title_len = @min(title.len, result.title.len);
            @memcpy(result.title[0..title_len], title[0..title_len]);
            result.title_len = title_len;
        } else {
            result.title_len = 0;
        }

        // 2. Capture history
        const history = (capture_history_fn(callback_ctx, self.allocator, tab_index) catch |err| {
            if (err == error.RendererLocked) {
                self.last_renderer_locked.store(true, .release);
            }
            return false;
        }) orelse return false;
        defer self.allocator.free(history);

        const history_len = @min(history.len, result.viewport.len);
        @memcpy(result.viewport[0..history_len], history[0..history_len]);
        result.viewport_len = history_len;

        return true;
    }

    fn provNewTab(ctx: *anyopaque) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = postMessageWarn(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.new_tab), 0, "WM_APP_CONTROL_ACTION");
    }

    fn provCloseTab(ctx: *anyopaque, index: usize) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = postMessageWarn(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.close_tab), @bitCast(index), "WM_APP_CONTROL_ACTION");
    }

    fn provSwitchTab(ctx: *anyopaque, index: usize) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = postMessageWarn(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.switch_tab), @bitCast(index), "WM_APP_CONTROL_ACTION");
    }

    fn provFocus(ctx: *anyopaque) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = postMessageWarn(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.focus_window), 0, "WM_APP_CONTROL_ACTION");
    }

    fn provHwnd(ctx: *anyopaque) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        return @intFromPtr(self.hwnd);
    }

    // Push notification API removed — event threads deleted in zig-control-plane.
    // Agent-deck polls TAIL/STATE directly; push events are unused.
    pub fn notifyStatus(self: *ControlPlane, status: []const u8) void {
        _ = self;
        _ = status;
    }
};

fn commandName(req: []const u8) []const u8 {
    const ws = std.mem.indexOfAny(u8, req, " \t\r\n") orelse req.len;
    const pipe = std.mem.indexOfScalar(u8, req, '|') orelse req.len;
    return req[0..@min(ws, pipe)];
}

/// Sort-and-pick percentile over a small slice. `pct` is 0..100 inclusive.
/// Empty slice → 0 (sentinel "no data" rather than a fabricated value).
/// We mutate the caller-owned slice in place; callers pass a stack copy
/// so the ring itself is never reordered.
fn percentile(samples: []u64, pct: u32) u64 {
    if (samples.len == 0) return 0;
    std.mem.sort(u64, samples, {}, std.sort.asc(u64));
    // Nearest-rank: index = ceil(pct/100 * N) - 1, clamped to [0, N-1].
    // Integer math: (pct * N + 99) / 100 - 1.
    const n = samples.len;
    const raw = (@as(usize, pct) * n + 99) / 100;
    const idx = if (raw == 0) 0 else @min(raw - 1, n - 1);
    return samples[idx];
}

fn isCacheableCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "STATE") or
        std.mem.eql(u8, cmd, "TAIL") or
        std.mem.eql(u8, cmd, "HISTORY") or
        std.mem.eql(u8, cmd, "LIST_TABS");
}

fn isMutatingCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "INPUT") or
        std.mem.eql(u8, cmd, "RAW_INPUT") or
        std.mem.eql(u8, cmd, "PASTE") or
        std.mem.eql(u8, cmd, "NEW_TAB") or
        std.mem.eql(u8, cmd, "CLOSE_TAB") or
        std.mem.eql(u8, cmd, "SWITCH_TAB") or
        std.mem.eql(u8, cmd, "FOCUS");
}

fn isBackpressureCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "INPUT") or
        std.mem.eql(u8, cmd, "RAW_INPUT") or
        std.mem.eql(u8, cmd, "PASTE");
}

fn isDataLaneCommand(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "STATE") or
        std.mem.eql(u8, cmd, "TAIL") or
        std.mem.eql(u8, cmd, "HISTORY") or
        std.mem.eql(u8, cmd, "LIST_TABS");
}

fn loadSessionName(allocator: Allocator, pid: u32) ![]u8 {
    const env_name = std.process.getEnvVarOwned(allocator, "GHOSTTY_SESSION_NAME") catch null;
    if (env_name) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len == 0) {
            allocator.free(value);
        } else if (trimmed.ptr == value.ptr and trimmed.len == value.len) {
            return value;
        } else {
            const duped = try allocator.dupe(u8, trimmed);
            allocator.free(value);
            return duped;
        }
    }
    return std.fmt.allocPrint(allocator, "ghostty-{d}", .{pid});
}

// ═══════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════

test "commandName parses up to delimiter" {
    try std.testing.expectEqualStrings("STATE", commandName("STATE"));
    try std.testing.expectEqualStrings("TAIL", commandName("TAIL|1"));
    try std.testing.expectEqualStrings("LIST_TABS", commandName("LIST_TABS \r\n"));
}

test "isCacheableCommand classification" {
    try std.testing.expect(isCacheableCommand("STATE"));
    try std.testing.expect(isCacheableCommand("TAIL"));
    try std.testing.expect(isCacheableCommand("HISTORY"));
    try std.testing.expect(isCacheableCommand("LIST_TABS"));
    try std.testing.expect(!isCacheableCommand("INPUT"));
    try std.testing.expect(!isCacheableCommand("RAW_INPUT"));
}

test "isMutatingCommand classification" {
    try std.testing.expect(isMutatingCommand("INPUT"));
    try std.testing.expect(isMutatingCommand("RAW_INPUT"));
    try std.testing.expect(isMutatingCommand("PASTE"));
    try std.testing.expect(isMutatingCommand("NEW_TAB"));
    try std.testing.expect(isMutatingCommand("CLOSE_TAB"));
    try std.testing.expect(isMutatingCommand("SWITCH_TAB"));
    try std.testing.expect(isMutatingCommand("FOCUS"));
    try std.testing.expect(!isMutatingCommand("PING"));
    try std.testing.expect(!isMutatingCommand("STATE"));
    try std.testing.expect(!isMutatingCommand("TAIL"));
}

test "isBackpressureCommand classification" {
    try std.testing.expect(isBackpressureCommand("INPUT"));
    try std.testing.expect(isBackpressureCommand("RAW_INPUT"));
    try std.testing.expect(isBackpressureCommand("PASTE"));
    try std.testing.expect(!isBackpressureCommand("TAIL"));
    try std.testing.expect(!isBackpressureCommand("STATE"));
}

test "isDataLaneCommand classification" {
    try std.testing.expect(isDataLaneCommand("STATE"));
    try std.testing.expect(isDataLaneCommand("TAIL"));
    try std.testing.expect(isDataLaneCommand("HISTORY"));
    try std.testing.expect(isDataLaneCommand("LIST_TABS"));
    try std.testing.expect(!isDataLaneCommand("PING"));
    try std.testing.expect(!isDataLaneCommand("INPUT"));
}

test "ResponseCache clear keeps ttl" {
    var cache = ResponseCache{
        .req = try std.testing.allocator.dupe(u8, "TAIL|x|40"),
        .resp = try std.testing.allocator.dupe(u8, "OK|cached"),
        .ts_ns = 123,
        .ttl_ns = 777,
    };
    defer cache.clear(std.testing.allocator);
    cache.clear(std.testing.allocator);
    try std.testing.expect(cache.req == null);
    try std.testing.expect(cache.resp == null);
    try std.testing.expectEqual(@as(i128, 0), cache.ts_ns);
    try std.testing.expectEqual(@as(i128, 777), cache.ttl_ns);
}

const TestBackendCtx = struct {
    calls: usize = 0,
};

fn testBackend(ctx: ?*anyopaque, request: []const u8, allocator: Allocator) ![]const u8 {
    const tb: *TestBackendCtx = @ptrCast(@alignCast(ctx orelse return error.InvalidContext));
    tb.calls += 1;
    return try std.fmt.allocPrint(allocator, "OK|calls={d}|req={s}", .{ tb.calls, request });
}

fn contractBackend(_: ?*anyopaque, request: []const u8, allocator: Allocator) ![]const u8 {
    const cmd = commandName(std.mem.trim(u8, request, " \r\n\t"));
    if (std.mem.eql(u8, cmd, "PING")) return try allocator.dupe(u8, "OK|PONG\n");
    if (std.mem.eql(u8, cmd, "STATE")) return try allocator.dupe(u8, "OK|state\n");
    if (std.mem.eql(u8, cmd, "TAIL")) return try allocator.dupe(u8, "OK|tail\n");
    if (std.mem.eql(u8, cmd, "INPUT")) return try allocator.dupe(u8, "OK|input\n");
    if (std.mem.eql(u8, cmd, "ACK_POLL")) return try allocator.dupe(u8, "OK|ack\n");
    return try std.fmt.allocPrint(allocator, "ERR|UNSUPPORTED|{s}\n", .{cmd});
}

test "handleRequestWith caches read commands and invalidates on mutating command" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    cp.cache.ttl_ns = 5 * std.time.ns_per_s;
    defer cp.cache.clear(std.testing.allocator);

    var tb = TestBackendCtx{};

    const r1 = cp.handleRequestWith("TAIL|test-client|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqual(@as(usize, 1), tb.calls);

    const r2 = cp.handleRequestWith("TAIL|test-client|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqual(@as(usize, 1), tb.calls);
    try std.testing.expectEqualStrings(r1, r2);

    const r3 = cp.handleRequestWith("INPUT|test-client|echo hi", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqual(@as(usize, 2), tb.calls);

    const r4 = cp.handleRequestWith("TAIL|test-client|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r4);
    try std.testing.expectEqual(@as(usize, 3), tb.calls);
}

test "handleRequestWith rejects input when queue is full" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
        .max_pending_inputs = 1,
    };
    defer cp.clearPendingInputs();

    try std.testing.expect(cp.enqueueInput("zig-cp", "echo hi", false, 1));

    const resp = cp.handleRequestWith("INPUT|test-client|echo again", std.testing.allocator, null, testBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|BUSY|input_queue_full\n", resp);
}

test "handleRequestWith limits data lane but allows control lane" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
        .max_inflight_data_requests = 1,
    };
    cp.inflight_data_requests.store(1, .release);

    var tb = TestBackendCtx{};

    const data_resp = cp.handleRequestWith("TAIL|test-client|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(data_resp);
    try std.testing.expectEqualStrings("ERR|BUSY|data_lane_full\n", data_resp);
    try std.testing.expectEqual(@as(usize, 0), tb.calls);

    const ping_resp = cp.handleRequestWith("PING", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(ping_resp);
    try std.testing.expectEqual(@as(usize, 1), tb.calls);
}

test "handleRequestWith serves CAPABILITIES without backend call" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
        .session_name = "ghostty-test",
    };

    var tb = TestBackendCtx{};
    const resp = cp.handleRequestWith("CAPABILITIES", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(resp);

    try std.testing.expectEqual(@as(usize, 0), tb.calls);
    try std.testing.expect(std.mem.startsWith(u8, resp, "OK|ghostty-test|CAPABILITIES|"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "reads=STATE,CAPTURE_PANE,TAIL,HISTORY,WAIT_FOR,PANE_PID,CURSOR_POS,PANE_TITLE,LIST_TABS") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "writes=INPUT,RAW_INPUT,PASTE,SEND_KEYS,ACK_POLL") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "control=NEW_TAB,CLOSE_TAB,SWITCH_TAB,FOCUS") != null);
}

test "handleRequestWith keeps legacy commands working without CAPABILITIES query" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };

    const ping = cp.handleRequestWith("PING", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(ping);
    try std.testing.expectEqualStrings("OK|PONG\n", ping);

    const state = cp.handleRequestWith("STATE|test-client|0", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(state);
    try std.testing.expectEqualStrings("OK|state\n", state);

    const tail = cp.handleRequestWith("TAIL|test-client|20", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(tail);
    try std.testing.expectEqualStrings("OK|tail\n", tail);

    const input = cp.handleRequestWith("INPUT|test-client|echo hi", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(input);
    try std.testing.expectEqualStrings("OK|input\n", input);

    const ack = cp.handleRequestWith("ACK_POLL|test-client", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(ack);
    try std.testing.expectEqualStrings("OK|ack\n", ack);
}

test "handleRequestWith returns deterministic ERR for unsupported command" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };

    const resp = cp.handleRequestWith("RAW_INPUT|test-client|hello", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|UNSUPPORTED|RAW_INPUT\n", resp);
}

// ── #212: UI-thread stall watchdog ──
//
// These tests drive the module-level `pending_posted_at` / `last_drained_at`
// atomics directly via `resetWatchdogForTest` + the public store helpers,
// so the assertions don't depend on the wall clock or on any actual UI
// thread. `isStalledAt` takes the synthetic `now_ns` so each test pins a
// deterministic time.

test "isStalled: fresh state never alarms (no posts, no drains)" {
    resetWatchdogForTest();
    // Both sentinels at 0. Even at very large `now_ns` and tiny threshold,
    // we must NOT report stalled — that would be a spurious alarm before
    // CP has actually seen any traffic.
    try std.testing.expect(!isStalledAt(1_000_000_000_000, 1));
    try std.testing.expect(!isStalledAt(0, 0));
}

test "isStalled: post without subsequent drain past threshold returns true" {
    resetWatchdogForTest();
    const t_post: i64 = 1_000_000_000;
    pending_posted_at.store(t_post, .release);
    // 5ms threshold, simulate 10ms elapsed since post.
    const threshold_ns: i64 = 5 * std.time.ns_per_ms;
    const now: i64 = t_post + 10 * std.time.ns_per_ms;
    try std.testing.expect(isStalledAt(now, threshold_ns));
}

test "isStalled: post and drain at same instant is not stalled" {
    resetWatchdogForTest();
    const t: i64 = 1_000_000_000;
    pending_posted_at.store(t, .release);
    last_drained_at.store(t, .release);
    // Even far past the post timestamp, drained==posted means caught up,
    // so we are not stalled. (drained < posted is false.)
    const threshold_ns: i64 = 1 * std.time.ns_per_ms;
    const now: i64 = t + 1 * std.time.ns_per_s;
    try std.testing.expect(!isStalledAt(now, threshold_ns));
}

test "isStalled: post→drain→repost within threshold is not stalled" {
    resetWatchdogForTest();
    const t1: i64 = 1_000_000_000;
    pending_posted_at.store(t1, .release);
    last_drained_at.store(t1 + 1 * std.time.ns_per_ms, .release);
    // Second post happens AFTER the first drain — drained < posted now true.
    const t2: i64 = t1 + 5 * std.time.ns_per_ms;
    pending_posted_at.store(t2, .release);
    // 50ms threshold; only 10ms has elapsed since the second post.
    const threshold_ns: i64 = 50 * std.time.ns_per_ms;
    const now: i64 = t2 + 10 * std.time.ns_per_ms;
    try std.testing.expect(!isStalledAt(now, threshold_ns));
}

test "isStalled: post→drain→repost past threshold returns true" {
    resetWatchdogForTest();
    const t1: i64 = 1_000_000_000;
    pending_posted_at.store(t1, .release);
    last_drained_at.store(t1 + 1 * std.time.ns_per_ms, .release);
    const t2: i64 = t1 + 5 * std.time.ns_per_ms;
    pending_posted_at.store(t2, .release);
    // 50ms threshold; 100ms has elapsed since the second post — stalled.
    const threshold_ns: i64 = 50 * std.time.ns_per_ms;
    const now: i64 = t2 + 100 * std.time.ns_per_ms;
    try std.testing.expect(isStalledAt(now, threshold_ns));
}

test "lastObservation reflects the most recent stored values" {
    resetWatchdogForTest();
    const tp: i64 = 12_345;
    const td: i64 = 67_890;
    pending_posted_at.store(tp, .release);
    last_drained_at.store(td, .release);
    const obs = lastObservation();
    try std.testing.expectEqual(tp, obs.pending_posted_at);
    try std.testing.expectEqual(td, obs.last_drained_at);
}

// ── #269 observability tests ──
//
// All counter paths covered: happy path, type bounds, concurrent
// fanin, per-BUSY-kind isolation, inflight balance, percentile shape.

test "observability: counters start at zero" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    const s = cp.snapshotStats();
    try std.testing.expectEqual(@as(u32, 0), s.inflight);
    try std.testing.expectEqual(@as(u32, 0), s.inflight_max);
    try std.testing.expectEqual(@as(u64, 0), s.requests_total);
    try std.testing.expectEqual(@as(u64, 0), s.busy_total);
    try std.testing.expectEqual(@as(u64, 0), s.busy_renderer_locked);
    try std.testing.expectEqual(@as(u64, 0), s.busy_data_lane_full);
    try std.testing.expectEqual(@as(u64, 0), s.busy_input_queue_full);
    try std.testing.expectEqual(@as(u64, 0), s.circuit_open_emissions);
    // 0 / max(0,1) = 0 — no division by zero.
    try std.testing.expectEqual(@as(u32, 0), s.busy_rate_per_thousand);
    // Empty ring → percentile sentinel 0.
    try std.testing.expectEqual(@as(u64, 0), s.recent_p50_ok_ns);
    try std.testing.expectEqual(@as(u64, 0), s.recent_p99_ok_ns);
}

test "observability: counter type widths accommodate u64::MAX semantics" {
    // Comptime asserts that the field types are wide enough to never
    // pin a real-world counter. We don't actually count up to maxInt;
    // the contract is "the type doesn't artificially cap us".
    const cp_t = ControlPlane;
    comptime {
        std.debug.assert(@TypeOf(@as(cp_t, undefined).cp_requests_total) == std.atomic.Value(u64));
        std.debug.assert(@TypeOf(@as(cp_t, undefined).cp_busy_total) == std.atomic.Value(u64));
        std.debug.assert(@TypeOf(@as(cp_t, undefined).cp_inflight) == std.atomic.Value(u32));
    }
}

test "observability: recordRequestStart/End balance inflight to zero" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    const t1 = cp.recordRequestStart();
    const t2 = cp.recordRequestStart();
    const t3 = cp.recordRequestStart();
    try std.testing.expectEqual(@as(u32, 3), cp.cp_inflight.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 3), cp.cp_inflight_max.load(.monotonic));
    cp.recordRequestEnd(t1, .ok);
    cp.recordRequestEnd(t2, .busy);
    cp.recordRequestEnd(t3, .error_other);
    try std.testing.expectEqual(@as(u32, 0), cp.cp_inflight.load(.monotonic));
    // High-water mark is monotonic — does not retreat.
    try std.testing.expectEqual(@as(u32, 3), cp.cp_inflight_max.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 3), cp.cp_requests_total.load(.monotonic));
}

test "observability: inflight high-water mark only grows" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    const a = cp.recordRequestStart();
    const b = cp.recordRequestStart();
    cp.recordRequestEnd(a, .ok);
    cp.recordRequestEnd(b, .ok);
    // Single subsequent request must not regress the high-water mark.
    const c = cp.recordRequestStart();
    cp.recordRequestEnd(c, .ok);
    try std.testing.expectEqual(@as(u32, 2), cp.cp_inflight_max.load(.monotonic));
}

test "observability: recordBusy isolates each BUSY kind" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    cp.recordBusy(.renderer_locked);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_renderer_locked.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_busy_data_lane_full.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_busy_input_queue_full.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_circuit_open_emissions.load(.monotonic));
    cp.recordBusy(.data_lane_full);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_data_lane_full.load(.monotonic));
    cp.recordBusy(.input_queue_full);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_input_queue_full.load(.monotonic));
    cp.recordBusy(.circuit_open);
    // circuit_open ALSO counts as renderer_locked semantically — both
    // counters move so the renderer_locked-rate metric stays honest.
    try std.testing.expectEqual(@as(u64, 2), cp.cp_busy_renderer_locked.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), cp.cp_circuit_open_emissions.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 4), cp.cp_busy_total.load(.monotonic));
}

test "observability: ring fills, wraps, and percentile reflects content" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    // Hand-write 64 OK samples with durations [1..64] ns. We bypass
    // the timing path and write directly to the ring.
    for (0..cp_recent_capacity) |i| {
        cp.cp_recent[i] = .{
            .duration_ns = @as(u64, @intCast(i + 1)),
            .outcome = .ok,
            .timestamp_ns = 1, // non-zero so snapshotStats counts it
        };
    }
    cp.cp_recent_idx.store(cp_recent_capacity, .release);
    const s = cp.snapshotStats();
    // Nearest-rank: p50 of [1..64] → idx ceil(50*64/100)-1 = 31 → value 32.
    try std.testing.expectEqual(@as(u64, 32), s.recent_p50_ok_ns);
    // p99 → idx ceil(99*64/100)-1 = 63 → value 64.
    try std.testing.expectEqual(@as(u64, 64), s.recent_p99_ok_ns);
    // No busy samples written → busy percentiles still 0.
    try std.testing.expectEqual(@as(u64, 0), s.recent_p50_busy_ns);
    try std.testing.expectEqual(@as(u64, 0), s.recent_p99_busy_ns);
}

test "observability: ring of identical values returns that value at every percentile" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    for (0..cp_recent_capacity) |i| {
        cp.cp_recent[i] = .{
            .duration_ns = 42,
            .outcome = .busy,
            .timestamp_ns = 1,
        };
    }
    cp.cp_recent_idx.store(cp_recent_capacity, .release);
    const s = cp.snapshotStats();
    try std.testing.expectEqual(@as(u64, 42), s.recent_p50_busy_ns);
    try std.testing.expectEqual(@as(u64, 42), s.recent_p99_busy_ns);
    // OK bucket must remain empty.
    try std.testing.expectEqual(@as(u64, 0), s.recent_p50_ok_ns);
}

test "observability: percentile helper handles empty/single/sorted slices" {
    var empty = [_]u64{};
    try std.testing.expectEqual(@as(u64, 0), percentile(&empty, 50));
    try std.testing.expectEqual(@as(u64, 0), percentile(&empty, 99));

    var one = [_]u64{7};
    try std.testing.expectEqual(@as(u64, 7), percentile(&one, 0));
    try std.testing.expectEqual(@as(u64, 7), percentile(&one, 50));
    try std.testing.expectEqual(@as(u64, 7), percentile(&one, 99));

    // Out-of-order input must be sorted internally; result independent of
    // input permutation.
    var perm = [_]u64{ 5, 1, 4, 2, 3 };
    try std.testing.expectEqual(@as(u64, 3), percentile(&perm, 50));
    try std.testing.expectEqual(@as(u64, 5), percentile(&perm, 99));
}

test "observability: busy_rate_per_thousand math" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    cp.cp_requests_total.store(1000, .monotonic);
    cp.cp_busy_total.store(37, .monotonic);
    const s = cp.snapshotStats();
    try std.testing.expectEqual(@as(u32, 37), s.busy_rate_per_thousand);
    // No requests → no division by zero, returns 0.
    cp.cp_requests_total.store(0, .monotonic);
    cp.cp_busy_total.store(5, .monotonic);
    const s2 = cp.snapshotStats();
    try std.testing.expectEqual(@as(u32, 0), s2.busy_rate_per_thousand);
}

test "observability: handleRequestWith bumps requests_total + leaves inflight at zero" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    var tb = TestBackendCtx{};
    const r = cp.handleRequestWith("PING", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_requests_total.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), cp.cp_inflight.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_busy_total.load(.monotonic));
}

test "observability: handleRequestWith counts data_lane_full BUSY" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
        .max_inflight_data_requests = 1,
    };
    cp.inflight_data_requests.store(1, .release);
    var tb = TestBackendCtx{};
    const resp = cp.handleRequestWith("TAIL|test|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|BUSY|data_lane_full\n", resp);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_data_lane_full.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_total.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_busy_renderer_locked.load(.monotonic));
}

test "observability: handleRequestWith counts input_queue_full BUSY" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
        .max_pending_inputs = 1,
    };
    defer cp.clearPendingInputs();
    try std.testing.expect(cp.enqueueInput("zig-cp", "x", false, 1));

    const resp = cp.handleRequestWith("INPUT|test|y", std.testing.allocator, null, testBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|BUSY|input_queue_full\n", resp);
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_input_queue_full.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_total.load(.monotonic));
}

test "observability: handleRequestWith counts circuit_open BUSY" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    // Open the circuit far into the future so even a slow CI clock
    // sees us inside the open window.
    const future_ns: i64 = @intCast(std.time.nanoTimestamp() + 10 * std.time.ns_per_s);
    cp.renderer_locked_circuit_open_until_ns.store(future_ns, .release);
    var tb = TestBackendCtx{};
    const resp = cp.handleRequestWith("STATE|test|0", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|BUSY|renderer_locked\n", resp);
    try std.testing.expectEqual(@as(u64, 0), tb.calls); // backend not invoked
    try std.testing.expectEqual(@as(u64, 1), cp.cp_circuit_open_emissions.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), cp.cp_busy_renderer_locked.load(.monotonic));
}

// Concurrency: 4 threads × 1000 increments each — atomic correctness.
fn observabilityCounterBumpThread(cp: *ControlPlane) void {
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        cp.recordBusy(.renderer_locked);
    }
}

test "observability: concurrent recordBusy is atomic (4×1000=4000)" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, observabilityCounterBumpThread, .{&cp});
    }
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(u64, 4000), cp.cp_busy_renderer_locked.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 4000), cp.cp_busy_total.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), cp.cp_circuit_open_emissions.load(.monotonic));
}

fn observabilityRequestRoundtripThread(cp: *ControlPlane) void {
    var i: usize = 0;
    while (i < 250) : (i += 1) {
        const t = cp.recordRequestStart();
        cp.recordRequestEnd(t, .ok);
    }
}

test "observability: concurrent request lifecycle balances inflight" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, observabilityRequestRoundtripThread, .{&cp});
    }
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(u64, 1000), cp.cp_requests_total.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), cp.cp_inflight.load(.monotonic));
    // High-water mark is ≥1; exact value is timing-dependent so just
    // assert it observed at least one request and never exceeded the
    // physical thread count.
    const max = cp.cp_inflight_max.load(.monotonic);
    try std.testing.expect(max >= 1 and max <= 4);
}

test "observability: cp.stats log line format renders all fields" {
    // Regression catch for an external log-parser drift. We don't run
    // the cadenced emit (which would race the test logger) — instead
    // we reproduce the exact format string against a known Stats and
    // assert structure + ordering.
    const s = ControlPlane.Stats{
        .inflight = 3,
        .inflight_max = 7,
        .requests_total = 42,
        .busy_total = 5,
        .busy_renderer_locked = 4,
        .busy_data_lane_full = 1,
        .busy_input_queue_full = 0,
        .circuit_open_emissions = 2,
        .busy_rate_per_thousand = 119,
        .recent_p50_ok_ns = 8_000,
        .recent_p99_ok_ns = 250_000,
        .recent_p50_busy_ns = 110_000,
        .recent_p99_busy_ns = 900_000,
    };
    const line = try std.fmt.allocPrint(
        std.testing.allocator,
        "cp.stats inflight={d} inflight_max={d} req={d} busy={d} busy_rl={d} busy_dlf={d} busy_iqf={d} circuit={d} rate_pm={d} p50_ok={d} p99_ok={d} p50_busy={d} p99_busy={d}",
        .{
            s.inflight,              s.inflight_max,           s.requests_total,
            s.busy_total,            s.busy_renderer_locked,   s.busy_data_lane_full,
            s.busy_input_queue_full, s.circuit_open_emissions, s.busy_rate_per_thousand,
            s.recent_p50_ok_ns,      s.recent_p99_ok_ns,       s.recent_p50_busy_ns,
            s.recent_p99_busy_ns,
        },
    );
    defer std.testing.allocator.free(line);
    try std.testing.expectEqualStrings(
        "cp.stats inflight=3 inflight_max=7 req=42 busy=5 busy_rl=4 busy_dlf=1 busy_iqf=0 circuit=2 rate_pm=119 p50_ok=8000 p99_ok=250000 p50_busy=110000 p99_busy=900000",
        line,
    );
}

test "observability: maybeLogStats fast-path returns without emit on idle" {
    // Two back-to-back calls with no intervening counter movement
    // should not advance the cadence state — the second is a no-op.
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(1),
    };
    cp.maybeLogStats(); // first call: time_due (last_at == 0)
    const after_first = cp.cp_stats_last_log_at_ns.load(.monotonic);
    try std.testing.expect(after_first != 0);
    cp.maybeLogStats(); // second call: no busy step, no time elapsed
    const after_second = cp.cp_stats_last_log_at_ns.load(.monotonic);
    try std.testing.expectEqual(after_first, after_second);
}
