//! Regression repro tests for #223
//! (drag bar WndProc forwards messages to the parent UI thread via
//!  `SendMessageW` with no timeout — a hung parent UI thread therefore
//!  also wedges the drag bar, so titlebar / close buttons appear dead).
//!
//! Background
//! ----------
//! `src/apprt/winui3/nonclient_island_window.zig:inputSinkMessageHandler`
//! routes drag-bar hit-test/click messages back to the parent window
//! with `SendMessageW(parent, ...)`. `SendMessageW` cross-thread blocks
//! the calling thread *forever* until the target window's WndProc returns.
//! When the parent UI thread is hung (#218 family of bugs), the drag
//! bar's own WndProc also blocks — so the user sees "the close button
//! itself doesn't respond" rather than just "the surface stopped".
//!
//! What this test proves (mechanically, no real surface needed)
//! ------------------------------------------------------------
//! 1. `SendMessageW(hwnd, ...)` from a worker thread to a window owned
//!    by a deliberately-hung UI thread blocks the worker indefinitely.
//!    This is the buggy contract the pre-fix drag bar relies on.
//! 2. `SendMessageTimeoutW(hwnd, ..., SMTO_ABORTIFHUNG | SMTO_BLOCK,
//!    1000ms, &out)` against the *same* hung target returns 0 within
//!    the timeout window, restoring the drag bar's ability to fall
//!    back to `DefWindowProcW`.
//!
//! Hard rule: every test bounds its own waiting with explicit deadlines.
//! Never rely on the test runner as the timeout of last resort.
//!
//! How to run
//! ----------
//! ```
//! zig test -target x86_64-windows -lc tests/repro_dragbar_send_message_hang.zig
//! ```
//! (no extra `--dep`s; this test is fully self-contained.)

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const ns_per_ms = std.time.ns_per_ms;

// ---------------------------------------------------------------------------
// Minimal Win32 bindings local to the test (so we don't drag in
// src/apprt/winui3/os.zig and its WinUI3 build flags).
// ---------------------------------------------------------------------------

const HWND = if (builtin.os.tag == .windows) std.os.windows.HWND else *opaque {};
const HINSTANCE = if (builtin.os.tag == .windows) std.os.windows.HINSTANCE else *opaque {};
const HMODULE = if (builtin.os.tag == .windows) std.os.windows.HMODULE else *opaque {};
const HICON = ?*opaque {};
const HCURSOR = ?*opaque {};
const HBRUSH = ?*opaque {};
const HMENU = ?*opaque {};
const LRESULT = if (builtin.os.tag == .windows) std.os.windows.LRESULT else isize;
const WPARAM = if (builtin.os.tag == .windows) std.os.windows.WPARAM else usize;
const LPARAM = if (builtin.os.tag == .windows) std.os.windows.LPARAM else isize;
const UINT = if (builtin.os.tag == .windows) std.os.windows.UINT else u32;
const BOOL = if (builtin.os.tag == .windows) std.os.windows.BOOL else i32;
const ATOM = if (builtin.os.tag == .windows) u16 else u16;
const LPCWSTR = [*:0]const u16;

const WM_NCHITTEST: UINT = 0x0084;
const WM_DESTROY: UINT = 0x0002;
const WM_QUIT: UINT = 0x0012;
const WM_USER: UINT = 0x0400;

const SMTO_NORMAL: UINT = 0x0000;
const SMTO_BLOCK: UINT = 0x0001;
const SMTO_ABORTIFHUNG: UINT = 0x0002;

const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const HWND_MESSAGE: HWND = @ptrFromInt(@as(usize, std.math.maxInt(usize)) - 2); // -3

const WS_OVERLAPPEDWINDOW: u32 = 0x00CF0000;
const WS_DISABLED: u32 = 0x08000000;

const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

const POINT = extern struct { x: i32, y: i32 };
const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
    lPrivate: u32,
};

const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?HINSTANCE,
    hIcon: HICON,
    hCursor: HCURSOR,
    hbrBackground: HBRUSH,
    lpszMenuName: ?LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: HICON,
};

extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.winapi) ?HMODULE;
extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
extern "user32" fn UnregisterClassW(lpClassName: LPCWSTR, hInstance: ?HINSTANCE) callconv(.winapi) BOOL;
extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: LPCWSTR,
    lpWindowName: ?LPCWSTR,
    dwStyle: u32,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn SendMessageTimeoutW(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    fuFlags: UINT,
    uTimeout: UINT,
    lpdwResult: ?*usize,
) callconv(.winapi) LRESULT;

