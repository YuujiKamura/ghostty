/// COM aggregation helpers for WinUI 3 Application runtime.
///
/// Contains InitCallback (Application.Start() delegate), AppOuter (COM aggregation
/// wrapper for IXamlMetadataProvider), and guidEql helper.
const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");
const log = std.log.scoped(.winui3);

// ---------------------------------------------------------------
// ApplicationInitializationCallback — WinRT delegate for Application.Start()
// IID: {D8EEF1C9-1234-56F1-9963-45DD9C80A661}
// WinMD blob: 01 00 C9 F1 EE D8 34 12 F1 56 99 63 45 DD 9C 80 A6 61 00 00
// vtable: IUnknown(0-2) + Invoke(3)
// ---------------------------------------------------------------

pub fn InitCallback(comptime AppType: type) type {
    return struct {
        /// COM-visible part — extern struct with lpVtbl at offset 0.
        com: Com,
        app: *AppType,
        ref_count: std.atomic.Value(u32),

        const Self = @This();

        const Com = extern struct {
            lpVtbl: *const VTable,

            const VTable = extern struct {
                QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
                AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
                Release: *const fn (*anyopaque) callconv(.winapi) u32,
                Invoke: *const fn (*anyopaque, *anyopaque) callconv(.winapi) winrt.HRESULT,
            };
        };

        const vtable_inst = Com.VTable{
            .QueryInterface = &qiFn,
            .AddRef = &addRefFn,
            .Release = &releaseFn,
            .Invoke = &invokeFn,
        };

        pub fn create(app: *AppType) Self {
            return .{
                .com = .{ .lpVtbl = &vtable_inst },
                .app = app,
                .ref_count = std.atomic.Value(u32).init(1),
            };
        }

        pub fn comPtr(self: *Self) *anyopaque {
            return @ptrCast(&self.com);
        }

        fn fromComPtr(ptr: *anyopaque) *Self {
            const com_ptr: *Com = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("com", com_ptr);
        }

        fn qiFn(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
            const IID_Self = winrt.GUID{ .data1 = 0xd8eef1c9, .data2 = 0x1234, .data3 = 0x56f1, .data4 = .{ 0x99, 0x63, 0x45, 0xdd, 0x9c, 0x80, 0xa6, 0x61 } };

            if (guidEql(riid, &winrt.IID_IUnknown) or guidEql(riid, &winrt.IID_IAgileObject) or guidEql(riid, &IID_Self)) {
                ppv.* = this;
                _ = addRefFn(this);
                return winrt.S_OK;
            }
            ppv.* = null;
            return winrt.E_NOINTERFACE;
        }

        fn addRefFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            return self.ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseFn(this: *anyopaque) callconv(.winapi) u32 {
            const self = fromComPtr(this);
            const prev = self.ref_count.fetchSub(1, .monotonic);
            return prev - 1;
        }

        fn invokeFn(this: *anyopaque, _: *anyopaque) callconv(.winapi) winrt.HRESULT {
            const self = fromComPtr(this);
            self.app.initXaml() catch |err| {
                log.err("initXaml failed in Application.Start callback: {}", .{err});
                return winrt.E_FAIL;
            };
            return winrt.S_OK;
        }
    };
}

pub fn guidEql(a: *const winrt.GUID, b: *const winrt.GUID) bool {
    return a.data1 == b.data1 and a.data2 == b.data2 and a.data3 == b.data3 and
        std.mem.eql(u8, &a.data4, &b.data4);
}

// ---------------------------------------------------------------
// AppOuter — COM aggregation wrapper for Application
//
// WinUI 3 custom controls (TabView, etc.) require their XAML templates to be
// loaded via XamlControlsResources. The XAML framework discovers these templates
// by calling IXamlMetadataProvider on the Application object. In normal C++/WinRT
// apps, the XAML compiler generates this. Without a XAML compiler, we must
// implement the COM aggregation pattern manually:
//
//   1. AppOuter acts as the "outer" (controlling) IUnknown
//   2. IApplicationFactory::CreateInstance receives AppOuter as outer
//   3. The WinRT Application becomes the "inner" (non-delegating) object
//   4. QI for IXamlMetadataProvider → AppOuter handles it, delegating to
//      an activated XamlControlsXamlMetaDataProvider instance
//   5. QI for anything else → delegates to inner
// ---------------------------------------------------------------

