const std = @import("std");
const os = @import("os.zig");

const windows = std.os.windows;
const kernel32 = windows.kernel32;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.winui3_control_plane);

extern "kernel32" fn ConnectNamedPipe(
    hNamedPipe: windows.HANDLE,
    lpOverlapped: ?*windows.OVERLAPPED,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn DisconnectNamedPipe(
    hNamedPipe: windows.HANDLE,
) callconv(.winapi) windows.BOOL;

pub const ControlPlane = struct {
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

    const PendingInput = struct {
        from: []u8,
        text: []u8,
    };

    allocator: Allocator,
    hwnd: os.HWND,
    pid: u32,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    pending_inputs_lock: std.Thread.Mutex = .{},
    pending_inputs: std.ArrayListUnmanaged(PendingInput) = .{},
    session_name: []u8,
    safe_session_name: []u8,
    pipe_name: []u8,
    pipe_path: []u8,
    root_dir: []u8,
    sessions_dir: []u8,
    logs_dir: []u8,
    session_file_path: []u8,
    log_file_path: []u8,
    callback_ctx: ?*anyopaque = null,
    capture_state_fn: ?CaptureStateFn = null,
    capture_tail_fn: ?CaptureTailFn = null,

    pub fn isEnabled(allocator: Allocator) bool {
        return checkEnvFlag(allocator, "GHOSTTY_CONTROL_PLANE") or
            checkEnvFlag(allocator, "GHOSTTY_WIN32_CONTROL_PLANE");
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
    ) !*ControlPlane {
        const self = try allocator.create(ControlPlane);
        errdefer allocator.destroy(self);

        const pid = windows.GetCurrentProcessId();
        const session_name = try loadSessionName(allocator, pid);
        errdefer allocator.free(session_name);

        const safe_session_name = try sanitizeSessionName(allocator, session_name);
        errdefer allocator.free(safe_session_name);

        const local_appdata = try std.process.getEnvVarOwned(allocator, "LOCALAPPDATA");
        defer allocator.free(local_appdata);

        const root_dir = try std.fs.path.join(allocator, &.{ local_appdata, "ghostty", "control-plane", "winui3" });
        errdefer allocator.free(root_dir);
        const sessions_dir = try std.fs.path.join(allocator, &.{ root_dir, "sessions" });
        errdefer allocator.free(sessions_dir);
        const logs_dir = try std.fs.path.join(allocator, &.{ root_dir, "logs" });
        errdefer allocator.free(logs_dir);

        const pipe_name = try std.fmt.allocPrint(allocator, "ghostty-winui3-{s}-{d}", .{ safe_session_name, pid });
        errdefer allocator.free(pipe_name);
        const pipe_path = try std.fmt.allocPrint(allocator, "\\\\.\\pipe\\{s}", .{pipe_name});
        errdefer allocator.free(pipe_path);

        const session_file_name = try std.fmt.allocPrint(allocator, "{s}-{d}.session", .{ safe_session_name, pid });
        defer allocator.free(session_file_name);
        const session_file_path = try std.fs.path.join(allocator, &.{ sessions_dir, session_file_name });
        errdefer allocator.free(session_file_path);

        const log_file_name = try std.fmt.allocPrint(allocator, "{s}-{d}.log", .{ safe_session_name, pid });
        defer allocator.free(log_file_name);
        const log_file_path = try std.fs.path.join(allocator, &.{ logs_dir, log_file_name });
        errdefer allocator.free(log_file_path);

        self.* = .{
            .allocator = allocator,
            .hwnd = hwnd,
            .pid = pid,
            .session_name = session_name,
            .safe_session_name = safe_session_name,
            .pipe_name = pipe_name,
            .pipe_path = pipe_path,
            .root_dir = root_dir,
            .sessions_dir = sessions_dir,
            .logs_dir = logs_dir,
            .session_file_path = session_file_path,
            .log_file_path = log_file_path,
            .callback_ctx = callback_ctx,
            .capture_state_fn = capture_state_fn,
            .capture_tail_fn = capture_tail_fn,
        };
        errdefer self.freeOwned();

        try self.ensureDirectories();
        try self.writeSessionFile();
        self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
        log.info("control plane started session={s} pipe={s}", .{ self.session_name, self.pipe_name });
        return self;
    }

    pub fn destroy(self: *ControlPlane) void {
        self.stop.store(true, .seq_cst);
        self.wakeServer();
        if (self.thread) |thread| {
            thread.join();
        }
        self.clearPendingInputs();
        std.fs.deleteFileAbsolute(self.session_file_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => log.warn("failed to remove session file: {}", .{err}),
        };
        log.info("control plane stopped session={s}", .{self.session_name});
        self.freeOwned();
        self.allocator.destroy(self);
    }

    fn freeOwned(self: *ControlPlane) void {
        self.allocator.free(self.session_name);
        self.allocator.free(self.safe_session_name);
        self.allocator.free(self.pipe_name);
        self.allocator.free(self.pipe_path);
        self.allocator.free(self.root_dir);
        self.allocator.free(self.sessions_dir);
        self.allocator.free(self.logs_dir);
        self.allocator.free(self.session_file_path);
        self.allocator.free(self.log_file_path);
    }

    fn ensureDirectories(self: *ControlPlane) !void {
        makeDirIfMissing(self.root_dir) catch |err| return err;
        makeDirIfMissing(self.sessions_dir) catch |err| return err;
        makeDirIfMissing(self.logs_dir) catch |err| return err;
    }

    fn writeSessionFile(self: *ControlPlane) !void {
        const hwnd_int: usize = @intFromPtr(self.hwnd);
        const body = try std.fmt.allocPrint(
            self.allocator,
            "session_name={s}\nsafe_session_name={s}\npid={d}\nhwnd=0x{x}\nruntime=winui3\npipe_name={s}\npipe_path={s}\nlog_file={s}\n",
            .{ self.session_name, self.safe_session_name, self.pid, hwnd_int, self.pipe_name, self.pipe_path, self.log_file_path },
        );
        defer self.allocator.free(body);

        var file = try std.fs.createFileAbsolute(self.session_file_path, .{ .truncate = true, .read = false });
        defer file.close();
        try file.writeAll(body);
    }

    fn appendLog(self: *ControlPlane, line: []const u8) void {
        var file = std.fs.openFileAbsolute(self.log_file_path, .{ .mode = .read_write }) catch blk: {
            break :blk std.fs.createFileAbsolute(self.log_file_path, .{ .truncate = false, .read = true }) catch |err| {
                log.warn("failed to open log file: {}", .{err});
                return;
            };
        };
        defer file.close();
        file.seekFromEnd(0) catch |err| {
            log.warn("failed to seek log file: {}", .{err});
            return;
        };
        file.writeAll(line) catch |err| {
            log.warn("failed to write log file: {}", .{err});
        };
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
    }

    fn wakeServer(self: *ControlPlane) void {
        const pipe_w = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, self.pipe_path) catch return;
        defer self.allocator.free(pipe_w);

        const handle = kernel32.CreateFileW(
            pipe_w.ptr,
            windows.GENERIC_READ | windows.GENERIC_WRITE,
            0,
            null,
            windows.OPEN_EXISTING,
            0,
            null,
        );
        if (handle != windows.INVALID_HANDLE_VALUE) {
            windows.CloseHandle(handle);
        }
    }

    fn createServerPipe(self: *ControlPlane) !windows.HANDLE {
        const pipe_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, self.pipe_path);
        defer self.allocator.free(pipe_w);

        const handle = kernel32.CreateNamedPipeW(
            pipe_w.ptr,
            windows.PIPE_ACCESS_DUPLEX,
            windows.PIPE_TYPE_MESSAGE | windows.PIPE_READMODE_MESSAGE | windows.PIPE_WAIT,
            1,
            4096,
            4096,
            0,
            null,
        );
        if (handle == windows.INVALID_HANDLE_VALUE) {
            return error.CreateNamedPipeFailed;
        }
        return handle;
    }

    fn threadMain(self: *ControlPlane) void {
        while (!self.stop.load(.seq_cst)) {
            const pipe = self.createServerPipe() catch |err| {
                if (!self.stop.load(.seq_cst)) {
                    log.warn("failed to create named pipe: {}", .{err});
                    std.Thread.sleep(200 * std.time.ns_per_ms);
                }
                continue;
            };

            const connected = ConnectNamedPipe(pipe, null);
            if (connected == 0) {
                const last = windows.GetLastError();
                if (last != .PIPE_CONNECTED) {
                    if (!self.stop.load(.seq_cst)) {
                        log.warn("ConnectNamedPipe failed: {}", .{last});
                    }
                    windows.CloseHandle(pipe);
                    if (self.stop.load(.seq_cst)) break;
                    continue;
                }
            }

            self.handleClient(pipe);
            _ = DisconnectNamedPipe(pipe);
            windows.CloseHandle(pipe);
        }
    }

    fn handleClient(self: *ControlPlane, pipe: windows.HANDLE) void {
        var buffer: [4096]u8 = undefined;
        const size = windows.ReadFile(pipe, buffer[0..], null) catch |err| {
            if (err != error.BrokenPipe and !self.stop.load(.seq_cst)) {
                log.warn("pipe read failed: {}", .{err});
            }
            return;
        };
        if (size == 0) return;

        const request = std.mem.trimRight(u8, buffer[0..size], "\r\n");
        const response = self.buildResponse(request) catch |err| {
            log.warn("failed to build response: {}", .{err});
            return;
        };
        defer self.allocator.free(response);

        _ = windows.WriteFile(pipe, response, null) catch |err| {
            if (err != error.BrokenPipe and !self.stop.load(.seq_cst)) {
                log.warn("pipe write failed: {}", .{err});
            }
        };
        _ = kernel32.FlushFileBuffers(pipe);
    }

    fn buildResponse(self: *ControlPlane, request: []const u8) ![]u8 {
        if (std.mem.eql(u8, request, "PING")) {
            return std.fmt.allocPrint(self.allocator, "PONG|{s}|{d}|0x{x}\n", .{ self.session_name, self.pid, @intFromPtr(self.hwnd) });
        }

        if (std.mem.eql(u8, request, "STATE") or std.mem.startsWith(u8, request, "STATE|")) {
            const tab_idx: ?usize = if (std.mem.startsWith(u8, request, "STATE|"))
                std.fmt.parseUnsigned(usize, request[6..], 10) catch null
            else
                null;

            const title = try self.getWindowTitle();
            defer self.allocator.free(title);
            var snapshot: ?StateSnapshot = null;
            if (self.capture_state_fn) |capture| {
                if (self.callback_ctx) |ctx| {
                    snapshot = capture(ctx, self.allocator, tab_idx) catch |err| blk: {
                        log.warn("failed to capture state snapshot: {}", .{err});
                        break :blk null;
                    };
                }
            }
            defer if (snapshot) |*s| s.deinit(self.allocator);

            const pwd = if (snapshot) |s| s.pwd orelse "" else "";
            var prompt: u8 = if (snapshot) |s| if (s.at_prompt) 1 else 0 else 0;
            const selection: u8 = if (snapshot) |s| if (s.has_selection) 1 else 0 else 0;
            const tab_count: usize = if (snapshot) |s| s.tab_count else 0;
            const active_tab: usize = if (snapshot) |s| s.active_tab else 0;

            // Win32 cmd/pwsh sessions may not have shell integration enabled.
            // In that case, fall back to a viewport-based prompt heuristic so the
            // control plane can still distinguish an idle prompt from raw output.
            if (prompt == 0 and self.capture_tail_fn != null and self.callback_ctx != null) {
                if (try self.inferPromptFromViewport(pwd, title)) {
                    prompt = 1;
                }
            }

            return std.fmt.allocPrint(
                self.allocator,
                "STATE|{s}|{d}|0x{x}|{s}|prompt={d}|selection={d}|pwd={s}|tab_count={d}|active_tab={d}\n",
                .{ self.session_name, self.pid, @intFromPtr(self.hwnd), title, prompt, selection, pwd, tab_count, active_tab },
            );
        }

        if (std.mem.startsWith(u8, request, "TAIL")) {
            const lines = parseTailCount(request);
            return self.buildTailResponse(lines);
        }

        if (std.mem.startsWith(u8, request, "MSG|")) {
            const payload = request[4..];
            const sep = std.mem.indexOfScalar(u8, payload, '|');
            const from = if (sep) |idx| payload[0..idx] else "unknown";
            const text = if (sep) |idx| payload[idx + 1 ..] else payload;
            const ts = std.time.milliTimestamp();
            const line = try std.fmt.allocPrint(self.allocator, "{d}|MSG|{s}|{s}\n", .{ ts, from, text });
            defer self.allocator.free(line);
            self.appendLog(line);
            return std.fmt.allocPrint(self.allocator, "ACK|{s}|{d}\n", .{ self.session_name, self.pid });
        }

        if (std.mem.startsWith(u8, request, "INPUT|")) {
            const payload = request[6..];
            const sep = std.mem.indexOfScalar(u8, payload, '|');
            const from = if (sep) |idx| payload[0..idx] else "unknown";
            const encoded = if (sep) |idx| payload[idx + 1 ..] else "";
            const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
                return std.fmt.allocPrint(self.allocator, "ERR|{s}|invalid-base64\n", .{self.session_name});
            };
            const decoded = try self.allocator.alloc(u8, decoded_len);
            defer self.allocator.free(decoded);
            _ = std.base64.standard.Decoder.decode(decoded, encoded) catch {
                return std.fmt.allocPrint(self.allocator, "ERR|{s}|invalid-base64\n", .{self.session_name});
            };

            try self.enqueueInput(from, decoded);
            const ts = std.time.milliTimestamp();
            const line = try std.fmt.allocPrint(self.allocator, "{d}|INPUT_ENQUEUED|{s}|{d}\n", .{ ts, from, decoded.len });
            defer self.allocator.free(line);
            self.appendLog(line);
            _ = os.PostMessageW(self.hwnd, os.WM_APP_CONTROL_INPUT, 0, 0);
            return std.fmt.allocPrint(self.allocator, "ACK|{s}|{d}\n", .{ self.session_name, self.pid });
        }

        return std.fmt.allocPrint(self.allocator, "ERR|{s}|unknown-request\n", .{self.session_name});
    }

    fn enqueueInput(self: *ControlPlane, from: []const u8, text: []const u8) !void {
        const owned_from = try self.allocator.dupe(u8, from);
        errdefer self.allocator.free(owned_from);
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        self.pending_inputs_lock.lock();
        defer self.pending_inputs_lock.unlock();
        try self.pending_inputs.append(self.allocator, .{
            .from = owned_from,
            .text = owned_text,
        });
    }

    pub fn drainPendingInputs(self: *ControlPlane, surface: anytype) void {
        self.pending_inputs_lock.lock();
        var pending = self.pending_inputs;
        self.pending_inputs = .{};
        self.pending_inputs_lock.unlock();
        defer pending.deinit(self.allocator);

        for (pending.items) |entry| {
            defer self.allocator.free(entry.from);
            defer self.allocator.free(entry.text);

            const ts = std.time.milliTimestamp();
            surface.textCallback(entry.text) catch |err| {
                const line = std.fmt.allocPrint(self.allocator, "{d}|INPUT_FAILED|{s}|{d}|{s}\n", .{ ts, entry.from, entry.text.len, @errorName(err) }) catch null;
                if (line) |owned| {
                    defer self.allocator.free(owned);
                    self.appendLog(owned);
                }
                log.warn("failed to apply control-plane input: {}", .{err});
                continue;
            };

            const line = std.fmt.allocPrint(self.allocator, "{d}|INPUT_APPLIED|{s}|{d}\n", .{ ts, entry.from, entry.text.len }) catch null;
            if (line) |owned| {
                defer self.allocator.free(owned);
                self.appendLog(owned);
            }
        }
    }

    fn getWindowTitle(self: *ControlPlane) ![]u8 {
        const len = os.GetWindowTextLengthW(self.hwnd);
        if (len <= 0) return self.allocator.dupe(u8, "");

        const needed: usize = @intCast(len + 1);
        const utf16 = try self.allocator.alloc(u16, needed);
        defer self.allocator.free(utf16);

        @memset(utf16, 0);
        const copied = os.GetWindowTextW(self.hwnd, utf16.ptr, @intCast(needed));
        if (copied <= 0) return self.allocator.dupe(u8, "");

        return std.unicode.utf16LeToUtf8Alloc(self.allocator, utf16[0..@intCast(copied)]);
    }

    fn buildTailResponse(self: *ControlPlane, requested_lines: usize) ![]u8 {
        const lines = if (requested_lines == 0) 20 else requested_lines;
        if (self.capture_tail_fn) |capture| {
            if (self.callback_ctx) |ctx| {
                const viewport = capture(ctx, self.allocator, null) catch |err| blk: {
                    log.warn("failed to capture viewport tail: {}", .{err});
                    break :blk null;
                };
                if (viewport) |text| {
                    defer self.allocator.free(text);
                    const tail = sliceLastLines(text, lines);
                    return std.fmt.allocPrint(self.allocator, "TAIL|{s}|{d}\n{s}", .{ self.session_name, lines, tail });
                }
            }
        }

        const file = std.fs.openFileAbsolute(self.log_file_path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return std.fmt.allocPrint(self.allocator, "TAIL|{s}|0|\n", .{self.session_name}),
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 64 * 1024);
        defer self.allocator.free(content);

        const tail = sliceLastLines(content, lines);
        return std.fmt.allocPrint(self.allocator, "TAIL|{s}|{d}\n{s}", .{ self.session_name, lines, tail });
    }

    fn inferPromptFromViewport(self: *ControlPlane, pwd: []const u8, title: []const u8) !bool {
        const capture = self.capture_tail_fn orelse return false;
        const ctx = self.callback_ctx orelse return false;
        const viewport = (capture(ctx, self.allocator, null) catch |err| {
            log.warn("failed to capture viewport for prompt heuristic: {}", .{err});
            return false;
        }) orelse return false;
        defer self.allocator.free(viewport);

        const last_line = lastNonEmptyLine(viewport) orelse return false;
        const line = std.mem.trimRight(u8, last_line, " \t\r");
        if (line.len == 0) return false;

        if (pwd.len != 0) {
            if (std.mem.eql(u8, title, "C:\\WINDOWS\\System32\\cmd.exe")) {
                return std.mem.startsWith(u8, line, pwd) and std.mem.endsWith(u8, line, ">");
            }
            if (std.mem.indexOf(u8, title, "pwsh") != null or std.mem.indexOf(u8, title, "powershell") != null) {
                const ps_prefix = try std.fmt.allocPrint(self.allocator, "PS {s}", .{pwd});
                defer self.allocator.free(ps_prefix);
                return std.mem.startsWith(u8, line, ps_prefix) and std.mem.endsWith(u8, line, ">");
            }
        }

        return false;
    }
};

