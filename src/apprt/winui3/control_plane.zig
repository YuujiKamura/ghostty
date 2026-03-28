const std = @import("std");
const os = @import("os.zig");

const zcp = @import("zig-control-plane");
const ControlPlaneLib = zcp.ControlPlane;
const Provider = zcp.Provider;
const PipeServer = zcp.pipe_server.PipeServer;

const windows = std.os.windows;
const Allocator = std.mem.Allocator;

extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;

const log = std.log.scoped(.winui3_control_plane);

const PendingInput = struct {
    from: []u8,
    text: []u8,
    raw: bool = false,
};

/// Query kind for CpQuery — dispatched via WM_APP_CP_QUERY (SendMessageW).
pub const QueryKind = enum {
    read_buffer,
    tab_count,
    active_tab,
    tab_title,
    tab_working_dir,
    tab_has_selection,
    capture_tab_list,
};

/// Synchronous query struct passed via SendMessageW(WM_APP_CP_QUERY, 0, @intFromPtr(&query)).
/// Pipe thread creates on stack → SendMessageW blocks → UI thread fills result → returns.
pub const CpQuery = struct {
    kind: QueryKind,
    tab_index: ?usize = null,
    /// For read_buffer/tab_title/tab_working_dir: caller-owned buffer to write into.
    out_buf: ?[*]u8 = null,
    out_buf_len: usize = 0,
    /// Result: bytes written to out_buf.
    result_len: usize = 0,
    /// Result: scalar value (tabCount, activeTab).
    result_usize: usize = 0,
    /// Result: boolean (tabHasSelection).
    result_bool: bool = false,
    /// Result: heap-allocated response (capture_tab_list). Caller must free.
    result_owned: ?[]u8 = null,
    /// Allocator for heap results.
    allocator: Allocator,
};