pub const AppOuter = struct {
    const TypeKind = enum(i32) {
        primitive = 0,
        metadata = 1,
        custom = 2,
    };

    const TypeName = extern struct {
        name: ?winrt.HSTRING,
        kind: TypeKind,
    };

    /// The COM-visible IUnknown vtable pointer — must be at offset 0.
    iunknown: IUnknownVtblPtr,
    /// The IXamlMetadataProvider vtable pointer — at offset 8.
    imetadata: IMetadataVtblPtr,
    /// Reference count. Must be atomic because we expose IXamlMetadataProvider
    /// to the XAML framework, which may call AddRef/Release from background
    /// threads during template resolution and layout.
    ref_count: std.atomic.Value(u32),
    /// The inner (non-delegating) IInspectable from Application.
    inner: ?*winrt.IInspectable,
    /// XamlControlsXamlMetaDataProvider instance for IXamlMetadataProvider delegation.
    provider: ?*com.IXamlMetadataProvider,

    const IUnknownVtblPtr = extern struct {
        lpVtbl: *const IUnknownVtbl,
    };
    const IUnknownVtbl = extern struct {
        QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };

    const IMetadataVtblPtr = extern struct {
        lpVtbl: *const IMetadataVtbl,
    };
    const IMetadataVtbl = extern struct {
        // IUnknown (slots 0-2) — delegating to outer
        QueryInterface: *const fn (*anyopaque, *const winrt.GUID, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IInspectable (slots 3-5)
        GetIids: *const fn (*anyopaque, *u32, *?[*]winrt.GUID) callconv(.winapi) winrt.HRESULT,
        GetRuntimeClassName: *const fn (*anyopaque, *?winrt.HSTRING) callconv(.winapi) winrt.HRESULT,
        GetTrustLevel: *const fn (*anyopaque, *u32) callconv(.winapi) winrt.HRESULT,
        // IXamlMetadataProvider (slots 6-8)
        GetXamlType: *const fn (*anyopaque, TypeName, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        GetXamlType_2: *const fn (*anyopaque, ?winrt.HSTRING, *?*anyopaque) callconv(.winapi) winrt.HRESULT,
        GetXmlnsDefinitions: *const fn (*anyopaque, *u32, *?[*]*anyopaque) callconv(.winapi) winrt.HRESULT,
    };

    const iunknown_vtable = IUnknownVtbl{
        .QueryInterface = &outerQueryInterface,
        .AddRef = &outerAddRef,
        .Release = &outerRelease,
    };

    const imetadata_vtable = IMetadataVtbl{
        .QueryInterface = &metadataQueryInterface,
        .AddRef = &metadataAddRef,
        .Release = &metadataRelease,
        .GetIids = &metadataGetIids,
        .GetRuntimeClassName = &metadataGetRuntimeClassName,
        .GetTrustLevel = &metadataGetTrustLevel,
        .GetXamlType = &metadataGetXamlType,
        .GetXamlType_2 = &metadataGetXamlType2,
        .GetXmlnsDefinitions = &metadataGetXmlnsDefinitions,
    };

    pub fn init(self: *AppOuter) void {
        self.* = .{
            .iunknown = .{ .lpVtbl = &iunknown_vtable },
            .imetadata = .{ .lpVtbl = &imetadata_vtable },
            .ref_count = std.atomic.Value(u32).init(1),
            .inner = null,
            .provider = null,
        };
    }

    pub fn deinit(self: *AppOuter) void {
        if (self.provider) |provider| {
            provider.release();
            self.provider = null;
        }
        if (self.inner) |inner| {
            _ = inner.release();
            self.inner = null;
        }
    }

    pub fn outerPtr(self: *AppOuter) *anyopaque {
        return @ptrCast(&self.iunknown);
    }

    fn fromIUnknownPtr(ptr: *anyopaque) *AppOuter {
        const p: *IUnknownVtblPtr = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iunknown", p);
    }

    fn fromIMetadataPtr(ptr: *anyopaque) *AppOuter {
        const p: *IMetadataVtblPtr = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("imetadata", p);
    }

    // --- Outer IUnknown (controlling unknown) ---

    fn outerQueryInterface(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIUnknownPtr(this);

        // Keep this on debug to avoid noisy startup logs in normal runs.
        log.debug("outerQI: iid={{{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}}} inner={}", .{
            riid.data1,    riid.data2,    riid.data3,
            riid.data4[0], riid.data4[1], riid.data4[2],
            riid.data4[3], riid.data4[4], riid.data4[5],
            riid.data4[6], riid.data4[7], @intFromPtr(self.inner),
        });

        // IXamlMetadataProvider → return our metadata interface
        if (guidEql(riid, &com.IXamlMetadataProvider.IID)) {
            log.debug("outerQI: -> IXamlMetadataProvider (handled by outer)", .{});
            ppv.* = @ptrCast(&self.imetadata);
            _ = outerAddRef(this);
            return winrt.S_OK;
        }

        // IUnknown / IAgileObject → return outer (the controlling unknown).
        // We intentionally claim IAgileObject here to avoid noisy E_NOINTERFACE
        // probes during WinUI startup; metadata methods still enforce safe fallback
        // behavior and never assume cross-thread provider access is mandatory.
        if (guidEql(riid, &winrt.IID_IUnknown) or guidEql(riid, &winrt.IID_IAgileObject)) {
            log.debug("outerQI: -> IUnknown (handled by outer)", .{});
            ppv.* = this;
            _ = outerAddRef(this);
            return winrt.S_OK;
        }

        // Everything else → delegate to inner (non-delegating QI)
        if (self.inner) |inner| {
            const hr = inner.lpVtbl.QueryInterface(@ptrCast(inner), riid, ppv);
            log.debug("outerQI: -> delegated to inner, hr=0x{x:0>8}", .{@as(u32, @bitCast(hr))});
            return hr;
        }

        ppv.* = null;
        log.debug("outerQI: -> NO INNER, returning E_NOINTERFACE", .{});
        return winrt.E_NOINTERFACE;
    }

    fn outerAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIUnknownPtr(this);
        const next = self.ref_count.fetchAdd(1, .monotonic) + 1;
        log.info(
            "lifetime: outerAddRef this=0x{x} ref={} inner=0x{x} provider=0x{x}",
            .{
                @intFromPtr(this),
                next,
                if (self.inner) |p| @intFromPtr(p) else @as(usize, 0),
                if (self.provider) |p| @intFromPtr(p) else @as(usize, 0),
            },
        );
        return next;
    }

    fn outerRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIUnknownPtr(this);
        const prev = self.ref_count.fetchSub(1, .monotonic);
        const next = prev - 1;
        log.info(
            "lifetime: outerRelease this=0x{x} ref={} -> {} inner=0x{x} provider=0x{x}",
            .{
                @intFromPtr(this),
                prev,
                next,
                if (self.inner) |p| @intFromPtr(p) else @as(usize, 0),
                if (self.provider) |p| @intFromPtr(p) else @as(usize, 0),
            },
        );
        if (next == 0) {
            log.warn("lifetime: outer refcount reached zero (AppOuter is stack-owned; explicit deinit handles inner/provider)", .{});
        }
        return next;
    }

    // --- IXamlMetadataProvider interface (delegating IUnknown to outer) ---

    fn metadataQueryInterface(this: *anyopaque, riid: *const winrt.GUID, ppv: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        return outerQueryInterface(@ptrCast(&self.iunknown), riid, ppv);
    }

    fn metadataAddRef(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIMetadataPtr(this);
        const next = outerAddRef(@ptrCast(&self.iunknown));
        log.info("lifetime: metadataAddRef this=0x{x} ref={}", .{ @intFromPtr(this), next });
        return next;
    }

    fn metadataRelease(this: *anyopaque) callconv(.winapi) u32 {
        const self = fromIMetadataPtr(this);
        const next = outerRelease(@ptrCast(&self.iunknown));
        log.info("lifetime: metadataRelease this=0x{x} ref={}", .{ @intFromPtr(this), next });
        return next;
    }

    fn metadataGetIids(_: *anyopaque, count: *u32, iids: *?[*]winrt.GUID) callconv(.winapi) winrt.HRESULT {
        count.* = 0;
        iids.* = null;
        return winrt.S_OK;
    }

    fn metadataGetRuntimeClassName(_: *anyopaque, name: *?winrt.HSTRING) callconv(.winapi) winrt.HRESULT {
        name.* = null;
        return winrt.S_OK;
    }

    fn metadataGetTrustLevel(_: *anyopaque, level: *u32) callconv(.winapi) winrt.HRESULT {
        level.* = 0; // BaseTrust
        return winrt.S_OK;
    }

    fn metadataGetXamlType(this: *anyopaque, type_name: TypeName, result: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        log.info("metadataGetXamlType called (slot 6, TypeName overload)", .{});
        const self = fromIMetadataPtr(this);
        result.* = null;
        if (self.provider) |provider| {
            // TypeName is 16 bytes on x64 -> passed via hidden pointer in Windows ABI.
            // The provider VTable expects ?*anyopaque (the hidden pointer), so pass &type_name.
            const hr = provider.lpVtbl.GetXamlType(@ptrCast(provider), @constCast(@ptrCast(&type_name)), result);
            const hr_u32: u32 = @bitCast(hr);
            if (hr_u32 == @as(u32, @bitCast(winrt.E_NOINTERFACE))) {
                log.warn("metadataGetXamlType: provider returned E_NOINTERFACE, using null-type fallback", .{});
                result.* = null;
                return winrt.S_OK;
            }
            log.info("metadataGetXamlType delegated, hr=0x{x}", .{hr_u32});
            return hr;
        }
        return winrt.S_OK; // return null IXamlType (type not found)
    }

    fn metadataGetXamlType2(this: *anyopaque, full_name: ?winrt.HSTRING, result: *?*anyopaque) callconv(.winapi) winrt.HRESULT {
        log.info("metadataGetXamlType2 called (slot 7, HSTRING overload)", .{});
        const self = fromIMetadataPtr(this);
        result.* = null;
        if (self.provider) |provider| {
            const hr = provider.lpVtbl.GetXamlType_2(@ptrCast(provider), full_name, result);
            const hr_u32: u32 = @bitCast(hr);
            if (hr_u32 == @as(u32, @bitCast(winrt.E_NOINTERFACE))) {
                log.warn("metadataGetXamlType2: provider returned E_NOINTERFACE, using null-type fallback", .{});
                result.* = null;
                return winrt.S_OK; // fallback contract
            }
            log.info("metadataGetXamlType2 delegated, hr=0x{x}", .{hr_u32});
            return hr;
        }
        return winrt.S_OK; // return null IXamlType (type not found)
    }

    fn metadataGetXmlnsDefinitions(this: *anyopaque, count: *u32, definitions: *?[*]*anyopaque) callconv(.winapi) winrt.HRESULT {
        const self = fromIMetadataPtr(this);
        if (self.provider) |provider| {
            // Cast *?[*]*anyopaque to *?*anyopaque to match VTable signature
            return provider.lpVtbl.GetXmlnsDefinitions(@ptrCast(provider), count, @ptrCast(definitions));
        }
        count.* = 0;
        definitions.* = null;
        return winrt.S_OK;
    }
};
