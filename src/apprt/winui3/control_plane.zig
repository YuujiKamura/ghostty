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
        if (isBackpressureCommand(cmd) and self.pendingInputLen() >= self.max_pending_inputs) {
            return allocator.dupe(u8, "ERR|BUSY|input_queue_full\n") catch "ERR|BUSY|input_queue_full\n";
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
                return allocator.dupe(u8, "ERR|BUSY|data_lane_full\n") catch "ERR|BUSY|data_lane_full\n";
            }
            data_lane_token = true;
        }
        defer if (data_lane_token) {
            _ = self.inflight_data_requests.fetchSub(1, .acq_rel);
        };

        const resp = backend_fn(backend_ctx, request, allocator) catch |err| {
            log.warn("handleRequest error: {}", .{err});
            return allocator.dupe(u8, "ERR|internal_error\n") catch return "ERR|internal_error\n";
        };
        if (self.last_provider_timeout.swap(false, .acq_rel)) {
            allocator.free(resp);
            return allocator.dupe(u8, "ERR|TIMEOUT|ui_thread_busy\n") catch return "ERR|TIMEOUT|ui_thread_busy\n";
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

            if (entry.raw) {
                const msg = termio.Message.writeReq(self.allocator, entry.text) catch |err| {
                    log.warn("failed to create raw write message: {}", .{err});
                    continue;
                };
                surface.queueIo(msg, .unlocked);
            } else {
                surface.textCallback(entry.text) catch |err| {
                    log.warn("failed to apply control-plane input: {}", .{err});
                    continue;
                };
            }
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

    // ── Provider callbacks ──
    // Called from the pipe server thread. Read callbacks use SendMessageW
    // (WM_APP_CP_QUERY) to execute on the UI thread, avoiding data races
    // with App state (Issue #139 H1 fix).

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
        var snapshot = (capture_fn(callback_ctx, self.allocator, tab_index) catch return false) orelse return false;
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
        const tail = (capture_tail_fn(callback_ctx, self.allocator, tab_index) catch return false) orelse return false;
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
        var snapshot = (capture_fn(callback_ctx, self.allocator, tab_index) catch return false) orelse return false;
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
        const history = (capture_history_fn(callback_ctx, self.allocator, tab_index) catch return false) orelse return false;
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
        .hwnd = @ptrFromInt(0),
    };
    cp.cache.ttl_ns = 5 * std.time.ns_per_s;
    defer cp.cache.clear(std.testing.allocator);

    var tb = TestBackendCtx{};

    const r1 = cp.handleRequestWith("TAIL|deckpilot|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqual(@as(usize, 1), tb.calls);

    const r2 = cp.handleRequestWith("TAIL|deckpilot|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqual(@as(usize, 1), tb.calls);
    try std.testing.expectEqualStrings(r1, r2);

    const r3 = cp.handleRequestWith("INPUT|deckpilot|echo hi", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqual(@as(usize, 2), tb.calls);

    const r4 = cp.handleRequestWith("TAIL|deckpilot|20", std.testing.allocator, &tb, testBackend);
    defer std.testing.allocator.free(r4);
    try std.testing.expectEqual(@as(usize, 3), tb.calls);
}

test "handleRequestWith rejects input when queue is full" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(0),
        .max_pending_inputs = 1,
    };
    defer cp.clearPendingInputs();

    try std.testing.expect(cp.enqueueInput("zig-cp", "echo hi", false, 1));

    const resp = cp.handleRequestWith("INPUT|deckpilot|echo again", std.testing.allocator, null, testBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|BUSY|input_queue_full\n", resp);
}

test "handleRequestWith limits data lane but allows control lane" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(0),
        .max_inflight_data_requests = 1,
    };
    cp.inflight_data_requests.store(1, .release);

    var tb = TestBackendCtx{};

    const data_resp = cp.handleRequestWith("TAIL|deckpilot|20", std.testing.allocator, &tb, testBackend);
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
        .hwnd = @ptrFromInt(0),
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
        .hwnd = @ptrFromInt(0),
    };

    const ping = cp.handleRequestWith("PING", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(ping);
    try std.testing.expectEqualStrings("OK|PONG\n", ping);

    const state = cp.handleRequestWith("STATE|deckpilot|0", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(state);
    try std.testing.expectEqualStrings("OK|state\n", state);

    const tail = cp.handleRequestWith("TAIL|deckpilot|20", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(tail);
    try std.testing.expectEqualStrings("OK|tail\n", tail);

    const input = cp.handleRequestWith("INPUT|deckpilot|echo hi", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(input);
    try std.testing.expectEqualStrings("OK|input\n", input);

    const ack = cp.handleRequestWith("ACK_POLL|deckpilot", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(ack);
    try std.testing.expectEqualStrings("OK|ack\n", ack);
}

test "handleRequestWith returns deterministic ERR for unsupported command" {
    var cp = ControlPlane{
        .allocator = std.testing.allocator,
        .hwnd = @ptrFromInt(0),
    };

    const resp = cp.handleRequestWith("RAW_INPUT|deckpilot|hello", std.testing.allocator, null, contractBackend);
    defer std.testing.allocator.free(resp);
    try std.testing.expectEqualStrings("ERR|UNSUPPORTED|RAW_INPUT\n", resp);
}