/// Zig-native control plane that replaces the Rust DLL.
///
/// Integrates the zig-control-plane library with the WinUI3 App runtime.
/// Thread-safe: ALL callbacks are routed to the UI thread.
/// - Mutations (newTab, closeTab, etc.) via PostMessageW (async).
/// - Reads (readBuffer, tabCount, etc.) via SendMessageW (sync).
pub const ControlPlane = struct {
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
        has_selection: bool = false,
        at_prompt: bool = false,
        tab_count: usize = 0,
        active_tab: usize = 0,

        pub fn deinit(self: *StateSnapshot, allocator: Allocator) void {
            if (self.pwd) |pwd| allocator.free(pwd);
            self.* = .{};
        }
    };

    pub const CaptureStateFn = *const fn (ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) anyerror!?StateSnapshot;
    pub const CaptureTailFn = *const fn (ctx: *anyopaque, allocator: Allocator, tab_idx: ?usize) anyerror!?[]u8;
    pub const CaptureTabListFn = *const fn (ctx: *anyopaque, allocator: Allocator) anyerror!?[]u8;

    allocator: Allocator,
    hwnd: os.HWND,
    /// Session name (e.g. "ghostty-30052") — stored for window title display.
    session_name: ?[:0]const u8 = null,
    pending_inputs_lock: std.Thread.Mutex = .{},
    pending_inputs: std.ArrayListUnmanaged(PendingInput) = .{},
    pending_ime_injects_lock: std.Thread.Mutex = .{},
    pending_ime_injects: std.ArrayListUnmanaged([]u8) = .{},
    callback_ctx: ?*anyopaque = null,

    // zig-control-plane library state
    cp: ?ControlPlaneLib = null,
    pipe_server: ?PipeServer = null,
    provider: ?Provider = null,

    capture_state_fn: ?CaptureStateFn = null,
    capture_tail_fn: ?CaptureTailFn = null,
    capture_tab_list_fn: ?CaptureTabListFn = null,

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
            .capture_tab_list_fn = capture_tab_list_fn,
        };

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
            .readBuffer = &provReadBuffer,
            .sendInput = &provSendInput,
            .tabCount = &provTabCount,
            .activeTab = &provActiveTab,
            .tabTitle = &provTabTitle,
            .tabWorkingDir = &provTabWorkingDir,
            .tabHasSelection = &provTabHasSelection,
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
        if (self.cp) |*cp| {
            return cp.handleRequest(request) catch |err| {
                log.warn("handleRequest error: {}", .{err});
                return allocator.dupe(u8, "ERR|internal_error\n") catch return "ERR|internal_error\n";
            };
        }
        return allocator.dupe(u8, "ERR|not_initialized\n") catch return "ERR|not_initialized\n";
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

    fn enqueueInput(self: *ControlPlane, from: []const u8, text: []const u8, raw: bool) void {
        const owned_from = self.allocator.dupe(u8, from) catch return;
        const owned_text = self.allocator.dupe(u8, text) catch {
            self.allocator.free(owned_from);
            return;
        };

        self.pending_inputs_lock.lock();
        defer self.pending_inputs_lock.unlock();
        self.pending_inputs.append(self.allocator, .{
            .from = owned_from,
            .text = owned_text,
            .raw = raw,
        }) catch {
            self.allocator.free(owned_from);
            self.allocator.free(owned_text);
        };
    }

    pub fn drainPendingInputs(self: *ControlPlane, surface: anytype) void {
        self.pending_inputs_lock.lock();
        var pending = self.pending_inputs;
        self.pending_inputs = .{};
        self.pending_inputs_lock.unlock();
        defer pending.deinit(self.allocator);

        log.info("drainPendingInputs: {} items", .{pending.items.len});

        const termio = @import("../../termio.zig");

        for (pending.items) |entry| {
            defer self.allocator.free(entry.from);
            defer self.allocator.free(entry.text);

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

    fn provReadBuffer(ctx: *anyopaque, tab_index: ?usize, buf: []u8) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        if (buf.len == 0) return 0;
        var query = CpQuery{
            .kind = .read_buffer,
            .tab_index = tab_index,
            .out_buf = buf.ptr,
            .out_buf_len = buf.len,
            .allocator = self.allocator,
        };
        _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @bitCast(@intFromPtr(&query)));
        return query.result_len;
    }

    fn provSendInput(ctx: *anyopaque, text: []const u8, raw: bool, tab_index: ?usize) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = tab_index; // TODO: route to specific tab
        log.info("provSendInput hwnd=0x{x} len={} raw={}", .{ @intFromPtr(self.hwnd), text.len, raw });

        // Special prefix "\x1b[TSF:" routes text through the TSF commit path
        const tsf_prefix = "\x1b[TSF:";
        if (text.len > tsf_prefix.len and std.mem.startsWith(u8, text, tsf_prefix)) {
            const payload = text[tsf_prefix.len..];
            self.enqueueImeInject(payload);
            const tsf_result = os.PostMessageW(self.hwnd, os.WM_APP_TSF_INJECT, 0, 0);
            log.info("provSendInput PostMessageW(WM_APP_TSF_INJECT) result={}", .{tsf_result});
            if (tsf_result == 0) {
                log.warn("provSendInput PostMessageW(WM_APP_TSF_INJECT) failed err={}", .{os.GetLastError()});
            }
            return;
        }

        self.enqueueInput("zig-cp", text, raw);
        const result = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_INPUT, 0, 0);
        log.info("provSendInput PostMessageW(WM_APP_CONTROL_INPUT) result={}", .{result});
        if (result == 0) {
            log.warn("provSendInput PostMessageW(WM_APP_CONTROL_INPUT) failed err={}", .{os.GetLastError()});
        }
    }

    fn provTabCount(ctx: *anyopaque) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        var query = CpQuery{
            .kind = .tab_count,
            .allocator = self.allocator,
        };
        _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @bitCast(@intFromPtr(&query)));
        return query.result_usize;
    }

    fn provActiveTab(ctx: *anyopaque) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        var query = CpQuery{
            .kind = .active_tab,
            .allocator = self.allocator,
        };
        _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @bitCast(@intFromPtr(&query)));
        return query.result_usize;
    }

    fn provTabTitle(ctx: *anyopaque, _: usize, buf: []u8) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        // Return window title via Win32
        const len = os.GetWindowTextLengthW(self.hwnd);
        if (len <= 0) return 0;
        const needed: usize = @intCast(len + 1);
        const utf16 = self.allocator.alloc(u16, needed) catch return 0;
        defer self.allocator.free(utf16);
        @memset(utf16, 0);
        const copied = os.GetWindowTextW(self.hwnd, utf16.ptr, @intCast(needed));
        if (copied <= 0) return 0;
        const title = std.unicode.utf16LeToUtf8Alloc(self.allocator, utf16[0..@intCast(copied)]) catch return 0;
        defer self.allocator.free(title);
        const copy_len = @min(title.len, buf.len);
        @memcpy(buf[0..copy_len], title[0..copy_len]);
        return copy_len;
    }

    fn provTabWorkingDir(ctx: *anyopaque, index: usize, buf: []u8) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        if (buf.len == 0) return 0;
        var query = CpQuery{
            .kind = .tab_working_dir,
            .tab_index = index,
            .out_buf = buf.ptr,
            .out_buf_len = buf.len,
            .allocator = self.allocator,
        };
        _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @bitCast(@intFromPtr(&query)));
        return query.result_len;
    }

    fn provTabHasSelection(ctx: *anyopaque, index: usize) bool {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        var query = CpQuery{
            .kind = .tab_has_selection,
            .tab_index = index,
            .allocator = self.allocator,
        };
        _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @bitCast(@intFromPtr(&query)));
        return query.result_bool;
    }

    fn provNewTab(ctx: *anyopaque) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.new_tab), 0);
    }

    fn provCloseTab(ctx: *anyopaque, index: usize) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.close_tab), @bitCast(index));
    }

    fn provSwitchTab(ctx: *anyopaque, index: usize) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.switch_tab), @bitCast(index));
    }

    fn provFocus(ctx: *anyopaque) void {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.focus_window), 0);
    }

    fn provHwnd(ctx: *anyopaque) usize {
        const self: *ControlPlane = @ptrCast(@alignCast(ctx));
        return @intFromPtr(self.hwnd);
    }

    // ── Push notification API ──

    /// Notify all subscribers of a status change (idle/running).
    /// Called from the UI thread (e.g., drainMailbox). Thread-safe: pushEvent
    /// acquires its own lock on the pipe_server subscriber list.
    pub fn notifyStatus(self: *ControlPlane, status: []const u8) void {
        const ps = &(self.pipe_server orelse return);
        const ts = std.time.milliTimestamp();
        const line = std.fmt.allocPrint(self.allocator, "EVENT|STATUS|{s}|{d}\n", .{ status, ts }) catch return;
        defer self.allocator.free(line);
        ps.pushEvent(.status, line);
    }
};

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

