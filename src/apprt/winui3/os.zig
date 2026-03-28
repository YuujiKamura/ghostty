/// Win32 API types, constants, structs, and extern declarations needed by the WinUI 3 apprt.
/// Expanded to support full terminal surface implementation (input, clipboard, IME, DPI, subclass).
const std = @import("std");
const win32 = std.os.windows;

// --- Primitive types ---
pub const HWND = win32.HANDLE;
pub const HDC = win32.HANDLE;
pub const HGLRC = win32.HANDLE;
pub const HINSTANCE = win32.HANDLE;
pub const HICON = win32.HANDLE;
pub const HCURSOR = win32.HANDLE;
pub const HBRUSH = win32.HANDLE;
pub const HMENU = win32.HANDLE;
pub const HANDLE = win32.HANDLE;
pub const LPARAM = win32.LPARAM;
pub const WPARAM = win32.WPARAM;
pub const LRESULT = win32.LRESULT;
pub const BOOL = win32.BOOL;
pub const UINT = c_uint;
pub const UINT_PTR = usize;
pub const DWORD = win32.DWORD;
pub const LONG = c_long;
pub const WORD = u16;
pub const ATOM = u16;
pub const BYTE = u8;
pub const LPVOID = ?*anyopaque;
pub const LPCWSTR = [*:0]align(1) const u16;
pub const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT;

// --- Window messages ---
pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_QUIT: UINT = 0x0012;
pub const WM_SYSCOMMAND: UINT = 0x0112;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KEYUP: UINT = 0x0101;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_SYSKEYDOWN: UINT = 0x0104;
pub const WM_SYSKEYUP: UINT = 0x0105;
pub const WM_TIMER: UINT = 0x0113;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_LBUTTONDBLCLK: UINT = 0x0203;
pub const WM_RBUTTONDOWN: UINT = 0x0204;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_MBUTTONDOWN: UINT = 0x0207;
pub const WM_MBUTTONUP: UINT = 0x0208;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WM_MOUSEHWHEEL: UINT = 0x020E;
pub const WM_ENTERSIZEMOVE: UINT = 0x0231;
pub const WM_EXITSIZEMOVE: UINT = 0x0232;
pub const WM_NCCREATE: UINT = 0x0081;
pub const WM_NCCALCSIZE: UINT = 0x0083;
pub const WM_NCHITTEST: UINT = 0x0084;
pub const WM_NCLBUTTONDOWN: UINT = 0x00A1;
pub const WM_NCLBUTTONUP: UINT = 0x00A2;
pub const WM_NCLBUTTONDBLCLK: UINT = 0x00A3;
pub const WM_NCMOUSEMOVE: UINT = 0x00A0;
pub const WM_NCRBUTTONDOWN: UINT = 0x00A4;
pub const WM_NCRBUTTONUP: UINT = 0x00A5;
pub const WM_NCRBUTTONDBLCLK: UINT = 0x00A6;
pub const WM_SETCURSOR: UINT = 0x0020;
pub const WM_ACTIVATE: UINT = 0x0006;
pub const WM_DPICHANGED: UINT = 0x02E0;
pub const WM_USER: UINT = 0x0400;

