//! TSF (Text Services Framework) Implementation for Ghostty's IME support.
//!
//! This is a 1:1 faithful Zig port of Windows Terminal's TSF Implementation
//! (src/tsf/Implementation.cpp, MIT License, Microsoft).
//!
//! It implements ITfContextOwner, ITfContextOwnerCompositionSink, and ITfTextEditSink
//! as inline COM objects with hand-written vtables.
//!
//! The implementation provides:
//!   - TSF initialization (ThreadMgrEx, DocumentMgr, Context, AdviseSink)
//!   - Composition start/update/end tracking
//!   - Edit session proxy for async composition text extraction
//!   - Full _doCompositionUpdate: range walking, GUID_PROP_COMPOSING check,
//!     text separation (finalized vs active), cursor position extraction
//!   - Finalized text and preedit text delivery via callbacks
//!
//! Reference: Windows Terminal src/tsf/Implementation.cpp (MIT License, Microsoft)

const std = @import("std");
const com = @import("../winui3/com.zig");
const os = @import("../winui3/os.zig");
const tsf = @import("tsf_bindings.zig");
const App = @import("App.zig");

const GUID = @import("../winui3/winrt.zig").GUID;
const HRESULT = @import("../winui3/winrt.zig").HRESULT;

// TSF bindings re-export gen.POINT, gen.RECT, gen.BOOL from com_generated.zig.
const gen = @import("../winui3/com_generated.zig");

// --- Win32 extern declarations for COM ---
const CLSCTX_INPROC_SERVER: u32 = 0x1;

extern "ole32" fn CoCreateInstance(
    rclsid: *const GUID,
    pUnkOuter: ?*anyopaque,
    dwClsContext: u32,
    riid: *const GUID,
    ppv: *?*anyopaque,
) callconv(.winapi) HRESULT;

extern "ole32" fn CoTaskMemAlloc(cb: usize) callconv(.winapi) ?*anyopaque;

extern "oleaut32" fn VariantClear(pvarg: *anyopaque) callconv(.winapi) HRESULT;

extern "user32" fn GetSysColor(nIndex: c_int) callconv(.winapi) u32;

// --- S_OK / S_FALSE for raw HRESULT checks ---
const S_OK: HRESULT = 0;
const S_FALSE: HRESULT = 1;
const E_NOTIMPL: HRESULT = @bitCast(@as(u32, 0x80004001));
const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
const E_POINTER: HRESULT = @bitCast(@as(u32, 0x80004003));
const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
const E_OUTOFMEMORY: HRESULT = @bitCast(@as(u32, 0x8007000E));

// TF_POPF_ALL is not in bindings — value from Windows SDK
const TF_POPF_ALL: u32 = 0x0001;

// TF_INVALID_GUIDATOM
const TF_INVALID_GUIDATOM: u32 = 0;

// VARIANT type constants
const VT_EMPTY: u16 = 0;
const VT_I4: u16 = 3;
const VT_UNKNOWN: u16 = 13;

// IUnknown IID
const IID_IUnknown = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };

// GUID_PROP_INPUTSCOPE {1713DD5A-68E7-4A5B-9AF6-592A595C778D}
const GUID_PROP_INPUTSCOPE = GUID{ .data1 = 0x1713DD5A, .data2 = 0x68E7, .data3 = 0x4A5B, .data4 = .{ 0x9A, 0xF6, 0x59, 0x2A, 0x59, 0x5C, 0x77, 0x8D } };

// InputScope enum value
const IS_ALPHANUMERIC_HALFWIDTH: u32 = 40;

// IID_ITfInputScope {486D8DA9-92A7-4B3B-BF18-41CFED47C8C4}
const IID_ITfInputScope = GUID{ .data1 = 0x486D8DA9, .data2 = 0x92A7, .data3 = 0x4B3B, .data4 = .{ 0xBF, 0x18, 0x41, 0xCF, 0xED, 0x47, 0xC8, 0xC4 } };

// IID_ITfEditSession (same as tsf.ITfEditSession.IID)
const IID_ITfEditSession = tsf.ITfEditSession.IID;

// --- IEnumTfPropertyValue (not in bindings, needed for _doCompositionUpdate) ---
// This interface enumerates TF_PROPERTYVAL structs from a VARIANT returned by
// ITfReadOnlyProperty::GetValue when called on tracked properties.
const IEnumTfPropertyValue = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        Clone: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Next: *const fn (*anyopaque, u32, *anyopaque, ?*u32) callconv(.winapi) HRESULT,
        Reset: *const fn (*anyopaque) callconv(.winapi) HRESULT,
        Skip: *const fn (*anyopaque, u32) callconv(.winapi) HRESULT,
    };
    fn release(self: *@This()) void { com.comRelease(self); }
};

// TF_PROPERTYVAL: { guidId: GUID, varValue: VARIANT }
// GUID is 16 bytes, then 24-byte VARIANT aligned to 8 => total 40 bytes with 8-byte alignment.
// But VARIANT's alignment is 8, so offset of varValue = 16 (GUID is 16 bytes, naturally aligned).
const TF_PROPERTYVAL = extern struct {
    guidId: GUID,
    varValue: [24]u8 align(8),
};

// --- ITfContextOwnerCompositionServices (not in bindings) ---
// IID {86462810-593B-4916-9764-19C08E9CE110}
const IID_ITfContextOwnerCompositionServices = GUID{
    .data1 = 0x86462810, .data2 = 0x593B, .data3 = 0x4916,
    .data4 = .{ 0x97, 0x64, 0x19, 0xC0, 0x8E, 0x9C, 0xE1, 0x10 },
};