test "CpQuery default values" {
    const alloc = std.testing.allocator;
    const q = CpQuery{
        .kind = .tab_count,
        .allocator = alloc,
    };
    try std.testing.expectEqual(@as(usize, 0), q.result_usize);
    try std.testing.expectEqual(false, q.result_bool);
    try std.testing.expectEqual(@as(usize, 0), q.result_len);
    try std.testing.expect(q.result_owned == null);
    try std.testing.expect(q.out_buf == null);
    try std.testing.expect(q.tab_index == null);
}

test "CpQuery with buffer" {
    const alloc = std.testing.allocator;
    var buf: [64]u8 = undefined;
    var q = CpQuery{
        .kind = .read_buffer,
        .tab_index = 0,
        .out_buf = &buf,
        .out_buf_len = buf.len,
        .allocator = alloc,
    };
    // Simulate UI thread writing result
    const data = "hello world";
    @memcpy(q.out_buf.?[0..data.len], data);
    q.result_len = data.len;

    try std.testing.expectEqual(data.len, q.result_len);
    try std.testing.expectEqualStrings(data, buf[0..q.result_len]);
}

test "QueryKind exhaustive" {
    // Ensure all variants are handled (compile-time exhaustiveness)
    const kinds = [_]QueryKind{
        .read_buffer,
        .tab_count,
        .active_tab,
        .tab_title,
        .tab_working_dir,
        .tab_has_selection,
        .capture_tab_list,
    };
    try std.testing.expectEqual(@as(usize, 7), kinds.len);

    for (kinds) |k| {
        switch (k) {
            .read_buffer, .tab_count, .active_tab, .tab_title, .tab_working_dir, .tab_has_selection, .capture_tab_list => {},
        }
    }
}