// --- Application-defined messages (WM_USER + N) ---
/// Posted by the renderer thread to request swap chain binding on the UI thread.
pub const WM_APP_BIND_SWAP_CHAIN: UINT = WM_USER + 1;
/// Posted by the renderer thread to request swap chain HANDLE binding on the UI thread.
pub const WM_APP_BIND_SWAP_CHAIN_HANDLE: UINT = WM_USER + 2;
/// Test-only: set ime_composing = true for focus-loss cleanup testing.
pub const WM_APP_TEST_FAKE_IME_COMPOSING: UINT = WM_USER + 3;
/// Control plane: dequeue pending inputs on the UI thread.
pub const WM_APP_CONTROL_INPUT: UINT = WM_USER + 4;
/// Control plane: execute a tab/window action on the UI thread.
/// wparam encodes the action type, lparam encodes a parameter (e.g. tab index).
pub const WM_APP_CONTROL_ACTION: UINT = WM_USER + 5;
/// Posted to close the currently active tab.
pub const WM_APP_CLOSE_TAB: UINT = WM_USER + 6;
/// Control plane: inject text into IME TextBox on the UI thread (simulates committed IME input).
pub const WM_APP_IME_INJECT: UINT = WM_USER + 7;
/// Control plane: inject text through TSF path (simulates TSF composition commit for testing).
pub const WM_APP_TSF_INJECT: UINT = WM_USER + 8;
/// Control plane: synchronous query from pipe thread → UI thread via SendMessageW.
/// lparam = pointer to CpQuery struct. UI thread fills result fields.
pub const WM_APP_CP_QUERY: UINT = WM_USER + 9;

// --- Window styles ---
pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_EX_LAYERED: DWORD = 0x00080000;
pub const WS_EX_NOREDIRECTIONBITMAP: DWORD = 0x00200000;
pub const WS_EX_TRANSPARENT: DWORD = 0x00000020;
pub const CW_USEDEFAULT: c_int = @bitCast(@as(c_uint, 0x80000000));

// --- Class styles ---
pub const CS_OWNDC: UINT = 0x0020;
pub const CS_DBLCLKS: UINT = 0x0008;
pub const CS_HREDRAW: UINT = 0x0002;
pub const CS_VREDRAW: UINT = 0x0001;

// --- Misc constants ---
// Win32 MAKEINTRESOURCE cursor IDs — these are integer resource IDs cast to
// pointer type, not real pointers. LPCWSTR is align(1) to allow odd values.
pub const IDC_ARROW: LPCWSTR = @ptrFromInt(32512);
pub const IDC_IBEAM: LPCWSTR = @ptrFromInt(32513);
pub const IDC_WAIT: LPCWSTR = @ptrFromInt(32514);
pub const IDC_CROSS: LPCWSTR = @ptrFromInt(32515);
pub const IDC_SIZEALL: LPCWSTR = @ptrFromInt(32646);
pub const IDC_SIZENWSE: LPCWSTR = @ptrFromInt(32642);
pub const IDC_SIZENESW: LPCWSTR = @ptrFromInt(32643);
pub const IDC_SIZEWE: LPCWSTR = @ptrFromInt(32644);
pub const IDC_SIZENS: LPCWSTR = @ptrFromInt(32645);
pub const IDC_NO: LPCWSTR = @ptrFromInt(32648);
pub const IDC_HAND: LPCWSTR = @ptrFromInt(32649);
pub const IDC_APPSTARTING: LPCWSTR = @ptrFromInt(32650);
pub const IDC_HELP: LPCWSTR = @ptrFromInt(32651);
pub const COLOR_WINDOW: c_int = 5;
pub const BLACK_BRUSH: c_int = 4;
pub const SW_HIDE: c_int = 0;
pub const SW_SHOWNORMAL: c_int = 1;
pub const SW_SHOWMINIMIZED: c_int = 2;
pub const SW_SHOWMAXIMIZED: c_int = 3;
pub const SW_SHOW: c_int = 5;
pub const PM_REMOVE: UINT = 0x0001;
pub const PM_NOREMOVE: UINT = 0x0000;
pub const GWLP_USERDATA: c_int = -21;
pub const CF_UNICODETEXT: UINT = 13;
pub const GMEM_MOVEABLE: UINT = 0x0002;
pub const SC_CLOSE: usize = 0xF060;
pub const SC_MINIMIZE: usize = 0xF020;
pub const SC_MAXIMIZE: usize = 0xF030;
pub const SC_RESTORE: usize = 0xF120;
pub const SC_MOVE: usize = 0xF010;
pub const MF_STRING: UINT = 0x0000;
pub const MF_SEPARATOR: UINT = 0x0800;
pub const TPM_RIGHTBUTTON: UINT = 0x0002;
pub const TPM_RETURNCMD: UINT = 0x0100;

