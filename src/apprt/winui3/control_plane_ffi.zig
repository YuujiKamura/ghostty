const std = @import("std");
const os = @import("os.zig");

const windows = std.os.windows;
const kernel32 = windows.kernel32;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.winui3_control_plane_ffi);

/// DLL-backed control plane that bridges to the Rust control_plane_server.dll.
///
/// This is the "islands" variant of the control plane, intended for use with
/// the winui3 App runtime. It loads control_plane_server.dll at runtime,
/// wires up a C-ABI VTable of callbacks, and delegates terminal operations
/// (read buffer, send input, tab management, etc.) back to the App.
pub const ControlPlaneFfi = struct {
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

    /// Action codes posted via WM_APP_CONTROL_ACTION (wparam).
    pub const Action = enum(usize) {
        new_tab = 1,
        close_tab = 2,
        switch_tab = 3,
        focus_window = 4,
    };

    const PendingInput = struct {
        from: []u8,
        text: []u8,
        raw: bool = false,
    };

    // ── DLL function pointer types ──
    const CpServerCreateFn = *const fn (
        session_name: [*:0]const u8,
        pipe_prefix: [*:0]const u8,
        provider_vtable: *const TerminalProviderVTable,
    ) callconv(.c) ?*anyopaque;
    const CpServerStartFn = *const fn (server: *anyopaque) callconv(.c) i32;
    const CpServerStopFn = *const fn (server: *anyopaque) callconv(.c) void;
    const CpServerDestroyFn = *const fn (server: *anyopaque) callconv(.c) void;

    // ── VTable struct matching Rust repr(C) TerminalProviderVTable ──
    const TerminalProviderVTable = extern struct {
        read_buffer: *const fn (ctx: *anyopaque, buf: [*]u8, buf_len: usize) callconv(.c) usize,
        send_input: *const fn (ctx: *anyopaque, text: [*]const u8, len: usize, raw: bool) callconv(.c) void,
        tab_count: *const fn (ctx: *anyopaque) callconv(.c) usize,
        active_tab: *const fn (ctx: *anyopaque) callconv(.c) usize,
        switch_tab: *const fn (ctx: *anyopaque, index: usize) callconv(.c) void,
        new_tab: *const fn (ctx: *anyopaque) callconv(.c) void,
        close_tab: *const fn (ctx: *anyopaque, index: usize) callconv(.c) void,
        focus: *const fn (ctx: *anyopaque) callconv(.c) void,
        hwnd: *const fn (ctx: *anyopaque) callconv(.c) usize,
        tab_title: *const fn (ctx: *anyopaque, index: usize, buf: [*]u8, buf_len: usize) callconv(.c) usize,
        tab_working_dir: *const fn (ctx: *anyopaque, index: usize, buf: [*]u8, buf_len: usize) callconv(.c) usize,
        tab_has_selection: *const fn (ctx: *anyopaque, index: usize) callconv(.c) bool,
        ctx: *anyopaque,
    };

    allocator: Allocator,
    hwnd: os.HWND,
    pending_inputs_lock: std.Thread.Mutex = .{},
    pending_inputs: std.ArrayListUnmanaged(PendingInput) = .{},
    pending_ime_injects_lock: std.Thread.Mutex = .{},
    pending_ime_injects: std.ArrayListUnmanaged([]u8) = .{},
    callback_ctx: ?*anyopaque = null,
    capture_state_fn: ?CaptureStateFn = null,
    capture_tail_fn: ?CaptureTailFn = null,
    capture_tab_list_fn: ?CaptureTabListFn = null,

    // DLL runtime state
    dll_handle: ?windows.HMODULE = null,
    dll_server: ?*anyopaque = null,
    fn_stop: ?CpServerStopFn = null,
    fn_destroy: ?CpServerDestroyFn = null,

    // Keep vtable alive for the lifetime of the server (Rust holds a pointer to it).
    vtable: ?*TerminalProviderVTable = null,

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
    ) !*ControlPlaneFfi {
        const self = try allocator.create(ControlPlaneFfi);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .hwnd = hwnd,
            .callback_ctx = callback_ctx,
            .capture_state_fn = capture_state_fn,
            .capture_tail_fn = capture_tail_fn,
            .capture_tab_list_fn = capture_tab_list_fn,
        };

        // Try to load the DLL
        self.initDll() catch |err| {
            log.warn("control plane DLL init failed: {} — control plane disabled", .{err});
            // Not fatal: control plane is simply disabled.
            return self;
        };

        return self;
    }

    fn initDll(self: *ControlPlaneFfi) !void {
        // LoadLibraryW("control_plane_server.dll")
        const dll_name = comptime std.unicode.utf8ToUtf16LeStringLiteral("control_plane_server.dll");
        const module = kernel32.LoadLibraryW(dll_name) orelse {
            const err_code = windows.GetLastError();
            log.warn("LoadLibrary(control_plane_server.dll) failed, error={} — control plane disabled", .{err_code});
            return error.DllNotFound;
        };
        errdefer _ = kernel32.FreeLibrary(module);

        // GetProcAddress × 4
        const fn_create: CpServerCreateFn = @ptrCast(kernel32.GetProcAddress(module, "cp_server_create_with_prefix") orelse {
            log.warn("GetProcAddress(cp_server_create_with_prefix) failed", .{});
            return error.ProcNotFound;
        });
        const fn_start: CpServerStartFn = @ptrCast(kernel32.GetProcAddress(module, "cp_server_start") orelse {
            log.warn("GetProcAddress(cp_server_start) failed", .{});
            return error.ProcNotFound;
        });
        const fn_stop: CpServerStopFn = @ptrCast(kernel32.GetProcAddress(module, "cp_server_stop") orelse {
            log.warn("GetProcAddress(cp_server_stop) failed", .{});
            return error.ProcNotFound;
        });
        const fn_destroy: CpServerDestroyFn = @ptrCast(kernel32.GetProcAddress(module, "cp_server_destroy") orelse {
            log.warn("GetProcAddress(cp_server_destroy) failed", .{});
            return error.ProcNotFound;
        });

        // Build session name
        const pid = windows.GetCurrentProcessId();
        const session_name = loadSessionName(self.allocator, pid) catch |err| {
            log.warn("failed to load session name: {}", .{err});
            return error.SessionNameFailed;
        };
        defer self.allocator.free(session_name);

        // Null-terminate session name for C ABI
        const session_name_z = try self.allocator.dupeZ(u8, session_name);
        defer self.allocator.free(session_name_z);

        // Pipe prefix for ghostty-islands
        const pipe_prefix_z: [*:0]const u8 = "ghostty-winui3";

        // Heap-allocate the VTable so it outlives this function.
        // The Rust DLL holds a raw pointer to it for the lifetime of the server.
        const vtable = try self.allocator.create(TerminalProviderVTable);
        errdefer self.allocator.destroy(vtable);

        vtable.* = .{
            .read_buffer = &vtReadBuffer,
            .send_input = &vtSendInput,
            .tab_count = &vtTabCount,
            .active_tab = &vtActiveTab,
            .switch_tab = &vtSwitchTab,
            .new_tab = &vtNewTab,
            .close_tab = &vtCloseTab,
            .focus = &vtFocus,
            .hwnd = &vtHwnd,
            .tab_title = &vtTabTitle,
            .tab_working_dir = &vtTabWorkingDir,
            .tab_has_selection = &vtTabHasSelection,
            .ctx = @ptrCast(self),
        };

        // cp_server_create
        const server = fn_create(session_name_z, pipe_prefix_z, vtable) orelse {
            log.warn("cp_server_create returned null — control plane disabled", .{});
            return error.ServerCreateFailed;
        };

        // cp_server_start
        const start_result = fn_start(server);
        if (start_result != 0) {
            log.warn("cp_server_start failed with code={}", .{start_result});
            fn_destroy(server);
            return error.ServerStartFailed;
        }

        self.dll_handle = module;
        self.dll_server = server;
        self.fn_stop = fn_stop;
        self.fn_destroy = fn_destroy;
        self.vtable = vtable;

        log.info("control plane DLL started successfully (pipe_prefix=ghostty-winui3)", .{});
    }

    pub fn destroy(self: *ControlPlaneFfi) void {
        // Stop and destroy the DLL server
        if (self.dll_server) |server| {
            if (self.fn_stop) |stop_fn| stop_fn(server);
            if (self.fn_destroy) |destroy_fn| destroy_fn(server);
            self.dll_server = null;
        }
        if (self.vtable) |vt| {
            self.allocator.destroy(vt);
            self.vtable = null;
        }
        if (self.dll_handle) |module| {
            _ = kernel32.FreeLibrary(module);
            self.dll_handle = null;
        }

        self.clearPendingInputs();
        log.info("control plane stopped", .{});
        self.allocator.destroy(self);
    }

    fn clearPendingInputs(self: *ControlPlaneFfi) void {
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

    fn enqueueInput(self: *ControlPlaneFfi, from: []const u8, text: []const u8, raw: bool) void {
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

    pub fn drainPendingInputs(self: *ControlPlaneFfi, surface: anytype) void {
        self.pending_inputs_lock.lock();
        var pending = self.pending_inputs;
        self.pending_inputs = .{};
        self.pending_inputs_lock.unlock();
        defer pending.deinit(self.allocator);

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

    pub fn drainPendingImeInjects(self: *ControlPlaneFfi) ?[]u8 {
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

    // ── VTable callback implementations (extern "C") ──
    // These are called from the DLL's pipe server thread.
    // ctx points to *ControlPlaneFfi.

    fn vtReadBuffer(ctx: *anyopaque, buf: [*]u8, buf_len: usize) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_tail_fn orelse return 0;
        const cb_ctx = self.callback_ctx orelse return 0;
        const viewport = (capture(cb_ctx, self.allocator, null) catch return 0) orelse return 0;
        defer self.allocator.free(viewport);
        const copy_len = @min(viewport.len, buf_len);
        @memcpy(buf[0..copy_len], viewport[0..copy_len]);
        return copy_len;
    }

    fn vtSendInput(ctx: *anyopaque, text: [*]const u8, len: usize, raw: bool) callconv(.c) void {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        self.enqueueInput("dll", text[0..len], raw);
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_INPUT, 0, 0);
    }

    fn vtTabCount(ctx: *anyopaque) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_state_fn orelse return 0;
        const cb_ctx = self.callback_ctx orelse return 0;
        var snapshot = (capture(cb_ctx, self.allocator, null) catch return 0) orelse return 0;
        defer snapshot.deinit(self.allocator);
        return snapshot.tab_count;
    }

    fn vtActiveTab(ctx: *anyopaque) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_state_fn orelse return 0;
        const cb_ctx = self.callback_ctx orelse return 0;
        var snapshot = (capture(cb_ctx, self.allocator, null) catch return 0) orelse return 0;
        defer snapshot.deinit(self.allocator);
        return snapshot.active_tab;
    }

    fn vtSwitchTab(ctx: *anyopaque, index: usize) callconv(.c) void {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.switch_tab), @bitCast(index));
    }

    fn vtNewTab(ctx: *anyopaque) callconv(.c) void {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.new_tab), 0);
    }

    fn vtCloseTab(ctx: *anyopaque, index: usize) callconv(.c) void {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.close_tab), @bitCast(index));
    }

    fn vtFocus(ctx: *anyopaque) callconv(.c) void {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(Action.focus_window), 0);
    }

    fn vtHwnd(ctx: *anyopaque) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        return @intFromPtr(self.hwnd);
    }

    fn vtTabTitle(ctx: *anyopaque, index: usize, buf: [*]u8, buf_len: usize) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_state_fn orelse return 0;
        const cb_ctx = self.callback_ctx orelse return 0;
        var snapshot = (capture(cb_ctx, self.allocator, index) catch return 0) orelse return 0;
        defer snapshot.deinit(self.allocator);
        // StateSnapshot doesn't have title; return window title via Win32
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
        const copy_len = @min(title.len, buf_len);
        @memcpy(buf[0..copy_len], title[0..copy_len]);
        return copy_len;
    }

    fn vtTabWorkingDir(ctx: *anyopaque, index: usize, buf: [*]u8, buf_len: usize) callconv(.c) usize {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_state_fn orelse return 0;
        const cb_ctx = self.callback_ctx orelse return 0;
        var snapshot = (capture(cb_ctx, self.allocator, index) catch return 0) orelse return 0;
        defer snapshot.deinit(self.allocator);
        const pwd = snapshot.pwd orelse return 0;
        const copy_len = @min(pwd.len, buf_len);
        @memcpy(buf[0..copy_len], pwd[0..copy_len]);
        return copy_len;
    }

    fn vtTabHasSelection(ctx: *anyopaque, index: usize) callconv(.c) bool {
        const self: *ControlPlaneFfi = @ptrCast(@alignCast(ctx));
        const capture = self.capture_state_fn orelse return false;
        const cb_ctx = self.callback_ctx orelse return false;
        var snapshot = (capture(cb_ctx, self.allocator, index) catch return false) orelse return false;
        defer snapshot.deinit(self.allocator);
        return snapshot.has_selection;
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