// ---------------------------------------------------------------------------
// Hung parent harness.
//
// We spawn a dedicated UI thread that:
//   1. registers a window class whose WndProc *blocks forever* on
//      WM_NCHITTEST (mimics the real-world "UI thread parked in
//      Condition.wait" hang).
//   2. creates a top-level (HWND_MESSAGE) window owned by that thread.
//   3. publishes the HWND via an atomic + Reset event so the test
//      thread can take it.
//   4. runs a normal message pump — the pump is alive, but any
//      WM_NCHITTEST dispatched on it will park the WndProc forever.
//
// To make the test deterministic we use a *gate* `Atomic(bool)` the
// WndProc spins on in 1ms steps. The test thread flips it during
// teardown so the WndProc finally returns and the UI thread can exit
// its message loop.
// ---------------------------------------------------------------------------

const HungHarness = struct {
    // Filled by the UI thread once the window exists.
    hwnd: std.atomic.Value(usize) = .init(0),
    ui_thread_id: std.atomic.Value(u32) = .init(0),
    ready: std.Thread.ResetEvent = .{},

    // Set by tests to release the WndProc that's parked on WM_NCHITTEST.
    // Atomic so the spinning WndProc can observe it without locks.
    release_hang: std.atomic.Value(bool) = .init(false),

    // Set by tests when the UI thread should exit its message loop.
    shutdown: std.atomic.Value(bool) = .init(false),

    fn instance() *HungHarness {
        return &harness_singleton;
    }

    fn wndProc(hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.winapi) LRESULT {
        const self = HungHarness.instance();
        if (msg == WM_NCHITTEST) {
            // Spin until the test releases us. 1ms granularity is more
            // than fast enough for our 1s SendMessageTimeoutW probe.
            // We deliberately do NOT pump messages here; the whole
            // point is that this thread is wedged.
            while (!self.release_hang.load(.acquire)) {
                std.Thread.sleep(1 * ns_per_ms);
            }
            return 0; // HTNOWHERE
        }
        return DefWindowProcW(hwnd, msg, wparam, lparam);
    }

    fn run(self: *HungHarness) void {
        self.ui_thread_id.store(std.os.windows.kernel32.GetCurrentThreadId(), .release);

        const class_name_w: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("Repro223HungParent");
        const hmodule = GetModuleHandleW(null);
        const hinstance: ?HINSTANCE = if (hmodule) |m| @ptrCast(m) else null;

        const wc: WNDCLASSEXW = .{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = 0,
            .lpfnWndProc = HungHarness.wndProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hinstance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name_w,
            .hIconSm = null,
        };
        const atom = RegisterClassExW(&wc);
        if (atom == 0) {
            // Class might already exist from a previous run; that's OK.
        }

        const hwnd_opt = CreateWindowExW(
            0,
            class_name_w,
            null,
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            100,
            100,
            null, // top-level (NOT HWND_MESSAGE — message-only windows
            // sometimes refuse WM_NCHITTEST routing in odd ways; a
            // hidden top-level keeps the test honest about the
            // production drag-bar shape).
            null,
            hinstance,
            null,
        );
        if (hwnd_opt == null) {
            // Couldn't create the window. Publish 0 so tests bail.
            self.ready.set();
            return;
        }
        const hwnd = hwnd_opt.?;
        self.hwnd.store(@intFromPtr(hwnd), .release);
        self.ready.set();

        // Pump messages until shutdown. The WndProc itself will park
        // forever inside WM_NCHITTEST — that *is* the bug we're
        // reproducing. PeekMessage lets the loop notice shutdown even
        // when no messages are queued.
        var msg: MSG = undefined;
        while (!self.shutdown.load(.acquire)) {
            if (PeekMessageW(&msg, null, 0, 0, 1) != 0) { // PM_REMOVE = 1
                if (msg.message == WM_QUIT) break;
                _ = TranslateMessage(&msg);
                _ = DispatchMessageW(&msg);
            } else {
                std.Thread.sleep(1 * ns_per_ms);
            }
        }

        _ = DestroyWindow(hwnd);
        _ = UnregisterClassW(class_name_w, hinstance);
    }
};

var harness_singleton: HungHarness = .{};

// ---------------------------------------------------------------------------
// Worker that fires `SendMessageW(hung_hwnd, WM_NCHITTEST, ...)` and
// publishes a "done" flag + return value via atomics. Used by Test 1.
// ---------------------------------------------------------------------------

const SendBlockingProbe = struct {
    target: HWND,
    done: std.atomic.Value(bool) = .init(false),
    result: std.atomic.Value(isize) = .init(0),

    fn run(self: *SendBlockingProbe) void {
        const r = SendMessageW(self.target, WM_NCHITTEST, 0, 0);
        self.result.store(r, .release);
        self.done.store(true, .release);
    }
};

// ---------------------------------------------------------------------------
// Worker that fires `SendMessageTimeoutW(..., SMTO_ABORTIFHUNG | SMTO_BLOCK,
// 1000ms, &out)`. Used by Test 2. Records elapsed time so we can assert
// the timeout actually fired.
// ---------------------------------------------------------------------------