// --- MsgWaitForMultipleObjectsEx ---
pub const QS_ALLINPUT: DWORD = 0x04FF;
pub const MWMO_INPUTAVAILABLE: DWORD = 0x0004;
pub const WAIT_TIMEOUT: DWORD = 0x00000102;
pub const INFINITE: DWORD = 0xFFFFFFFF;

// --- MapVirtualKeyW ---
pub const MAPVK_VK_TO_CHAR: UINT = 2;

// --- SetWindowPos flags ---
pub const SWP_NOSIZE: UINT = 0x0001;
pub const SWP_NOMOVE: UINT = 0x0002;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;
pub const SWP_SHOWWINDOW: UINT = 0x0040;
pub const SWP_HIDEWINDOW: UINT = 0x0080;
pub const SWP_FRAMECHANGED: UINT = 0x0020;
pub const SWP_NOSENDCHANGING: UINT = 0x0400;

// --- Pixel format ---
pub const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
pub const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;
pub const PFD_DOUBLEBUFFER: DWORD = 0x00000001;
pub const PFD_TYPE_RGBA: BYTE = 0;
pub const PFD_MAIN_PLANE: BYTE = 0;

// --- Structs ---
pub const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.winapi) LRESULT,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON = null,
};

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: DWORD = 0,
    dwVisibleMask: DWORD = 0,
    dwDamageMask: DWORD = 0,
};

pub const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};

pub const MSG = extern struct {
    hwnd: ?HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
};

pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};

pub const PAINTSTRUCT = extern struct {
    hdc: ?HDC = null,
    fErase: BOOL = 0,
    rcPaint: RECT = .{},
    fRestore: BOOL = 0,
    fIncUpdate: BOOL = 0,
    rgbReserved: [32]BYTE = [_]BYTE{0} ** 32,
};

// --- Window subclass callback type ---
pub const SUBCLASSPROC = *const fn (HWND, UINT, WPARAM, LPARAM, usize, usize) callconv(.winapi) LRESULT;

// --- user32 extern declarations ---
pub extern "user32" fn RegisterClassExW(lpWndClass: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: LPCWSTR,
    lpWindowName: LPCWSTR,
    dwStyle: DWORD,
    x: c_int,
    y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: LPVOID,
) callconv(.winapi) ?HWND;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;
pub extern "user32" fn PostMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) BOOL;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: LPCWSTR) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn SetCursor(hCursor: ?HCURSOR) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.winapi) BOOL;
pub extern "user32" fn GetSystemMetricsForDpi(nIndex: c_int, dpi: UINT) callconv(.winapi) c_int;

