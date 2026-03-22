/// Named Pipe IPC server for the WinUI3 apprt.
///
/// Creates a named pipe `\\.\pipe\ghostty-{instance_id}` and listens for
/// JSON requests from other Ghostty processes (e.g. `ghostty --new-window`).
///
/// Protocol:
///   Request:  `{"action":"new-window"}` or `{"action":"new-tab"}` (newline-terminated)
///   Response: `{"success":true}` or `{"success":false,"error":"message"}`
///
/// The listener runs in a dedicated thread. Actions are dispatched to the UI
/// thread via PostMessageW + WM_APP_CONTROL_ACTION (same mechanism as the
/// control plane) to avoid UI-thread-safety violations.
const IpcServer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const windows = std.os.windows;
const os = @import("os.zig");
const ControlPlaneFfi = @import("control_plane_ffi.zig").ControlPlaneFfi;
const ControlPlaneNative = @import("control_plane.zig").ControlPlane;

const log = std.log.scoped(.ipc);

// --- Win32 Named Pipe constants and externs ---
const PIPE_ACCESS_DUPLEX: u32 = 0x00000003;
const PIPE_TYPE_BYTE: u32 = 0x00000000;
const PIPE_READMODE_BYTE: u32 = 0x00000000;
const PIPE_WAIT: u32 = 0x00000000;
const PIPE_UNLIMITED_INSTANCES: u32 = 255;
const ERROR_PIPE_CONNECTED: u32 = 535;

extern "kernel32" fn CreateNamedPipeW(
    lpName: [*:0]const u16,
    dwOpenMode: u32,
    dwPipeMode: u32,
    nMaxInstances: u32,
    nOutBufferSize: u32,
    nInBufferSize: u32,
    nDefaultTimeOut: u32,
    lpSecurityAttributes: ?*anyopaque,
) callconv(.winapi) windows.HANDLE;