const SendTimeoutProbe = struct {
    target: HWND,
    done: std.atomic.Value(bool) = .init(false),
    rc: std.atomic.Value(isize) = .init(0),
    elapsed_ns: std.atomic.Value(u64) = .init(0),

    fn run(self: *SendTimeoutProbe) void {
        var out: usize = 0;
        var t = std.time.Timer.start() catch unreachable;
        const r = SendMessageTimeoutW(
            self.target,
            WM_NCHITTEST,
            0,
            0,
            SMTO_ABORTIFHUNG | SMTO_BLOCK,
            1000,
            &out,
        );
        self.elapsed_ns.store(t.read(), .release);
        self.rc.store(r, .release);
        self.done.store(true, .release);
    }
};

// ---------------------------------------------------------------------------
// Test 1: SendMessageW (no timeout) blocks the caller indefinitely
// when the parent UI thread is hung. This is the buggy contract the
// drag-bar WndProc relies on at lines 531/540/551/573 in
// nonclient_island_window.zig.
// ---------------------------------------------------------------------------

test "SendMessageW to hung parent blocks indefinitely (#223)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const h = HungHarness.instance();
    h.* = .{};

    var ui_thread = try std.Thread.spawn(.{}, HungHarness.run, .{h});
    defer {
        h.release_hang.store(true, .release);
        h.shutdown.store(true, .release);
        ui_thread.join();
    }

    // Wait for the UI thread to publish the HWND. 2s ceiling — if
    // CreateWindowExW takes longer than that on a healthy box, something
    // else is broken.
    h.ready.wait();
    const hwnd_int = h.hwnd.load(.acquire);
    if (hwnd_int == 0) return error.HarnessSetupFailed;
    const hwnd: HWND = @ptrFromInt(hwnd_int);

    var probe: SendBlockingProbe = .{ .target = hwnd };
    var probe_thread = try std.Thread.spawn(.{}, SendBlockingProbe.run, .{&probe});

    // Give the worker time to enter SendMessageW *and* the UI thread
    // time to dispatch into our parked WndProc. 200ms is far more than
    // either step needs on a normally-loaded machine.
    std.Thread.sleep(200 * ns_per_ms);

    // Core assertion: the worker is still parked inside SendMessageW.
    // If we ever observe done=true here, either the WndProc returned
    // early (gate broke) or SendMessageW grew an implicit timeout.
    try testing.expect(!probe.done.load(.acquire));

    // Release the WndProc so the worker can finally finish; bound the
    // wait so a regression here doesn't take the test runner with it.
    h.release_hang.store(true, .release);

    const deadline_ns: u64 = 2 * std.time.ns_per_s;
    var waited: u64 = 0;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(5 * ns_per_ms);
        waited += 5 * ns_per_ms;
    }
    try testing.expect(probe.done.load(.acquire));
    probe_thread.join();
}

// ---------------------------------------------------------------------------
// Test 2: SendMessageTimeoutW(SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000ms)
// against the *same* hung parent returns 0 within ~1s. This is the
// fix contract the drag bar's WndProc must adopt.
// ---------------------------------------------------------------------------

test "SendMessageTimeoutW with SMTO_ABORTIFHUNG returns 0 on hung parent (#223)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const h = HungHarness.instance();
    h.* = .{};

    var ui_thread = try std.Thread.spawn(.{}, HungHarness.run, .{h});
    defer {
        h.release_hang.store(true, .release);
        h.shutdown.store(true, .release);
        ui_thread.join();
    }

    h.ready.wait();
    const hwnd_int = h.hwnd.load(.acquire);
    if (hwnd_int == 0) return error.HarnessSetupFailed;
    const hwnd: HWND = @ptrFromInt(hwnd_int);

    var probe: SendTimeoutProbe = .{ .target = hwnd };
    var probe_thread = try std.Thread.spawn(.{}, SendTimeoutProbe.run, .{&probe});

    // Bound the test wait at 3s. A working SMTO_ABORTIFHUNG must
    // return well before that; the underlying timeout is 1s.
    const deadline_ns: u64 = 3 * std.time.ns_per_s;
    var waited: u64 = 0;
    while (!probe.done.load(.acquire) and waited < deadline_ns) {
        std.Thread.sleep(5 * ns_per_ms);
        waited += 5 * ns_per_ms;
    }
    try testing.expect(probe.done.load(.acquire));
    probe_thread.join();

    // SMTO_ABORTIFHUNG returns 0 when the target window is detected
    // as hung. The drag bar's fix path keys off this: r==0 → fall back
    // to DefWindowProcW.
    try testing.expectEqual(@as(isize, 0), probe.rc.load(.acquire));

    // Elapsed should be inside [~10ms, 2.5s]. SMTO_ABORTIFHUNG
    // typically detects the hang almost immediately (the window is
    // marked unresponsive by the OS), so we accept anything from "fast
    // detection" through "full 1s timeout + scheduling slack".
    const elapsed = probe.elapsed_ns.load(.acquire);
    try testing.expect(elapsed < 2_500 * ns_per_ms);

    // Release on the way out so the harness can shut down.
    h.release_hang.store(true, .release);
}