// System metrics indices
pub const SM_CXPADDEDBORDER: c_int = 92;
pub const SM_CXSIZEFRAME: c_int = 32;
pub const SM_CYSIZEFRAME: c_int = 33;
pub extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(.winapi) ?HDC;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: c_int, dwNewLong: usize) callconv(.winapi) usize;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: c_int) callconv(.winapi) usize;
pub extern "user32" fn InvalidateRect(hWnd: HWND, lpRect: ?*const RECT, bErase: BOOL) callconv(.winapi) BOOL;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn TrackPopupMenuEx(hmenu: HMENU, uFlags: UINT, x: c_int, y: c_int, hwnd: HWND, lptpm: ?*const anyopaque) callconv(.winapi) UINT;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn ClientToScreen(hWnd: HWND, lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowTextW(hWnd: HWND, lpString: LPCWSTR) callconv(.winapi) BOOL;
pub extern "user32" fn GetWindowTextW(hWnd: HWND, lpString: [*]u16, nMaxCount: c_int) callconv(.winapi) c_int;
pub extern "user32" fn GetWindowTextLengthW(hWnd: HWND) callconv(.winapi) c_int;
pub extern "user32" fn GetDpiForWindow(hWnd: HWND) callconv(.winapi) UINT;
pub extern "user32" fn GetDpiForSystem() callconv(.winapi) UINT;
pub extern "user32" fn AdjustWindowRectExForDpi(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL, dwExStyle: DWORD, dpi: UINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetKeyState(nVirtKey: c_int) callconv(.winapi) c_short;
pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.winapi) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.winapi) LPVOID;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: LPVOID) callconv(.winapi) LPVOID;
pub extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
pub extern "user32" fn SetCapture(hWnd: HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
pub extern "user32" fn GetFocus() callconv(.winapi) ?HWND;
pub extern "user32" fn GetWindow(hWnd: HWND, uCmd: UINT) callconv(.winapi) ?HWND;
pub extern "user32" fn GetAncestor(hWnd: HWND, gaFlags: UINT) callconv(.winapi) ?HWND;
pub const GW_CHILD: UINT = 5;
pub const GW_HWNDNEXT: UINT = 2;
pub const GA_PARENT: UINT = 1;
pub const GA_ROOT: UINT = 2;
pub extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn SetLayeredWindowAttributes(hWnd: HWND, crKey: DWORD, bAlpha: u8, dwFlags: DWORD) callconv(.winapi) BOOL;
pub const LWA_ALPHA: DWORD = 0x00000002;
pub extern "user32" fn UnregisterClassW(lpClassName: LPCWSTR, hInstance: ?HINSTANCE) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPos(
    hWnd: HWND,
    hWndInsertAfter: ?HWND,
    X: c_int,
    Y: c_int,
    cx: c_int,
    cy: c_int,
    uFlags: UINT,
) callconv(.winapi) BOOL;
pub extern "user32" fn SetTimer(hWnd: ?HWND, nIDEvent: usize, uElapse: UINT, lpTimerFunc: ?*const anyopaque) callconv(.winapi) usize;
pub extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.winapi) BOOL;
pub extern "user32" fn MsgWaitForMultipleObjectsEx(
    nCount: DWORD,
    pHandles: ?[*]const HANDLE,
    dwMilliseconds: DWORD,
    dwWakeMask: DWORD,
    dwFlags: DWORD,
) callconv(.winapi) DWORD;

pub extern "user32" fn MapVirtualKeyW(uCode: UINT, uMapType: UINT) callconv(.winapi) UINT;
pub extern "user32" fn GetKeyboardLayout(idThread: DWORD) callconv(.winapi) usize;

// --- kernel32 extern declarations ---
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "kernel32" fn SetLastError(dwErrCode: DWORD) callconv(.winapi) void;
pub extern "kernel32" fn ExitProcess(uExitCode: UINT) callconv(.winapi) noreturn;
pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;
pub extern "kernel32" fn GetModuleFileNameW(hModule: ?HINSTANCE, lpFilename: [*]u16, nSize: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn RtlCaptureStackBackTrace(FramesToSkip: DWORD, FramesToCapture: DWORD, BackTrace: [*]?*anyopaque, BackTraceHash: ?*DWORD) callconv(.winapi) u16;
pub extern "kernel32" fn SetUnhandledExceptionFilter(lpTopLevelExceptionFilter: ?VectoredExceptionHandler) callconv(.winapi) ?VectoredExceptionHandler;
pub extern "kernel32" fn FlushFileBuffers(hFile: std.os.windows.HANDLE) callconv(.winapi) c_int;

pub const MODULEENTRY32W = extern struct {
    dwSize: DWORD,
    th32ModuleID: DWORD,
    th32ProcessID: DWORD,
    GlblcntUsage: DWORD,
    ProccntUsage: DWORD,
    modBaseAddr: ?[*]u8,
    modBaseSize: DWORD,
    hModule: ?HINSTANCE,
    szModule: [256]u16,
    szExePath: [260]u16,
};

pub extern "kernel32" fn CreateToolhelp32Snapshot(dwFlags: DWORD, th32ProcessID: DWORD) callconv(.winapi) HANDLE;
pub extern "kernel32" fn Module32FirstW(hSnapshot: HANDLE, lpme: *MODULEENTRY32W) callconv(.winapi) BOOL;
pub extern "kernel32" fn Module32NextW(hSnapshot: HANDLE, lpme: *MODULEENTRY32W) callconv(.winapi) BOOL;
pub const TH32CS_SNAPMODULE: DWORD = 0x00000008;
pub const TH32CS_SNAPMODULE32: DWORD = 0x00000010;

pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.winapi) LPVOID;
pub extern "kernel32" fn GlobalLock(hMem: LPVOID) callconv(.winapi) LPVOID;
pub extern "kernel32" fn GlobalUnlock(hMem: LPVOID) callconv(.winapi) BOOL;
pub extern "kernel32" fn GlobalFree(hMem: LPVOID) callconv(.winapi) LPVOID;