extern "kernel32" fn ConnectNamedPipe(
    hNamedPipe: windows.HANDLE,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn DisconnectNamedPipe(
    hNamedPipe: windows.HANDLE,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn FlushFileBuffers(
    hFile: windows.HANDLE,
) callconv(.winapi) windows.BOOL;

// --- Server state ---

allocator: Allocator,
pipe_name: [:0]const u16,
listener_thread: ?std.Thread = null,
running: std.atomic.Value(bool),
hwnd: os.HWND,

/// Create and start the IPC server.
/// `hwnd` is the main window handle used for PostMessageW dispatch.
pub fn init(allocator: Allocator, hwnd: os.HWND) !*IpcServer {
    const instance_id = std.process.getEnvVarOwned(allocator, "GHOSTTY_INSTANCE_ID") catch null;
    defer if (instance_id) |id| allocator.free(id);

    const name_utf8 = if (instance_id) |id|
        try std.fmt.allocPrint(allocator, "\\\\.\\pipe\\ghostty-{s}", .{id})
    else
        try allocator.dupe(u8, "\\\\.\\pipe\\ghostty-default");
    defer allocator.free(name_utf8);

    const pipe_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name_utf8);

    const self = try allocator.create(IpcServer);
    self.* = .{
        .allocator = allocator,
        .pipe_name = pipe_name,
        .running = std.atomic.Value(bool).init(true),
        .hwnd = hwnd,
    };

    log.info("IPC server starting on: {s}", .{name_utf8});

    self.listener_thread = std.Thread.spawn(.{}, listenerLoop, .{self}) catch |err| {
        log.err("IPC listener thread spawn failed: {}", .{err});
        allocator.free(pipe_name);
        allocator.destroy(self);
        return err;
    };

    return self;
}

/// Stop the server and clean up.
pub fn deinit(self: *IpcServer) void {
    log.info("IPC server shutting down", .{});
    self.running.store(false, .release);

    // Create a dummy connection to unblock ConnectNamedPipe in the listener.
    unblockListener(self.pipe_name);

    if (self.listener_thread) |t| {
        t.join();
        self.listener_thread = null;
    }

    self.allocator.free(self.pipe_name);
    self.allocator.destroy(self);
}

fn unblockListener(pipe_name: [:0]const u16) void {
    // Retry a few times — the listener may be between CloseHandle (old pipe)
    // and CreateNamedPipeW (new pipe), so the pipe might not exist momentarily.
    var attempts: u32 = 0;
    while (attempts < 10) : (attempts += 1) {
        const h = windows.kernel32.CreateFileW(
            pipe_name.ptr,
            windows.GENERIC_READ,
            0,
            null,
            windows.OPEN_EXISTING,
            0,
            null,
        );
        if (h != windows.INVALID_HANDLE_VALUE) {
            windows.CloseHandle(h);
            return;
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}

/// Main listener loop — runs in a background thread.
fn listenerLoop(self: *IpcServer) void {
    while (self.running.load(.acquire)) {
        // Create a new pipe instance for each connection.
        const pipe = CreateNamedPipeW(
            self.pipe_name.ptr,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            PIPE_UNLIMITED_INSTANCES,
            4096, // output buffer
            4096, // input buffer
            0, // default timeout
            null,
        );

        if (pipe == windows.INVALID_HANDLE_VALUE) {
            log.err("CreateNamedPipeW failed: {}", .{windows.kernel32.GetLastError()});
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        }

        // Wait for a client to connect (blocks until connection or error).
        const connected = ConnectNamedPipe(pipe, null);
        if (connected == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != @as(windows.Win32Error, @enumFromInt(ERROR_PIPE_CONNECTED))) {
                windows.CloseHandle(pipe);
                if (!self.running.load(.acquire)) break;
                continue;
            }
        }

        if (!self.running.load(.acquire)) {
            windows.CloseHandle(pipe);
            break;
        }

        self.handleConnection(pipe);
        _ = DisconnectNamedPipe(pipe);
        windows.CloseHandle(pipe);
    }
    log.info("IPC listener loop exited", .{});
}

/// Handle a single client connection: read request, dispatch via PostMessageW, send response.
fn handleConnection(self: *IpcServer, pipe: windows.HANDLE) void {
    var buf: [4096]u8 = undefined;
    var total: usize = 0;

    // Read until newline or buffer full.
    while (total < buf.len) {
        var bytes_read: u32 = 0;
        const ok = windows.kernel32.ReadFile(
            pipe,
            @ptrCast(buf[total..].ptr),
            @intCast(buf.len - total),
            &bytes_read,
            null,
        );
        if (ok == 0 or bytes_read == 0) break;
        total += bytes_read;
        if (std.mem.indexOfScalar(u8, buf[0..total], '\n') != null) break;
    }

    if (total == 0) {
        writeResponse(pipe, false, "empty request");
        return;
    }

    const request = std.mem.trimRight(u8, buf[0..total], &.{ '\n', '\r', ' ' });
    log.info("IPC request: {s}", .{request});

    // Parse JSON.
    const parsed = std.json.parseFromSlice(IpcRequest, self.allocator, request, .{
        .ignore_unknown_fields = true,
    }) catch {
        writeResponse(pipe, false, "invalid JSON");
        return;
    };
    defer parsed.deinit();
    const req = parsed.value;

    // Dispatch action via PostMessageW to the UI thread.
    self.dispatchAction(req.action) catch |err| {
        writeResponse(pipe, false, @errorName(err));
        return;
    };

    writeResponse(pipe, true, null);
}

const IpcRequest = struct {
    action: []const u8,
};

/// Map IPC action string to a ControlPlane.Action and post to the UI thread.
/// This ensures all UI mutations happen on the XAML/Win32 message loop thread.
fn dispatchAction(self: *IpcServer, action_str: []const u8) !void {
    const action: ControlPlaneNative.Action = if (std.mem.eql(u8, action_str, "new-window"))
        .new_tab // single-window mode: new-window creates a new tab
    else if (std.mem.eql(u8, action_str, "new-tab"))
        .new_tab
    else if (std.mem.eql(u8, action_str, "close-tab"))
        .close_tab
    else if (std.mem.eql(u8, action_str, "focus"))
        .focus_window
    else {
        log.warn("IPC unknown action: {s}", .{action_str});
        return error.UnknownAction;
    };

    log.info("IPC dispatch: {s} -> PostMessageW WM_APP_CONTROL_ACTION({d})", .{ action_str, @intFromEnum(action) });
    _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_ACTION, @intFromEnum(action), 0);
}

fn writeResponse(pipe: windows.HANDLE, success: bool, err_msg: ?[]const u8) void {
    var buf: [512]u8 = undefined;
    const response = if (success)
        std.fmt.bufPrint(&buf, "{{\"success\":true}}\n", .{}) catch return
    else if (err_msg) |msg|
        std.fmt.bufPrint(&buf, "{{\"success\":false,\"error\":\"{s}\"}}\n", .{msg}) catch return
    else
        std.fmt.bufPrint(&buf, "{{\"success\":false}}\n", .{}) catch return;

    var written: u32 = 0;
    _ = windows.kernel32.WriteFile(
        pipe,
        @ptrCast(response.ptr),
        @intCast(response.len),
        &written,
        null,
    );
    _ = FlushFileBuffers(pipe);
}

// ---------------------------------------------------------------
// Client side: try to connect to an existing instance
// ---------------------------------------------------------------

/// Try to send an IPC action to a running Ghostty instance.
/// Returns true if the message was sent and acknowledged, false if no instance found.
pub fn sendIpc(allocator: Allocator, action: []const u8) !bool {
    const instance_id = std.process.getEnvVarOwned(allocator, "GHOSTTY_INSTANCE_ID") catch null;
    defer if (instance_id) |id| allocator.free(id);

    const name_utf8 = if (instance_id) |id|
        try std.fmt.allocPrint(allocator, "\\\\.\\pipe\\ghostty-{s}", .{id})
    else
        try allocator.dupe(u8, "\\\\.\\pipe\\ghostty-default");
    defer allocator.free(name_utf8);

    const pipe_name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, name_utf8);
    defer allocator.free(pipe_name);

    const pipe = windows.kernel32.CreateFileW(
        pipe_name.ptr,
        windows.GENERIC_READ | windows.GENERIC_WRITE,
        0,
        null,
        windows.OPEN_EXISTING,
        0,
        null,
    );
    if (pipe == windows.INVALID_HANDLE_VALUE) {
        // No running instance found.
        return false;
    }
    defer windows.CloseHandle(pipe);

    // Build and send request.
    var buf: [512]u8 = undefined;
    const request = std.fmt.bufPrint(&buf, "{{\"action\":\"{s}\"}}\n", .{action}) catch return error.IPCFailed;

    var written: u32 = 0;
    const ok = windows.kernel32.WriteFile(
        pipe,
        @ptrCast(request.ptr),
        @intCast(request.len),
        &written,
        null,
    );
    if (ok == 0) return error.IPCFailed;
    _ = FlushFileBuffers(pipe);

    // Read response.
    var resp_buf: [512]u8 = undefined;
    var bytes_read: u32 = 0;
    const rok = windows.kernel32.ReadFile(
        pipe,
        @ptrCast(&resp_buf),
        @intCast(resp_buf.len),
        &bytes_read,
        null,
    );
    if (rok == 0 or bytes_read == 0) return error.IPCFailed;

    const resp = std.mem.trimRight(u8, resp_buf[0..bytes_read], &.{ '\n', '\r', ' ' });

    // Parse response to check success.
    const parsed = std.json.parseFromSlice(IpcResponse, allocator, resp, .{
        .ignore_unknown_fields = true,
    }) catch return error.IPCFailed;
    defer parsed.deinit();

    if (!parsed.value.success) {
        log.err("IPC action '{s}' failed: {s}", .{ action, parsed.value.@"error" orelse "unknown" });
        return error.IPCFailed;
    }

    log.info("IPC action '{s}' succeeded", .{action});
    return true;
}

const IpcResponse = struct {
    success: bool,
    @"error": ?[]const u8 = null,
};