fn parseTailCount(request: []const u8) usize {
    if (std.mem.eql(u8, request, "TAIL")) return 20;
    if (!std.mem.startsWith(u8, request, "TAIL|")) return 20;
    return std.fmt.parseUnsigned(usize, request[5..], 10) catch 20;
}

fn sliceLastLines(content: []const u8, requested_lines: usize) []const u8 {
    if (content.len == 0 or requested_lines == 0) return content;

    var seen: usize = 0;
    var idx: usize = content.len;
    while (idx > 0) {
        idx -= 1;
        if (content[idx] == '\n') {
            seen += 1;
            if (seen > requested_lines) {
                return content[idx + 1 ..];
            }
        }
    }
    return content;
}

fn lastNonEmptyLine(content: []const u8) ?[]const u8 {
    if (content.len == 0) return null;

    var end = content.len;
    while (end > 0) {
        var start = end;
        while (start > 0 and content[start - 1] != '\n') : (start -= 1) {}
        const line = std.mem.trim(u8, content[start..end], " \t\r\n");
        if (line.len != 0) return line;
        if (start == 0) break;
        end = start - 1;
    }
    return null;
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
    return std.fmt.allocPrint(allocator, "winui3-{d}", .{pid});
}

fn sanitizeSessionName(allocator: Allocator, raw: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    for (raw) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.') {
            try list.append(allocator, ch);
        } else {
            try list.append(allocator, '_');
        }
    }

    const trimmed = std.mem.trim(u8, list.items, "_");
    if (trimmed.len == 0) return allocator.dupe(u8, "session");
    return allocator.dupe(u8, trimmed);
}

fn makeDirIfMissing(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}
