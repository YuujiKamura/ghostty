//! TSF (Text Services Framework) Implementation for Ghostty's IME support.
//!
//! This is a Zig port of Windows Terminal's TSF Implementation (src/tsf/Implementation.cpp).
//! It implements ITfContextOwner, ITfContextOwnerCompositionSink, and ITfTextEditSink
//! as COM objects using hand-written vtables — matching the ghostty-win COM pattern.
//!
//! The implementation provides:
//!   - TSF initialization (ThreadMgrEx, DocumentMgr, Context)
//!   - Composition start/update/end tracking
//!   - Edit session proxy for composition text extraction
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
// We use these for vtable callback signatures to match exactly.
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

extern "oleaut32" fn VariantClear(pvarg: *anyopaque) callconv(.winapi) HRESULT;

// --- S_OK / S_FALSE for raw HRESULT checks ---
const S_OK: HRESULT = 0;
const S_FALSE: HRESULT = 1;
const E_NOTIMPL: HRESULT = @bitCast(@as(u32, 0x80004001));
const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
const E_POINTER: HRESULT = @bitCast(@as(u32, 0x80004003));
const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));

// TF_POPF_ALL is not in bindings — value from Windows SDK
const TF_POPF_ALL: u32 = 0x0001;

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

    // --- Edit session proxy (must survive async callbacks, so stored as a field) ---
    _editSessionProxy: EditSessionProxy = undefined, // initialized in requestEditSession
    _editSessionInFlight: bool = false,

    // --- Inline COM objects (vtable pointers for ITfContextOwner, CompositionSink, TextEditSink) ---
    // Placed here so @fieldParentPtr can recover `self` from any of them.
    _contextOwnerObj: ContextOwnerObj = .{},
    _compositionSinkObj: CompositionSinkObj = .{},
    _textEditSinkObj: TextEditSinkObj = .{},

    // ========================================================================
    // Public API
    // ========================================================================

    /// Initialize TSF: create ThreadMgrEx, DocumentMgr, Context, and advise sinks.
    pub fn initialize(self: *TsfImplementation) !void {
        App.fileLog("TSF: initialize() starting", .{});

        // CoCreateInstance for CategoryMgr
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(
                &tsf.CLSID_TF_CategoryMgr,
                null,
                CLSCTX_INPROC_SERVER,
                &tsf.ITfCategoryMgr.IID,
                &ptr,
            );
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(CategoryMgr) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._categoryMgr = @ptrCast(@alignCast(ptr));
        }

        // CoCreateInstance for DisplayAttributeMgr
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(
                &tsf.CLSID_TF_DisplayAttributeMgr,
                null,
                CLSCTX_INPROC_SERVER,
                &tsf.ITfDisplayAttributeMgr.IID,
                &ptr,
            );
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(DisplayAttributeMgr) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._displayAttributeMgr = @ptrCast(@alignCast(ptr));
        }

        // CoCreateInstance for ThreadMgrEx
        {
            var ptr: ?*anyopaque = null;
            const hr = CoCreateInstance(
                &tsf.CLSID_TF_ThreadMgr,
                null,
                CLSCTX_INPROC_SERVER,
                &tsf.ITfThreadMgrEx.IID,
                &ptr,
            );
            if (hr < 0) {
                App.fileLog("TSF: CoCreateInstance(ThreadMgrEx) failed: 0x{x}", .{@as(u32, @bitCast(hr))});
                return error.WinRTFailed;
            }
            self._threadMgrEx = @ptrCast(@alignCast(ptr));
        }

        // ActivateEx with same flags as conhost v1 / Windows Terminal
        const activate_flags = tsf.TF_TMAE_NOACTIVATETIP | tsf.TF_TMAE_NOACTIVATEKEYBOARDLAYOUT | tsf.TF_TMAE_CONSOLE;
        try self._threadMgrEx.?.ActivateEx(&self._clientId, activate_flags);
        App.fileLog("TSF: ActivateEx succeeded, clientId={}", .{self._clientId});

        // CreateDocumentMgr
        {
            var doc_ptr: ?*anyopaque = null;
            try com.hrCheck(self._threadMgrEx.?.lpVtbl.CreateDocumentMgr(self._threadMgrEx.?, &doc_ptr));
            self._documentMgr = @ptrCast(@alignCast(doc_ptr));
        }

        // CreateContext — pass our ITfContextOwnerCompositionSink as the punk parameter.
        // TSF will QI this for ITfContextOwner and ITfContextOwnerCompositionSink.
        var ec_text_store: u32 = 0;
        {
            var ctx_ptr: ?*anyopaque = null;
            // We pass a pointer to our composition sink vtable as the IUnknown/punk parameter.
            // TSF will call QueryInterface on it to get ITfContextOwner, etc.
            const punk: ?*anyopaque = @ptrCast(self.asCompositionSink());
            try com.hrCheck(self._documentMgr.?.lpVtbl.CreateContext(
                self._documentMgr.?,
                self._clientId,
                0,
                punk,
                &ctx_ptr,
                &ec_text_store,
            ));
            self._context = @ptrCast(@alignCast(ctx_ptr));
        }
        // ec_text_store is set by CreateContext but not used further
        // (the edit cookie for AdviseSink is managed by TSF internally)

        // Get ITfSource from the context for advising sinks
        {
            var source_ptr: ?*anyopaque = null;
            try com.hrCheck(self._context.?.lpVtbl.QueryInterface(
                self._context.?,
                &tsf.ITfSource.IID,
                &source_ptr,
            ));
            self._contextSource = @ptrCast(@alignCast(source_ptr));
        }

        // AdviseSink: ITfContextOwner
        try com.hrCheck(self._contextSource.?.lpVtbl.AdviseSink(
            self._contextSource.?,
            @constCast(&tsf.IID_ITfContextOwner),
            @ptrCast(self.asContextOwner()),
            &self._cookieContextOwner,
        ));

        // AdviseSink: ITfTextEditSink
        try com.hrCheck(self._contextSource.?.lpVtbl.AdviseSink(
            self._contextSource.?,
            @constCast(&tsf.IID_ITfTextEditSink),
            @ptrCast(self.asTextEditSink()),
            &self._cookieTextEditSink,
        ));

        // Push context onto document manager
        try com.hrCheck(self._documentMgr.?.lpVtbl.Push(
            self._documentMgr.?,
            @ptrCast(self._context.?),
        ));

        App.fileLog("TSF: initialize() complete", .{});
    }

    /// Uninitialize TSF: unadvise sinks, pop context, deactivate.
    pub fn uninitialize(self: *TsfImplementation) void {
        App.fileLog("TSF: uninitialize()", .{});

        // Unassociate focus
        if (self._associatedHwnd != null and self._threadMgrEx != null) {
            var prev: ?*anyopaque = null;
            _ = self._threadMgrEx.?.lpVtbl.AssociateFocus(
                self._threadMgrEx.?,
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
                _ = src.lpVtbl.UnadviseSink(src, self._cookieTextEditSink);
            }
            self._cookieTextEditSink = tsf.TF_INVALID_COOKIE;
        }
        if (self._cookieContextOwner != tsf.TF_INVALID_COOKIE) {
            if (self._contextSource) |src| {
                _ = src.lpVtbl.UnadviseSink(src, self._cookieContextOwner);
            }
            self._cookieContextOwner = tsf.TF_INVALID_COOKIE;
        }

        // Pop document
        if (self._documentMgr) |dm| {
            _ = dm.lpVtbl.Pop(dm, TF_POPF_ALL);
        }

        // Deactivate
        if (self._threadMgrEx) |tmgr| {
            _ = tmgr.lpVtbl.Deactivate(tmgr);
        }

        // Release COM objects in reverse order
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

    /// Associate this TSF document with a window handle.
    pub fn associateFocus(self: *TsfImplementation, hwnd: os.HWND) void {
        self._associatedHwnd = hwnd;
        if (self._threadMgrEx) |tmgr| {
            var prev: ?*anyopaque = null;
            _ = tmgr.lpVtbl.AssociateFocus(
                tmgr,
                @bitCast(@intFromPtr(hwnd)),
                @ptrCast(self._documentMgr.?),
                &prev,
            );
            if (prev) |p| {
                const unk: *com.IUnknown = @ptrCast(@alignCast(p));
                unk.release();
            }
            App.fileLog("TSF: associateFocus hwnd=0x{x}", .{@intFromPtr(hwnd)});
        }
    }

    /// Set TSF focus to our document (call when terminal surface gains focus).
    pub fn focus(self: *TsfImplementation) void {
        if (self._threadMgrEx) |tmgr| {
            _ = tmgr.lpVtbl.SetFocus(tmgr, @ptrCast(self._documentMgr.?));
            App.fileLog("TSF: focus()", .{});
        }
    }

    /// Remove TSF focus, terminate any active composition, clear preedit.
    pub fn unfocus(self: *TsfImplementation) void {
        App.fileLog("TSF: unfocus() compositions={}", .{self._compositions});

        // Clear preedit display
        if (self._handlePreedit) |cb| {
            cb(null);
        }

        // Terminate active compositions
        if (self._compositions > 0) {
            // We don't have ITfContextOwnerCompositionServices in bindings,
            // so we rely on TSF cleaning up when we lose focus.
            // A future enhancement could QI for that interface.
            self._compositions = 0;
        }
    }

    /// Returns true if there is an active IME composition.
    pub fn hasActiveComposition(self: *const TsfImplementation) bool {
        return self._compositions > 0;
    }

    // ========================================================================
    // COM interface casting helpers
    // ========================================================================

    /// Get a pointer that looks like an ITfContextOwner COM object.
    /// We store a vtable pointer at a known offset from `self`.
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
        return E_NOTIMPL;
    }

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

    fn ctxOwnerGetStatus(_: *anyopaque, pdcs: *?*anyopaque) callconv(.winapi) HRESULT {
        // pdcs is actually a *TS_STATUS
        const status: *tsf.TS_STATUS = @ptrCast(@alignCast(pdcs));
        status.dwDynamicFlags = 0;
        // TS_SS_TRANSITORY is critical — see Windows Terminal Implementation.cpp for details.
        // Without it, TSF expects access to previously completed contents, which we can't provide.
        status.dwStaticFlags = tsf.TS_SS_TRANSITORY | tsf.TS_SS_NOHIDDENTEXT;
        return S_OK;
    }

    fn ctxOwnerGetWnd(this: *anyopaque, phwnd: *gen.HWND) callconv(.winapi) HRESULT {
        const self = selfFromContextOwner(this);
        if (self._associatedHwnd) |hwnd| {
            phwnd.* = @bitCast(@intFromPtr(hwnd));
        } else {
            phwnd.*.Value = 0;
        }
        return S_OK;
    }

    fn ctxOwnerGetAttribute(_: *anyopaque, _: *GUID, pvarValue: *?*anyopaque) callconv(.winapi) HRESULT {
        // pvarValue is actually a VARIANT* (24 bytes). Set VT_EMPTY by zeroing the VARIANT.
        const var_ptr: *tsf.VARIANT = @ptrCast(@alignCast(pvarValue));
        @memset(&var_ptr._data, 0);
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

    fn compSinkOnEndComposition(this: *anyopaque, _: ?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromCompositionSink(this);
        if (self._compositions <= 0) return E_FAIL;

        self._compositions -= 1;
        App.fileLog("TSF: OnEndComposition (compositions={})", .{self._compositions});

        if (self._compositions == 0) {
            // Request an async edit session to extract the finalized text.
            self.requestEditSession(tsf.TF_ES_READWRITE | tsf.TF_ES_ASYNC);
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

    fn textEditSinkOnEndEdit(this: *anyopaque, _: ?*anyopaque, _: u32, _: ?*anyopaque) callconv(.winapi) HRESULT {
        const self = selfFromTextEditSink(this);
        if (self._compositions == 1) {
            // During active composition, request edit session to update preedit.
            self.requestEditSession(tsf.TF_ES_READWRITE | tsf.TF_ES_ASYNC);
        }
        return S_OK;
    }

    // ========================================================================
    // Common IUnknown implementation (shared by all three interfaces)
    // ========================================================================

    fn commonQueryInterface(self: *TsfImplementation, riid: *const GUID, ppvObj: *?*anyopaque) HRESULT {
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
        // IUnknown — return our composition sink (arbitrary choice, just needs to be stable)
        const IID_IUnknown = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        if (guidsEqual(riid, &IID_IUnknown)) {
            ppvObj.* = @ptrCast(self.asCompositionSink());
            _ = commonAddRef(self);
            return S_OK;
        }

        ppvObj.* = null;
        return E_NOINTERFACE;
    }

    fn commonAddRef(self: *TsfImplementation) u32 {
        self._referenceCount += 1;
        return self._referenceCount;
    }

    fn commonRelease(self: *TsfImplementation) u32 {
        if (self._referenceCount > 0) {
            self._referenceCount -= 1;
        }
        return self._referenceCount;
    }

    // ========================================================================
    // Edit Session — ITfEditSession implementation
    // ========================================================================

    /// Stack-allocated proxy object that TSF calls DoEditSession on.
    const EditSessionProxy = extern struct {
        lpVtbl: *const tsf.ITfEditSession.VTable,
        owner: *TsfImplementation,
    };

    const edit_session_vtable = tsf.ITfEditSession.VTable{
        .QueryInterface = &editSessionQueryInterface,
        .AddRef = &editSessionAddRef,
        .Release = &editSessionRelease,
        .DoEditSession = &editSessionDoEditSession,
    };

    fn editSessionQueryInterface(this: *anyopaque, riid: *const GUID, ppvObj: *?*anyopaque) callconv(.winapi) HRESULT {
        const IID_IUnknown = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
        if (guidsEqual(riid, &tsf.ITfEditSession.IID) or guidsEqual(riid, &IID_IUnknown)) {
            ppvObj.* = this;
            return S_OK;
        }
        ppvObj.* = null;
        return E_NOINTERFACE;
    }

    fn editSessionAddRef(_: *anyopaque) callconv(.winapi) u32 {
        return 1; // Stack-allocated, no-op
    }

    fn editSessionRelease(_: *anyopaque) callconv(.winapi) u32 {
        return 1; // Stack-allocated, no-op
    }

    fn editSessionDoEditSession(this: *anyopaque, ec: u32) callconv(.winapi) HRESULT {
        const proxy: *EditSessionProxy = @ptrCast(@alignCast(this));
        const owner = proxy.owner;
        owner._editSessionInFlight = false;
        owner.doCompositionUpdate(ec);
        return S_OK;
    }

    /// Request an edit session from TSF.
    fn requestEditSession(self: *TsfImplementation, flags: u32) void {
        const ctx = self._context orelse return;

        // Don't send another request if one is still in flight (async).
        if (self._editSessionInFlight) return;

        // Initialize the proxy (stored as a field so it survives async callbacks)
        self._editSessionProxy = EditSessionProxy{
            .lpVtbl = &edit_session_vtable,
            .owner = self,
        };
        self._editSessionInFlight = true;

        var hr_session: HRESULT = S_OK;
        const hr = ctx.lpVtbl.RequestEditSession(
            ctx,
            self._clientId,
            @ptrCast(&self._editSessionProxy),
            @bitCast(flags),
            &hr_session,
        );
        if (hr < 0) {
            App.fileLog("TSF: RequestEditSession failed: 0x{x}", .{@as(u32, @bitCast(hr))});
            self._editSessionInFlight = false;
        }
    }

    // ========================================================================
    // Core composition update logic (ported from WT Implementation.cpp)
    // ========================================================================

    /// Extract finalized and active composition text from the TSF context.
    /// Called within an edit session (ec = edit cookie).
    fn doCompositionUpdate(self: *TsfImplementation, ec: u32) void {
        const ctx = self._context orelse return;

        // Get full range of the document
        var full_range_ptr: ?*anyopaque = null;
        if (ctx.lpVtbl.GetStart(ctx, ec, &full_range_ptr) < 0) return;
        const full_range: *tsf.ITfRange = @ptrCast(@alignCast(full_range_ptr orelse return));
        defer full_range.release();

        var full_range_length: i32 = 0;
        var null_halt: ?*anyopaque = null;
        _ = full_range.lpVtbl.ShiftEnd(full_range, ec, std.math.maxInt(i32), &full_range_length, &null_halt);

        // Track GUID_PROP_COMPOSING and GUID_PROP_ATTRIBUTE properties
        var guids: [2]?*anyopaque = .{
            @constCast(@ptrCast(&tsf.GUID_PROP_COMPOSING)),
            @constCast(@ptrCast(&tsf.GUID_PROP_ATTRIBUTE)),
        };
        var no_app_props: ?*anyopaque = null;
        var props_ptr: ?*anyopaque = null;
        if (ctx.lpVtbl.TrackProperties(ctx, @ptrCast(&guids[0]), 2, @ptrCast(&no_app_props), 0, &props_ptr) < 0) return;
        const props: *tsf.ITfReadOnlyProperty = @ptrCast(@alignCast(props_ptr orelse return));
        defer props.release();

        // Enumerate ranges
        var enum_ranges_ptr: ?*anyopaque = null;
        if (props.lpVtbl.EnumRanges(props, ec, &enum_ranges_ptr, @ptrCast(full_range)) < 0) return;
        const enum_ranges: *tsf.IEnumTfRanges = @ptrCast(@alignCast(enum_ranges_ptr orelse return));
        defer enum_ranges.release();

        // Buffers for collecting text (UTF-16)
        var finalized_buf: [512]u16 = undefined;
        var finalized_len: usize = 0;
        var active_buf: [512]u16 = undefined;
        var active_len: usize = 0;
        var active_composition_encountered = false;

        // Iterate over ranges
        var next_result: HRESULT = S_OK;
        while (next_result == S_OK) {
            var range_ptr: ?*anyopaque = null;
            var ranges_count: u32 = 0;
            next_result = enum_ranges.lpVtbl.Next(enum_ranges, 1, &range_ptr, &ranges_count);
            if (ranges_count == 0) break;

            const range: *tsf.ITfRange = @ptrCast(@alignCast(range_ptr orelse break));
            defer range.release();

            // Get property value for this range to determine if composing
            var composing = false;
            {
                // GetValue writes a VARIANT (24 bytes). Use a VARIANT-sized buffer.
                var variant: tsf.VARIANT = .{ ._data = [_]u8{0} ** 24 };
                if (props.lpVtbl.GetValue(props, ec, @ptrCast(range), @ptrCast(&variant)) >= 0) {
                    // The VARIANT contains an IUnknown (IEnumTfPropertyValue) with
                    // GUID_PROP_COMPOSING/GUID_PROP_ATTRIBUTE values.
                    // For this initial implementation, we use a simplified heuristic:
                    // if we have active compositions, treat all text as composing.
                    // A more complete implementation would extract the IEnumTfPropertyValue
                    // and check GUID_PROP_COMPOSING for each range.
                    composing = self._compositions > 0;

                    // Release the VARIANT's contained COM object via VariantClear.
                    _ = VariantClear(@ptrCast(&variant));
                }
            }

            // Read text from range
            var text_buf: [128]u16 = undefined;
            while (true) {
                var text_len: u32 = 128;
                const gt_hr = range.lpVtbl.GetText(
                    range,
                    ec,
                    tsf.TF_TF_MOVESTART,
                    @ptrCast(&text_buf),
                    128,
                    &text_len,
                );
                if (gt_hr < 0 or text_len == 0) break;

                const slice = text_buf[0..text_len];

                if (!composing and !active_composition_encountered) {
                    // Finalized text
                    const avail = finalized_buf.len - finalized_len;
                    const copy_len = @min(slice.len, avail);
                    @memcpy(finalized_buf[finalized_len..][0..copy_len], slice[0..copy_len]);
                    finalized_len += copy_len;
                } else {
                    // Active composition text
                    const avail = active_buf.len - active_len;
                    const copy_len = @min(slice.len, avail);
                    @memcpy(active_buf[active_len..][0..copy_len], slice[0..copy_len]);
                    active_len += copy_len;
                }

                if (text_len < 128) break;
            }
            if (composing) {
                active_composition_encountered = true;
            }
        }

        // Erase finalized text from the TSF context so it doesn't accumulate
        if (finalized_len > 0) {
            var erase_range_ptr: ?*anyopaque = null;
            if (ctx.lpVtbl.GetStart(ctx, ec, &erase_range_ptr) >= 0) {
                if (erase_range_ptr) |erp| {
                    const erase_range: *tsf.ITfRange = @ptrCast(@alignCast(erp));
                    defer erase_range.release();
                    var cch: i32 = 0;
                    var null_halt2: ?*anyopaque = null;
                    _ = erase_range.lpVtbl.ShiftEnd(erase_range, ec, @intCast(finalized_len), &cch, &null_halt2);
                    _ = erase_range.lpVtbl.SetText(erase_range, ec, 0, null, 0);
                }
            }
        }

        // Convert UTF-16 to UTF-8 and deliver via callbacks
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

        // Deliver preedit (active composition)
        if (active_len > 0) {
            var utf8_buf: [2048]u8 = undefined;
            const utf8_len = utf16ToUtf8(&utf8_buf, active_buf[0..active_len]);
            if (utf8_len > 0) {
                if (self._handlePreedit) |cb| {
                    cb(utf8_buf[0..utf8_len]);
                }
            }
        } else if (active_composition_encountered or self._compositions == 0) {
            // Composition ended with no active text — clear preedit
            if (self._handlePreedit) |cb| {
                cb(null);
            }
        }
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
                    codepoint = 0xFFFD; // replacement character
                    i += 1;
                }
            } else if (src[i] >= 0xDC00 and src[i] <= 0xDFFF) {
                codepoint = 0xFFFD;
                i += 1;
            } else {
                codepoint = src[i];
                i += 1;
            }

            // Encode codepoint as UTF-8
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