// --- gdi32 extern declarations ---
pub extern "gdi32" fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) c_int;
pub extern "gdi32" fn SetPixelFormat(hdc: HDC, format: c_int, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(.winapi) BOOL;
pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;
pub extern "gdi32" fn GetStockObject(i: c_int) callconv(.winapi) ?HANDLE;

// GetDC/ReleaseDC are exported from user32.dll (not gdi32)
pub extern "user32" fn GetDC(hWnd: ?HWND) callconv(.winapi) ?HDC;
pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(.winapi) c_int;

// --- opengl32 extern declarations ---
pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?HGLRC;
pub extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglGetProcAddress(lpszProc: [*:0]const u8) callconv(.winapi) ?*const anyopaque;

// --- comctl32 extern declarations (window subclass API) ---
pub extern "comctl32" fn SetWindowSubclass(hWnd: HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: usize, dwRefData: usize) callconv(.winapi) BOOL;
pub extern "comctl32" fn DefSubclassProc(hWnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
pub extern "comctl32" fn RemoveWindowSubclass(hWnd: HWND, pfnSubclass: SUBCLASSPROC, uIdSubclass: usize) callconv(.winapi) BOOL;

// --- IME types ---
pub const HIMC = ?*anyopaque;

// --- IME constants ---
pub const WM_IME_STARTCOMPOSITION: UINT = 0x010D;
pub const WM_IME_ENDCOMPOSITION: UINT = 0x010E;
pub const WM_IME_COMPOSITION: UINT = 0x010F;
pub const GCS_COMPSTR: DWORD = 0x0008;
pub const GCS_RESULTSTR: DWORD = 0x0800;
pub const CFS_POINT: DWORD = 0x0002;

pub const COMPOSITIONFORM = extern struct {
    dwStyle: DWORD = 0,
    ptCurrentPos: POINT = .{},
    rcArea: RECT = .{},
};

// --- imm32 extern declarations ---
pub extern "imm32" fn ImmGetContext(hWnd: HWND) callconv(.winapi) HIMC;
pub extern "imm32" fn ImmReleaseContext(hWnd: HWND, hIMC: HIMC) callconv(.winapi) BOOL;
pub extern "imm32" fn ImmGetCompositionStringW(hIMC: HIMC, dwIndex: DWORD, lpBuf: LPVOID, dwBufLen: DWORD) callconv(.winapi) LONG;
pub extern "imm32" fn ImmSetCompositionWindow(hIMC: HIMC, lpCompForm: *const COMPOSITIONFORM) callconv(.winapi) BOOL;
pub extern "imm32" fn ImmAssociateContextEx(hWnd: HWND, hIMC: HIMC, dwFlags: DWORD) callconv(.winapi) BOOL;
pub const IACE_DEFAULT: DWORD = 0x0010;

// --- Window styles (for input overlay HWND) ---
pub const WS_EX_NOACTIVATE: DWORD = 0x08000000;

// --- SetFocus / SetParent ---
pub extern "user32" fn SetFocus(hWnd: ?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn SetParent(hWndChild: HWND, hWndNewParent: ?HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn MoveWindow(hWnd: HWND, X: c_int, Y: c_int, nWidth: c_int, nHeight: c_int, bRepaint: BOOL) callconv(.winapi) BOOL;

// --- WM_SETFOCUS / WM_KILLFOCUS ---
pub const WM_SETFOCUS: UINT = 0x0007;
pub const WM_KILLFOCUS: UINT = 0x0008;

// --- WM_IME_SETCONTEXT ---
pub const WM_IME_SETCONTEXT: UINT = 0x0281;
pub const WM_IME_NOTIFY: UINT = 0x0282;
pub const WM_IME_CHAR: UINT = 0x0286;

// --- ImmSetOpenStatus / ImmGetOpenStatus ---
pub extern "imm32" fn ImmSetOpenStatus(hIMC: HIMC, fOpen: BOOL) callconv(.winapi) BOOL;
pub extern "imm32" fn ImmGetOpenStatus(hIMC: HIMC) callconv(.winapi) BOOL;

// --- CREATESTRUCTW (passed via WM_CREATE lparam) ---
pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: c_int,
    cx: c_int,
    y: c_int,
    x: c_int,
    style: LONG,
    lpszName: ?LPCWSTR,
    lpszClass: ?LPCWSTR,
    dwExStyle: DWORD,
};

// --- WS_CLIPCHILDREN ---
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;

// --- NCCALCSIZE_PARAMS ---
pub const NCCALCSIZE_PARAMS = extern struct {
    rgrc: [3]RECT,
    lppos: ?*anyopaque, // WINDOWPOS*
};

// --- WM_NCHITTEST return values ---
pub const HTNOWHERE: c_int = 0;
pub const HTTRANSPARENT: c_int = -1;
pub const HTCLIENT: c_int = 1;
pub const HTCAPTION: c_int = 2;
pub const HTSYSMENU: c_int = 3;
pub const HTMINBUTTON: c_int = 8;
pub const HTMAXBUTTON: c_int = 9;
pub const HTLEFT: c_int = 10;
pub const HTRIGHT: c_int = 11;
pub const HTTOP: c_int = 12;
pub const HTTOPLEFT: c_int = 13;
pub const HTTOPRIGHT: c_int = 14;
pub const HTBOTTOM: c_int = 15;
pub const HTBOTTOMLEFT: c_int = 16;
pub const HTBOTTOMRIGHT: c_int = 17;
pub const HTCLOSE: c_int = 20;

// --- DWM (Desktop Window Manager) ---
pub const MARGINS = extern struct {
    cxLeftWidth: c_int,
    cxRightWidth: c_int,
    cyTopHeight: c_int,
    cyBottomHeight: c_int,
};

pub extern "dwmapi" fn DwmDefWindowProc(
    hWnd: HWND,
    msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    plResult: *LRESULT,
) callconv(.winapi) c_int; // BOOL

pub extern "dwmapi" fn DwmExtendFrameIntoClientArea(
    hWnd: HWND,
    pMarInset: *const MARGINS,
) callconv(.winapi) c_long;

pub extern "dwmapi" fn DwmSetWindowAttribute(
    hWnd: HWND,
    dwAttribute: DWORD,
    pvAttribute: *const anyopaque,
    cbAttribute: DWORD,
) callconv(.winapi) c_long;

pub const DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20;
pub const DWMWA_CAPTION_COLOR: DWORD = 35;

// --- Buffered Paint (uxtheme) — required for DWM caption button rendering ---
pub const BP_PAINTPARAMS = extern struct {
    cbSize: DWORD = @sizeOf(BP_PAINTPARAMS),
    dwFlags: DWORD = 0,
    prcExclude: ?*const RECT = null,
    pBlendFunction: ?*const anyopaque = null,
};
pub const BPPF_ERASE: DWORD = 0x0001;
pub const BPPF_NOCLIP: DWORD = 0x0002;
pub const BPBF_TOPDOWNDIB: c_int = 2;

pub extern "uxtheme" fn BufferedPaintInit() callconv(.winapi) c_long;
pub extern "uxtheme" fn BufferedPaintUnInit() callconv(.winapi) c_long;
pub extern "uxtheme" fn BeginBufferedPaint(
    hdcTarget: HDC,
    prcTarget: *const RECT,
    dwFormat: c_int,
    pPaintParams: *const BP_PAINTPARAMS,
    phdcPaint: *?HDC,
) callconv(.winapi) ?*anyopaque; // HPAINTBUFFER
pub extern "uxtheme" fn EndBufferedPaint(
    hBufferedPaint: *anyopaque,
    fUpdateTarget: BOOL,
) callconv(.winapi) c_long;
pub extern "uxtheme" fn BufferedPaintSetAlpha(
    hBufferedPaint: *anyopaque,
    prc: ?*const RECT,
    alpha: u8,
) callconv(.winapi) c_long;

// --- Fullscreen support ---
pub const GWL_STYLE: c_int = -16;
pub const GWL_EXSTYLE: c_int = -20;
pub const WS_CAPTION: DWORD = 0x00C00000;
pub const WS_THICKFRAME: DWORD = 0x00040000;
pub const SWP_NOOWNERZORDER: UINT = 0x0200;
pub const MONITOR_DEFAULTTONEAREST: DWORD = 0x00000002;
pub const HWND_TOP: ?HWND = null;
pub const HWND_BOTTOM: ?HWND = @ptrFromInt(1);

pub const WINDOWPLACEMENT = extern struct {
    length: UINT = @sizeOf(WINDOWPLACEMENT),
    flags: UINT = 0,
    showCmd: UINT = 0,
    ptMinPosition: POINT = .{},
    ptMaxPosition: POINT = .{},
    rcNormalPosition: RECT = .{},
};

pub const MONITORINFO = extern struct {
    cbSize: DWORD = @sizeOf(MONITORINFO),
    rcMonitor: RECT = .{},
    rcWork: RECT = .{},
    dwFlags: DWORD = 0,
};

pub extern "user32" fn GetWindowPlacement(hWnd: HWND, lpwndpl: *WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowPlacement(hWnd: HWND, lpwndpl: *const WINDOWPLACEMENT) callconv(.winapi) BOOL;
pub extern "user32" fn MonitorFromWindow(hWnd: HWND, dwFlags: DWORD) callconv(.winapi) ?HANDLE;
pub extern "user32" fn GetMonitorInfoW(hMonitor: HANDLE, lpmi: *MONITORINFO) callconv(.winapi) BOOL;

// --- Caption button support ---
pub const WS_CLIPSIBLINGS: DWORD = 0x04000000;
pub const HGDIOBJ = ?*anyopaque;
pub const HFONT = ?*anyopaque;
pub const COLORREF = DWORD;

pub extern "user32" fn GetParent(hWnd: HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn IsZoomed(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetMenu(hWnd: HWND) callconv(.winapi) ?*anyopaque;
pub extern "user32" fn FillRect(hDC: HDC, lprc: *const RECT, hbr: HBRUSH) callconv(.winapi) c_int;
pub extern "user32" fn DrawTextW(hdc: HDC, lpchText: [*:0]const u16, cchText: c_int, lprc: *RECT, format: UINT) callconv(.winapi) c_int;

pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.winapi) HBRUSH;
pub extern "gdi32" fn DeleteObject(ho: HGDIOBJ) callconv(.winapi) BOOL;
pub extern "gdi32" fn SelectObject(hdc: HDC, h: HGDIOBJ) callconv(.winapi) HGDIOBJ;
pub extern "gdi32" fn SetBkMode(hdc: HDC, mode: c_int) callconv(.winapi) c_int;
pub extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.winapi) COLORREF;
pub extern "gdi32" fn CreateFontW(
    cHeight: c_int,
    cWidth: c_int,
    cEscapement: c_int,
    cOrientation: c_int,
    cWeight: c_int,
    bItalic: DWORD,
    bUnderline: DWORD,
    bStrikeOut: DWORD,
    iCharSet: DWORD,
    iOutPrecision: DWORD,
    iClipPrecision: DWORD,
    iQuality: DWORD,
    iPitchAndFamily: DWORD,
    pszFaceName: [*:0]const u16,
) callconv(.winapi) HFONT;

// --- winmm extern declarations ---
pub extern "winmm" fn timeBeginPeriod(uPeriod: UINT) callconv(.winapi) UINT;
pub extern "winmm" fn timeEndPeriod(uPeriod: UINT) callconv(.winapi) UINT;

// --- Vectored Exception Handling ---
pub const EXCEPTION_RECORD = extern struct {
    ExceptionCode: DWORD,
    ExceptionFlags: DWORD,
    ExceptionRecord: ?*EXCEPTION_RECORD,
    ExceptionAddress: ?*anyopaque,
    NumberParameters: DWORD,
    ExceptionInformation: [15]usize,
};

pub const EXCEPTION_POINTERS = extern struct {
    ExceptionRecord: ?*EXCEPTION_RECORD,
    ContextRecord: ?*anyopaque,
};

pub const EXCEPTION_CONTINUE_SEARCH: c_long = 0;
pub const STATUS_STOWED_EXCEPTION: DWORD = 0xC000027B;

/// Stowed exception info v2 header — first 8 bytes of each entry.
pub const STOWED_EXCEPTION_INFORMATION_V2 = extern struct {
    size: u32,
    signature: u32, // "SE02" = 0x32304553, "SE01" = 0x31304553
    result_code: i32, // HRESULT
    exception_form: u32,
    // ... more fields follow but we only need result_code
};

pub const VectoredExceptionHandler = *const fn (*EXCEPTION_POINTERS) callconv(.winapi) c_long;
pub extern "kernel32" fn AddVectoredExceptionHandler(first: u32, handler: VectoredExceptionHandler) callconv(.winapi) ?*anyopaque;
pub extern "kernel32" fn RemoveVectoredExceptionHandler(handle: *anyopaque) callconv(.winapi) u32;

// --- Debug logging: redirect stderr to a file for GUI apps ---
pub extern "kernel32" fn SetStdHandle(nStdHandle: DWORD, hHandle: HANDLE) callconv(.winapi) BOOL;
pub const STD_ERROR_HANDLE: DWORD = @as(DWORD, @bitCast(@as(i32, -12)));

pub extern "user32" fn MessageBeep(uType: UINT) callconv(.winapi) BOOL;
pub const MB_OK: UINT = 0x00000000;

const CreateFileW = win32.kernel32.CreateFileW;
pub fn attachDebugConsole() void {
    // Redirect stderr to a log file in the temp directory.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const temp_path = std.process.getEnvVarOwned(allocator, "TEMP") catch ".";
    const log_path = std.fs.path.join(allocator, &.{ temp_path, "ghostty_debug.log" }) catch return;
    const name = std.unicode.utf8ToUtf16LeAllocZ(allocator, log_path) catch return;
    defer allocator.free(name);

    const h = CreateFileW(
        name.ptr,
        win32.GENERIC_WRITE,
        win32.FILE_SHARE_READ,
        null,
        win32.CREATE_ALWAYS,
        0,
        null,
    );
    if (h != win32.INVALID_HANDLE_VALUE) {
        _ = SetStdHandle(STD_ERROR_HANDLE, h);
    }
}