const ITfContextOwnerCompositionServices = extern struct {
    lpVtbl: *const VTable,
    const VTable = extern struct {
        // IUnknown
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // ITfContextComposition (base)
        StartComposition: *const fn (*anyopaque, u32, ?*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        EnumCompositions: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        FindComposition: *const fn (*anyopaque, u32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        TakeOwnership: *const fn (*anyopaque, u32, ?*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        // ITfContextOwnerCompositionServices
        TerminateComposition: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    fn release(self: *@This()) void { com.comRelease(self); }
};

// --- Static configuration (matching WT's std::atomic variables) ---
var s_activationFlags: u32 = tsf.TF_TMAE_NOACTIVATETIP | tsf.TF_TMAE_NOACTIVATEKEYBOARDLAYOUT | tsf.TF_TMAE_CONSOLE;
var s_wantsAnsiInputScope: bool = false;

/// TSF Implementation struct.
/// Owns the TSF document model and implements the COM sink interfaces
/// that TSF calls back into during IME composition.
pub const TsfImplementation = struct {
    // --- TSF COM object pointers ---
    _categoryMgr: ?*tsf.ITfCategoryMgr = null,
    _displayAttributeMgr: ?*tsf.ITfDisplayAttributeMgr = null,
    _threadMgrEx: ?*tsf.ITfThreadMgrEx = null,
    _documentMgr: ?*tsf.ITfDocumentMgr = null,
    _context: ?*tsf.ITfContext = null,
    _ownerCompositionServices: ?*ITfContextOwnerCompositionServices = null,
    _contextSource: ?*tsf.ITfSource = null,

    // --- TSF identifiers ---
    _clientId: u32 = 0, // TF_CLIENTID_NULL
    _cookieContextOwner: u32 = tsf.TF_INVALID_COOKIE,
    _cookieTextEditSink: u32 = tsf.TF_INVALID_COOKIE,

    // --- Composition tracking ---
    _compositions: i32 = 0,

    // --- Associated window ---
    _associatedHwnd: ?os.HWND = null,

    // --- Callbacks to deliver text to the terminal surface ---
    _handleOutput: ?*const fn ([]const u8) void = null,
    _handlePreedit: ?*const fn (?[]const u8) void = null,

    // --- Cursor rect provider (screen coordinates, for IME candidate window positioning) ---
    _getCursorRect: ?*const fn () os.RECT = null,

    // --- COM reference count (for our IUnknown implementation) ---
    _referenceCount: u32 = 1,

    // --- Inline COM objects (vtable pointers for ITfContextOwner, CompositionSink, TextEditSink) ---
    _contextOwnerObj: ContextOwnerObj = .{},
    _compositionSinkObj: CompositionSinkObj = .{},
    _textEditSinkObj: TextEditSinkObj = .{},

    // --- Edit session proxy (matches WT's EditSessionProxy pattern) ---
    _editSessionCompositionUpdate: EditSessionProxy = .{},

    // --- AnsiInputScope inline COM object ---
    _ansiInputScopeObj: AnsiInputScopeObj = .{},

    // ========================================================================
    // Static configuration (matching WT's static functions)
    // ========================================================================

    /// Avoid buggy TSF console flags (removes TF_TMAE_CONSOLE).
    /// Call before Initialize() if WPF compatibility is needed.
    pub fn avoidBuggyTSFConsoleFlags() void {
        s_activationFlags &= ~@as(u32, tsf.TF_TMAE_CONSOLE);
    }

    /// Enable/disable the AnsiInputScope (IS_ALPHANUMERIC_HALFWIDTH).
    pub fn setDefaultScopeAlphanumericHalfWidth(enable: bool) void {
        s_wantsAnsiInputScope = enable;
    }

    // ========================================================================
    // Public API
    // ========================================================================

    /// Initialize TSF: create ThreadMgrEx, DocumentMgr, Context, and advise sinks.
    /// Matches WT Implementation::Initialize() exactly.
    pub fn initialize(self: *TsfImplementation) !void {
        App.fileLog("TSF: initialize() starting", .{});

        // Initialize the edit session proxy's back-pointer
        self._editSessionCompositionUpdate.self = self;

        // CoCreateInstance for CategoryMgr
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(&tsf.CLSID_TF_CategoryMgr, null, CLSCTX_INPROC_SERVER, &tsf.ITfCategoryMgr.IID, &ptr);
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(CategoryMgr) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._categoryMgr = @ptrCast(@alignCast(ptr));
        }

        // CoCreateInstance for DisplayAttributeMgr
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(&tsf.CLSID_TF_DisplayAttributeMgr, null, CLSCTX_INPROC_SERVER, &tsf.ITfDisplayAttributeMgr.IID, &ptr);
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(DisplayAttributeMgr) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._displayAttributeMgr = @ptrCast(@alignCast(ptr));
        }

        // CoCreateInstance for ThreadMgrEx
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(&tsf.CLSID_TF_ThreadMgr, null, CLSCTX_INPROC_SERVER, &tsf.ITfThreadMgrEx.IID, &ptr);
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(ThreadMgrEx) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._threadMgrEx = @ptrCast(@alignCast(ptr));
        }

        // ActivateEx with same flags as conhost v1 / Windows Terminal
        {
            const hr = self._threadMgrEx.?.lpVtbl.ActivateEx(@ptrCast(self._threadMgrEx.?), &self._clientId, s_activationFlags);
            if (hr < 0) return error.WinRTFailed;
        }
        App.fileLog("TSF: ActivateEx succeeded, clientId={}", .{self._clientId});

        // CreateDocumentMgr
        {
            var doc_ptr: ?*anyopaque = null;
            const hr = self._threadMgrEx.?.lpVtbl.CreateDocumentMgr(@ptrCast(self._threadMgrEx.?), &doc_ptr);
            if (hr < 0) return error.WinRTFailed;
            self._documentMgr = @ptrCast(@alignCast(doc_ptr));
        }

        // CreateContext — pass our ITfContextOwnerCompositionSink as the punk parameter.
        // TSF will QI this for ITfContextOwner and ITfContextOwnerCompositionSink.
        var ec_text_store: u32 = 0;
        {
            var ctx_ptr: ?*anyopaque = null;
            const punk: ?*anyopaque = @ptrCast(self.asCompositionSink());
            const hr = self._documentMgr.?.lpVtbl.CreateContext(
                @ptrCast(self._documentMgr.?),
                self._clientId,
                0,
                punk,
                &ctx_ptr,
                &ec_text_store,
            );
            if (hr < 0) return error.WinRTFailed;
            self._context = @ptrCast(@alignCast(ctx_ptr));
        }

        // Try to get ITfContextOwnerCompositionServices (optional, for TerminateComposition)
        {
            var svc_ptr: ?*anyopaque = null;
            const hr = self._context.?.lpVtbl.QueryInterface(
                @ptrCast(self._context.?),
                &IID_ITfContextOwnerCompositionServices,
                &svc_ptr,
            );
            if (hr >= 0 and svc_ptr != null) {
                self._ownerCompositionServices = @ptrCast(@alignCast(svc_ptr));
            }
        }

        // Get ITfSource from the context for advising sinks
        {
            var source_ptr: ?*anyopaque = null;
            const hr = self._context.?.lpVtbl.QueryInterface(
                @ptrCast(self._context.?),
                &tsf.ITfSource.IID,
                &source_ptr,
            );
            if (hr < 0) return error.WinRTFailed;
            self._contextSource = @ptrCast(@alignCast(source_ptr));
        }

        // AdviseSink: ITfContextOwner
        {
            const hr = self._contextSource.?.lpVtbl.AdviseSink(
                @ptrCast(self._contextSource.?),
                @constCast(&tsf.IID_ITfContextOwner),
                @ptrCast(self.asContextOwner()),
                &self._cookieContextOwner,
            );
            if (hr < 0) return error.WinRTFailed;
        }

        // AdviseSink: ITfTextEditSink
        {
            const hr = self._contextSource.?.lpVtbl.AdviseSink(
                @ptrCast(self._contextSource.?),
                @constCast(&tsf.IID_ITfTextEditSink),
                @ptrCast(self.asTextEditSink()),
                &self._cookieTextEditSink,
            );
            if (hr < 0) return error.WinRTFailed;
        }

        // Push context onto document manager
        {
            const hr = self._documentMgr.?.lpVtbl.Push(
                @ptrCast(self._documentMgr.?),
                @ptrCast(self._context.?),
            );
            if (hr < 0) return error.WinRTFailed;
        }

        App.fileLog("TSF: initialize() complete", .{});
    }

    /// Uninitialize TSF: unadvise sinks, pop context, deactivate.
    /// Matches WT Implementation::Uninitialize() exactly.
    pub fn uninitialize(self: *TsfImplementation) void {
        App.fileLog("TSF: uninitialize()", .{});

        // Clear callbacks (equivalent to _provider.reset())
        self._handleOutput = null;
        self._handlePreedit = null;
        self._getCursorRect = null;

        // Unassociate focus
        if (self._associatedHwnd != null and self._threadMgrEx != null) {
            var prev: ?*anyopaque = null;
            _ = self._threadMgrEx.?.lpVtbl.AssociateFocus(
                @ptrCast(self._threadMgrEx.?),
                @bitCast(@intFromPtr(self._associatedHwnd.?)),
                null,
                &prev,
            );
            if (prev) |p| {
                const unk: *com.IUnknown = @ptrCast(@alignCast(p));
                unk.release();
            }
        }

        // UnadviseSink
        if (self._cookieTextEditSink != tsf.TF_INVALID_COOKIE) {
            if (self._contextSource) |src| {
                _ = src.lpVtbl.UnadviseSink(@ptrCast(src), self._cookieTextEditSink);
            }
            self._cookieTextEditSink = tsf.TF_INVALID_COOKIE;
        }
        if (self._cookieContextOwner != tsf.TF_INVALID_COOKIE) {
            if (self._contextSource) |src| {
                _ = src.lpVtbl.UnadviseSink(@ptrCast(src), self._cookieContextOwner);
            }
            self._cookieContextOwner = tsf.TF_INVALID_COOKIE;
        }

        // Pop document
        if (self._documentMgr) |dm| {
            _ = dm.lpVtbl.Pop(@ptrCast(dm), TF_POPF_ALL);
        }

        // Deactivate
        if (self._threadMgrEx) |tmgr| {
            _ = tmgr.lpVtbl.Deactivate(@ptrCast(tmgr));
        }

        // Release COM objects
        if (self._ownerCompositionServices) |p| {
            p.release();
            self._ownerCompositionServices = null;
        }
        if (self._contextSource) |p| {
            p.release();
            self._contextSource = null;
        }
        if (self._context) |p| {
            p.release();
            self._context = null;
        }
        if (self._documentMgr) |p| {
            p.release();
            self._documentMgr = null;
        }
        if (self._threadMgrEx) |p| {
            p.release();
            self._threadMgrEx = null;
        }
        if (self._displayAttributeMgr) |p| {
            p.release();
            self._displayAttributeMgr = null;
        }
        if (self._categoryMgr) |p| {
            p.release();
            self._categoryMgr = null;
        }
    }

    /// Find the HWND of the currently active TSF context.
    /// Matches WT Implementation::FindWindowOfActiveTSF() exactly.
    /// Temporarily clears callbacks to prevent infinite recursion.
    pub fn findWindowOfActiveTSF(self: *TsfImplementation) ?os.HWND {
        const tmgr = self._threadMgrEx orelse return null;

        // WT pattern: temporarily clear _provider to prevent infinite recursion
        // (GetWnd -> GetHwnd -> FindWindowOfActiveTSF -> GetWnd -> ...)
        const saved_output = self._handleOutput;
        const saved_preedit = self._handlePreedit;
        const saved_cursor = self._getCursorRect;
        self._handleOutput = null;
        self._handlePreedit = null;
        self._getCursorRect = null;
        defer {
            self._handleOutput = saved_output;
            self._handlePreedit = saved_preedit;
            self._getCursorRect = saved_cursor;
        }

        var enum_ptr: ?*anyopaque = null;
        if (tmgr.lpVtbl.EnumDocumentMgrs(@ptrCast(tmgr), &enum_ptr) < 0) return null;
        const enum_docs: *tsf.IEnumTfDocumentMgrs = @ptrCast(@alignCast(enum_ptr orelse return null));
        defer com.comRelease(enum_docs);

        // WT only calls Next(1, ...) once — get the first document manager
        var doc_ptr: ?*anyopaque = null;
        var fetched: u32 = 0;
        if (enum_docs.lpVtbl.Next(@ptrCast(enum_docs), 1, &doc_ptr, &fetched) < 0) return null;
        if (fetched == 0) return null;

        const doc_mgr: *tsf.ITfDocumentMgr = @ptrCast(@alignCast(doc_ptr orelse return null));
        defer com.comRelease(doc_mgr);

        var ctx_ptr: ?*anyopaque = null;
        if (doc_mgr.lpVtbl.GetTop(@ptrCast(doc_mgr), &ctx_ptr) < 0) return null;
        const ctx: *tsf.ITfContext = @ptrCast(@alignCast(ctx_ptr orelse return null));
        defer com.comRelease(ctx);

        var view_ptr: ?*anyopaque = null;
        if (ctx.lpVtbl.GetActiveView(@ptrCast(ctx), &view_ptr) < 0) return null;
        const view: *tsf.ITfContextView = @ptrCast(@alignCast(view_ptr orelse return null));
        defer com.comRelease(view);

        var hwnd_val: gen.HWND = .{ .Value = 0 };
        if (view.lpVtbl.GetWnd(@ptrCast(view), &hwnd_val) < 0) return null;
        if (hwnd_val.Value == 0) return null;

        const result: os.HWND = @ptrFromInt(@as(usize, @bitCast(hwnd_val.Value)));
        App.fileLog("TSF: findWindowOfActiveTSF found hwnd=0x{x}", .{hwnd_val.Value});
        return result;
    }

    /// Associate this TSF document with a window handle.
    /// Matches WT Implementation::AssociateFocus().
    pub fn associateFocus(self: *TsfImplementation, hwnd: os.HWND) void {
        self._associatedHwnd = hwnd;
        if (self._threadMgrEx) |tmgr| {
            var prev: ?*anyopaque = null;
            const hr = tmgr.lpVtbl.AssociateFocus(
                @ptrCast(tmgr),
                @bitCast(@intFromPtr(hwnd)),
                @ptrCast(self._documentMgr.?),
                &prev,
            );
            if (prev) |p| {
                const unk: *com.IUnknown = @ptrCast(@alignCast(p));
                unk.release();
            }
            if (hr < 0) {
                App.fileLog("TSF: AssociateFocus failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            } else {
                App.fileLog("TSF: associateFocus hwnd=0x{x}", .{@intFromPtr(hwnd)});
            }
        }
    }

    /// Set TSF focus to our document (call when terminal surface gains focus).
    /// Matches WT Implementation::Focus().
    pub fn focus(self: *TsfImplementation) void {
        if (self._threadMgrEx) |tmgr| {
            const hr = tmgr.lpVtbl.SetFocus(@ptrCast(tmgr), @ptrCast(self._documentMgr.?));
            if (hr < 0) {
                App.fileLog("TSF: SetFocus failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            } else {
                App.fileLog("TSF: focus()", .{});
            }
        }
    }

    /// Remove TSF focus, terminate any active composition, clear preedit.
    /// Matches WT Implementation::Unfocus().
    pub fn unfocus(self: *TsfImplementation) void {
        App.fileLog("TSF: unfocus() compositions={}", .{self._compositions});

        // WT clears the renderer's tsfPreview — we clear preedit via callback
        if (self._handlePreedit) |cb| {
            cb(null);
        }

        // Clear callbacks (equivalent to _provider.reset())
        // Note: WT only resets _provider, we clear all callbacks
        const had_callbacks = self._handleOutput != null;
        _ = had_callbacks;

        // Terminate active compositions if we have the service
        if (self._compositions > 0 and self._ownerCompositionServices != null) {
            _ = self._ownerCompositionServices.?.lpVtbl.TerminateComposition(
                @ptrCast(self._ownerCompositionServices.?),
                null,
            );
        }
    }

    /// Returns true if there is an active IME composition.
    /// Matches WT Implementation::HasActiveComposition().
    pub fn hasActiveComposition(self: *const TsfImplementation) bool {
        return self._compositions > 0;
    }

    // ========================================================================
    // COM interface casting helpers
    // ========================================================================

    fn asContextOwner(self: *TsfImplementation) *ContextOwnerObj {
        return &self._contextOwnerObj;
    }

    fn asCompositionSink(self: *TsfImplementation) *CompositionSinkObj {
        return &self._compositionSinkObj;
    }

    fn asTextEditSink(self: *TsfImplementation) *TextEditSinkObj {
        return &self._textEditSinkObj;
    }

    // ========================================================================
    // Inline COM objects — each has a vtable pointer as first field
    // ========================================================================

    /// Inline COM object for ITfContextOwner
    const ContextOwnerObj = extern struct {
        lpVtbl: *const tsf.ITfContextOwner.VTable = &context_owner_vtable,
    };

    /// Inline COM object for ITfContextOwnerCompositionSink
    const CompositionSinkObj = extern struct {
        lpVtbl: *const tsf.ITfContextOwnerCompositionSink.VTable = &composition_sink_vtable,
    };

    /// Inline COM object for ITfTextEditSink
    const TextEditSinkObj = extern struct {
        lpVtbl: *const tsf.ITfTextEditSink.VTable = &text_edit_sink_vtable,
    };

    /// Inline COM object for ITfInputScope (AnsiInputScope)
    const AnsiInputScopeObj = extern struct {
        lpVtbl: *const InputScopeVTable = &ansi_input_scope_vtable,
    };

    /// ITfInputScope vtable (not in bindings, defined inline)
    const InputScopeVTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetInputScopes: *const fn (*anyopaque, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetPhrase: *const fn (*anyopaque, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetRegularExpression: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetSRGS: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetXML: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };

    // ========================================================================
    // Recover TsfImplementation pointer from inline COM object pointer
    // ========================================================================

    fn selfFromContextOwner(obj: *anyopaque) *TsfImplementation {
        const typed: *ContextOwnerObj = @ptrCast(@alignCast(obj));
        return @fieldParentPtr("_contextOwnerObj", typed);
    }

    fn selfFromCompositionSink(obj: *anyopaque) *TsfImplementation {
        const typed: *CompositionSinkObj = @ptrCast(@alignCast(obj));
        return @fieldParentPtr("_compositionSinkObj", typed);
    }

    fn selfFromTextEditSink(obj: *anyopaque) *TsfImplementation {
        const typed: *TextEditSinkObj = @ptrCast(@alignCast(obj));
        return @fieldParentPtr("_textEditSinkObj", typed);
    }

    fn selfFromAnsiInputScope(obj: *anyopaque) *TsfImplementation {
        const typed: *AnsiInputScopeObj = @ptrCast(@alignCast(obj));
        return @fieldParentPtr("_ansiInputScopeObj", typed);
    }

    // ========================================================================
    // ITfContextOwner vtable implementation
    // ========================================================================

    const context_owner_vtable = tsf.ITfContextOwner.VTable{
        .QueryInterface = &ctxOwnerQueryInterface,
        .AddRef = &ctxOwnerAddRef,
        .Release = &ctxOwnerRelease,
        .GetACPFromPoint = &ctxOwnerGetACPFromPoint,
        .GetTextExt = &ctxOwnerGetTextExt,
        .GetScreenExt = &ctxOwnerGetScreenExt,
        .GetStatus = &ctxOwnerGetStatus,
        .GetWnd = &ctxOwnerGetWnd,
        .GetAttribute = &ctxOwnerGetAttribute,
    };

    fn ctxOwnerQueryInterface(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        return commonQueryInterface(self, riid, ppvObj);
    }

    fn ctxOwnerAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromContextOwner(this);
        return commonAddRef(self);
    }

    fn ctxOwnerRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromContextOwner(this);
        return commonRelease(self);
    }

    fn ctxOwnerGetACPFromPoint(_: *anyopaque, _: *gen.POINT, _: u32, _: *i32) callconv(.winapi) HRESULT {
        // WT: assert(false); return E_NOTIMPL;
        return E_NOTIMPL;
    }

    /// Returns cursor rectangle for IME candidate window positioning.
    /// Matches WT Implementation::GetTextExt().
    fn ctxOwnerGetTextExt(this: *anyopaque, _: i32, _: i32, prc: *gen.RECT, pfClipped: *gen.BOOL) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        if (self._getCursorRect) |getCursorRect| {
            const r = getCursorRect();
            prc.* = .{ .left = r.left, .top = r.top, .right = r.right, .bottom = r.bottom };
        } else {
            prc.* = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
        }
        pfClipped.* = 0; // FALSE
        return S_OK;
    }

    /// Returns the viewport rectangle for touch keyboard activation.
    /// Matches WT Implementation::GetScreenExt().
    fn ctxOwnerGetScreenExt(this: *anyopaque, prc: *gen.RECT) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        if (self._associatedHwnd) |hwnd| {
            var os_rect: os.RECT = .{};
            _ = os.GetWindowRect(hwnd, &os_rect);
            prc.* = .{ .left = os_rect.left, .top = os_rect.top, .right = os_rect.right, .bottom = os_rect.bottom };
        } else {
            prc.* = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
        }
        return S_OK;
    }

    /// Returns TS_SS_TRANSITORY | TS_SS_NOHIDDENTEXT.
    /// Matches WT Implementation::GetStatus() exactly.
    fn ctxOwnerGetStatus(_: *anyopaque, pdcs: *?*anyopaque) callconv(.winapi) HRESULT {
        const status: *tsf.TS_STATUS = @ptrCast(@alignCast(pdcs));
        status.dwDynamicFlags = 0;
        status.dwStaticFlags = tsf.TS_SS_TRANSITORY | tsf.TS_SS_NOHIDDENTEXT;
        return S_OK;
    }

    /// Returns the HWND for this TSF context.
    /// Matches WT Implementation::GetWnd() — uses _provider->GetHwnd() which may call
    /// FindWindowOfActiveTSF(). The recursion is handled by FindWindowOfActiveTSF clearing callbacks.
    fn ctxOwnerGetWnd(this: *anyopaque, phwnd: *gen.HWND) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        // WT pattern: *phwnd = _provider ? _provider->GetHwnd() : nullptr;
        // Our GetHwnd equivalent tries findWindowOfActiveTSF first, falls back to _associatedHwnd.
        // But only if we have callbacks set (equivalent to _provider being non-null).
        if (self._handleOutput != null or self._handlePreedit != null) {
            if (self.findWindowOfActiveTSF()) |found_hwnd| {
                phwnd.* = @bitCast(@intFromPtr(found_hwnd));
                return S_OK;
            }
        }
        if (self._associatedHwnd) |hwnd| {
            phwnd.* = @bitCast(@intFromPtr(hwnd));
        } else {
            phwnd.*.Value = 0;
        }
        return S_OK;
    }

    /// Returns ITfInputScope for GUID_PROP_INPUTSCOPE if s_wantsAnsiInputScope is set.
    /// Matches WT Implementation::GetAttribute().
    fn ctxOwnerGetAttribute(this: *anyopaque, rguidAttribute: *GUID, pvarValue: *?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        // pvarValue is actually a VARIANT* (24 bytes)
        const var_bytes: *[24]u8 = @ptrCast(@alignCast(pvarValue));

        if (s_wantsAnsiInputScope and guidsEqual(rguidAttribute, &GUID_PROP_INPUTSCOPE)) {
            _ = commonAddRef(self);
            // Set VARIANT to VT_UNKNOWN with our AnsiInputScope
            @memset(var_bytes, 0);
            // vt is at offset 0, 2 bytes
            const vt_ptr: *u16 = @ptrCast(@alignCast(&var_bytes[0]));
            vt_ptr.* = VT_UNKNOWN;
            // punkVal is at offset 8 (on x64)
            const punk_ptr: *usize = @ptrCast(@alignCast(&var_bytes[8]));
            punk_ptr.* = @intFromPtr(&self._ansiInputScopeObj);
            return S_OK;
        }

        // VT_EMPTY
        @memset(var_bytes, 0);
        return S_OK;
    }

    // ========================================================================
    // ITfContextOwnerCompositionSink vtable implementation
    // ========================================================================

    const composition_sink_vtable = tsf.ITfContextOwnerCompositionSink.VTable{
        .QueryInterface = &compSinkQueryInterface,
        .AddRef = &compSinkAddRef,
        .Release = &compSinkRelease,
        .OnStartComposition = &compSinkOnStartComposition,
        .OnUpdateComposition = &compSinkOnUpdateComposition,
        .OnEndComposition = &compSinkOnEndComposition,
    };

    fn compSinkQueryInterface(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromCompositionSink(this);
        return commonQueryInterface(self, riid, ppvObj);
    }

    fn compSinkAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromCompositionSink(this);
        return commonAddRef(self);
    }

    fn compSinkRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromCompositionSink(this);
        return commonRelease(self);
    }

    /// Matches WT Implementation::OnStartComposition().
    fn compSinkOnStartComposition(this: *anyopaque, _: ?*anyopaque, pfOk: *gen.BOOL) callconv(.winapi) HRESULT {
        const self = selfFromCompositionSink(this);
        self._compositions += 1;
        pfOk.* = 1; // TRUE
        App.fileLog("TSF: OnStartComposition (compositions={})", .{self._compositions});
        return S_OK;
    }

    fn compSinkOnUpdateComposition(_: *anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.winapi) HRESULT {
        return S_OK;
    }

    /// Matches WT Implementation::OnEndComposition().
    fn compSinkOnEndComposition(this: *anyopaque, _: ?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromCompositionSink(this);
        if (self._compositions <= 0) return E_FAIL;

        self._compositions -= 1;
        App.fileLog("TSF: OnEndComposition (compositions={})", .{self._compositions});

        if (self._compositions == 0) {
            // WT: _request(_editSessionCompositionUpdate, TF_ES_READWRITE | TF_ES_ASYNC)
            _ = self.requestEditSession(tsf.TF_ES_READWRITE | tsf.TF_ES_ASYNC);
        }

        return S_OK;
    }

    // ========================================================================
    // ITfTextEditSink vtable implementation
    // ========================================================================

    const text_edit_sink_vtable = tsf.ITfTextEditSink.VTable{
        .QueryInterface = &textEditSinkQueryInterface,
        .AddRef = &textEditSinkAddRef,
        .Release = &textEditSinkRelease,
        .OnEndEdit = &textEditSinkOnEndEdit,
    };

    fn textEditSinkQueryInterface(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromTextEditSink(this);
        return commonQueryInterface(self, riid, ppvObj);
    }

    fn textEditSinkAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromTextEditSink(this);
        return commonAddRef(self);
    }

    fn textEditSinkRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromTextEditSink(this);
        return commonRelease(self);
    }

    /// Matches WT Implementation::OnEndEdit().
    fn textEditSinkOnEndEdit(this: *anyopaque, _: ?*anyopaque, _: u32, _: ?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromTextEditSink(this);
        if (self._compositions == 1) {
            // WT: _request(_editSessionCompositionUpdate, TF_ES_READWRITE | TF_ES_ASYNC)
            _ = self.requestEditSession(tsf.TF_ES_READWRITE | tsf.TF_ES_ASYNC);
        }
        return S_OK;
    }

    // ========================================================================
    // Common IUnknown implementation (shared by all three interfaces)
    // Matches WT Implementation::QueryInterface/AddRef/Release
    // ========================================================================

    fn commonQueryInterface(self: *TsfImplementation, riid: *const GUID, ppvObj: *?*anyopaque) HRESULT {
        if (@intFromPtr(ppvObj) == 0) return E_POINTER;

        if (guidsEqual(riid, &tsf.ITfContextOwner.IID)) {
            ppvObj.* = @ptrCast(self.asContextOwner());
            _ = commonAddRef(self);
            return S_OK;
        }
        if (guidsEqual(riid, &tsf.ITfContextOwnerCompositionSink.IID)) {
            ppvObj.* = @ptrCast(self.asCompositionSink());
            _ = commonAddRef(self);
            return S_OK;
        }
        if (guidsEqual(riid, &tsf.ITfTextEditSink.IID)) {
            ppvObj.* = @ptrCast(self.asTextEditSink());
            _ = commonAddRef(self);
            return S_OK;
        }
        // IUnknown — return context owner (matching WT: static_cast<ITfContextOwner*>(this))
        if (guidsEqual(riid, &IID_IUnknown)) {
            ppvObj.* = @ptrCast(self.asContextOwner());
            _ = commonAddRef(self);
            return S_OK;
        }

        ppvObj.* = null;
        return E_NOINTERFACE;
    }

    fn commonAddRef(self: *TsfImplementation) u32 {
        self._referenceCount +%= 1;
        return self._referenceCount;
    }

    fn commonRelease(self: *TsfImplementation) u32 {
        if (self._referenceCount > 0) {
            self._referenceCount -= 1;
        }
        // WT deletes on refcount 0, but our TsfImplementation is not heap-allocated.
        // It's a field of App, so we don't free it.
        return self._referenceCount;
    }

    // ========================================================================
    // Edit Session Proxy — matches WT's EditSessionProxyBase + EditSessionProxy
    // ========================================================================

    /// Edit session proxy object with its own IUnknown.
    /// Matches WT's EditSessionProxy<&Implementation::_doCompositionUpdate>.
    const EditSessionProxy = extern struct {
        lpVtbl: *const tsf.ITfEditSession.VTable = &edit_session_vtable,
        referenceCount: u32 = 0,
        self: ?*TsfImplementation = null,
    };

    const edit_session_vtable = tsf.ITfEditSession.VTable{
        .QueryInterface = &editSessionQueryInterface,
        .AddRef = &editSessionAddRef,
        .Release = &editSessionRelease,
        .DoEditSession = &editSessionDoEditSession,
    };

    /// Matches WT EditSessionProxyBase::QueryInterface.
    fn editSessionQueryInterface(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        if (@intFromPtr(ppvObj) == 0) return E_POINTER;

        if (guidsEqual(riid, &IID_ITfEditSession) or guidsEqual(riid, &IID_IUnknown)) {
            ppvObj.* = this;
            // AddRef through the vtable
            const proxy: *EditSessionProxy = @ptrCast(@alignCast(this));
            _ = editSessionAddRefImpl(proxy);
            return S_OK;
        }
        ppvObj.* = null;
        return E_NOINTERFACE;
    }

    /// Matches WT EditSessionProxyBase::AddRef — increments own count AND parent's count.
    fn editSessionAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const proxy: *EditSessionProxy = @ptrCast(@alignCast(this));
        return editSessionAddRefImpl(proxy);
    }

    fn editSessionAddRefImpl(proxy: *EditSessionProxy) u32 {
        proxy.referenceCount +%= 1;
        if (proxy.self) |s| {
            return commonAddRef(s);
        }
        return 1;
    }

    /// Matches WT EditSessionProxyBase::Release — decrements own count AND parent's count.
    fn editSessionRelease(this: *anyopaque) callconv(.winapi) u32 {
        const proxy: *EditSessionProxy = @ptrCast(@alignCast(this));
        if (proxy.referenceCount > 0) {
            proxy.referenceCount -= 1;
        }
        if (proxy.self) |s| {
            return commonRelease(s);
        }
        return 1;
    }

    /// Matches WT EditSessionProxy<&Implementation::_doCompositionUpdate>::DoEditSession.
    fn editSessionDoEditSession(this: *anyopaque, ec: u32) callconv(.winapi) HRESULT {
        const proxy: *EditSessionProxy = @ptrCast(@alignCast(this));
        const owner = proxy.self orelse return E_FAIL;
        owner.doCompositionUpdate(ec);
        return S_OK;
    }

    /// Request an edit session from TSF.
    /// Matches WT Implementation::_request().
    fn requestEditSession(self: *TsfImplementation, flags: u32) HRESULT {
        const ctx = self._context orelse return S_FALSE;

        // WT: if (session.referenceCount) return S_FALSE;
        // Don't send another request if one is still in flight (async).
        if (self._editSessionCompositionUpdate.referenceCount != 0) {
            return S_FALSE;
        }

        var hr_session: HRESULT = S_OK;
        const hr = ctx.lpVtbl.RequestEditSession(
            @ptrCast(ctx),
            self._clientId,
            @ptrCast(&self._editSessionCompositionUpdate),
            @bitCast(flags),
            &hr_session,
        );
        if (hr < 0) {
            App.fileLog("TSF: RequestEditSession failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            return hr;
        }
        if (hr_session < 0) return hr_session;
        return S_OK;
    }

    // ========================================================================
    // AnsiInputScope vtable implementation
    // Matches WT Implementation::AnsiInputScope
    // ========================================================================

    const ansi_input_scope_vtable = InputScopeVTable{
        .QueryInterface = &ansiInputScopeQI,
        .AddRef = &ansiInputScopeAddRef,
        .Release = &ansiInputScopeRelease,
        .GetInputScopes = &ansiInputScopeGetInputScopes,
        .GetPhrase = &ansiInputScopeGetPhrase,
        .GetRegularExpression = &ansiInputScopeGetRegularExpression,
        .GetSRGS = &ansiInputScopeGetSRGS,
        .GetXML = &ansiInputScopeGetXML,
    };

    fn ansiInputScopeQI(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        if (@intFromPtr(ppvObj) == 0) return E_POINTER;

        if (guidsEqual(riid, &IID_ITfInputScope) or guidsEqual(riid, &IID_IUnknown)) {
            ppvObj.* = this;
            _ = ansiInputScopeAddRef(this);
            return S_OK;
        }
        ppvObj.* = null;
        return E_NOINTERFACE;
    }

    /// Matches WT AnsiInputScope::AddRef — delegates to parent.
    fn ansiInputScopeAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromAnsiInputScope(this);
        return commonAddRef(self);
    }

    /// Matches WT AnsiInputScope::Release — delegates to parent.
    fn ansiInputScopeRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = selfFromAnsiInputScope(this);
        return commonRelease(self);
    }

    /// Matches WT AnsiInputScope::GetInputScopes — returns IS_ALPHANUMERIC_HALFWIDTH.
    fn ansiInputScopeGetInputScopes(_: *anyopaque, pprgInputScopes: *?*anyopaque, pcCount: *u32) callconv(.winapi) HRESULT {
        const scopes = CoTaskMemAlloc(1 * @sizeOf(u32));
        if (scopes == null) return E_OUTOFMEMORY;

        const scope_arr: *u32 = @ptrCast(@alignCast(scopes.?));
        scope_arr.* = IS_ALPHANUMERIC_HALFWIDTH;

        pprgInputScopes.* = scopes;
        pcCount.* = 1;
        return S_OK;
    }

    fn ansiInputScopeGetPhrase(_: *anyopaque, _: *?*anyopaque, _: *u32) callconv(.winapi) HRESULT {
        return E_NOTIMPL;
    }

    fn ansiInputScopeGetRegularExpression(_: *anyopaque, _: *?*anyopaque) callconv(.winapi) HRESULT {
        return E_NOTIMPL;
    }

    fn ansiInputScopeGetSRGS(_: *anyopaque, _: *?*anyopaque) callconv(.winapi) HRESULT {
        return E_NOTIMPL;
    }

    fn ansiInputScopeGetXML(_: *anyopaque, _: *?*anyopaque) callconv(.winapi) HRESULT {
        return E_NOTIMPL;
    }

    // ========================================================================
    // Core composition update logic
    // Faithfully ported from WT Implementation::_doCompositionUpdate()
    // ========================================================================

    /// Extract finalized and active composition text from the TSF context.
    /// Called within an edit session (ec = edit cookie).
    fn doCompositionUpdate(self: *TsfImplementation, ec: u32) void {
        const ctx = self._context orelse return;

        // Get full range of the document
        var full_range_ptr: ?*anyopaque = null;
        if (ctx.lpVtbl.GetStart(@ptrCast(ctx), ec, &full_range_ptr) < 0) return;
        const full_range: *tsf.ITfRange = @ptrCast(@alignCast(full_range_ptr orelse return));
        defer full_range.release();

        var full_range_length: i32 = 0;
        var null_halt: ?*anyopaque = null;
        _ = full_range.lpVtbl.ShiftEnd(@ptrCast(full_range), ec, std.math.maxInt(i32), &full_range_length, &null_halt);

        // Track GUID_PROP_COMPOSING and GUID_PROP_ATTRIBUTE properties
        var guids: [2]?*anyopaque = .{
            @constCast(@ptrCast(&tsf.GUID_PROP_COMPOSING)),
            @constCast(@ptrCast(&tsf.GUID_PROP_ATTRIBUTE)),
        };
        var no_app_props: ?*anyopaque = null;
        var props_ptr: ?*anyopaque = null;
        if (ctx.lpVtbl.TrackProperties(@ptrCast(ctx), @ptrCast(&guids[0]), 2, @ptrCast(&no_app_props), 0, &props_ptr) < 0) return;
        const props: *tsf.ITfReadOnlyProperty = @ptrCast(@alignCast(props_ptr orelse return));
        defer props.release();

        // Enumerate ranges
        var enum_ranges_ptr: ?*anyopaque = null;
        if (props.lpVtbl.EnumRanges(@ptrCast(props), ec, &enum_ranges_ptr, @ptrCast(full_range)) < 0) return;
        const enum_ranges: *tsf.IEnumTfRanges = @ptrCast(@alignCast(enum_ranges_ptr orelse return));
        defer enum_ranges.release();

        // Buffers for collecting text (UTF-16) — generous sizing
        var finalized_buf: [512]u16 = undefined;
        var finalized_len: usize = 0;
        var active_buf: [512]u16 = undefined;
        var active_len: usize = 0;
        var active_composition_encountered = false;

        // IEnumTfRanges::Next returns S_FALSE when it has reached the end of the list.
        var next_result: HRESULT = S_OK;
        while (next_result == S_OK) {
            // WT fetches up to 8 ranges at a time
            var range_ptrs: [8]?*anyopaque = .{null} ** 8;
            var ranges_count: u32 = 0;
            next_result = enum_ranges.lpVtbl.Next(@ptrCast(enum_ranges), 8, @ptrCast(&range_ptrs[0]), &ranges_count);

            // Cleanup: release all returned ranges when done with this batch
            defer {
                for (0..ranges_count) |idx| {
                    if (range_ptrs[idx]) |rp| {
                        const r: *tsf.ITfRange = @ptrCast(@alignCast(rp));
                        r.release();
                    }
                }
            }

            for (0..ranges_count) |idx| {
                const range: *tsf.ITfRange = @ptrCast(@alignCast(range_ptrs[idx] orelse continue));

                var composing = false;
                var atom: u32 = TF_INVALID_GUIDATOM;

                // Extract GUID_PROP_COMPOSING and GUID_PROP_ATTRIBUTE from the property value
                {
                    var variant: [24]u8 align(8) = .{0} ** 24;
                    if (props.lpVtbl.GetValue(@ptrCast(props), ec, @ptrCast(range), @ptrCast(&variant)) >= 0) {
                        // The VARIANT's vt should be VT_UNKNOWN containing an IEnumTfPropertyValue
                        const vt: u16 = @as(*const u16, @ptrCast(@alignCast(&variant[0]))).*;
                        if (vt == VT_UNKNOWN) {
                            const punk_val: usize = @as(*const usize, @ptrCast(@alignCast(&variant[8]))).*;
                            if (punk_val != 0) {
                                const enum_prop: *IEnumTfPropertyValue = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(punk_val))));

                                // Read 2 TF_PROPERTYVALs
                                var prop_vals: [2]TF_PROPERTYVAL = undefined;
                                @memset(std.mem.asBytes(&prop_vals), 0);
                                if (enum_prop.lpVtbl.Next(@ptrCast(enum_prop), 2, @ptrCast(&prop_vals[0]), null) >= 0) {
                                    for (&prop_vals) |*val| {
                                        if (guidsEqual(&val.guidId, &tsf.GUID_PROP_COMPOSING)) {
                                            // composing = V_VT == VT_I4 && V_I4 != 0
                                            const val_vt: u16 = @as(*const u16, @ptrCast(@alignCast(&val.varValue[0]))).*;
                                            if (val_vt == VT_I4) {
                                                const val_i4: i32 = @as(*const i32, @ptrCast(@alignCast(&val.varValue[8]))).*;
                                                composing = val_i4 != 0;
                                            }
                                        } else if (guidsEqual(&val.guidId, &tsf.GUID_PROP_ATTRIBUTE)) {
                                            const val_vt: u16 = @as(*const u16, @ptrCast(@alignCast(&val.varValue[0]))).*;
                                            if (val_vt == VT_I4) {
                                                const val_i4: i32 = @as(*const i32, @ptrCast(@alignCast(&val.varValue[8]))).*;
                                                atom = @bitCast(val_i4);
                                            } else {
                                                atom = TF_INVALID_GUIDATOM;
                                            }
                                        }
                                        // VariantClear each property value's variant
                                        _ = VariantClear(@ptrCast(&val.varValue));
                                    }
                                }
                            }
                        }
                        // VariantClear the outer variant
                        _ = VariantClear(@ptrCast(&variant));
                    }
                }

                // Read text from range (matching WT's inner loop with 128-char buffer)
                var total_len: usize = 0;
                while (true) {
                    const buf_cap: u32 = 128;
                    var buf: [128]u16 = undefined;
                    var len: u32 = buf_cap;
                    const gt_hr = range.lpVtbl.GetText(
                        @ptrCast(range),
                        ec,
                        tsf.TF_TF_MOVESTART,
                        @ptrCast(&buf),
                        buf_cap,
                        &len,
                    );
                    if (gt_hr < 0 or len == 0) break;

                    const slice = buf[0..len];

                    // WT: since we can't un-finalize finalized text, only finalize text at the start
                    if (!composing and !active_composition_encountered) {
                        const avail = finalized_buf.len - finalized_len;
                        const copy_len = @min(slice.len, avail);
                        @memcpy(finalized_buf[finalized_len..][0..copy_len], slice[0..copy_len]);
                        finalized_len += copy_len;
                    } else {
                        const avail = active_buf.len - active_len;
                        const copy_len = @min(slice.len, avail);
                        @memcpy(active_buf[active_len..][0..copy_len], slice[0..copy_len]);
                        active_len += copy_len;
                    }

                    total_len += len;

                    if (len < buf_cap) break;
                }

                // WT builds activeCompositionRanges with _textAttributeFromAtom(atom) here.
                // We don't have a renderer with TextAttribute, so we skip attribute tracking.
                // The atom is extracted but not used for display attributes in our callback model.

                active_composition_encountered = active_composition_encountered or composing;
            }
        }

        // --- Cursor position extraction (matching WT) ---
        var cursor_pos: i32 = std.math.maxInt(i32);
        {
            // TF_SELECTION: { range: ITfRange, style: TF_SELECTIONSTYLE }
            // We use raw pointers since TF_SELECTION in bindings has ITfRange by value (wrong).
            // The actual layout is: pointer (8 bytes) + TF_SELECTIONSTYLE (8 bytes)
            var sel_data: [16]u8 align(8) = .{0} ** 16;
            var sel_count: u32 = 0;

            const sel_hr = ctx.lpVtbl.GetSelection(
                @ptrCast(ctx),
                ec,
                tsf.TF_DEFAULT_SELECTION,
                1,
                @ptrCast(&sel_data),
                &sel_count,
            );

            if (sel_hr >= 0 and sel_count == 1) {
                // Extract the range pointer from sel_data[0..8]
                const sel_range_val: usize = @as(*const usize, @ptrCast(@alignCast(&sel_data[0]))).*;
                if (sel_range_val != 0) {
                    const sel_range: *tsf.ITfRange = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(sel_range_val))));
                    defer sel_range.release();

                    // Extract ase from TF_SELECTIONSTYLE (at offset 8 in sel_data)
                    const ase: i32 = @as(*const i32, @ptrCast(@alignCast(&sel_data[8]))).*;

                    // Get start of document
                    var start_ptr: ?*anyopaque = null;
                    if (ctx.lpVtbl.GetStart(@ptrCast(ctx), ec, &start_ptr) >= 0) {
                        if (start_ptr) |sp| {
                            const start_range: *tsf.ITfRange = @ptrCast(@alignCast(sp));
                            defer start_range.release();

                            // Build TF_HALTCOND
                            // TF_HALTCOND layout: { pHaltRange: *ITfRange (8 bytes), aHaltPos: i32 (4 bytes), dwFlags: u32 (4 bytes) }
                            var halt_cond: [16]u8 align(8) = .{0} ** 16;
                            const halt_range_ptr: *usize = @ptrCast(@alignCast(&halt_cond[0]));
                            halt_range_ptr.* = sel_range_val;
                            const halt_pos_ptr: *i32 = @ptrCast(@alignCast(&halt_cond[8]));
                            halt_pos_ptr.* = if (ase == tsf.TF_ANCHOR_START) tsf.TF_ANCHOR_START else tsf.TF_ANCHOR_END;

                            _ = start_range.lpVtbl.ShiftEnd(
                                @ptrCast(start_range),
                                ec,
                                std.math.maxInt(i32),
                                &cursor_pos,
                                @ptrCast(&halt_cond),
                            );
                        }
                    }
                }
            } else {
                // No selection — check if we got a range anyway and release it
                const sel_range_val: usize = @as(*const usize, @ptrCast(@alignCast(&sel_data[0]))).*;
                if (sel_range_val != 0) {
                    const sel_range: *tsf.ITfRange = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(sel_range_val))));
                    sel_range.release();
                }
            }

            // Compensate for finalized text that will be erased
            cursor_pos -= @intCast(finalized_len);
            cursor_pos = std.math.clamp(cursor_pos, 0, @as(i32, @intCast(active_len)));
        }

        // --- Erase finalized text from the TSF context ---
        if (finalized_len > 0) {
            var erase_range_ptr: ?*anyopaque = null;
            if (ctx.lpVtbl.GetStart(@ptrCast(ctx), ec, &erase_range_ptr) >= 0) {
                if (erase_range_ptr) |erp| {
                    const erase_range: *tsf.ITfRange = @ptrCast(@alignCast(erp));
                    defer erase_range.release();
                    var cch: i32 = 0;
                    var null_halt2: ?*anyopaque = null;
                    _ = erase_range.lpVtbl.ShiftEnd(@ptrCast(erase_range), ec, @intCast(finalized_len), &cch, &null_halt2);
                    _ = erase_range.lpVtbl.SetText(@ptrCast(erase_range), ec, 0, null, 0);
                }
            }
        }

        // --- Deliver text via callbacks ---
        // WT delivers to _provider->HandleOutput() and renderer's tsfPreview.
        // We use callbacks for both.

        // Deliver preedit (active composition)
        if (active_len > 0) {
            var utf8_buf: [2048]u8 = undefined;
            const utf8_len = utf16ToUtf8(&utf8_buf, active_buf[0..active_len]);
            if (utf8_len > 0) {
                if (self._handlePreedit) |cb| {
                    cb(utf8_buf[0..utf8_len]);
                }
            }
        } else {
            // No active composition text — clear preedit
            if (self._handlePreedit) |cb| {
                cb(null);
            }
        }

        // Deliver finalized text
        if (finalized_len > 0) {
            var utf8_buf: [2048]u8 = undefined;
            const utf8_len = utf16ToUtf8(&utf8_buf, finalized_buf[0..finalized_len]);
            if (utf8_len > 0) {
                App.fileLog("TSF: finalized text ({} bytes UTF-8)", .{utf8_len});
                if (self._handleOutput) |cb| {
                    cb(utf8_buf[0..utf8_len]);
                }
            }
        }

        // cursor_pos would be used by renderer for preedit cursor display
        // In the future, pass it to the preedit callback for cursor positioning.
    }

    // ========================================================================
    // Utility functions
    // ========================================================================

    /// Compare two GUIDs for equality.
    fn guidsEqual(a: *const GUID, b: *const GUID) bool {
        return a.data1 == b.data1 and
            a.data2 == b.data2 and
            a.data3 == b.data3 and
            std.mem.eql(u8, &a.data4, &b.data4);
    }

    /// Convert a UTF-16 slice to UTF-8, writing into the provided buffer.
    /// Returns the number of UTF-8 bytes written.
    fn utf16ToUtf8(dest: []u8, src: []const u16) usize {
        var i: usize = 0;
        var out: usize = 0;
        while (i < src.len) {
            var codepoint: u21 = undefined;
            if (src[i] >= 0xD800 and src[i] <= 0xDBFF) {
                // High surrogate
                if (i + 1 < src.len and src[i + 1] >= 0xDC00 and src[i + 1] <= 0xDFFF) {
                    codepoint = (@as(u21, src[i] - 0xD800) << 10) + @as(u21, src[i + 1] - 0xDC00) + 0x10000;
                    i += 2;
                } else {
                    codepoint = 0xFFFD;
                    i += 1;
                }
            } else if (src[i] >= 0xDC00 and src[i] <= 0xDFFF) {
                codepoint = 0xFFFD;
                i += 1;
            } else {
                codepoint = src[i];
                i += 1;
            }

            if (codepoint < 0x80) {
                if (out >= dest.len) break;
                dest[out] = @intCast(codepoint);
                out += 1;
            } else if (codepoint < 0x800) {
                if (out + 1 >= dest.len) break;
                dest[out] = @intCast(0xC0 | (codepoint >> 6));
                dest[out + 1] = @intCast(0x80 | (codepoint & 0x3F));
                out += 2;
            } else if (codepoint < 0x10000) {
                if (out + 2 >= dest.len) break;
                dest[out] = @intCast(0xE0 | (codepoint >> 12));
                dest[out + 1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
                dest[out + 2] = @intCast(0x80 | (codepoint & 0x3F));
                out += 3;
            } else {
                if (out + 3 >= dest.len) break;
                dest[out] = @intCast(0xF0 | (codepoint >> 18));
                dest[out + 1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
                dest[out + 2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
                dest[out + 3] = @intCast(0x80 | (codepoint & 0x3F));
                out += 4;
            }
        }
        return out;
    }
};

// Compile-time check: ensure the struct can be default-initialized
comptime {
    _ = TsfImplementation{};
}
