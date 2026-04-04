//! --- WinRT Binding Provenance ---
//! Generator: win-zig-bindgen (master (WIP))
//! Primary WinMD: Windows.Win32.winmd (auto-generated from microsoft.windows.sdk.win32metadata)
//!   - SHA256: 6aec29be3359468d9eba03c3ae932591b39960f1812b6d25d33c0d9f14a6d665
//! Companion WinMD: Windows.winmd (Windows Kits UnionMetadata)
//!   - SHA256: e2dee80d011cb9fc1276a0bd9f244f7a58d5ca72fe906a56e90d61c68cf8601a
//! Companion WinMD: Microsoft.UI.winmd (microsoft.windowsappsdk)
//!   - SHA256: 8ebbf9ef154241f7e3faa07230050cae6acbb587943909111f02a5914ab2d3ed
//! Command: win-zig-bindgen --winmd Windows.Win32.winmd --deploy ghostty-win/src/font/dwrite_generated.zig --iface Windows.Win32.Graphics.DirectWrite.IDWriteFactory --iface Windows.Win32.Graphics.DirectWrite.IDWriteFactory2 --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontFallback --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontCollection --iface Windows.Win32.Graphics.DirectWrite.IDWriteFont --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontFamily --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontFace --iface Windows.Win32.Graphics.DirectWrite.IDWriteLocalizedStrings --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontFile --iface Windows.Win32.Graphics.DirectWrite.IDWriteTextAnalysisSource --iface Windows.Win32.Graphics.DirectWrite.IDWriteFontFileLoader --iface Windows.Win32.Graphics.DirectWrite.IDWriteLocalFontFileLoader
//! --------------------------------

//! WinUI 3 COM interface definitions for Zig.
//! GENERATED CODE - DO NOT EDIT.
const std = @import("std");
pub const GUID = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,

    pub fn equals(self: GUID, other: GUID) bool {
        return self.data1 == other.data1 and self.data2 == other.data2 and self.data3 == other.data3 and std.mem.eql(u8, &self.data4, &other.data4);
    }
};
pub const HRESULT = i32;
pub const BOOL = i32;
pub const FARPROC = ?*anyopaque;
pub const HSTRING = ?*anyopaque;
pub const HANDLE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HWND = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HINSTANCE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const HMODULE = extern struct {
    Value: isize,
    pub fn is_invalid(self: @This()) bool { return self.Value == 0 or self.Value == -1; }
};
pub const WPARAM = extern struct { Value: usize };
pub const LPARAM = extern struct { Value: isize };
pub const LPCWSTR = [*]const u16;
pub const LPWSTR = [*]u16;
pub const POINT = extern struct {
    x: i32,
    y: i32,
};
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};
pub const EventRegistrationToken = i64;

pub const VtblPlaceholder = ?*const anyopaque;

pub fn comRelease(self: anytype) void {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    _ = obj.lpVtbl.Release(@ptrCast(obj));
}

pub fn comQueryInterface(self: anytype, comptime T: type) !*T {
    const obj: *IUnknown = @ptrCast(@alignCast(self));
    var out: ?*anyopaque = null;
    const hr = obj.lpVtbl.QueryInterface(@ptrCast(obj), &T.IID, &out);
    if (hr < 0) return error.WinRTFailed;
    return @ptrCast(@alignCast(out.?));
}

pub fn hrCheck(hr: HRESULT) !void {
    if (hr < 0) return error.WinRTFailed;
}

pub fn isValidComPtr(ptr: usize) bool {
    if (ptr == 0 or ptr == 0xFFFFFFFF or ptr == 0xFFFFFFFFFFFFFFFF) return false;
    if (ptr < 0x10000) return false;
    return true;
}

pub const IUnknown = extern struct {
    pub const IID = GUID{ .data1 = 0x00000000, .data2 = 0x0000, .data3 = 0x0000, .data4 = .{ 0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};

pub const IInspectable = extern struct {
    pub const IID = GUID{ .data1 = 0xAFDBDF05, .data2 = 0x2D12, .data3 = 0x4D31, .data4 = .{ 0x84, 0x1F, 0x72, 0x71, 0x50, 0x51, 0x46, 0x46 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetIids: VtblPlaceholder,
        GetRuntimeClassName: VtblPlaceholder,
        GetTrustLevel: VtblPlaceholder,
    };
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
};
pub const IDWriteFactory = extern struct {
    pub const IID = GUID{ .data1 = 0xb859ee5a, .data2 = 0xd838, .data3 = 0x4b5b, .data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSystemFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        CreateCustomFontCollection: *const fn (*anyopaque, ?*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFileReference: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomFontFileReference: *const fn (*anyopaque, *void, u32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFace: *const fn (*anyopaque, i32, u32, *?*anyopaque, u32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateRenderingParams: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateMonitorRenderingParams: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams: *const fn (*anyopaque, f32, f32, f32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextFormat: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque, i32, i32, i32, f32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTypography: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetGdiInterop: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGdiCompatibleTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, f32, *?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateEllipsisTrimmingSign: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextAnalyzer: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateNumberSubstitution: *const fn (*anyopaque, i32, ?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGlyphRunAnalysis: *const fn (*anyopaque, *?*anyopaque, f32, *?*anyopaque, i32, i32, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getSystemFontCollection(self: *@This(), fontCollection: *?*anyopaque, checkForUpdates: BOOL) !void { try hrCheck(self.lpVtbl.GetSystemFontCollection(self, fontCollection, checkForUpdates)); }
    pub fn GetSystemFontCollection(self: *@This(), fontCollection: *?*anyopaque, checkForUpdates: BOOL) !void { try self.getSystemFontCollection(fontCollection, checkForUpdates); }
    pub fn createCustomFontCollection(self: *@This(), collectionLoader: ?*anyopaque, collectionKey: *void, collectionKeySize: u32, fontCollection: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateCustomFontCollection(self, collectionLoader, collectionKey, collectionKeySize, fontCollection)); }
    pub fn CreateCustomFontCollection(self: *@This(), collectionLoader: ?*anyopaque, collectionKey: *void, collectionKeySize: u32, fontCollection: *?*anyopaque) !void { try self.createCustomFontCollection(collectionLoader, collectionKey, collectionKeySize, fontCollection); }
    pub fn registerFontCollectionLoader(self: *@This(), fontCollectionLoader: ?*anyopaque) !void { try hrCheck(self.lpVtbl.RegisterFontCollectionLoader(self, fontCollectionLoader)); }
    pub fn RegisterFontCollectionLoader(self: *@This(), fontCollectionLoader: ?*anyopaque) !void { try self.registerFontCollectionLoader(fontCollectionLoader); }
    pub fn unregisterFontCollectionLoader(self: *@This(), fontCollectionLoader: ?*anyopaque) !void { try hrCheck(self.lpVtbl.UnregisterFontCollectionLoader(self, fontCollectionLoader)); }
    pub fn UnregisterFontCollectionLoader(self: *@This(), fontCollectionLoader: ?*anyopaque) !void { try self.unregisterFontCollectionLoader(fontCollectionLoader); }
    pub fn createFontFileReference(self: *@This(), filePath: ?*anyopaque, lastWriteTime: *?*anyopaque, fontFile: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFileReference(self, filePath, lastWriteTime, fontFile)); }
    pub fn CreateFontFileReference(self: *@This(), filePath: ?*anyopaque, lastWriteTime: *?*anyopaque, fontFile: *?*anyopaque) !void { try self.createFontFileReference(filePath, lastWriteTime, fontFile); }
    pub fn createCustomFontFileReference(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, fontFileLoader: ?*anyopaque, fontFile: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateCustomFontFileReference(self, fontFileReferenceKey, fontFileReferenceKeySize, fontFileLoader, fontFile)); }
    pub fn CreateCustomFontFileReference(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, fontFileLoader: ?*anyopaque, fontFile: *?*anyopaque) !void { try self.createCustomFontFileReference(fontFileReferenceKey, fontFileReferenceKeySize, fontFileLoader, fontFile); }
    pub fn createFontFace(self: *@This(), fontFaceType: i32, numberOfFiles: u32, fontFiles: *?*anyopaque, faceIndex: u32, fontFaceSimulationFlags: i32, fontFace: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFace(self, fontFaceType, numberOfFiles, fontFiles, faceIndex, fontFaceSimulationFlags, fontFace)); }
    pub fn CreateFontFace(self: *@This(), fontFaceType: i32, numberOfFiles: u32, fontFiles: *?*anyopaque, faceIndex: u32, fontFaceSimulationFlags: i32, fontFace: *?*anyopaque) !void { try self.createFontFace(fontFaceType, numberOfFiles, fontFiles, faceIndex, fontFaceSimulationFlags, fontFace); }
    pub fn createRenderingParams(self: *@This(), renderingParams: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateRenderingParams(self, renderingParams)); }
    pub fn CreateRenderingParams(self: *@This(), renderingParams: *?*anyopaque) !void { try self.createRenderingParams(renderingParams); }
    pub fn createMonitorRenderingParams(self: *@This(), monitor: ?*anyopaque, renderingParams: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateMonitorRenderingParams(self, monitor, renderingParams)); }
    pub fn CreateMonitorRenderingParams(self: *@This(), monitor: ?*anyopaque, renderingParams: *?*anyopaque) !void { try self.createMonitorRenderingParams(monitor, renderingParams); }
    pub fn createCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, renderingParams: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateCustomRenderingParams(self, gamma, enhancedContrast, clearTypeLevel, pixelGeometry, renderingMode, renderingParams)); }
    pub fn CreateCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, renderingParams: *?*anyopaque) !void { try self.createCustomRenderingParams(gamma, enhancedContrast, clearTypeLevel, pixelGeometry, renderingMode, renderingParams); }
    pub fn registerFontFileLoader(self: *@This(), fontFileLoader: ?*anyopaque) !void { try hrCheck(self.lpVtbl.RegisterFontFileLoader(self, fontFileLoader)); }
    pub fn RegisterFontFileLoader(self: *@This(), fontFileLoader: ?*anyopaque) !void { try self.registerFontFileLoader(fontFileLoader); }
    pub fn unregisterFontFileLoader(self: *@This(), fontFileLoader: ?*anyopaque) !void { try hrCheck(self.lpVtbl.UnregisterFontFileLoader(self, fontFileLoader)); }
    pub fn UnregisterFontFileLoader(self: *@This(), fontFileLoader: ?*anyopaque) !void { try self.unregisterFontFileLoader(fontFileLoader); }
    pub fn createTextFormat(self: *@This(), fontFamilyName: ?*anyopaque, fontCollection: ?*anyopaque, fontWeight: i32, fontStyle: i32, fontStretch: i32, fontSize: f32, localeName: ?*anyopaque, textFormat: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateTextFormat(self, fontFamilyName, fontCollection, fontWeight, fontStyle, fontStretch, fontSize, localeName, textFormat)); }
    pub fn CreateTextFormat(self: *@This(), fontFamilyName: ?*anyopaque, fontCollection: ?*anyopaque, fontWeight: i32, fontStyle: i32, fontStretch: i32, fontSize: f32, localeName: ?*anyopaque, textFormat: *?*anyopaque) !void { try self.createTextFormat(fontFamilyName, fontCollection, fontWeight, fontStyle, fontStretch, fontSize, localeName, textFormat); }
    pub fn createTypography(self: *@This(), typography: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateTypography(self, typography)); }
    pub fn CreateTypography(self: *@This(), typography: *?*anyopaque) !void { try self.createTypography(typography); }
    pub fn getGdiInterop(self: *@This(), gdiInterop: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetGdiInterop(self, gdiInterop)); }
    pub fn GetGdiInterop(self: *@This(), gdiInterop: *?*anyopaque) !void { try self.getGdiInterop(gdiInterop); }
    pub fn createTextLayout(self: *@This(), string: ?*anyopaque, stringLength: u32, textFormat: ?*anyopaque, maxWidth: f32, maxHeight: f32, textLayout: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateTextLayout(self, string, stringLength, textFormat, maxWidth, maxHeight, textLayout)); }
    pub fn CreateTextLayout(self: *@This(), string: ?*anyopaque, stringLength: u32, textFormat: ?*anyopaque, maxWidth: f32, maxHeight: f32, textLayout: *?*anyopaque) !void { try self.createTextLayout(string, stringLength, textFormat, maxWidth, maxHeight, textLayout); }
    pub fn createGdiCompatibleTextLayout(self: *@This(), string: ?*anyopaque, stringLength: u32, textFormat: ?*anyopaque, layoutWidth: f32, layoutHeight: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, textLayout: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateGdiCompatibleTextLayout(self, string, stringLength, textFormat, layoutWidth, layoutHeight, pixelsPerDip, transform, useGdiNatural, textLayout)); }
    pub fn CreateGdiCompatibleTextLayout(self: *@This(), string: ?*anyopaque, stringLength: u32, textFormat: ?*anyopaque, layoutWidth: f32, layoutHeight: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, textLayout: *?*anyopaque) !void { try self.createGdiCompatibleTextLayout(string, stringLength, textFormat, layoutWidth, layoutHeight, pixelsPerDip, transform, useGdiNatural, textLayout); }
    pub fn createEllipsisTrimmingSign(self: *@This(), textFormat: ?*anyopaque, trimmingSign: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateEllipsisTrimmingSign(self, textFormat, trimmingSign)); }
    pub fn CreateEllipsisTrimmingSign(self: *@This(), textFormat: ?*anyopaque, trimmingSign: *?*anyopaque) !void { try self.createEllipsisTrimmingSign(textFormat, trimmingSign); }
    pub fn createTextAnalyzer(self: *@This(), textAnalyzer: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateTextAnalyzer(self, textAnalyzer)); }
    pub fn CreateTextAnalyzer(self: *@This(), textAnalyzer: *?*anyopaque) !void { try self.createTextAnalyzer(textAnalyzer); }
    pub fn createNumberSubstitution(self: *@This(), substitutionMethod: i32, localeName: ?*anyopaque, ignoreUserOverride: BOOL, numberSubstitution: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateNumberSubstitution(self, substitutionMethod, localeName, ignoreUserOverride, numberSubstitution)); }
    pub fn CreateNumberSubstitution(self: *@This(), substitutionMethod: i32, localeName: ?*anyopaque, ignoreUserOverride: BOOL, numberSubstitution: *?*anyopaque) !void { try self.createNumberSubstitution(substitutionMethod, localeName, ignoreUserOverride, numberSubstitution); }
    pub fn createGlyphRunAnalysis(self: *@This(), glyphRun: *?*anyopaque, pixelsPerDip: f32, transform: *?*anyopaque, renderingMode: i32, measuringMode: i32, baselineOriginX: f32, baselineOriginY: f32, glyphRunAnalysis: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateGlyphRunAnalysis(self, glyphRun, pixelsPerDip, transform, renderingMode, measuringMode, baselineOriginX, baselineOriginY, glyphRunAnalysis)); }
    pub fn CreateGlyphRunAnalysis(self: *@This(), glyphRun: *?*anyopaque, pixelsPerDip: f32, transform: *?*anyopaque, renderingMode: i32, measuringMode: i32, baselineOriginX: f32, baselineOriginY: f32, glyphRunAnalysis: *?*anyopaque) !void { try self.createGlyphRunAnalysis(glyphRun, pixelsPerDip, transform, renderingMode, measuringMode, baselineOriginX, baselineOriginY, glyphRunAnalysis); }
};

pub const IDWriteFactory2 = extern struct {
    pub const IID = GUID{ .data1 = 0x0439fc60, .data2 = 0xca44, .data3 = 0x4994, .data4 = .{ 0x8d, 0xee, 0x3a, 0x9a, 0xf7, 0xb7, 0x32, 0xec } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSystemFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        CreateCustomFontCollection: *const fn (*anyopaque, ?*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFileReference: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomFontFileReference: *const fn (*anyopaque, *void, u32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFace: *const fn (*anyopaque, i32, u32, *?*anyopaque, u32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateRenderingParams: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateMonitorRenderingParams: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams: *const fn (*anyopaque, f32, f32, f32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextFormat: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque, i32, i32, i32, f32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTypography: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetGdiInterop: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGdiCompatibleTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, f32, *?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateEllipsisTrimmingSign: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextAnalyzer: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateNumberSubstitution: *const fn (*anyopaque, i32, ?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGlyphRunAnalysis: *const fn (*anyopaque, *?*anyopaque, f32, *?*anyopaque, i32, i32, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetEudcFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams_2: *const fn (*anyopaque, f32, f32, f32, f32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetSystemFontFallback: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFallbackBuilder: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        TranslateColorGlyphRun: *const fn (*anyopaque, f32, f32, *?*anyopaque, *?*anyopaque, i32, *?*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams_3: *const fn (*anyopaque, f32, f32, f32, f32, i32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGlyphRunAnalysis_2: *const fn (*anyopaque, *?*anyopaque, *?*anyopaque, i32, i32, i32, i32, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWriteFactory1 = true; // requires IDWriteFactory1
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getSystemFontFallback(self: *@This(), fontFallback: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetSystemFontFallback(self, fontFallback)); }
    pub fn GetSystemFontFallback(self: *@This(), fontFallback: *?*anyopaque) !void { try self.getSystemFontFallback(fontFallback); }
    pub fn createFontFallbackBuilder(self: *@This(), fontFallbackBuilder: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFallbackBuilder(self, fontFallbackBuilder)); }
    pub fn CreateFontFallbackBuilder(self: *@This(), fontFallbackBuilder: *?*anyopaque) !void { try self.createFontFallbackBuilder(fontFallbackBuilder); }
    pub fn translateColorGlyphRun(self: *@This(), baselineOriginX: f32, baselineOriginY: f32, glyphRun: *?*anyopaque, glyphRunDescription: *?*anyopaque, measuringMode: i32, worldToDeviceTransform: *?*anyopaque, colorPaletteIndex: u32, colorLayers: *?*anyopaque) !void { try hrCheck(self.lpVtbl.TranslateColorGlyphRun(self, baselineOriginX, baselineOriginY, glyphRun, glyphRunDescription, measuringMode, worldToDeviceTransform, colorPaletteIndex, colorLayers)); }
    pub fn TranslateColorGlyphRun(self: *@This(), baselineOriginX: f32, baselineOriginY: f32, glyphRun: *?*anyopaque, glyphRunDescription: *?*anyopaque, measuringMode: i32, worldToDeviceTransform: *?*anyopaque, colorPaletteIndex: u32, colorLayers: *?*anyopaque) !void { try self.translateColorGlyphRun(baselineOriginX, baselineOriginY, glyphRun, glyphRunDescription, measuringMode, worldToDeviceTransform, colorPaletteIndex, colorLayers); }
    pub fn createCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, grayscaleEnhancedContrast: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, gridFitMode: i32, renderingParams: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateCustomRenderingParams(self, gamma, enhancedContrast, grayscaleEnhancedContrast, clearTypeLevel, pixelGeometry, renderingMode, gridFitMode, renderingParams)); }
    pub fn CreateCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, grayscaleEnhancedContrast: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, gridFitMode: i32, renderingParams: *?*anyopaque) !void { try self.createCustomRenderingParams(gamma, enhancedContrast, grayscaleEnhancedContrast, clearTypeLevel, pixelGeometry, renderingMode, gridFitMode, renderingParams); }
    pub fn createGlyphRunAnalysis(self: *@This(), glyphRun: *?*anyopaque, transform: *?*anyopaque, renderingMode: i32, measuringMode: i32, gridFitMode: i32, antialiasMode: i32, baselineOriginX: f32, baselineOriginY: f32, glyphRunAnalysis: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateGlyphRunAnalysis(self, glyphRun, transform, renderingMode, measuringMode, gridFitMode, antialiasMode, baselineOriginX, baselineOriginY, glyphRunAnalysis)); }
    pub fn CreateGlyphRunAnalysis(self: *@This(), glyphRun: *?*anyopaque, transform: *?*anyopaque, renderingMode: i32, measuringMode: i32, gridFitMode: i32, antialiasMode: i32, baselineOriginX: f32, baselineOriginY: f32, glyphRunAnalysis: *?*anyopaque) !void { try self.createGlyphRunAnalysis(glyphRun, transform, renderingMode, measuringMode, gridFitMode, antialiasMode, baselineOriginX, baselineOriginY, glyphRunAnalysis); }
};

pub const IDWriteFontFallback = extern struct {
    pub const IID = GUID{ .data1 = 0xefa008f9, .data2 = 0xf7a1, .data3 = 0x48bf, .data4 = .{ 0xb0, 0x5c, 0xf2, 0x24, 0x71, 0x3c, 0xc0, 0xff } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        MapCharacters: *const fn (*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque, ?*anyopaque, i32, i32, i32, *u32, *?*anyopaque, *f32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn mapCharacters(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, baseFontCollection: ?*anyopaque, baseFamilyName: ?*anyopaque, baseWeight: i32, baseStyle: i32, baseStretch: i32, mappedLength: *u32, mappedFont: *?*anyopaque, scale: *f32) !void { try hrCheck(self.lpVtbl.MapCharacters(self, analysisSource, textPosition, textLength, baseFontCollection, baseFamilyName, baseWeight, baseStyle, baseStretch, mappedLength, mappedFont, scale)); }
    pub fn MapCharacters(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, baseFontCollection: ?*anyopaque, baseFamilyName: ?*anyopaque, baseWeight: i32, baseStyle: i32, baseStretch: i32, mappedLength: *u32, mappedFont: *?*anyopaque, scale: *f32) !void { try self.mapCharacters(analysisSource, textPosition, textLength, baseFontCollection, baseFamilyName, baseWeight, baseStyle, baseStretch, mappedLength, mappedFont, scale); }
};

pub const IDWriteFontCollection = extern struct {
    pub const IID = GUID{ .data1 = 0xa84cee02, .data2 = 0x3eea, .data3 = 0x4eee, .data4 = .{ 0xa8, 0x27, 0x87, 0xc1, 0xa0, 0x2a, 0x0f, 0xcc } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamilyCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamily: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        FindFamilyName: *const fn (*anyopaque, ?*anyopaque, *u32, *BOOL) callconv(.winapi) HRESULT,
        GetFontFromFontFace: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getFontFamilyCount(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontFamilyCount(self)); }
    pub fn GetFontFamilyCount(self: *@This()) !void { try self.getFontFamilyCount(); }
    pub fn getFontFamily(self: *@This(), index: u32, fontFamily: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFamily(self, index, fontFamily)); }
    pub fn GetFontFamily(self: *@This(), index: u32, fontFamily: *?*anyopaque) !void { try self.getFontFamily(index, fontFamily); }
    pub fn findFamilyName(self: *@This(), familyName: ?*anyopaque, index: *u32, exists: *BOOL) !void { try hrCheck(self.lpVtbl.FindFamilyName(self, familyName, index, exists)); }
    pub fn FindFamilyName(self: *@This(), familyName: ?*anyopaque, index: *u32, exists: *BOOL) !void { try self.findFamilyName(familyName, index, exists); }
    pub fn getFontFromFontFace(self: *@This(), fontFace: ?*anyopaque, font: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFromFontFace(self, fontFace, font)); }
    pub fn GetFontFromFontFace(self: *@This(), fontFace: ?*anyopaque, font: *?*anyopaque) !void { try self.getFontFromFontFace(fontFace, font); }
};

pub const IDWriteFont = extern struct {
    pub const IID = GUID{ .data1 = 0xacd16696, .data2 = 0x8c14, .data3 = 0x4f5d, .data4 = .{ 0x87, 0x7e, 0xfe, 0x3f, 0xc1, 0xd3, 0x27, 0x37 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamily: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetWeight: *const fn (*anyopaque) callconv(.winapi) i32,
        GetStretch: *const fn (*anyopaque) callconv(.winapi) i32,
        GetStyle: *const fn (*anyopaque) callconv(.winapi) i32,
        IsSymbolFont: *const fn (*anyopaque) callconv(.winapi) BOOL,
        GetFaceNames: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetInformationalStrings: *const fn (*anyopaque, i32, *?*anyopaque, *BOOL) callconv(.winapi) HRESULT,
        GetSimulations: *const fn (*anyopaque) callconv(.winapi) i32,
        GetMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) void,
        HasCharacter: *const fn (*anyopaque, u32, *BOOL) callconv(.winapi) HRESULT,
        CreateFontFace: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getFontFamily(self: *@This(), fontFamily: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFamily(self, fontFamily)); }
    pub fn GetFontFamily(self: *@This(), fontFamily: *?*anyopaque) !void { try self.getFontFamily(fontFamily); }
    pub fn getWeight(self: *@This()) !void { try hrCheck(self.lpVtbl.GetWeight(self)); }
    pub fn GetWeight(self: *@This()) !void { try self.getWeight(); }
    pub fn getStretch(self: *@This()) !void { try hrCheck(self.lpVtbl.GetStretch(self)); }
    pub fn GetStretch(self: *@This()) !void { try self.getStretch(); }
    pub fn getStyle(self: *@This()) !void { try hrCheck(self.lpVtbl.GetStyle(self)); }
    pub fn GetStyle(self: *@This()) !void { try self.getStyle(); }
    pub fn isSymbolFont(self: *@This()) !void { try hrCheck(self.lpVtbl.IsSymbolFont(self)); }
    pub fn IsSymbolFont(self: *@This()) !void { try self.isSymbolFont(); }
    pub fn getFaceNames(self: *@This(), names: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFaceNames(self, names)); }
    pub fn GetFaceNames(self: *@This(), names: *?*anyopaque) !void { try self.getFaceNames(names); }
    pub fn getInformationalStrings(self: *@This(), informationalStringID: i32, informationalStrings: *?*anyopaque, exists: *BOOL) !void { try hrCheck(self.lpVtbl.GetInformationalStrings(self, informationalStringID, informationalStrings, exists)); }
    pub fn GetInformationalStrings(self: *@This(), informationalStringID: i32, informationalStrings: *?*anyopaque, exists: *BOOL) !void { try self.getInformationalStrings(informationalStringID, informationalStrings, exists); }
    pub fn getSimulations(self: *@This()) !void { try hrCheck(self.lpVtbl.GetSimulations(self)); }
    pub fn GetSimulations(self: *@This()) !void { try self.getSimulations(); }
    pub fn getMetrics(self: *@This(), fontMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetMetrics(self, fontMetrics)); }
    pub fn GetMetrics(self: *@This(), fontMetrics: *?*anyopaque) !void { try self.getMetrics(fontMetrics); }
    pub fn hasCharacter(self: *@This(), unicodeValue: u32, exists: *BOOL) !void { try hrCheck(self.lpVtbl.HasCharacter(self, unicodeValue, exists)); }
    pub fn HasCharacter(self: *@This(), unicodeValue: u32, exists: *BOOL) !void { try self.hasCharacter(unicodeValue, exists); }
    pub fn createFontFace(self: *@This(), fontFace: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFace(self, fontFace)); }
    pub fn CreateFontFace(self: *@This(), fontFace: *?*anyopaque) !void { try self.createFontFace(fontFace); }
};

pub const IDWriteFontFamily = extern struct {
    pub const IID = GUID{ .data1 = 0xda20d8ef, .data2 = 0x812a, .data3 = 0x4c43, .data4 = .{ 0x98, 0x02, 0x62, 0xec, 0x4a, 0xbd, 0x7a, 0xdd } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontCollection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFont: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFamilyNames: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFirstMatchingFont: *const fn (*anyopaque, i32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetMatchingFonts: *const fn (*anyopaque, i32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWriteFontList = true; // requires IDWriteFontList
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn GetFontCount(self: *@This()) !void { const base = try self.queryInterface(IDWriteFontList); _ = try base.GetFontCount(); }
    pub fn getFamilyNames(self: *@This(), names: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFamilyNames(self, names)); }
    pub fn GetFamilyNames(self: *@This(), names: *?*anyopaque) !void { try self.getFamilyNames(names); }
    pub fn getFirstMatchingFont(self: *@This(), weight: i32, stretch: i32, style: i32, matchingFont: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFirstMatchingFont(self, weight, stretch, style, matchingFont)); }
    pub fn GetFirstMatchingFont(self: *@This(), weight: i32, stretch: i32, style: i32, matchingFont: *?*anyopaque) !void { try self.getFirstMatchingFont(weight, stretch, style, matchingFont); }
    pub fn getMatchingFonts(self: *@This(), weight: i32, stretch: i32, style: i32, matchingFonts: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetMatchingFonts(self, weight, stretch, style, matchingFonts)); }
    pub fn GetMatchingFonts(self: *@This(), weight: i32, stretch: i32, style: i32, matchingFonts: *?*anyopaque) !void { try self.getMatchingFonts(weight, stretch, style, matchingFonts); }
};

pub const IDWriteFontFace = extern struct {
    pub const IID = GUID{ .data1 = 0x5f49804d, .data2 = 0x7024, .data3 = 0x4d43, .data4 = .{ 0xbf, 0xa9, 0xd2, 0x59, 0x84, 0xf5, 0x38, 0x49 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetType: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFiles: *const fn (*anyopaque, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetIndex: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSimulations: *const fn (*anyopaque) callconv(.winapi) i32,
        IsSymbolFont: *const fn (*anyopaque) callconv(.winapi) BOOL,
        GetMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) void,
        GetGlyphCount: *const fn (*anyopaque) callconv(.winapi) u16,
        GetDesignGlyphMetrics: *const fn (*anyopaque, *u16, u32, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        GetGlyphIndices: *const fn (*anyopaque, *u32, u32, *u16) callconv(.winapi) HRESULT,
        TryGetFontTable: *const fn (*anyopaque, u32, *?*anyopaque, *u32, *?*anyopaque, *BOOL) callconv(.winapi) HRESULT,
        ReleaseFontTable: *const fn (*anyopaque, *void) callconv(.winapi) void,
        GetGlyphRunOutline: *const fn (*anyopaque, f32, *u16, *f32, *?*anyopaque, u32, BOOL, BOOL, ?*anyopaque) callconv(.winapi) HRESULT,
        GetRecommendedRenderingMode: *const fn (*anyopaque, f32, f32, i32, ?*anyopaque, *i32) callconv(.winapi) HRESULT,
        GetGdiCompatibleMetrics: *const fn (*anyopaque, f32, f32, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetGdiCompatibleGlyphMetrics: *const fn (*anyopaque, f32, f32, *?*anyopaque, BOOL, *u16, u32, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getType(self: *@This()) !void { try hrCheck(self.lpVtbl.GetType(self)); }
    pub fn GetType(self: *@This()) !void { try self.getType(); }
    pub fn getFiles(self: *@This(), numberOfFiles: *u32, fontFiles: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFiles(self, numberOfFiles, fontFiles)); }
    pub fn GetFiles(self: *@This(), numberOfFiles: *u32, fontFiles: *?*anyopaque) !void { try self.getFiles(numberOfFiles, fontFiles); }
    pub fn getIndex(self: *@This()) !void { try hrCheck(self.lpVtbl.GetIndex(self)); }
    pub fn GetIndex(self: *@This()) !void { try self.getIndex(); }
    pub fn getSimulations(self: *@This()) !void { try hrCheck(self.lpVtbl.GetSimulations(self)); }
    pub fn GetSimulations(self: *@This()) !void { try self.getSimulations(); }
    pub fn isSymbolFont(self: *@This()) !void { try hrCheck(self.lpVtbl.IsSymbolFont(self)); }
    pub fn IsSymbolFont(self: *@This()) !void { try self.isSymbolFont(); }
    pub fn getMetrics(self: *@This(), fontFaceMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetMetrics(self, fontFaceMetrics)); }
    pub fn GetMetrics(self: *@This(), fontFaceMetrics: *?*anyopaque) !void { try self.getMetrics(fontFaceMetrics); }
    pub fn getGlyphCount(self: *@This()) !void { try hrCheck(self.lpVtbl.GetGlyphCount(self)); }
    pub fn GetGlyphCount(self: *@This()) !void { try self.getGlyphCount(); }
    pub fn getDesignGlyphMetrics(self: *@This(), glyphIndices: *u16, glyphCount: u32, glyphMetrics: *?*anyopaque, isSideways: BOOL) !void { try hrCheck(self.lpVtbl.GetDesignGlyphMetrics(self, glyphIndices, glyphCount, glyphMetrics, isSideways)); }
    pub fn GetDesignGlyphMetrics(self: *@This(), glyphIndices: *u16, glyphCount: u32, glyphMetrics: *?*anyopaque, isSideways: BOOL) !void { try self.getDesignGlyphMetrics(glyphIndices, glyphCount, glyphMetrics, isSideways); }
    pub fn getGlyphIndices(self: *@This(), codePoints: *u32, codePointCount: u32, glyphIndices: *u16) !void { try hrCheck(self.lpVtbl.GetGlyphIndices(self, codePoints, codePointCount, glyphIndices)); }
    pub fn GetGlyphIndices(self: *@This(), codePoints: *u32, codePointCount: u32, glyphIndices: *u16) !void { try self.getGlyphIndices(codePoints, codePointCount, glyphIndices); }
    pub fn tryGetFontTable(self: *@This(), openTypeTableTag: u32, tableData: *?*anyopaque, tableSize: *u32, tableContext: *?*anyopaque, exists: *BOOL) !void { try hrCheck(self.lpVtbl.TryGetFontTable(self, openTypeTableTag, tableData, tableSize, tableContext, exists)); }
    pub fn TryGetFontTable(self: *@This(), openTypeTableTag: u32, tableData: *?*anyopaque, tableSize: *u32, tableContext: *?*anyopaque, exists: *BOOL) !void { try self.tryGetFontTable(openTypeTableTag, tableData, tableSize, tableContext, exists); }
    pub fn releaseFontTable(self: *@This(), tableContext: *void) !void { try hrCheck(self.lpVtbl.ReleaseFontTable(self, tableContext)); }
    pub fn ReleaseFontTable(self: *@This(), tableContext: *void) !void { try self.releaseFontTable(tableContext); }
    pub fn getGlyphRunOutline(self: *@This(), emSize: f32, glyphIndices: *u16, glyphAdvances: *f32, glyphOffsets: *?*anyopaque, glyphCount: u32, isSideways: BOOL, isRightToLeft: BOOL, geometrySink: ?*anyopaque) !void { try hrCheck(self.lpVtbl.GetGlyphRunOutline(self, emSize, glyphIndices, glyphAdvances, glyphOffsets, glyphCount, isSideways, isRightToLeft, geometrySink)); }
    pub fn GetGlyphRunOutline(self: *@This(), emSize: f32, glyphIndices: *u16, glyphAdvances: *f32, glyphOffsets: *?*anyopaque, glyphCount: u32, isSideways: BOOL, isRightToLeft: BOOL, geometrySink: ?*anyopaque) !void { try self.getGlyphRunOutline(emSize, glyphIndices, glyphAdvances, glyphOffsets, glyphCount, isSideways, isRightToLeft, geometrySink); }
    pub fn getRecommendedRenderingMode(self: *@This(), emSize: f32, pixelsPerDip: f32, measuringMode: i32, renderingParams: ?*anyopaque, renderingMode: *i32) !void { try hrCheck(self.lpVtbl.GetRecommendedRenderingMode(self, emSize, pixelsPerDip, measuringMode, renderingParams, renderingMode)); }
    pub fn GetRecommendedRenderingMode(self: *@This(), emSize: f32, pixelsPerDip: f32, measuringMode: i32, renderingParams: ?*anyopaque, renderingMode: *i32) !void { try self.getRecommendedRenderingMode(emSize, pixelsPerDip, measuringMode, renderingParams, renderingMode); }
    pub fn getGdiCompatibleMetrics(self: *@This(), emSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, fontFaceMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetGdiCompatibleMetrics(self, emSize, pixelsPerDip, transform, fontFaceMetrics)); }
    pub fn GetGdiCompatibleMetrics(self: *@This(), emSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, fontFaceMetrics: *?*anyopaque) !void { try self.getGdiCompatibleMetrics(emSize, pixelsPerDip, transform, fontFaceMetrics); }
    pub fn getGdiCompatibleGlyphMetrics(self: *@This(), emSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, glyphIndices: *u16, glyphCount: u32, glyphMetrics: *?*anyopaque, isSideways: BOOL) !void { try hrCheck(self.lpVtbl.GetGdiCompatibleGlyphMetrics(self, emSize, pixelsPerDip, transform, useGdiNatural, glyphIndices, glyphCount, glyphMetrics, isSideways)); }
    pub fn GetGdiCompatibleGlyphMetrics(self: *@This(), emSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, glyphIndices: *u16, glyphCount: u32, glyphMetrics: *?*anyopaque, isSideways: BOOL) !void { try self.getGdiCompatibleGlyphMetrics(emSize, pixelsPerDip, transform, useGdiNatural, glyphIndices, glyphCount, glyphMetrics, isSideways); }
};

pub const IDWriteLocalizedStrings = extern struct {
    pub const IID = GUID{ .data1 = 0x08256209, .data2 = 0x099a, .data3 = 0x4b34, .data4 = .{ 0xb8, 0x6d, 0xc2, 0x2b, 0x11, 0x0e, 0x77, 0x71 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetCount: *const fn (*anyopaque) callconv(.winapi) u32,
        FindLocaleName: *const fn (*anyopaque, ?*anyopaque, *u32, *BOOL) callconv(.winapi) HRESULT,
        GetLocaleNameLength: *const fn (*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        GetLocaleName: *const fn (*anyopaque, u32, ?*anyopaque, u32) callconv(.winapi) HRESULT,
        GetStringLength: *const fn (*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        GetString: *const fn (*anyopaque, u32, ?*anyopaque, u32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getCount(self: *@This()) !void { try hrCheck(self.lpVtbl.GetCount(self)); }
    pub fn GetCount(self: *@This()) !void { try self.getCount(); }
    pub fn findLocaleName(self: *@This(), localeName: ?*anyopaque, index: *u32, exists: *BOOL) !void { try hrCheck(self.lpVtbl.FindLocaleName(self, localeName, index, exists)); }
    pub fn FindLocaleName(self: *@This(), localeName: ?*anyopaque, index: *u32, exists: *BOOL) !void { try self.findLocaleName(localeName, index, exists); }
    pub fn getLocaleNameLength(self: *@This(), index: u32, length: *u32) !void { try hrCheck(self.lpVtbl.GetLocaleNameLength(self, index, length)); }
    pub fn GetLocaleNameLength(self: *@This(), index: u32, length: *u32) !void { try self.getLocaleNameLength(index, length); }
    pub fn getLocaleName(self: *@This(), index: u32, localeName: ?*anyopaque, size: u32) !void { try hrCheck(self.lpVtbl.GetLocaleName(self, index, localeName, size)); }
    pub fn GetLocaleName(self: *@This(), index: u32, localeName: ?*anyopaque, size: u32) !void { try self.getLocaleName(index, localeName, size); }
    pub fn getStringLength(self: *@This(), index: u32, length: *u32) !void { try hrCheck(self.lpVtbl.GetStringLength(self, index, length)); }
    pub fn GetStringLength(self: *@This(), index: u32, length: *u32) !void { try self.getStringLength(index, length); }
    pub fn getString(self: *@This(), index: u32, stringBuffer: ?*anyopaque, size: u32) !void { try hrCheck(self.lpVtbl.GetString(self, index, stringBuffer, size)); }
    pub fn GetString(self: *@This(), index: u32, stringBuffer: ?*anyopaque, size: u32) !void { try self.getString(index, stringBuffer, size); }
};

pub const IDWriteFontFile = extern struct {
    pub const IID = GUID{ .data1 = 0x739d886a, .data2 = 0xcef5, .data3 = 0x47dc, .data4 = .{ 0x87, 0x69, 0x1a, 0x8b, 0x41, 0xbe, 0xbb, 0xb0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetReferenceKey: *const fn (*anyopaque, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetLoader: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Analyze: *const fn (*anyopaque, *BOOL, *i32, *i32, *u32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getReferenceKey(self: *@This(), fontFileReferenceKey: *?*anyopaque, fontFileReferenceKeySize: *u32) !void { try hrCheck(self.lpVtbl.GetReferenceKey(self, fontFileReferenceKey, fontFileReferenceKeySize)); }
    pub fn GetReferenceKey(self: *@This(), fontFileReferenceKey: *?*anyopaque, fontFileReferenceKeySize: *u32) !void { try self.getReferenceKey(fontFileReferenceKey, fontFileReferenceKeySize); }
    pub fn getLoader(self: *@This(), fontFileLoader: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetLoader(self, fontFileLoader)); }
    pub fn GetLoader(self: *@This(), fontFileLoader: *?*anyopaque) !void { try self.getLoader(fontFileLoader); }
    pub fn analyze(self: *@This(), isSupportedFontType: *BOOL, fontFileType: *i32, fontFaceType: *i32, numberOfFaces: *u32) !void { try hrCheck(self.lpVtbl.Analyze(self, isSupportedFontType, fontFileType, fontFaceType, numberOfFaces)); }
    pub fn Analyze(self: *@This(), isSupportedFontType: *BOOL, fontFileType: *i32, fontFaceType: *i32, numberOfFaces: *u32) !void { try self.analyze(isSupportedFontType, fontFileType, fontFaceType, numberOfFaces); }
};

pub const IDWriteTextAnalysisSource = extern struct {
    pub const IID = GUID{ .data1 = 0x688e1a58, .data2 = 0x5094, .data3 = 0x47c8, .data4 = .{ 0xad, 0xc8, 0xfb, 0xce, 0xa6, 0x0a, 0xe9, 0x2b } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetTextAtPosition: *const fn (*anyopaque, u32, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetTextBeforePosition: *const fn (*anyopaque, u32, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetParagraphReadingDirection: *const fn (*anyopaque) callconv(.winapi) i32,
        GetLocaleName: *const fn (*anyopaque, u32, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetNumberSubstitution: *const fn (*anyopaque, u32, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getTextAtPosition(self: *@This(), textPosition: u32, textString: *?*anyopaque, textLength: *u32) !void { try hrCheck(self.lpVtbl.GetTextAtPosition(self, textPosition, textString, textLength)); }
    pub fn GetTextAtPosition(self: *@This(), textPosition: u32, textString: *?*anyopaque, textLength: *u32) !void { try self.getTextAtPosition(textPosition, textString, textLength); }
    pub fn getTextBeforePosition(self: *@This(), textPosition: u32, textString: *?*anyopaque, textLength: *u32) !void { try hrCheck(self.lpVtbl.GetTextBeforePosition(self, textPosition, textString, textLength)); }
    pub fn GetTextBeforePosition(self: *@This(), textPosition: u32, textString: *?*anyopaque, textLength: *u32) !void { try self.getTextBeforePosition(textPosition, textString, textLength); }
    pub fn getParagraphReadingDirection(self: *@This()) !void { try hrCheck(self.lpVtbl.GetParagraphReadingDirection(self)); }
    pub fn GetParagraphReadingDirection(self: *@This()) !void { try self.getParagraphReadingDirection(); }
    pub fn getLocaleName(self: *@This(), textPosition: u32, textLength: *u32, localeName: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetLocaleName(self, textPosition, textLength, localeName)); }
    pub fn GetLocaleName(self: *@This(), textPosition: u32, textLength: *u32, localeName: *?*anyopaque) !void { try self.getLocaleName(textPosition, textLength, localeName); }
    pub fn getNumberSubstitution(self: *@This(), textPosition: u32, textLength: *u32, numberSubstitution: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetNumberSubstitution(self, textPosition, textLength, numberSubstitution)); }
    pub fn GetNumberSubstitution(self: *@This(), textPosition: u32, textLength: *u32, numberSubstitution: *?*anyopaque) !void { try self.getNumberSubstitution(textPosition, textLength, numberSubstitution); }
};

pub const IDWriteFontFileLoader = extern struct {
    pub const IID = GUID{ .data1 = 0x727cad4e, .data2 = 0xd6af, .data3 = 0x4c9e, .data4 = .{ 0x8a, 0x08, 0xd6, 0x95, 0xb1, 0x1c, 0xaa, 0x49 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateStreamFromKey: *const fn (*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn createStreamFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, fontFileStream: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateStreamFromKey(self, fontFileReferenceKey, fontFileReferenceKeySize, fontFileStream)); }
    pub fn CreateStreamFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, fontFileStream: *?*anyopaque) !void { try self.createStreamFromKey(fontFileReferenceKey, fontFileReferenceKeySize, fontFileStream); }
};

pub const IDWriteLocalFontFileLoader = extern struct {
    pub const IID = GUID{ .data1 = 0xb2d9f3ec, .data2 = 0xc9fe, .data3 = 0x4a11, .data4 = .{ 0xa2, 0xec, 0xd8, 0x62, 0x08, 0xf7, 0xc0, 0xa2 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateStreamFromKey: *const fn (*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFilePathLengthFromKey: *const fn (*anyopaque, *void, u32, *u32) callconv(.winapi) HRESULT,
        GetFilePathFromKey: *const fn (*anyopaque, *void, u32, ?*anyopaque, u32) callconv(.winapi) HRESULT,
        GetLastWriteTimeFromKey: *const fn (*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWriteFontFileLoader = true; // requires IDWriteFontFileLoader
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getFilePathLengthFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, filePathLength: *u32) !void { try hrCheck(self.lpVtbl.GetFilePathLengthFromKey(self, fontFileReferenceKey, fontFileReferenceKeySize, filePathLength)); }
    pub fn GetFilePathLengthFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, filePathLength: *u32) !void { try self.getFilePathLengthFromKey(fontFileReferenceKey, fontFileReferenceKeySize, filePathLength); }
    pub fn getFilePathFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, filePath: ?*anyopaque, filePathSize: u32) !void { try hrCheck(self.lpVtbl.GetFilePathFromKey(self, fontFileReferenceKey, fontFileReferenceKeySize, filePath, filePathSize)); }
    pub fn GetFilePathFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, filePath: ?*anyopaque, filePathSize: u32) !void { try self.getFilePathFromKey(fontFileReferenceKey, fontFileReferenceKeySize, filePath, filePathSize); }
    pub fn getLastWriteTimeFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, lastWriteTime: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetLastWriteTimeFromKey(self, fontFileReferenceKey, fontFileReferenceKeySize, lastWriteTime)); }
    pub fn GetLastWriteTimeFromKey(self: *@This(), fontFileReferenceKey: *void, fontFileReferenceKeySize: u32, lastWriteTime: *?*anyopaque) !void { try self.getLastWriteTimeFromKey(fontFileReferenceKey, fontFileReferenceKeySize, lastWriteTime); }
};

pub const IDWriteFontCollectionLoader = extern struct {
    pub const IID = GUID{ .data1 = 0xcca920e4, .data2 = 0x52f0, .data3 = 0x492b, .data4 = .{ 0xbf, 0xa8, 0x29, 0xc7, 0x2e, 0xe0, 0xa4, 0x68 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateEnumeratorFromKey: *const fn (*anyopaque, ?*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn createEnumeratorFromKey(self: *@This(), factory: ?*anyopaque, collectionKey: *void, collectionKeySize: u32, fontFileEnumerator: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateEnumeratorFromKey(self, factory, collectionKey, collectionKeySize, fontFileEnumerator)); }
    pub fn CreateEnumeratorFromKey(self: *@This(), factory: ?*anyopaque, collectionKey: *void, collectionKeySize: u32, fontFileEnumerator: *?*anyopaque) !void { try self.createEnumeratorFromKey(factory, collectionKey, collectionKeySize, fontFileEnumerator); }
};

pub const PWSTR = extern struct {
    Value: *u16,
};

pub const FILETIME = extern struct {
    dwLowDateTime: u32,
    dwHighDateTime: u32,
};

pub const DWRITE_FONT_FACE_TYPE = struct {
    pub const DWRITE_FONT_FACE_TYPE_CFF: i32 = 0;
    pub const DWRITE_FONT_FACE_TYPE_TRUETYPE: i32 = 1;
    pub const DWRITE_FONT_FACE_TYPE_OPENTYPE_COLLECTION: i32 = 2;
    pub const DWRITE_FONT_FACE_TYPE_TYPE1: i32 = 3;
    pub const DWRITE_FONT_FACE_TYPE_VECTOR: i32 = 4;
    pub const DWRITE_FONT_FACE_TYPE_BITMAP: i32 = 5;
    pub const DWRITE_FONT_FACE_TYPE_UNKNOWN: i32 = 6;
    pub const DWRITE_FONT_FACE_TYPE_RAW_CFF: i32 = 7;
    pub const DWRITE_FONT_FACE_TYPE_TRUETYPE_COLLECTION: i32 = 2;
};

pub const DWRITE_FONT_SIMULATIONS = struct {
    pub const DWRITE_FONT_SIMULATIONS_NONE: i32 = 0;
    pub const DWRITE_FONT_SIMULATIONS_BOLD: i32 = 1;
    pub const DWRITE_FONT_SIMULATIONS_OBLIQUE: i32 = 2;
};

pub const IDWriteRenderingParams = extern struct {
    pub const IID = GUID{ .data1 = 0x2f0da53a, .data2 = 0x2add, .data3 = 0x47cd, .data4 = .{ 0x82, 0xee, 0xd9, 0xec, 0x34, 0x68, 0x8e, 0x75 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetGamma: *const fn (*anyopaque) callconv(.winapi) f32,
        GetEnhancedContrast: *const fn (*anyopaque) callconv(.winapi) f32,
        GetClearTypeLevel: *const fn (*anyopaque) callconv(.winapi) f32,
        GetPixelGeometry: *const fn (*anyopaque) callconv(.winapi) i32,
        GetRenderingMode: *const fn (*anyopaque) callconv(.winapi) i32,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getGamma(self: *@This()) !void { try hrCheck(self.lpVtbl.GetGamma(self)); }
    pub fn GetGamma(self: *@This()) !void { try self.getGamma(); }
    pub fn getEnhancedContrast(self: *@This()) !void { try hrCheck(self.lpVtbl.GetEnhancedContrast(self)); }
    pub fn GetEnhancedContrast(self: *@This()) !void { try self.getEnhancedContrast(); }
    pub fn getClearTypeLevel(self: *@This()) !void { try hrCheck(self.lpVtbl.GetClearTypeLevel(self)); }
    pub fn GetClearTypeLevel(self: *@This()) !void { try self.getClearTypeLevel(); }
    pub fn getPixelGeometry(self: *@This()) !void { try hrCheck(self.lpVtbl.GetPixelGeometry(self)); }
    pub fn GetPixelGeometry(self: *@This()) !void { try self.getPixelGeometry(); }
    pub fn getRenderingMode(self: *@This()) !void { try hrCheck(self.lpVtbl.GetRenderingMode(self)); }
    pub fn GetRenderingMode(self: *@This()) !void { try self.getRenderingMode(); }
};

pub const HMONITOR = extern struct {
    Value: *void,
};

pub const DWRITE_PIXEL_GEOMETRY = struct {
    pub const DWRITE_PIXEL_GEOMETRY_FLAT: i32 = 0;
    pub const DWRITE_PIXEL_GEOMETRY_RGB: i32 = 1;
    pub const DWRITE_PIXEL_GEOMETRY_BGR: i32 = 2;
};

pub const DWRITE_RENDERING_MODE = struct {
    pub const DWRITE_RENDERING_MODE_DEFAULT: i32 = 0;
    pub const DWRITE_RENDERING_MODE_ALIASED: i32 = 1;
    pub const DWRITE_RENDERING_MODE_GDI_CLASSIC: i32 = 2;
    pub const DWRITE_RENDERING_MODE_GDI_NATURAL: i32 = 3;
    pub const DWRITE_RENDERING_MODE_NATURAL: i32 = 4;
    pub const DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC: i32 = 5;
    pub const DWRITE_RENDERING_MODE_OUTLINE: i32 = 6;
    pub const DWRITE_RENDERING_MODE_CLEARTYPE_GDI_CLASSIC: i32 = 2;
    pub const DWRITE_RENDERING_MODE_CLEARTYPE_GDI_NATURAL: i32 = 3;
    pub const DWRITE_RENDERING_MODE_CLEARTYPE_NATURAL: i32 = 4;
    pub const DWRITE_RENDERING_MODE_CLEARTYPE_NATURAL_SYMMETRIC: i32 = 5;
};

pub const DWRITE_FONT_WEIGHT = struct {
    pub const DWRITE_FONT_WEIGHT_THIN: i32 = 100;
    pub const DWRITE_FONT_WEIGHT_EXTRA_LIGHT: i32 = 200;
    pub const DWRITE_FONT_WEIGHT_ULTRA_LIGHT: i32 = 200;
    pub const DWRITE_FONT_WEIGHT_LIGHT: i32 = 300;
    pub const DWRITE_FONT_WEIGHT_SEMI_LIGHT: i32 = 350;
    pub const DWRITE_FONT_WEIGHT_NORMAL: i32 = 400;
    pub const DWRITE_FONT_WEIGHT_REGULAR: i32 = 400;
    pub const DWRITE_FONT_WEIGHT_MEDIUM: i32 = 500;
    pub const DWRITE_FONT_WEIGHT_DEMI_BOLD: i32 = 600;
    pub const DWRITE_FONT_WEIGHT_SEMI_BOLD: i32 = 600;
    pub const DWRITE_FONT_WEIGHT_BOLD: i32 = 700;
    pub const DWRITE_FONT_WEIGHT_EXTRA_BOLD: i32 = 800;
    pub const DWRITE_FONT_WEIGHT_ULTRA_BOLD: i32 = 800;
    pub const DWRITE_FONT_WEIGHT_BLACK: i32 = 900;
    pub const DWRITE_FONT_WEIGHT_HEAVY: i32 = 900;
    pub const DWRITE_FONT_WEIGHT_EXTRA_BLACK: i32 = 950;
    pub const DWRITE_FONT_WEIGHT_ULTRA_BLACK: i32 = 950;
};

pub const DWRITE_FONT_STYLE = struct {
    pub const DWRITE_FONT_STYLE_NORMAL: i32 = 0;
    pub const DWRITE_FONT_STYLE_OBLIQUE: i32 = 1;
    pub const DWRITE_FONT_STYLE_ITALIC: i32 = 2;
};

pub const DWRITE_FONT_STRETCH = struct {
    pub const DWRITE_FONT_STRETCH_UNDEFINED: i32 = 0;
    pub const DWRITE_FONT_STRETCH_ULTRA_CONDENSED: i32 = 1;
    pub const DWRITE_FONT_STRETCH_EXTRA_CONDENSED: i32 = 2;
    pub const DWRITE_FONT_STRETCH_CONDENSED: i32 = 3;
    pub const DWRITE_FONT_STRETCH_SEMI_CONDENSED: i32 = 4;
    pub const DWRITE_FONT_STRETCH_NORMAL: i32 = 5;
    pub const DWRITE_FONT_STRETCH_MEDIUM: i32 = 5;
    pub const DWRITE_FONT_STRETCH_SEMI_EXPANDED: i32 = 6;
    pub const DWRITE_FONT_STRETCH_EXPANDED: i32 = 7;
    pub const DWRITE_FONT_STRETCH_EXTRA_EXPANDED: i32 = 8;
    pub const DWRITE_FONT_STRETCH_ULTRA_EXPANDED: i32 = 9;
};

pub const IDWriteTextFormat = extern struct {
    pub const IID = GUID{ .data1 = 0x9c906818, .data2 = 0x31d7, .data3 = 0x4fd3, .data4 = .{ 0xa1, 0x51, 0x7c, 0x5e, 0x22, 0x5d, 0xb5, 0x5a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetTextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetParagraphAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetWordWrapping: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetReadingDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetFlowDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetIncrementalTabStop: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        SetTrimming: *const fn (*anyopaque, *?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetLineSpacing: *const fn (*anyopaque, i32, f32, f32) callconv(.winapi) HRESULT,
        GetTextAlignment: *const fn (*anyopaque) callconv(.winapi) i32,
        GetParagraphAlignment: *const fn (*anyopaque) callconv(.winapi) i32,
        GetWordWrapping: *const fn (*anyopaque) callconv(.winapi) i32,
        GetReadingDirection: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFlowDirection: *const fn (*anyopaque) callconv(.winapi) i32,
        GetIncrementalTabStop: *const fn (*anyopaque) callconv(.winapi) f32,
        GetTrimming: *const fn (*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetLineSpacing: *const fn (*anyopaque, *i32, *f32, *f32) callconv(.winapi) HRESULT,
        GetFontCollection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontFamilyNameLength: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamilyName: *const fn (*anyopaque, ?*anyopaque, u32) callconv(.winapi) HRESULT,
        GetFontWeight: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontStyle: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontStretch: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontSize: *const fn (*anyopaque) callconv(.winapi) f32,
        GetLocaleNameLength: *const fn (*anyopaque) callconv(.winapi) u32,
        GetLocaleName: *const fn (*anyopaque, ?*anyopaque, u32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn setTextAlignment(self: *@This(), textAlignment: i32) !void { try hrCheck(self.lpVtbl.SetTextAlignment(self, textAlignment)); }
    pub fn SetTextAlignment(self: *@This(), textAlignment: i32) !void { try self.setTextAlignment(textAlignment); }
    pub fn setParagraphAlignment(self: *@This(), paragraphAlignment: i32) !void { try hrCheck(self.lpVtbl.SetParagraphAlignment(self, paragraphAlignment)); }
    pub fn SetParagraphAlignment(self: *@This(), paragraphAlignment: i32) !void { try self.setParagraphAlignment(paragraphAlignment); }
    pub fn setWordWrapping(self: *@This(), wordWrapping: i32) !void { try hrCheck(self.lpVtbl.SetWordWrapping(self, wordWrapping)); }
    pub fn SetWordWrapping(self: *@This(), wordWrapping: i32) !void { try self.setWordWrapping(wordWrapping); }
    pub fn setReadingDirection(self: *@This(), readingDirection: i32) !void { try hrCheck(self.lpVtbl.SetReadingDirection(self, readingDirection)); }
    pub fn SetReadingDirection(self: *@This(), readingDirection: i32) !void { try self.setReadingDirection(readingDirection); }
    pub fn setFlowDirection(self: *@This(), flowDirection: i32) !void { try hrCheck(self.lpVtbl.SetFlowDirection(self, flowDirection)); }
    pub fn SetFlowDirection(self: *@This(), flowDirection: i32) !void { try self.setFlowDirection(flowDirection); }
    pub fn setIncrementalTabStop(self: *@This(), incrementalTabStop: f32) !void { try hrCheck(self.lpVtbl.SetIncrementalTabStop(self, incrementalTabStop)); }
    pub fn SetIncrementalTabStop(self: *@This(), incrementalTabStop: f32) !void { try self.setIncrementalTabStop(incrementalTabStop); }
    pub fn setTrimming(self: *@This(), trimmingOptions: *?*anyopaque, trimmingSign: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTrimming(self, trimmingOptions, trimmingSign)); }
    pub fn SetTrimming(self: *@This(), trimmingOptions: *?*anyopaque, trimmingSign: ?*anyopaque) !void { try self.setTrimming(trimmingOptions, trimmingSign); }
    pub fn setLineSpacing(self: *@This(), lineSpacingMethod: i32, lineSpacing: f32, baseline: f32) !void { try hrCheck(self.lpVtbl.SetLineSpacing(self, lineSpacingMethod, lineSpacing, baseline)); }
    pub fn SetLineSpacing(self: *@This(), lineSpacingMethod: i32, lineSpacing: f32, baseline: f32) !void { try self.setLineSpacing(lineSpacingMethod, lineSpacing, baseline); }
    pub fn getTextAlignment(self: *@This()) !void { try hrCheck(self.lpVtbl.GetTextAlignment(self)); }
    pub fn GetTextAlignment(self: *@This()) !void { try self.getTextAlignment(); }
    pub fn getParagraphAlignment(self: *@This()) !void { try hrCheck(self.lpVtbl.GetParagraphAlignment(self)); }
    pub fn GetParagraphAlignment(self: *@This()) !void { try self.getParagraphAlignment(); }
    pub fn getWordWrapping(self: *@This()) !void { try hrCheck(self.lpVtbl.GetWordWrapping(self)); }
    pub fn GetWordWrapping(self: *@This()) !void { try self.getWordWrapping(); }
    pub fn getReadingDirection(self: *@This()) !void { try hrCheck(self.lpVtbl.GetReadingDirection(self)); }
    pub fn GetReadingDirection(self: *@This()) !void { try self.getReadingDirection(); }
    pub fn getFlowDirection(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFlowDirection(self)); }
    pub fn GetFlowDirection(self: *@This()) !void { try self.getFlowDirection(); }
    pub fn getIncrementalTabStop(self: *@This()) !void { try hrCheck(self.lpVtbl.GetIncrementalTabStop(self)); }
    pub fn GetIncrementalTabStop(self: *@This()) !void { try self.getIncrementalTabStop(); }
    pub fn getTrimming(self: *@This(), trimmingOptions: *?*anyopaque, trimmingSign: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetTrimming(self, trimmingOptions, trimmingSign)); }
    pub fn GetTrimming(self: *@This(), trimmingOptions: *?*anyopaque, trimmingSign: *?*anyopaque) !void { try self.getTrimming(trimmingOptions, trimmingSign); }
    pub fn getLineSpacing(self: *@This(), lineSpacingMethod: *i32, lineSpacing: *f32, baseline: *f32) !void { try hrCheck(self.lpVtbl.GetLineSpacing(self, lineSpacingMethod, lineSpacing, baseline)); }
    pub fn GetLineSpacing(self: *@This(), lineSpacingMethod: *i32, lineSpacing: *f32, baseline: *f32) !void { try self.getLineSpacing(lineSpacingMethod, lineSpacing, baseline); }
    pub fn getFontCollection(self: *@This(), fontCollection: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontCollection(self, fontCollection)); }
    pub fn GetFontCollection(self: *@This(), fontCollection: *?*anyopaque) !void { try self.getFontCollection(fontCollection); }
    pub fn getFontFamilyNameLength(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontFamilyNameLength(self)); }
    pub fn GetFontFamilyNameLength(self: *@This()) !void { try self.getFontFamilyNameLength(); }
    pub fn getFontFamilyName(self: *@This(), fontFamilyName: ?*anyopaque, nameSize: u32) !void { try hrCheck(self.lpVtbl.GetFontFamilyName(self, fontFamilyName, nameSize)); }
    pub fn GetFontFamilyName(self: *@This(), fontFamilyName: ?*anyopaque, nameSize: u32) !void { try self.getFontFamilyName(fontFamilyName, nameSize); }
    pub fn getFontWeight(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontWeight(self)); }
    pub fn GetFontWeight(self: *@This()) !void { try self.getFontWeight(); }
    pub fn getFontStyle(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontStyle(self)); }
    pub fn GetFontStyle(self: *@This()) !void { try self.getFontStyle(); }
    pub fn getFontStretch(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontStretch(self)); }
    pub fn GetFontStretch(self: *@This()) !void { try self.getFontStretch(); }
    pub fn getFontSize(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontSize(self)); }
    pub fn GetFontSize(self: *@This()) !void { try self.getFontSize(); }
    pub fn getLocaleNameLength(self: *@This()) !void { try hrCheck(self.lpVtbl.GetLocaleNameLength(self)); }
    pub fn GetLocaleNameLength(self: *@This()) !void { try self.getLocaleNameLength(); }
    pub fn getLocaleName(self: *@This(), localeName: ?*anyopaque, nameSize: u32) !void { try hrCheck(self.lpVtbl.GetLocaleName(self, localeName, nameSize)); }
    pub fn GetLocaleName(self: *@This(), localeName: ?*anyopaque, nameSize: u32) !void { try self.getLocaleName(localeName, nameSize); }
};

pub const IDWriteTypography = extern struct {
    pub const IID = GUID{ .data1 = 0x55f1112b, .data2 = 0x1dc2, .data3 = 0x4b3c, .data4 = .{ 0x95, 0x41, 0xf4, 0x68, 0x94, 0xed, 0x85, 0xb6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        AddFontFeature: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetFontFeatureCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFeature: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn addFontFeature(self: *@This(), fontFeature: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AddFontFeature(self, fontFeature)); }
    pub fn AddFontFeature(self: *@This(), fontFeature: ?*anyopaque) !void { try self.addFontFeature(fontFeature); }
    pub fn getFontFeatureCount(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontFeatureCount(self)); }
    pub fn GetFontFeatureCount(self: *@This()) !void { try self.getFontFeatureCount(); }
    pub fn getFontFeature(self: *@This(), fontFeatureIndex: u32, fontFeature: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFeature(self, fontFeatureIndex, fontFeature)); }
    pub fn GetFontFeature(self: *@This(), fontFeatureIndex: u32, fontFeature: *?*anyopaque) !void { try self.getFontFeature(fontFeatureIndex, fontFeature); }
};

pub const IDWriteGdiInterop = extern struct {
    pub const IID = GUID{ .data1 = 0x1edd9491, .data2 = 0x9853, .data3 = 0x4299, .data4 = .{ 0x89, 0x8f, 0x64, 0x32, 0x98, 0x3b, 0x6f, 0x3a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        CreateFontFromLOGFONT: *const fn (*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        ConvertFontToLOGFONT: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *BOOL) callconv(.winapi) HRESULT,
        ConvertFontFaceToLOGFONT: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFaceFromHdc: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateBitmapRenderTarget: *const fn (*anyopaque, ?*anyopaque, u32, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn createFontFromLOGFONT(self: *@This(), logFont: *?*anyopaque, font: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFromLOGFONT(self, logFont, font)); }
    pub fn CreateFontFromLOGFONT(self: *@This(), logFont: *?*anyopaque, font: *?*anyopaque) !void { try self.createFontFromLOGFONT(logFont, font); }
    pub fn convertFontToLOGFONT(self: *@This(), font: ?*anyopaque, logFont: *?*anyopaque, isSystemFont: *BOOL) !void { try hrCheck(self.lpVtbl.ConvertFontToLOGFONT(self, font, logFont, isSystemFont)); }
    pub fn ConvertFontToLOGFONT(self: *@This(), font: ?*anyopaque, logFont: *?*anyopaque, isSystemFont: *BOOL) !void { try self.convertFontToLOGFONT(font, logFont, isSystemFont); }
    pub fn convertFontFaceToLOGFONT(self: *@This(), font: ?*anyopaque, logFont: *?*anyopaque) !void { try hrCheck(self.lpVtbl.ConvertFontFaceToLOGFONT(self, font, logFont)); }
    pub fn ConvertFontFaceToLOGFONT(self: *@This(), font: ?*anyopaque, logFont: *?*anyopaque) !void { try self.convertFontFaceToLOGFONT(font, logFont); }
    pub fn createFontFaceFromHdc(self: *@This(), hdc: ?*anyopaque, fontFace: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFaceFromHdc(self, hdc, fontFace)); }
    pub fn CreateFontFaceFromHdc(self: *@This(), hdc: ?*anyopaque, fontFace: *?*anyopaque) !void { try self.createFontFaceFromHdc(hdc, fontFace); }
    pub fn createBitmapRenderTarget(self: *@This(), hdc: ?*anyopaque, width: u32, height: u32, renderTarget: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateBitmapRenderTarget(self, hdc, width, height, renderTarget)); }
    pub fn CreateBitmapRenderTarget(self: *@This(), hdc: ?*anyopaque, width: u32, height: u32, renderTarget: *?*anyopaque) !void { try self.createBitmapRenderTarget(hdc, width, height, renderTarget); }
};

pub const IDWriteTextLayout = extern struct {
    pub const IID = GUID{ .data1 = 0x53737037, .data2 = 0x6d14, .data3 = 0x410b, .data4 = .{ 0x9b, 0xfe, 0x0b, 0x18, 0x2b, 0xb7, 0x09, 0x61 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetTextAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetParagraphAlignment: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetWordWrapping: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetReadingDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetFlowDirection: *const fn (*anyopaque, i32) callconv(.winapi) HRESULT,
        SetIncrementalTabStop: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        SetTrimming: *const fn (*anyopaque, *?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetLineSpacing: *const fn (*anyopaque, i32, f32, f32) callconv(.winapi) HRESULT,
        GetTextAlignment: *const fn (*anyopaque) callconv(.winapi) i32,
        GetParagraphAlignment: *const fn (*anyopaque) callconv(.winapi) i32,
        GetWordWrapping: *const fn (*anyopaque) callconv(.winapi) i32,
        GetReadingDirection: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFlowDirection: *const fn (*anyopaque) callconv(.winapi) i32,
        GetIncrementalTabStop: *const fn (*anyopaque) callconv(.winapi) f32,
        GetTrimming: *const fn (*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetLineSpacing: *const fn (*anyopaque, *i32, *f32, *f32) callconv(.winapi) HRESULT,
        GetFontCollection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontFamilyNameLength: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamilyName: *const fn (*anyopaque, ?*anyopaque, u32) callconv(.winapi) HRESULT,
        GetFontWeight: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontStyle: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontStretch: *const fn (*anyopaque) callconv(.winapi) i32,
        GetFontSize: *const fn (*anyopaque) callconv(.winapi) f32,
        GetLocaleNameLength: *const fn (*anyopaque) callconv(.winapi) u32,
        GetLocaleName: *const fn (*anyopaque, ?*anyopaque, u32) callconv(.winapi) HRESULT,
        SetMaxWidth: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        SetMaxHeight: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        SetFontCollection: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFontFamilyName: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFontWeight: *const fn (*anyopaque, i32, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFontStyle: *const fn (*anyopaque, i32, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFontStretch: *const fn (*anyopaque, i32, ?*anyopaque) callconv(.winapi) HRESULT,
        SetFontSize: *const fn (*anyopaque, f32, ?*anyopaque) callconv(.winapi) HRESULT,
        SetUnderline: *const fn (*anyopaque, BOOL, ?*anyopaque) callconv(.winapi) HRESULT,
        SetStrikethrough: *const fn (*anyopaque, BOOL, ?*anyopaque) callconv(.winapi) HRESULT,
        SetDrawingEffect: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetInlineObject: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetTypography: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        SetLocaleName: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        GetMaxWidth: *const fn (*anyopaque) callconv(.winapi) f32,
        GetMaxHeight: *const fn (*anyopaque) callconv(.winapi) f32,
        GetFontCollection_2: *const fn (*anyopaque, u32, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontFamilyNameLength_2: *const fn (*anyopaque, u32, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontFamilyName_2: *const fn (*anyopaque, u32, ?*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontWeight_2: *const fn (*anyopaque, u32, *i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontStyle_2: *const fn (*anyopaque, u32, *i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontStretch_2: *const fn (*anyopaque, u32, *i32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontSize_2: *const fn (*anyopaque, u32, *f32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetUnderline: *const fn (*anyopaque, u32, *BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        GetStrikethrough: *const fn (*anyopaque, u32, *BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        GetDrawingEffect: *const fn (*anyopaque, u32, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetInlineObject: *const fn (*anyopaque, u32, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetTypography: *const fn (*anyopaque, u32, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetLocaleNameLength_2: *const fn (*anyopaque, u32, *u32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetLocaleName_2: *const fn (*anyopaque, u32, ?*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        Draw: *const fn (*anyopaque, *void, ?*anyopaque, f32, f32) callconv(.winapi) HRESULT,
        GetLineMetrics: *const fn (*anyopaque, *?*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        GetMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetOverhangMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetClusterMetrics: *const fn (*anyopaque, *?*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        DetermineMinWidth: *const fn (*anyopaque, *f32) callconv(.winapi) HRESULT,
        HitTestPoint: *const fn (*anyopaque, f32, f32, *BOOL, *BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        HitTestTextPosition: *const fn (*anyopaque, u32, BOOL, *f32, *f32, *?*anyopaque) callconv(.winapi) HRESULT,
        HitTestTextRange: *const fn (*anyopaque, u32, u32, f32, f32, *?*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWriteTextFormat = true; // requires IDWriteTextFormat
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn GetTextAlignment(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetTextAlignment(); }
    pub fn GetParagraphAlignment(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetParagraphAlignment(); }
    pub fn GetWordWrapping(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetWordWrapping(); }
    pub fn GetReadingDirection(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetReadingDirection(); }
    pub fn GetFlowDirection(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFlowDirection(); }
    pub fn GetIncrementalTabStop(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetIncrementalTabStop(); }
    pub fn GetFontFamilyNameLength(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFontFamilyNameLength(); }
    pub fn GetFontWeight(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFontWeight(); }
    pub fn GetFontStyle(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFontStyle(); }
    pub fn GetFontStretch(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFontStretch(); }
    pub fn GetFontSize(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetFontSize(); }
    pub fn GetLocaleNameLength(self: *@This()) !void { const base = try self.queryInterface(IDWriteTextFormat); _ = try base.GetLocaleNameLength(); }
    pub fn setMaxWidth(self: *@This(), maxWidth: f32) !void { try hrCheck(self.lpVtbl.SetMaxWidth(self, maxWidth)); }
    pub fn SetMaxWidth(self: *@This(), maxWidth: f32) !void { try self.setMaxWidth(maxWidth); }
    pub fn setMaxHeight(self: *@This(), maxHeight: f32) !void { try hrCheck(self.lpVtbl.SetMaxHeight(self, maxHeight)); }
    pub fn SetMaxHeight(self: *@This(), maxHeight: f32) !void { try self.setMaxHeight(maxHeight); }
    pub fn setFontCollection(self: *@This(), fontCollection: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontCollection(self, fontCollection, textRange)); }
    pub fn SetFontCollection(self: *@This(), fontCollection: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setFontCollection(fontCollection, textRange); }
    pub fn setFontFamilyName(self: *@This(), fontFamilyName: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontFamilyName(self, fontFamilyName, textRange)); }
    pub fn SetFontFamilyName(self: *@This(), fontFamilyName: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setFontFamilyName(fontFamilyName, textRange); }
    pub fn setFontWeight(self: *@This(), fontWeight: i32, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontWeight(self, fontWeight, textRange)); }
    pub fn SetFontWeight(self: *@This(), fontWeight: i32, textRange: ?*anyopaque) !void { try self.setFontWeight(fontWeight, textRange); }
    pub fn setFontStyle(self: *@This(), fontStyle: i32, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontStyle(self, fontStyle, textRange)); }
    pub fn SetFontStyle(self: *@This(), fontStyle: i32, textRange: ?*anyopaque) !void { try self.setFontStyle(fontStyle, textRange); }
    pub fn setFontStretch(self: *@This(), fontStretch: i32, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontStretch(self, fontStretch, textRange)); }
    pub fn SetFontStretch(self: *@This(), fontStretch: i32, textRange: ?*anyopaque) !void { try self.setFontStretch(fontStretch, textRange); }
    pub fn setFontSize(self: *@This(), fontSize: f32, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetFontSize(self, fontSize, textRange)); }
    pub fn SetFontSize(self: *@This(), fontSize: f32, textRange: ?*anyopaque) !void { try self.setFontSize(fontSize, textRange); }
    pub fn setUnderline(self: *@This(), hasUnderline: BOOL, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetUnderline(self, hasUnderline, textRange)); }
    pub fn SetUnderline(self: *@This(), hasUnderline: BOOL, textRange: ?*anyopaque) !void { try self.setUnderline(hasUnderline, textRange); }
    pub fn setStrikethrough(self: *@This(), hasStrikethrough: BOOL, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetStrikethrough(self, hasStrikethrough, textRange)); }
    pub fn SetStrikethrough(self: *@This(), hasStrikethrough: BOOL, textRange: ?*anyopaque) !void { try self.setStrikethrough(hasStrikethrough, textRange); }
    pub fn setDrawingEffect(self: *@This(), drawingEffect: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetDrawingEffect(self, drawingEffect, textRange)); }
    pub fn SetDrawingEffect(self: *@This(), drawingEffect: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setDrawingEffect(drawingEffect, textRange); }
    pub fn setInlineObject(self: *@This(), inlineObject: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetInlineObject(self, inlineObject, textRange)); }
    pub fn SetInlineObject(self: *@This(), inlineObject: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setInlineObject(inlineObject, textRange); }
    pub fn setTypography(self: *@This(), typography: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetTypography(self, typography, textRange)); }
    pub fn SetTypography(self: *@This(), typography: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setTypography(typography, textRange); }
    pub fn setLocaleName(self: *@This(), localeName: ?*anyopaque, textRange: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetLocaleName(self, localeName, textRange)); }
    pub fn SetLocaleName(self: *@This(), localeName: ?*anyopaque, textRange: ?*anyopaque) !void { try self.setLocaleName(localeName, textRange); }
    pub fn getMaxWidth(self: *@This()) !void { try hrCheck(self.lpVtbl.GetMaxWidth(self)); }
    pub fn GetMaxWidth(self: *@This()) !void { try self.getMaxWidth(); }
    pub fn getMaxHeight(self: *@This()) !void { try hrCheck(self.lpVtbl.GetMaxHeight(self)); }
    pub fn GetMaxHeight(self: *@This()) !void { try self.getMaxHeight(); }
    pub fn getFontCollection(self: *@This(), currentPosition: u32, fontCollection: *?*anyopaque, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontCollection(self, currentPosition, fontCollection, textRange)); }
    pub fn GetFontCollection(self: *@This(), currentPosition: u32, fontCollection: *?*anyopaque, textRange: *?*anyopaque) !void { try self.getFontCollection(currentPosition, fontCollection, textRange); }
    pub fn getFontFamilyNameLength(self: *@This(), currentPosition: u32, nameLength: *u32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFamilyNameLength(self, currentPosition, nameLength, textRange)); }
    pub fn getFontFamilyName(self: *@This(), currentPosition: u32, fontFamilyName: ?*anyopaque, nameSize: u32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontFamilyName(self, currentPosition, fontFamilyName, nameSize, textRange)); }
    pub fn GetFontFamilyName(self: *@This(), currentPosition: u32, fontFamilyName: ?*anyopaque, nameSize: u32, textRange: *?*anyopaque) !void { try self.getFontFamilyName(currentPosition, fontFamilyName, nameSize, textRange); }
    pub fn getFontWeight(self: *@This(), currentPosition: u32, fontWeight: *i32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontWeight(self, currentPosition, fontWeight, textRange)); }
    pub fn getFontStyle(self: *@This(), currentPosition: u32, fontStyle: *i32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontStyle(self, currentPosition, fontStyle, textRange)); }
    pub fn getFontStretch(self: *@This(), currentPosition: u32, fontStretch: *i32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontStretch(self, currentPosition, fontStretch, textRange)); }
    pub fn getFontSize(self: *@This(), currentPosition: u32, fontSize: *f32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontSize(self, currentPosition, fontSize, textRange)); }
    pub fn getUnderline(self: *@This(), currentPosition: u32, hasUnderline: *BOOL, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetUnderline(self, currentPosition, hasUnderline, textRange)); }
    pub fn GetUnderline(self: *@This(), currentPosition: u32, hasUnderline: *BOOL, textRange: *?*anyopaque) !void { try self.getUnderline(currentPosition, hasUnderline, textRange); }
    pub fn getStrikethrough(self: *@This(), currentPosition: u32, hasStrikethrough: *BOOL, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetStrikethrough(self, currentPosition, hasStrikethrough, textRange)); }
    pub fn GetStrikethrough(self: *@This(), currentPosition: u32, hasStrikethrough: *BOOL, textRange: *?*anyopaque) !void { try self.getStrikethrough(currentPosition, hasStrikethrough, textRange); }
    pub fn getDrawingEffect(self: *@This(), currentPosition: u32, drawingEffect: *?*anyopaque, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetDrawingEffect(self, currentPosition, drawingEffect, textRange)); }
    pub fn GetDrawingEffect(self: *@This(), currentPosition: u32, drawingEffect: *?*anyopaque, textRange: *?*anyopaque) !void { try self.getDrawingEffect(currentPosition, drawingEffect, textRange); }
    pub fn getInlineObject(self: *@This(), currentPosition: u32, inlineObject: *?*anyopaque, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetInlineObject(self, currentPosition, inlineObject, textRange)); }
    pub fn GetInlineObject(self: *@This(), currentPosition: u32, inlineObject: *?*anyopaque, textRange: *?*anyopaque) !void { try self.getInlineObject(currentPosition, inlineObject, textRange); }
    pub fn getTypography(self: *@This(), currentPosition: u32, typography: *?*anyopaque, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetTypography(self, currentPosition, typography, textRange)); }
    pub fn GetTypography(self: *@This(), currentPosition: u32, typography: *?*anyopaque, textRange: *?*anyopaque) !void { try self.getTypography(currentPosition, typography, textRange); }
    pub fn getLocaleNameLength(self: *@This(), currentPosition: u32, nameLength: *u32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetLocaleNameLength(self, currentPosition, nameLength, textRange)); }
    pub fn getLocaleName(self: *@This(), currentPosition: u32, localeName: ?*anyopaque, nameSize: u32, textRange: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetLocaleName(self, currentPosition, localeName, nameSize, textRange)); }
    pub fn GetLocaleName(self: *@This(), currentPosition: u32, localeName: ?*anyopaque, nameSize: u32, textRange: *?*anyopaque) !void { try self.getLocaleName(currentPosition, localeName, nameSize, textRange); }
    pub fn draw(self: *@This(), clientDrawingContext: *void, renderer: ?*anyopaque, originX: f32, originY: f32) !void { try hrCheck(self.lpVtbl.Draw(self, clientDrawingContext, renderer, originX, originY)); }
    pub fn Draw(self: *@This(), clientDrawingContext: *void, renderer: ?*anyopaque, originX: f32, originY: f32) !void { try self.draw(clientDrawingContext, renderer, originX, originY); }
    pub fn getLineMetrics(self: *@This(), lineMetrics: *?*anyopaque, maxLineCount: u32, actualLineCount: *u32) !void { try hrCheck(self.lpVtbl.GetLineMetrics(self, lineMetrics, maxLineCount, actualLineCount)); }
    pub fn GetLineMetrics(self: *@This(), lineMetrics: *?*anyopaque, maxLineCount: u32, actualLineCount: *u32) !void { try self.getLineMetrics(lineMetrics, maxLineCount, actualLineCount); }
    pub fn getMetrics(self: *@This(), textMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetMetrics(self, textMetrics)); }
    pub fn GetMetrics(self: *@This(), textMetrics: *?*anyopaque) !void { try self.getMetrics(textMetrics); }
    pub fn getOverhangMetrics(self: *@This(), overhangs: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetOverhangMetrics(self, overhangs)); }
    pub fn GetOverhangMetrics(self: *@This(), overhangs: *?*anyopaque) !void { try self.getOverhangMetrics(overhangs); }
    pub fn getClusterMetrics(self: *@This(), clusterMetrics: *?*anyopaque, maxClusterCount: u32, actualClusterCount: *u32) !void { try hrCheck(self.lpVtbl.GetClusterMetrics(self, clusterMetrics, maxClusterCount, actualClusterCount)); }
    pub fn GetClusterMetrics(self: *@This(), clusterMetrics: *?*anyopaque, maxClusterCount: u32, actualClusterCount: *u32) !void { try self.getClusterMetrics(clusterMetrics, maxClusterCount, actualClusterCount); }
    pub fn determineMinWidth(self: *@This(), minWidth: *f32) !void { try hrCheck(self.lpVtbl.DetermineMinWidth(self, minWidth)); }
    pub fn DetermineMinWidth(self: *@This(), minWidth: *f32) !void { try self.determineMinWidth(minWidth); }
    pub fn hitTestPoint(self: *@This(), pointX: f32, pointY: f32, isTrailingHit: *BOOL, isInside: *BOOL, hitTestMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.HitTestPoint(self, pointX, pointY, isTrailingHit, isInside, hitTestMetrics)); }
    pub fn HitTestPoint(self: *@This(), pointX: f32, pointY: f32, isTrailingHit: *BOOL, isInside: *BOOL, hitTestMetrics: *?*anyopaque) !void { try self.hitTestPoint(pointX, pointY, isTrailingHit, isInside, hitTestMetrics); }
    pub fn hitTestTextPosition(self: *@This(), textPosition: u32, isTrailingHit: BOOL, pointX: *f32, pointY: *f32, hitTestMetrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.HitTestTextPosition(self, textPosition, isTrailingHit, pointX, pointY, hitTestMetrics)); }
    pub fn HitTestTextPosition(self: *@This(), textPosition: u32, isTrailingHit: BOOL, pointX: *f32, pointY: *f32, hitTestMetrics: *?*anyopaque) !void { try self.hitTestTextPosition(textPosition, isTrailingHit, pointX, pointY, hitTestMetrics); }
    pub fn hitTestTextRange(self: *@This(), textPosition: u32, textLength: u32, originX: f32, originY: f32, hitTestMetrics: *?*anyopaque, maxHitTestMetricsCount: u32, actualHitTestMetricsCount: *u32) !void { try hrCheck(self.lpVtbl.HitTestTextRange(self, textPosition, textLength, originX, originY, hitTestMetrics, maxHitTestMetricsCount, actualHitTestMetricsCount)); }
    pub fn HitTestTextRange(self: *@This(), textPosition: u32, textLength: u32, originX: f32, originY: f32, hitTestMetrics: *?*anyopaque, maxHitTestMetricsCount: u32, actualHitTestMetricsCount: *u32) !void { try self.hitTestTextRange(textPosition, textLength, originX, originY, hitTestMetrics, maxHitTestMetricsCount, actualHitTestMetricsCount); }
};

pub const DWRITE_MATRIX = extern struct {
    m11: f32,
    m12: f32,
    m21: f32,
    m22: f32,
    dx: f32,
    dy: f32,
};

pub const IDWriteInlineObject = extern struct {
    pub const IID = GUID{ .data1 = 0x8339fde3, .data2 = 0x106f, .data3 = 0x47ab, .data4 = .{ 0x83, 0x73, 0x1c, 0x62, 0x95, 0xeb, 0x10, 0xb3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        Draw: *const fn (*anyopaque, *void, ?*anyopaque, f32, f32, BOOL, BOOL, ?*anyopaque) callconv(.winapi) HRESULT,
        GetMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetOverhangMetrics: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetBreakConditions: *const fn (*anyopaque, *i32, *i32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn draw(self: *@This(), clientDrawingContext: *void, renderer: ?*anyopaque, originX: f32, originY: f32, isSideways: BOOL, isRightToLeft: BOOL, clientDrawingEffect: ?*anyopaque) !void { try hrCheck(self.lpVtbl.Draw(self, clientDrawingContext, renderer, originX, originY, isSideways, isRightToLeft, clientDrawingEffect)); }
    pub fn Draw(self: *@This(), clientDrawingContext: *void, renderer: ?*anyopaque, originX: f32, originY: f32, isSideways: BOOL, isRightToLeft: BOOL, clientDrawingEffect: ?*anyopaque) !void { try self.draw(clientDrawingContext, renderer, originX, originY, isSideways, isRightToLeft, clientDrawingEffect); }
    pub fn getMetrics(self: *@This(), metrics: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetMetrics(self, metrics)); }
    pub fn GetMetrics(self: *@This(), metrics: *?*anyopaque) !void { try self.getMetrics(metrics); }
    pub fn getOverhangMetrics(self: *@This(), overhangs: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetOverhangMetrics(self, overhangs)); }
    pub fn GetOverhangMetrics(self: *@This(), overhangs: *?*anyopaque) !void { try self.getOverhangMetrics(overhangs); }
    pub fn getBreakConditions(self: *@This(), breakConditionBefore: *i32, breakConditionAfter: *i32) !void { try hrCheck(self.lpVtbl.GetBreakConditions(self, breakConditionBefore, breakConditionAfter)); }
    pub fn GetBreakConditions(self: *@This(), breakConditionBefore: *i32, breakConditionAfter: *i32) !void { try self.getBreakConditions(breakConditionBefore, breakConditionAfter); }
};

pub const IDWriteTextAnalyzer = extern struct {
    pub const IID = GUID{ .data1 = 0xb7e6163e, .data2 = 0x7f46, .data3 = 0x43b4, .data4 = .{ 0x84, 0xb3, 0xe4, 0xe6, 0x24, 0x9c, 0x36, 0x5d } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        AnalyzeScript: *const fn (*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        AnalyzeBidi: *const fn (*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        AnalyzeNumberSubstitution: *const fn (*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        AnalyzeLineBreakpoints: *const fn (*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) HRESULT,
        GetGlyphs: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, BOOL, BOOL, *?*anyopaque, ?*anyopaque, ?*anyopaque, *?*anyopaque, *u32, u32, u32, *u16, *?*anyopaque, *u16, *?*anyopaque, *u32) callconv(.winapi) HRESULT,
        GetGlyphPlacements: *const fn (*anyopaque, ?*anyopaque, *u16, *?*anyopaque, u32, *u16, *?*anyopaque, u32, ?*anyopaque, f32, BOOL, BOOL, *?*anyopaque, ?*anyopaque, *?*anyopaque, *u32, u32, *f32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetGdiCompatibleGlyphPlacements: *const fn (*anyopaque, ?*anyopaque, *u16, *?*anyopaque, u32, *u16, *?*anyopaque, u32, ?*anyopaque, f32, f32, *?*anyopaque, BOOL, BOOL, BOOL, *?*anyopaque, ?*anyopaque, *?*anyopaque, *u32, u32, *f32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn analyzeScript(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AnalyzeScript(self, analysisSource, textPosition, textLength, analysisSink)); }
    pub fn AnalyzeScript(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try self.analyzeScript(analysisSource, textPosition, textLength, analysisSink); }
    pub fn analyzeBidi(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AnalyzeBidi(self, analysisSource, textPosition, textLength, analysisSink)); }
    pub fn AnalyzeBidi(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try self.analyzeBidi(analysisSource, textPosition, textLength, analysisSink); }
    pub fn analyzeNumberSubstitution(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AnalyzeNumberSubstitution(self, analysisSource, textPosition, textLength, analysisSink)); }
    pub fn AnalyzeNumberSubstitution(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try self.analyzeNumberSubstitution(analysisSource, textPosition, textLength, analysisSink); }
    pub fn analyzeLineBreakpoints(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AnalyzeLineBreakpoints(self, analysisSource, textPosition, textLength, analysisSink)); }
    pub fn AnalyzeLineBreakpoints(self: *@This(), analysisSource: ?*anyopaque, textPosition: u32, textLength: u32, analysisSink: ?*anyopaque) !void { try self.analyzeLineBreakpoints(analysisSource, textPosition, textLength, analysisSink); }
    pub fn getGlyphs(self: *@This(), textString: ?*anyopaque, textLength: u32, fontFace: ?*anyopaque, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, numberSubstitution: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, maxGlyphCount: u32, clusterMap: *u16, textProps: *?*anyopaque, glyphIndices: *u16, glyphProps: *?*anyopaque, actualGlyphCount: *u32) !void { try hrCheck(self.lpVtbl.GetGlyphs(self, textString, textLength, fontFace, isSideways, isRightToLeft, scriptAnalysis, localeName, numberSubstitution, features, featureRangeLengths, featureRanges, maxGlyphCount, clusterMap, textProps, glyphIndices, glyphProps, actualGlyphCount)); }
    pub fn GetGlyphs(self: *@This(), textString: ?*anyopaque, textLength: u32, fontFace: ?*anyopaque, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, numberSubstitution: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, maxGlyphCount: u32, clusterMap: *u16, textProps: *?*anyopaque, glyphIndices: *u16, glyphProps: *?*anyopaque, actualGlyphCount: *u32) !void { try self.getGlyphs(textString, textLength, fontFace, isSideways, isRightToLeft, scriptAnalysis, localeName, numberSubstitution, features, featureRangeLengths, featureRanges, maxGlyphCount, clusterMap, textProps, glyphIndices, glyphProps, actualGlyphCount); }
    pub fn getGlyphPlacements(self: *@This(), textString: ?*anyopaque, clusterMap: *u16, textProps: *?*anyopaque, textLength: u32, glyphIndices: *u16, glyphProps: *?*anyopaque, glyphCount: u32, fontFace: ?*anyopaque, fontEmSize: f32, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, glyphAdvances: *f32, glyphOffsets: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetGlyphPlacements(self, textString, clusterMap, textProps, textLength, glyphIndices, glyphProps, glyphCount, fontFace, fontEmSize, isSideways, isRightToLeft, scriptAnalysis, localeName, features, featureRangeLengths, featureRanges, glyphAdvances, glyphOffsets)); }
    pub fn GetGlyphPlacements(self: *@This(), textString: ?*anyopaque, clusterMap: *u16, textProps: *?*anyopaque, textLength: u32, glyphIndices: *u16, glyphProps: *?*anyopaque, glyphCount: u32, fontFace: ?*anyopaque, fontEmSize: f32, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, glyphAdvances: *f32, glyphOffsets: *?*anyopaque) !void { try self.getGlyphPlacements(textString, clusterMap, textProps, textLength, glyphIndices, glyphProps, glyphCount, fontFace, fontEmSize, isSideways, isRightToLeft, scriptAnalysis, localeName, features, featureRangeLengths, featureRanges, glyphAdvances, glyphOffsets); }
    pub fn getGdiCompatibleGlyphPlacements(self: *@This(), textString: ?*anyopaque, clusterMap: *u16, textProps: *?*anyopaque, textLength: u32, glyphIndices: *u16, glyphProps: *?*anyopaque, glyphCount: u32, fontFace: ?*anyopaque, fontEmSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, glyphAdvances: *f32, glyphOffsets: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetGdiCompatibleGlyphPlacements(self, textString, clusterMap, textProps, textLength, glyphIndices, glyphProps, glyphCount, fontFace, fontEmSize, pixelsPerDip, transform, useGdiNatural, isSideways, isRightToLeft, scriptAnalysis, localeName, features, featureRangeLengths, featureRanges, glyphAdvances, glyphOffsets)); }
    pub fn GetGdiCompatibleGlyphPlacements(self: *@This(), textString: ?*anyopaque, clusterMap: *u16, textProps: *?*anyopaque, textLength: u32, glyphIndices: *u16, glyphProps: *?*anyopaque, glyphCount: u32, fontFace: ?*anyopaque, fontEmSize: f32, pixelsPerDip: f32, transform: *?*anyopaque, useGdiNatural: BOOL, isSideways: BOOL, isRightToLeft: BOOL, scriptAnalysis: *?*anyopaque, localeName: ?*anyopaque, features: *?*anyopaque, featureRangeLengths: *u32, featureRanges: u32, glyphAdvances: *f32, glyphOffsets: *?*anyopaque) !void { try self.getGdiCompatibleGlyphPlacements(textString, clusterMap, textProps, textLength, glyphIndices, glyphProps, glyphCount, fontFace, fontEmSize, pixelsPerDip, transform, useGdiNatural, isSideways, isRightToLeft, scriptAnalysis, localeName, features, featureRangeLengths, featureRanges, glyphAdvances, glyphOffsets); }
};

pub const DWRITE_NUMBER_SUBSTITUTION_METHOD = struct {
    pub const DWRITE_NUMBER_SUBSTITUTION_METHOD_FROM_CULTURE: i32 = 0;
    pub const DWRITE_NUMBER_SUBSTITUTION_METHOD_CONTEXTUAL: i32 = 1;
    pub const DWRITE_NUMBER_SUBSTITUTION_METHOD_NONE: i32 = 2;
    pub const DWRITE_NUMBER_SUBSTITUTION_METHOD_NATIONAL: i32 = 3;
    pub const DWRITE_NUMBER_SUBSTITUTION_METHOD_TRADITIONAL: i32 = 4;
};

pub const IDWriteNumberSubstitution = extern struct {
    pub const IID = GUID{ .data1 = 0x14885cc9, .data2 = 0xbab0, .data3 = 0x4f90, .data4 = .{ 0xb6, 0xed, 0x5c, 0x36, 0x6a, 0x2c, 0xd0, 0x3d } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
};

pub const DWRITE_GLYPH_RUN = extern struct {
    fontFace: IDWriteFontFace,
    fontEmSize: f32,
    glyphCount: u32,
    glyphIndices: *u16,
    glyphAdvances: *f32,
    glyphOffsets: *DWRITE_GLYPH_OFFSET,
    isSideways: BOOL,
    bidiLevel: u32,
};

pub const DWRITE_MEASURING_MODE = struct {
    pub const DWRITE_MEASURING_MODE_NATURAL: i32 = 0;
    pub const DWRITE_MEASURING_MODE_GDI_CLASSIC: i32 = 1;
    pub const DWRITE_MEASURING_MODE_GDI_NATURAL: i32 = 2;
};

pub const IDWriteGlyphRunAnalysis = extern struct {
    pub const IID = GUID{ .data1 = 0x7d97dbf7, .data2 = 0xe085, .data3 = 0x42d4, .data4 = .{ 0x81, 0xe3, 0x6a, 0x88, 0x3b, 0xde, 0xd1, 0x18 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetAlphaTextureBounds: *const fn (*anyopaque, i32, *RECT) callconv(.winapi) HRESULT,
        CreateAlphaTexture: *const fn (*anyopaque, i32, *RECT, *u8, u32) callconv(.winapi) HRESULT,
        GetAlphaBlendParams: *const fn (*anyopaque, ?*anyopaque, *f32, *f32, *f32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getAlphaTextureBounds(self: *@This(), textureType: i32, textureBounds: *RECT) !void { try hrCheck(self.lpVtbl.GetAlphaTextureBounds(self, textureType, textureBounds)); }
    pub fn GetAlphaTextureBounds(self: *@This(), textureType: i32, textureBounds: *RECT) !void { try self.getAlphaTextureBounds(textureType, textureBounds); }
    pub fn createAlphaTexture(self: *@This(), textureType: i32, textureBounds: *RECT, alphaValues: *u8, bufferSize: u32) !void { try hrCheck(self.lpVtbl.CreateAlphaTexture(self, textureType, textureBounds, alphaValues, bufferSize)); }
    pub fn CreateAlphaTexture(self: *@This(), textureType: i32, textureBounds: *RECT, alphaValues: *u8, bufferSize: u32) !void { try self.createAlphaTexture(textureType, textureBounds, alphaValues, bufferSize); }
    pub fn getAlphaBlendParams(self: *@This(), renderingParams: ?*anyopaque, blendGamma: *f32, blendEnhancedContrast: *f32, blendClearTypeLevel: *f32) !void { try hrCheck(self.lpVtbl.GetAlphaBlendParams(self, renderingParams, blendGamma, blendEnhancedContrast, blendClearTypeLevel)); }
    pub fn GetAlphaBlendParams(self: *@This(), renderingParams: ?*anyopaque, blendGamma: *f32, blendEnhancedContrast: *f32, blendClearTypeLevel: *f32) !void { try self.getAlphaBlendParams(renderingParams, blendGamma, blendEnhancedContrast, blendClearTypeLevel); }
};

pub const IDWriteFontFallbackBuilder = extern struct {
    pub const IID = GUID{ .data1 = 0xfd882d06, .data2 = 0x8aba, .data3 = 0x4fb8, .data4 = .{ 0xb8, 0x49, 0x8b, 0xe8, 0xb7, 0x3e, 0x14, 0xde } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        AddMapping: *const fn (*anyopaque, *?*anyopaque, u32, *?*anyopaque, u32, ?*anyopaque, ?*anyopaque, ?*anyopaque, f32) callconv(.winapi) HRESULT,
        AddMappings: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFallback: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn addMapping(self: *@This(), ranges: *?*anyopaque, rangesCount: u32, targetFamilyNames: *?*anyopaque, targetFamilyNamesCount: u32, fontCollection: ?*anyopaque, localeName: ?*anyopaque, baseFamilyName: ?*anyopaque, scale: f32) !void { try hrCheck(self.lpVtbl.AddMapping(self, ranges, rangesCount, targetFamilyNames, targetFamilyNamesCount, fontCollection, localeName, baseFamilyName, scale)); }
    pub fn AddMapping(self: *@This(), ranges: *?*anyopaque, rangesCount: u32, targetFamilyNames: *?*anyopaque, targetFamilyNamesCount: u32, fontCollection: ?*anyopaque, localeName: ?*anyopaque, baseFamilyName: ?*anyopaque, scale: f32) !void { try self.addMapping(ranges, rangesCount, targetFamilyNames, targetFamilyNamesCount, fontCollection, localeName, baseFamilyName, scale); }
    pub fn addMappings(self: *@This(), fontFallback: ?*anyopaque) !void { try hrCheck(self.lpVtbl.AddMappings(self, fontFallback)); }
    pub fn AddMappings(self: *@This(), fontFallback: ?*anyopaque) !void { try self.addMappings(fontFallback); }
    pub fn createFontFallback(self: *@This(), fontFallback: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateFontFallback(self, fontFallback)); }
    pub fn CreateFontFallback(self: *@This(), fontFallback: *?*anyopaque) !void { try self.createFontFallback(fontFallback); }
};

pub const DWRITE_GLYPH_RUN_DESCRIPTION = extern struct {
    localeName: PWSTR,
    string: PWSTR,
    stringLength: u32,
    clusterMap: *u16,
    textPosition: u32,
};

pub const IDWriteColorGlyphRunEnumerator = extern struct {
    pub const IID = GUID{ .data1 = 0xd31fbe17, .data2 = 0xf157, .data3 = 0x41a2, .data4 = .{ 0x8d, 0x24, 0xcb, 0x77, 0x9e, 0x05, 0x60, 0xe8 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        MoveNext: *const fn (*anyopaque, *BOOL) callconv(.winapi) HRESULT,
        GetCurrentRun: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn moveNext(self: *@This(), hasRun: *BOOL) !void { try hrCheck(self.lpVtbl.MoveNext(self, hasRun)); }
    pub fn MoveNext(self: *@This(), hasRun: *BOOL) !void { try self.moveNext(hasRun); }
    pub fn getCurrentRun(self: *@This(), colorGlyphRun: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetCurrentRun(self, colorGlyphRun)); }
    pub fn GetCurrentRun(self: *@This(), colorGlyphRun: *?*anyopaque) !void { try self.getCurrentRun(colorGlyphRun); }
};

pub const DWRITE_GRID_FIT_MODE = struct {
    pub const DWRITE_GRID_FIT_MODE_DEFAULT: i32 = 0;
    pub const DWRITE_GRID_FIT_MODE_DISABLED: i32 = 1;
    pub const DWRITE_GRID_FIT_MODE_ENABLED: i32 = 2;
};

pub const IDWriteRenderingParams2 = extern struct {
    pub const IID = GUID{ .data1 = 0xf9d711c3, .data2 = 0x9777, .data3 = 0x40ae, .data4 = .{ 0x87, 0xe8, 0x3e, 0x5a, 0xf9, 0xbf, 0x09, 0x48 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetGamma: *const fn (*anyopaque) callconv(.winapi) f32,
        GetEnhancedContrast: *const fn (*anyopaque) callconv(.winapi) f32,
        GetClearTypeLevel: *const fn (*anyopaque) callconv(.winapi) f32,
        GetPixelGeometry: *const fn (*anyopaque) callconv(.winapi) i32,
        GetRenderingMode: *const fn (*anyopaque) callconv(.winapi) i32,
        GetGrayscaleEnhancedContrast: *const fn (*anyopaque) callconv(.winapi) f32,
        GetGridFitMode: *const fn (*anyopaque) callconv(.winapi) i32,
    };
    pub const Requires_IDWriteRenderingParams1 = true; // requires IDWriteRenderingParams1
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn GetGrayscaleEnhancedContrast(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams1); _ = try base.GetGrayscaleEnhancedContrast(); }
    pub fn getGridFitMode(self: *@This()) !void { try hrCheck(self.lpVtbl.GetGridFitMode(self)); }
    pub fn GetGridFitMode(self: *@This()) !void { try self.getGridFitMode(); }
};

pub const DWRITE_TEXT_ANTIALIAS_MODE = struct {
    pub const DWRITE_TEXT_ANTIALIAS_MODE_CLEARTYPE: i32 = 0;
    pub const DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE: i32 = 1;
};

pub const IDWriteRenderingParams1 = extern struct {
    pub const IID = GUID{ .data1 = 0x94413cf4, .data2 = 0xa6fc, .data3 = 0x4248, .data4 = .{ 0x8b, 0x50, 0x66, 0x74, 0x34, 0x8f, 0xca, 0xd3 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetGamma: *const fn (*anyopaque) callconv(.winapi) f32,
        GetEnhancedContrast: *const fn (*anyopaque) callconv(.winapi) f32,
        GetClearTypeLevel: *const fn (*anyopaque) callconv(.winapi) f32,
        GetPixelGeometry: *const fn (*anyopaque) callconv(.winapi) i32,
        GetRenderingMode: *const fn (*anyopaque) callconv(.winapi) i32,
        GetGrayscaleEnhancedContrast: *const fn (*anyopaque) callconv(.winapi) f32,
    };
    pub const Requires_IDWriteRenderingParams = true; // requires IDWriteRenderingParams
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn GetGamma(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams); _ = try base.GetGamma(); }
    pub fn GetEnhancedContrast(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams); _ = try base.GetEnhancedContrast(); }
    pub fn GetClearTypeLevel(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams); _ = try base.GetClearTypeLevel(); }
    pub fn GetPixelGeometry(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams); _ = try base.GetPixelGeometry(); }
    pub fn GetRenderingMode(self: *@This()) !void { const base = try self.queryInterface(IDWriteRenderingParams); _ = try base.GetRenderingMode(); }
    pub fn getGrayscaleEnhancedContrast(self: *@This()) !void { try hrCheck(self.lpVtbl.GetGrayscaleEnhancedContrast(self)); }
    pub fn GetGrayscaleEnhancedContrast(self: *@This()) !void { try self.getGrayscaleEnhancedContrast(); }
};

pub const IDWriteFactory1 = extern struct {
    pub const IID = GUID{ .data1 = 0x30572f99, .data2 = 0xdac6, .data3 = 0x41db, .data4 = .{ 0xa1, 0x6e, 0x04, 0x86, 0x30, 0x7e, 0x60, 0x6a } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSystemFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        CreateCustomFontCollection: *const fn (*anyopaque, ?*anyopaque, *void, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontCollectionLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFileReference: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomFontFileReference: *const fn (*anyopaque, *void, u32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateFontFace: *const fn (*anyopaque, i32, u32, *?*anyopaque, u32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateRenderingParams: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateMonitorRenderingParams: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams: *const fn (*anyopaque, f32, f32, f32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
        RegisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        UnregisterFontFileLoader: *const fn (*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextFormat: *const fn (*anyopaque, ?*anyopaque, ?*anyopaque, i32, i32, i32, f32, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTypography: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetGdiInterop: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGdiCompatibleTextLayout: *const fn (*anyopaque, ?*anyopaque, u32, ?*anyopaque, f32, f32, f32, *?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateEllipsisTrimmingSign: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateTextAnalyzer: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateNumberSubstitution: *const fn (*anyopaque, i32, ?*anyopaque, BOOL, *?*anyopaque) callconv(.winapi) HRESULT,
        CreateGlyphRunAnalysis: *const fn (*anyopaque, *?*anyopaque, f32, *?*anyopaque, i32, i32, f32, f32, *?*anyopaque) callconv(.winapi) HRESULT,
        GetEudcFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(.winapi) HRESULT,
        CreateCustomRenderingParams_2: *const fn (*anyopaque, f32, f32, f32, f32, i32, i32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWriteFactory = true; // requires IDWriteFactory
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn getEudcFontCollection(self: *@This(), fontCollection: *?*anyopaque, checkForUpdates: BOOL) !void { try hrCheck(self.lpVtbl.GetEudcFontCollection(self, fontCollection, checkForUpdates)); }
    pub fn GetEudcFontCollection(self: *@This(), fontCollection: *?*anyopaque, checkForUpdates: BOOL) !void { try self.getEudcFontCollection(fontCollection, checkForUpdates); }
    pub fn createCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, enhancedContrastGrayscale: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, renderingParams: *?*anyopaque) !void { try hrCheck(self.lpVtbl.CreateCustomRenderingParams(self, gamma, enhancedContrast, enhancedContrastGrayscale, clearTypeLevel, pixelGeometry, renderingMode, renderingParams)); }
    pub fn CreateCustomRenderingParams(self: *@This(), gamma: f32, enhancedContrast: f32, enhancedContrastGrayscale: f32, clearTypeLevel: f32, pixelGeometry: i32, renderingMode: i32, renderingParams: *?*anyopaque) !void { try self.createCustomRenderingParams(gamma, enhancedContrast, enhancedContrastGrayscale, clearTypeLevel, pixelGeometry, renderingMode, renderingParams); }
};

pub const DWRITE_INFORMATIONAL_STRING_ID = struct {
    pub const DWRITE_INFORMATIONAL_STRING_NONE: i32 = 0;
    pub const DWRITE_INFORMATIONAL_STRING_COPYRIGHT_NOTICE: i32 = 1;
    pub const DWRITE_INFORMATIONAL_STRING_VERSION_STRINGS: i32 = 2;
    pub const DWRITE_INFORMATIONAL_STRING_TRADEMARK: i32 = 3;
    pub const DWRITE_INFORMATIONAL_STRING_MANUFACTURER: i32 = 4;
    pub const DWRITE_INFORMATIONAL_STRING_DESIGNER: i32 = 5;
    pub const DWRITE_INFORMATIONAL_STRING_DESIGNER_URL: i32 = 6;
    pub const DWRITE_INFORMATIONAL_STRING_DESCRIPTION: i32 = 7;
    pub const DWRITE_INFORMATIONAL_STRING_FONT_VENDOR_URL: i32 = 8;
    pub const DWRITE_INFORMATIONAL_STRING_LICENSE_DESCRIPTION: i32 = 9;
    pub const DWRITE_INFORMATIONAL_STRING_LICENSE_INFO_URL: i32 = 10;
    pub const DWRITE_INFORMATIONAL_STRING_WIN32_FAMILY_NAMES: i32 = 11;
    pub const DWRITE_INFORMATIONAL_STRING_WIN32_SUBFAMILY_NAMES: i32 = 12;
    pub const DWRITE_INFORMATIONAL_STRING_TYPOGRAPHIC_FAMILY_NAMES: i32 = 13;
    pub const DWRITE_INFORMATIONAL_STRING_TYPOGRAPHIC_SUBFAMILY_NAMES: i32 = 14;
    pub const DWRITE_INFORMATIONAL_STRING_SAMPLE_TEXT: i32 = 15;
    pub const DWRITE_INFORMATIONAL_STRING_FULL_NAME: i32 = 16;
    pub const DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME: i32 = 17;
    pub const DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_CID_NAME: i32 = 18;
    pub const DWRITE_INFORMATIONAL_STRING_WEIGHT_STRETCH_STYLE_FAMILY_NAME: i32 = 19;
    pub const DWRITE_INFORMATIONAL_STRING_DESIGN_SCRIPT_LANGUAGE_TAG: i32 = 20;
    pub const DWRITE_INFORMATIONAL_STRING_SUPPORTED_SCRIPT_LANGUAGE_TAG: i32 = 21;
    pub const DWRITE_INFORMATIONAL_STRING_PREFERRED_FAMILY_NAMES: i32 = 13;
    pub const DWRITE_INFORMATIONAL_STRING_PREFERRED_SUBFAMILY_NAMES: i32 = 14;
    pub const DWRITE_INFORMATIONAL_STRING_WWS_FAMILY_NAME: i32 = 19;
};

pub const DWRITE_FONT_METRICS = extern struct {
    designUnitsPerEm: u16,
    ascent: u16,
    descent: u16,
    lineGap: i16,
    capHeight: u16,
    xHeight: u16,
    underlinePosition: i16,
    underlineThickness: u16,
    strikethroughPosition: i16,
    strikethroughThickness: u16,
};

pub const IDWriteFontList = extern struct {
    pub const IID = GUID{ .data1 = 0x1a0d8438, .data2 = 0x1d97, .data3 = 0x4ec1, .data4 = .{ 0xae, 0xf9, 0xa2, 0xfb, 0x86, 0xed, 0x6a, 0xcb } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontCollection: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetFontCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFont: *const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn getFontCollection(self: *@This(), fontCollection: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFontCollection(self, fontCollection)); }
    pub fn GetFontCollection(self: *@This(), fontCollection: *?*anyopaque) !void { try self.getFontCollection(fontCollection); }
    pub fn getFontCount(self: *@This()) !void { try hrCheck(self.lpVtbl.GetFontCount(self)); }
    pub fn GetFontCount(self: *@This()) !void { try self.getFontCount(); }
    pub fn getFont(self: *@This(), index: u32, font: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetFont(self, index, font)); }
    pub fn GetFont(self: *@This(), index: u32, font: *?*anyopaque) !void { try self.getFont(index, font); }
};

pub const DWRITE_GLYPH_METRICS = extern struct {
    leftSideBearing: i32,
    advanceWidth: u32,
    rightSideBearing: i32,
    topSideBearing: i32,
    advanceHeight: u32,
    bottomSideBearing: i32,
    verticalOriginY: i32,
};

pub const DWRITE_GLYPH_OFFSET = extern struct {
    advanceOffset: f32,
    ascenderOffset: f32,
};

pub const ID2D1SimplifiedGeometrySink = extern struct {
    pub const IID = GUID{ .data1 = 0x2cd9069e, .data2 = 0x12e2, .data3 = 0x11dc, .data4 = .{ 0x9f, 0xed, 0x00, 0x11, 0x43, 0xa0, 0x55, 0xf9 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetFillMode: *const fn (*anyopaque, i32) callconv(.winapi) void,
        SetSegmentFlags: *const fn (*anyopaque, i32) callconv(.winapi) void,
        BeginFigure: *const fn (*anyopaque, ?*anyopaque, i32) callconv(.winapi) void,
        AddLines: *const fn (*anyopaque, *?*anyopaque, u32) callconv(.winapi) void,
        AddBeziers: *const fn (*anyopaque, *?*anyopaque, u32) callconv(.winapi) void,
        EndFigure: *const fn (*anyopaque, i32) callconv(.winapi) void,
        Close: *const fn (*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn setFillMode(self: *@This(), fillMode: i32) !void { try hrCheck(self.lpVtbl.SetFillMode(self, fillMode)); }
    pub fn SetFillMode(self: *@This(), fillMode: i32) !void { try self.setFillMode(fillMode); }
    pub fn setSegmentFlags(self: *@This(), vertexFlags: i32) !void { try hrCheck(self.lpVtbl.SetSegmentFlags(self, vertexFlags)); }
    pub fn SetSegmentFlags(self: *@This(), vertexFlags: i32) !void { try self.setSegmentFlags(vertexFlags); }
    pub fn beginFigure(self: *@This(), startPoint: ?*anyopaque, figureBegin: i32) !void { try hrCheck(self.lpVtbl.BeginFigure(self, startPoint, figureBegin)); }
    pub fn BeginFigure(self: *@This(), startPoint: ?*anyopaque, figureBegin: i32) !void { try self.beginFigure(startPoint, figureBegin); }
    pub fn addLines(self: *@This(), points: *?*anyopaque, pointsCount: u32) !void { try hrCheck(self.lpVtbl.AddLines(self, points, pointsCount)); }
    pub fn AddLines(self: *@This(), points: *?*anyopaque, pointsCount: u32) !void { try self.addLines(points, pointsCount); }
    pub fn addBeziers(self: *@This(), beziers: *?*anyopaque, beziersCount: u32) !void { try hrCheck(self.lpVtbl.AddBeziers(self, beziers, beziersCount)); }
    pub fn AddBeziers(self: *@This(), beziers: *?*anyopaque, beziersCount: u32) !void { try self.addBeziers(beziers, beziersCount); }
    pub fn endFigure(self: *@This(), figureEnd: i32) !void { try hrCheck(self.lpVtbl.EndFigure(self, figureEnd)); }
    pub fn EndFigure(self: *@This(), figureEnd: i32) !void { try self.endFigure(figureEnd); }
    pub fn close(self: *@This()) !void { try hrCheck(self.lpVtbl.Close(self)); }
    pub fn Close(self: *@This()) !void { try self.close(); }
};

pub const DWRITE_FONT_FILE_TYPE = struct {
    pub const DWRITE_FONT_FILE_TYPE_UNKNOWN: i32 = 0;
    pub const DWRITE_FONT_FILE_TYPE_CFF: i32 = 1;
    pub const DWRITE_FONT_FILE_TYPE_TRUETYPE: i32 = 2;
    pub const DWRITE_FONT_FILE_TYPE_OPENTYPE_COLLECTION: i32 = 3;
    pub const DWRITE_FONT_FILE_TYPE_TYPE1_PFM: i32 = 4;
    pub const DWRITE_FONT_FILE_TYPE_TYPE1_PFB: i32 = 5;
    pub const DWRITE_FONT_FILE_TYPE_VECTOR: i32 = 6;
    pub const DWRITE_FONT_FILE_TYPE_BITMAP: i32 = 7;
    pub const DWRITE_FONT_FILE_TYPE_TRUETYPE_COLLECTION: i32 = 3;
};

pub const DWRITE_READING_DIRECTION = struct {
    pub const DWRITE_READING_DIRECTION_LEFT_TO_RIGHT: i32 = 0;
    pub const DWRITE_READING_DIRECTION_RIGHT_TO_LEFT: i32 = 1;
    pub const DWRITE_READING_DIRECTION_TOP_TO_BOTTOM: i32 = 2;
    pub const DWRITE_READING_DIRECTION_BOTTOM_TO_TOP: i32 = 3;
};

pub const IDWriteFontFileStream = extern struct {
    pub const IID = GUID{ .data1 = 0x6d4865fe, .data2 = 0x0ab8, .data3 = 0x4d91, .data4 = .{ 0x8f, 0x62, 0x5d, 0xd6, 0xbe, 0x34, 0xa3, 0xe0 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        ReadFileFragment: *const fn (*anyopaque, *?*anyopaque, u64, u64, *?*anyopaque) callconv(.winapi) HRESULT,
        ReleaseFileFragment: *const fn (*anyopaque, *void) callconv(.winapi) void,
        GetFileSize: *const fn (*anyopaque, *u64) callconv(.winapi) HRESULT,
        GetLastWriteTime: *const fn (*anyopaque, *u64) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn readFileFragment(self: *@This(), fragmentStart: *?*anyopaque, fileOffset: u64, fragmentSize: u64, fragmentContext: *?*anyopaque) !void { try hrCheck(self.lpVtbl.ReadFileFragment(self, fragmentStart, fileOffset, fragmentSize, fragmentContext)); }
    pub fn ReadFileFragment(self: *@This(), fragmentStart: *?*anyopaque, fileOffset: u64, fragmentSize: u64, fragmentContext: *?*anyopaque) !void { try self.readFileFragment(fragmentStart, fileOffset, fragmentSize, fragmentContext); }
    pub fn releaseFileFragment(self: *@This(), fragmentContext: *void) !void { try hrCheck(self.lpVtbl.ReleaseFileFragment(self, fragmentContext)); }
    pub fn ReleaseFileFragment(self: *@This(), fragmentContext: *void) !void { try self.releaseFileFragment(fragmentContext); }
    pub fn getFileSize(self: *@This(), fileSize: *u64) !void { try hrCheck(self.lpVtbl.GetFileSize(self, fileSize)); }
    pub fn GetFileSize(self: *@This(), fileSize: *u64) !void { try self.getFileSize(fileSize); }
    pub fn getLastWriteTime(self: *@This(), lastWriteTime: *u64) !void { try hrCheck(self.lpVtbl.GetLastWriteTime(self, lastWriteTime)); }
    pub fn GetLastWriteTime(self: *@This(), lastWriteTime: *u64) !void { try self.getLastWriteTime(lastWriteTime); }
};

pub const IDWriteFontFileEnumerator = extern struct {
    pub const IID = GUID{ .data1 = 0x72755049, .data2 = 0x5ff7, .data3 = 0x435d, .data4 = .{ 0x83, 0x48, 0x4b, 0xe9, 0x7c, 0xfa, 0x6c, 0x7c } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        MoveNext: *const fn (*anyopaque, *BOOL) callconv(.winapi) HRESULT,
        GetCurrentFontFile: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn moveNext(self: *@This(), hasCurrentFile: *BOOL) !void { try hrCheck(self.lpVtbl.MoveNext(self, hasCurrentFile)); }
    pub fn MoveNext(self: *@This(), hasCurrentFile: *BOOL) !void { try self.moveNext(hasCurrentFile); }
    pub fn getCurrentFontFile(self: *@This(), fontFile: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetCurrentFontFile(self, fontFile)); }
    pub fn GetCurrentFontFile(self: *@This(), fontFile: *?*anyopaque) !void { try self.getCurrentFontFile(fontFile); }
};

pub const DWRITE_TEXT_ALIGNMENT = struct {
    pub const DWRITE_TEXT_ALIGNMENT_LEADING: i32 = 0;
    pub const DWRITE_TEXT_ALIGNMENT_TRAILING: i32 = 1;
    pub const DWRITE_TEXT_ALIGNMENT_CENTER: i32 = 2;
    pub const DWRITE_TEXT_ALIGNMENT_JUSTIFIED: i32 = 3;
};

pub const DWRITE_PARAGRAPH_ALIGNMENT = struct {
    pub const DWRITE_PARAGRAPH_ALIGNMENT_NEAR: i32 = 0;
    pub const DWRITE_PARAGRAPH_ALIGNMENT_FAR: i32 = 1;
    pub const DWRITE_PARAGRAPH_ALIGNMENT_CENTER: i32 = 2;
};

pub const DWRITE_WORD_WRAPPING = struct {
    pub const DWRITE_WORD_WRAPPING_WRAP: i32 = 0;
    pub const DWRITE_WORD_WRAPPING_NO_WRAP: i32 = 1;
    pub const DWRITE_WORD_WRAPPING_EMERGENCY_BREAK: i32 = 2;
    pub const DWRITE_WORD_WRAPPING_WHOLE_WORD: i32 = 3;
    pub const DWRITE_WORD_WRAPPING_CHARACTER: i32 = 4;
};

pub const DWRITE_FLOW_DIRECTION = struct {
    pub const DWRITE_FLOW_DIRECTION_TOP_TO_BOTTOM: i32 = 0;
    pub const DWRITE_FLOW_DIRECTION_BOTTOM_TO_TOP: i32 = 1;
    pub const DWRITE_FLOW_DIRECTION_LEFT_TO_RIGHT: i32 = 2;
    pub const DWRITE_FLOW_DIRECTION_RIGHT_TO_LEFT: i32 = 3;
};

pub const DWRITE_TRIMMING = extern struct {
    granularity: i32,
    delimiter: u32,
    delimiterCount: u32,
};

pub const DWRITE_LINE_SPACING_METHOD = struct {
    pub const DWRITE_LINE_SPACING_METHOD_DEFAULT: i32 = 0;
    pub const DWRITE_LINE_SPACING_METHOD_UNIFORM: i32 = 1;
    pub const DWRITE_LINE_SPACING_METHOD_PROPORTIONAL: i32 = 2;
};

pub const DWRITE_FONT_FEATURE = extern struct {
    nameTag: i32,
    parameter: u32,
};

pub const LOGFONTW = extern struct {
    lfHeight: i32,
    lfWidth: i32,
    lfEscapement: i32,
    lfOrientation: i32,
    lfWeight: i32,
    lfItalic: u8,
    lfUnderline: u8,
    lfStrikeOut: u8,
    lfCharSet: i32,
    lfOutPrecision: i32,
    lfClipPrecision: i32,
    lfQuality: i32,
    lfPitchAndFamily: u8,
    lfFaceName: ?*anyopaque,
};

pub const HDC = extern struct {
    Value: *void,
};

pub const IDWriteBitmapRenderTarget = extern struct {
    pub const IID = GUID{ .data1 = 0x5e5a32a3, .data2 = 0x8dff, .data3 = 0x4773, .data4 = .{ 0x9f, 0xf6, 0x06, 0x96, 0xea, 0xb7, 0x72, 0x67 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        DrawGlyphRun: *const fn (*anyopaque, f32, f32, i32, *?*anyopaque, ?*anyopaque, ?*anyopaque, *RECT) callconv(.winapi) HRESULT,
        GetMemoryDC: *const fn (*anyopaque) callconv(.winapi) HDC,
        GetPixelsPerDip: *const fn (*anyopaque) callconv(.winapi) f32,
        SetPixelsPerDip: *const fn (*anyopaque, f32) callconv(.winapi) HRESULT,
        GetCurrentTransform: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        SetCurrentTransform: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        GetSize: *const fn (*anyopaque, *?*anyopaque) callconv(.winapi) HRESULT,
        Resize: *const fn (*anyopaque, u32, u32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn drawGlyphRun(self: *@This(), baselineOriginX: f32, baselineOriginY: f32, measuringMode: i32, glyphRun: *?*anyopaque, renderingParams: ?*anyopaque, textColor: ?*anyopaque, blackBoxRect: *RECT) !void { try hrCheck(self.lpVtbl.DrawGlyphRun(self, baselineOriginX, baselineOriginY, measuringMode, glyphRun, renderingParams, textColor, blackBoxRect)); }
    pub fn DrawGlyphRun(self: *@This(), baselineOriginX: f32, baselineOriginY: f32, measuringMode: i32, glyphRun: *?*anyopaque, renderingParams: ?*anyopaque, textColor: ?*anyopaque, blackBoxRect: *RECT) !void { try self.drawGlyphRun(baselineOriginX, baselineOriginY, measuringMode, glyphRun, renderingParams, textColor, blackBoxRect); }
    pub fn getMemoryDC(self: *@This()) !void { try hrCheck(self.lpVtbl.GetMemoryDC(self)); }
    pub fn GetMemoryDC(self: *@This()) !void { try self.getMemoryDC(); }
    pub fn getPixelsPerDip(self: *@This()) !void { try hrCheck(self.lpVtbl.GetPixelsPerDip(self)); }
    pub fn GetPixelsPerDip(self: *@This()) !void { try self.getPixelsPerDip(); }
    pub fn setPixelsPerDip(self: *@This(), pixelsPerDip: f32) !void { try hrCheck(self.lpVtbl.SetPixelsPerDip(self, pixelsPerDip)); }
    pub fn SetPixelsPerDip(self: *@This(), pixelsPerDip: f32) !void { try self.setPixelsPerDip(pixelsPerDip); }
    pub fn getCurrentTransform(self: *@This(), transform: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetCurrentTransform(self, transform)); }
    pub fn GetCurrentTransform(self: *@This(), transform: *?*anyopaque) !void { try self.getCurrentTransform(transform); }
    pub fn setCurrentTransform(self: *@This(), transform: *?*anyopaque) !void { try hrCheck(self.lpVtbl.SetCurrentTransform(self, transform)); }
    pub fn SetCurrentTransform(self: *@This(), transform: *?*anyopaque) !void { try self.setCurrentTransform(transform); }
    pub fn getSize(self: *@This(), size: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetSize(self, size)); }
    pub fn GetSize(self: *@This(), size: *?*anyopaque) !void { try self.getSize(size); }
    pub fn resize(self: *@This(), width: u32, height: u32) !void { try hrCheck(self.lpVtbl.Resize(self, width, height)); }
    pub fn Resize(self: *@This(), width: u32, height: u32) !void { try self.resize(width, height); }
};

pub const DWRITE_TEXT_RANGE = extern struct {
    startPosition: u32,
    length: u32,
};

pub const IDWriteTextRenderer = extern struct {
    pub const IID = GUID{ .data1 = 0xef8a8135, .data2 = 0x5cc6, .data3 = 0x45fe, .data4 = .{ 0x88, 0x25, 0xc5, 0xa0, 0x72, 0x4e, 0xb8, 0x19 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        IsPixelSnappingDisabled: *const fn (*anyopaque, *void, *BOOL) callconv(.winapi) HRESULT,
        GetCurrentTransform: *const fn (*anyopaque, *void, *?*anyopaque) callconv(.winapi) HRESULT,
        GetPixelsPerDip: *const fn (*anyopaque, *void, *f32) callconv(.winapi) HRESULT,
        DrawGlyphRun: *const fn (*anyopaque, *void, f32, f32, i32, *?*anyopaque, *?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        DrawUnderline: *const fn (*anyopaque, *void, f32, f32, *?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        DrawStrikethrough: *const fn (*anyopaque, *void, f32, f32, *?*anyopaque, ?*anyopaque) callconv(.winapi) HRESULT,
        DrawInlineObject: *const fn (*anyopaque, *void, f32, f32, ?*anyopaque, BOOL, BOOL, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IDWritePixelSnapping = true; // requires IDWritePixelSnapping
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn drawGlyphRun(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, measuringMode: i32, glyphRun: *?*anyopaque, glyphRunDescription: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try hrCheck(self.lpVtbl.DrawGlyphRun(self, clientDrawingContext, baselineOriginX, baselineOriginY, measuringMode, glyphRun, glyphRunDescription, clientDrawingEffect)); }
    pub fn DrawGlyphRun(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, measuringMode: i32, glyphRun: *?*anyopaque, glyphRunDescription: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try self.drawGlyphRun(clientDrawingContext, baselineOriginX, baselineOriginY, measuringMode, glyphRun, glyphRunDescription, clientDrawingEffect); }
    pub fn drawUnderline(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, underline: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try hrCheck(self.lpVtbl.DrawUnderline(self, clientDrawingContext, baselineOriginX, baselineOriginY, underline, clientDrawingEffect)); }
    pub fn DrawUnderline(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, underline: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try self.drawUnderline(clientDrawingContext, baselineOriginX, baselineOriginY, underline, clientDrawingEffect); }
    pub fn drawStrikethrough(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, strikethrough: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try hrCheck(self.lpVtbl.DrawStrikethrough(self, clientDrawingContext, baselineOriginX, baselineOriginY, strikethrough, clientDrawingEffect)); }
    pub fn DrawStrikethrough(self: *@This(), clientDrawingContext: *void, baselineOriginX: f32, baselineOriginY: f32, strikethrough: *?*anyopaque, clientDrawingEffect: ?*anyopaque) !void { try self.drawStrikethrough(clientDrawingContext, baselineOriginX, baselineOriginY, strikethrough, clientDrawingEffect); }
    pub fn drawInlineObject(self: *@This(), clientDrawingContext: *void, originX: f32, originY: f32, inlineObject: ?*anyopaque, isSideways: BOOL, isRightToLeft: BOOL, clientDrawingEffect: ?*anyopaque) !void { try hrCheck(self.lpVtbl.DrawInlineObject(self, clientDrawingContext, originX, originY, inlineObject, isSideways, isRightToLeft, clientDrawingEffect)); }
    pub fn DrawInlineObject(self: *@This(), clientDrawingContext: *void, originX: f32, originY: f32, inlineObject: ?*anyopaque, isSideways: BOOL, isRightToLeft: BOOL, clientDrawingEffect: ?*anyopaque) !void { try self.drawInlineObject(clientDrawingContext, originX, originY, inlineObject, isSideways, isRightToLeft, clientDrawingEffect); }
};

pub const DWRITE_LINE_METRICS = extern struct {
    length: u32,
    trailingWhitespaceLength: u32,
    newlineLength: u32,
    height: f32,
    baseline: f32,
    isTrimmed: BOOL,
};

pub const DWRITE_TEXT_METRICS = extern struct {
    left: f32,
    top: f32,
    width: f32,
    widthIncludingTrailingWhitespace: f32,
    height: f32,
    layoutWidth: f32,
    layoutHeight: f32,
    maxBidiReorderingDepth: u32,
    lineCount: u32,
};

pub const DWRITE_OVERHANG_METRICS = extern struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

pub const DWRITE_CLUSTER_METRICS = extern struct {
    width: f32,
    length: u16,
    _bitfield: u16,
};

pub const DWRITE_HIT_TEST_METRICS = extern struct {
    textPosition: u32,
    length: u32,
    left: f32,
    top: f32,
    width: f32,
    height: f32,
    bidiLevel: u32,
    isText: BOOL,
    isTrimmed: BOOL,
};

pub const DWRITE_INLINE_OBJECT_METRICS = extern struct {
    width: f32,
    height: f32,
    baseline: f32,
    supportsSideways: BOOL,
};

pub const DWRITE_BREAK_CONDITION = struct {
    pub const DWRITE_BREAK_CONDITION_NEUTRAL: i32 = 0;
    pub const DWRITE_BREAK_CONDITION_CAN_BREAK: i32 = 1;
    pub const DWRITE_BREAK_CONDITION_MAY_NOT_BREAK: i32 = 2;
    pub const DWRITE_BREAK_CONDITION_MUST_BREAK: i32 = 3;
};

pub const IDWriteTextAnalysisSink = extern struct {
    pub const IID = GUID{ .data1 = 0x5810cd44, .data2 = 0x0ca0, .data3 = 0x4701, .data4 = .{ 0xb3, 0xfa, 0xbe, 0xc5, 0x18, 0x2a, 0xe4, 0xf6 } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        SetScriptAnalysis: *const fn (*anyopaque, u32, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        SetLineBreakpoints: *const fn (*anyopaque, u32, u32, *?*anyopaque) callconv(.winapi) HRESULT,
        SetBidiLevel: *const fn (*anyopaque, u32, u32, u8, u8) callconv(.winapi) HRESULT,
        SetNumberSubstitution: *const fn (*anyopaque, u32, u32, ?*anyopaque) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn setScriptAnalysis(self: *@This(), textPosition: u32, textLength: u32, scriptAnalysis: *?*anyopaque) !void { try hrCheck(self.lpVtbl.SetScriptAnalysis(self, textPosition, textLength, scriptAnalysis)); }
    pub fn SetScriptAnalysis(self: *@This(), textPosition: u32, textLength: u32, scriptAnalysis: *?*anyopaque) !void { try self.setScriptAnalysis(textPosition, textLength, scriptAnalysis); }
    pub fn setLineBreakpoints(self: *@This(), textPosition: u32, textLength: u32, lineBreakpoints: *?*anyopaque) !void { try hrCheck(self.lpVtbl.SetLineBreakpoints(self, textPosition, textLength, lineBreakpoints)); }
    pub fn SetLineBreakpoints(self: *@This(), textPosition: u32, textLength: u32, lineBreakpoints: *?*anyopaque) !void { try self.setLineBreakpoints(textPosition, textLength, lineBreakpoints); }
    pub fn setBidiLevel(self: *@This(), textPosition: u32, textLength: u32, explicitLevel: u8, resolvedLevel: u8) !void { try hrCheck(self.lpVtbl.SetBidiLevel(self, textPosition, textLength, explicitLevel, resolvedLevel)); }
    pub fn SetBidiLevel(self: *@This(), textPosition: u32, textLength: u32, explicitLevel: u8, resolvedLevel: u8) !void { try self.setBidiLevel(textPosition, textLength, explicitLevel, resolvedLevel); }
    pub fn setNumberSubstitution(self: *@This(), textPosition: u32, textLength: u32, numberSubstitution: ?*anyopaque) !void { try hrCheck(self.lpVtbl.SetNumberSubstitution(self, textPosition, textLength, numberSubstitution)); }
    pub fn SetNumberSubstitution(self: *@This(), textPosition: u32, textLength: u32, numberSubstitution: ?*anyopaque) !void { try self.setNumberSubstitution(textPosition, textLength, numberSubstitution); }
};

pub const DWRITE_SCRIPT_ANALYSIS = extern struct {
    script: u16,
    shapes: i32,
};

pub const DWRITE_TYPOGRAPHIC_FEATURES = extern struct {
    features: *DWRITE_FONT_FEATURE,
    featureCount: u32,
};

pub const DWRITE_SHAPING_TEXT_PROPERTIES = extern struct {
    _bitfield: u16,
};

pub const DWRITE_SHAPING_GLYPH_PROPERTIES = extern struct {
    _bitfield: u16,
};

pub const DWRITE_TEXTURE_TYPE = struct {
    pub const DWRITE_TEXTURE_ALIASED_1x1: i32 = 0;
    pub const DWRITE_TEXTURE_CLEARTYPE_3x1: i32 = 1;
};

pub const DWRITE_UNICODE_RANGE = extern struct {
    first: u32,
    last: u32,
};

pub const DWRITE_COLOR_GLYPH_RUN = extern struct {
    glyphRun: DWRITE_GLYPH_RUN,
    glyphRunDescription: *DWRITE_GLYPH_RUN_DESCRIPTION,
    baselineOriginX: f32,
    baselineOriginY: f32,
    runColor: DWRITE_COLOR_F,
    paletteIndex: u16,
};

pub const D2D1_FILL_MODE = struct {
    pub const D2D1_FILL_MODE_ALTERNATE: i32 = 0;
    pub const D2D1_FILL_MODE_WINDING: i32 = 1;
};

pub const D2D1_PATH_SEGMENT = struct {
    pub const D2D1_PATH_SEGMENT_NONE: i32 = 0;
    pub const D2D1_PATH_SEGMENT_FORCE_UNSTROKED: i32 = 1;
    pub const D2D1_PATH_SEGMENT_FORCE_ROUND_LINE_JOIN: i32 = 2;
};

pub const D2D_POINT_2F = extern struct {
    x: f32,
    y: f32,
};

pub const D2D1_FIGURE_BEGIN = struct {
    pub const D2D1_FIGURE_BEGIN_FILLED: i32 = 0;
    pub const D2D1_FIGURE_BEGIN_HOLLOW: i32 = 1;
};

pub const D2D1_BEZIER_SEGMENT = extern struct {
    point1: D2D_POINT_2F,
    point2: D2D_POINT_2F,
    point3: D2D_POINT_2F,
};

pub const D2D1_FIGURE_END = struct {
    pub const D2D1_FIGURE_END_OPEN: i32 = 0;
    pub const D2D1_FIGURE_END_CLOSED: i32 = 1;
};

pub const DWRITE_TRIMMING_GRANULARITY = struct {
    pub const DWRITE_TRIMMING_GRANULARITY_NONE: i32 = 0;
    pub const DWRITE_TRIMMING_GRANULARITY_CHARACTER: i32 = 1;
    pub const DWRITE_TRIMMING_GRANULARITY_WORD: i32 = 2;
};

pub const DWRITE_FONT_FEATURE_TAG = struct {
    pub const DWRITE_FONT_FEATURE_TAG_ALTERNATIVE_FRACTIONS: i32 = 1668441697;
    pub const DWRITE_FONT_FEATURE_TAG_PETITE_CAPITALS_FROM_CAPITALS: i32 = 1668297315;
    pub const DWRITE_FONT_FEATURE_TAG_SMALL_CAPITALS_FROM_CAPITALS: i32 = 1668493923;
    pub const DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_ALTERNATES: i32 = 1953259875;
    pub const DWRITE_FONT_FEATURE_TAG_CASE_SENSITIVE_FORMS: i32 = 1702060387;
    pub const DWRITE_FONT_FEATURE_TAG_GLYPH_COMPOSITION_DECOMPOSITION: i32 = 1886217059;
    pub const DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_LIGATURES: i32 = 1734962275;
    pub const DWRITE_FONT_FEATURE_TAG_CAPITAL_SPACING: i32 = 1886613603;
    pub const DWRITE_FONT_FEATURE_TAG_CONTEXTUAL_SWASH: i32 = 1752658787;
    pub const DWRITE_FONT_FEATURE_TAG_CURSIVE_POSITIONING: i32 = 1936880995;
    pub const DWRITE_FONT_FEATURE_TAG_DEFAULT: i32 = 1953261156;
    pub const DWRITE_FONT_FEATURE_TAG_DISCRETIONARY_LIGATURES: i32 = 1734962276;
    pub const DWRITE_FONT_FEATURE_TAG_EXPERT_FORMS: i32 = 1953527909;
    pub const DWRITE_FONT_FEATURE_TAG_FRACTIONS: i32 = 1667330662;
    pub const DWRITE_FONT_FEATURE_TAG_FULL_WIDTH: i32 = 1684633446;
    pub const DWRITE_FONT_FEATURE_TAG_HALF_FORMS: i32 = 1718378856;
    pub const DWRITE_FONT_FEATURE_TAG_HALANT_FORMS: i32 = 1852596584;
    pub const DWRITE_FONT_FEATURE_TAG_ALTERNATE_HALF_WIDTH: i32 = 1953259880;
    pub const DWRITE_FONT_FEATURE_TAG_HISTORICAL_FORMS: i32 = 1953720680;
    pub const DWRITE_FONT_FEATURE_TAG_HORIZONTAL_KANA_ALTERNATES: i32 = 1634626408;
    pub const DWRITE_FONT_FEATURE_TAG_HISTORICAL_LIGATURES: i32 = 1734962280;
    pub const DWRITE_FONT_FEATURE_TAG_HALF_WIDTH: i32 = 1684633448;
    pub const DWRITE_FONT_FEATURE_TAG_HOJO_KANJI_FORMS: i32 = 1869246312;
    pub const DWRITE_FONT_FEATURE_TAG_JIS04_FORMS: i32 = 875589738;
    pub const DWRITE_FONT_FEATURE_TAG_JIS78_FORMS: i32 = 943157354;
    pub const DWRITE_FONT_FEATURE_TAG_JIS83_FORMS: i32 = 859336810;
    pub const DWRITE_FONT_FEATURE_TAG_JIS90_FORMS: i32 = 809070698;
    pub const DWRITE_FONT_FEATURE_TAG_KERNING: i32 = 1852990827;
    pub const DWRITE_FONT_FEATURE_TAG_STANDARD_LIGATURES: i32 = 1634167148;
    pub const DWRITE_FONT_FEATURE_TAG_LINING_FIGURES: i32 = 1836412524;
    pub const DWRITE_FONT_FEATURE_TAG_LOCALIZED_FORMS: i32 = 1818455916;
    pub const DWRITE_FONT_FEATURE_TAG_MARK_POSITIONING: i32 = 1802658157;
    pub const DWRITE_FONT_FEATURE_TAG_MATHEMATICAL_GREEK: i32 = 1802659693;
    pub const DWRITE_FONT_FEATURE_TAG_MARK_TO_MARK_POSITIONING: i32 = 1802333037;
    pub const DWRITE_FONT_FEATURE_TAG_ALTERNATE_ANNOTATION_FORMS: i32 = 1953259886;
    pub const DWRITE_FONT_FEATURE_TAG_NLC_KANJI_FORMS: i32 = 1801677934;
    pub const DWRITE_FONT_FEATURE_TAG_OLD_STYLE_FIGURES: i32 = 1836412527;
    pub const DWRITE_FONT_FEATURE_TAG_ORDINALS: i32 = 1852076655;
    pub const DWRITE_FONT_FEATURE_TAG_PROPORTIONAL_ALTERNATE_WIDTH: i32 = 1953259888;
    pub const DWRITE_FONT_FEATURE_TAG_PETITE_CAPITALS: i32 = 1885430640;
    pub const DWRITE_FONT_FEATURE_TAG_PROPORTIONAL_FIGURES: i32 = 1836412528;
    pub const DWRITE_FONT_FEATURE_TAG_PROPORTIONAL_WIDTHS: i32 = 1684633456;
    pub const DWRITE_FONT_FEATURE_TAG_QUARTER_WIDTHS: i32 = 1684633457;
    pub const DWRITE_FONT_FEATURE_TAG_REQUIRED_LIGATURES: i32 = 1734962290;
    pub const DWRITE_FONT_FEATURE_TAG_RUBY_NOTATION_FORMS: i32 = 2036495730;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_ALTERNATES: i32 = 1953259891;
    pub const DWRITE_FONT_FEATURE_TAG_SCIENTIFIC_INFERIORS: i32 = 1718511987;
    pub const DWRITE_FONT_FEATURE_TAG_SMALL_CAPITALS: i32 = 1885564275;
    pub const DWRITE_FONT_FEATURE_TAG_SIMPLIFIED_FORMS: i32 = 1819307379;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_1: i32 = 825258867;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_2: i32 = 842036083;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_3: i32 = 858813299;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_4: i32 = 875590515;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_5: i32 = 892367731;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_6: i32 = 909144947;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_7: i32 = 925922163;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_8: i32 = 942699379;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_9: i32 = 959476595;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_10: i32 = 808547187;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_11: i32 = 825324403;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_12: i32 = 842101619;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_13: i32 = 858878835;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_14: i32 = 875656051;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_15: i32 = 892433267;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_16: i32 = 909210483;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_17: i32 = 925987699;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_18: i32 = 942764915;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_19: i32 = 959542131;
    pub const DWRITE_FONT_FEATURE_TAG_STYLISTIC_SET_20: i32 = 808612723;
    pub const DWRITE_FONT_FEATURE_TAG_SUBSCRIPT: i32 = 1935832435;
    pub const DWRITE_FONT_FEATURE_TAG_SUPERSCRIPT: i32 = 1936749939;
    pub const DWRITE_FONT_FEATURE_TAG_SWASH: i32 = 1752397683;
    pub const DWRITE_FONT_FEATURE_TAG_TITLING: i32 = 1819568500;
    pub const DWRITE_FONT_FEATURE_TAG_TRADITIONAL_NAME_FORMS: i32 = 1835101812;
    pub const DWRITE_FONT_FEATURE_TAG_TABULAR_FIGURES: i32 = 1836412532;
    pub const DWRITE_FONT_FEATURE_TAG_TRADITIONAL_FORMS: i32 = 1684107892;
    pub const DWRITE_FONT_FEATURE_TAG_THIRD_WIDTHS: i32 = 1684633460;
    pub const DWRITE_FONT_FEATURE_TAG_UNICASE: i32 = 1667853941;
    pub const DWRITE_FONT_FEATURE_TAG_VERTICAL_WRITING: i32 = 1953654134;
    pub const DWRITE_FONT_FEATURE_TAG_VERTICAL_ALTERNATES_AND_ROTATION: i32 = 846492278;
    pub const DWRITE_FONT_FEATURE_TAG_SLASHED_ZERO: i32 = 1869768058;
};

pub const FONT_CHARSET = struct {
    pub const ANSI_CHARSET: i32 = 0;
    pub const DEFAULT_CHARSET: i32 = 0;
    pub const SYMBOL_CHARSET: i32 = 0;
    pub const SHIFTJIS_CHARSET: i32 = 0;
    pub const HANGEUL_CHARSET: i32 = 0;
    pub const HANGUL_CHARSET: i32 = 0;
    pub const GB2312_CHARSET: i32 = 0;
    pub const CHINESEBIG5_CHARSET: i32 = 0;
    pub const OEM_CHARSET: i32 = 0;
    pub const JOHAB_CHARSET: i32 = 0;
    pub const HEBREW_CHARSET: i32 = 0;
    pub const ARABIC_CHARSET: i32 = 0;
    pub const GREEK_CHARSET: i32 = 0;
    pub const TURKISH_CHARSET: i32 = 0;
    pub const VIETNAMESE_CHARSET: i32 = 0;
    pub const THAI_CHARSET: i32 = 0;
    pub const EASTEUROPE_CHARSET: i32 = 0;
    pub const RUSSIAN_CHARSET: i32 = 0;
    pub const MAC_CHARSET: i32 = 0;
    pub const BALTIC_CHARSET: i32 = 0;
};

pub const FONT_OUTPUT_PRECISION = struct {
    pub const OUT_DEFAULT_PRECIS: i32 = 0;
    pub const OUT_STRING_PRECIS: i32 = 0;
    pub const OUT_CHARACTER_PRECIS: i32 = 0;
    pub const OUT_STROKE_PRECIS: i32 = 0;
    pub const OUT_TT_PRECIS: i32 = 0;
    pub const OUT_DEVICE_PRECIS: i32 = 0;
    pub const OUT_RASTER_PRECIS: i32 = 0;
    pub const OUT_TT_ONLY_PRECIS: i32 = 0;
    pub const OUT_OUTLINE_PRECIS: i32 = 0;
    pub const OUT_SCREEN_OUTLINE_PRECIS: i32 = 0;
    pub const OUT_PS_ONLY_PRECIS: i32 = 0;
};

pub const FONT_CLIP_PRECISION = struct {
    pub const CLIP_DEFAULT_PRECIS: i32 = 0;
    pub const CLIP_CHARACTER_PRECIS: i32 = 0;
    pub const CLIP_STROKE_PRECIS: i32 = 0;
    pub const CLIP_MASK: i32 = 0;
    pub const CLIP_LH_ANGLES: i32 = 0;
    pub const CLIP_TT_ALWAYS: i32 = 0;
    pub const CLIP_DFA_DISABLE: i32 = 0;
    pub const CLIP_EMBEDDED: i32 = 0;
    pub const CLIP_DFA_OVERRIDE: i32 = 0;
};

pub const FONT_QUALITY = struct {
    pub const DEFAULT_QUALITY: i32 = 0;
    pub const DRAFT_QUALITY: i32 = 0;
    pub const PROOF_QUALITY: i32 = 0;
    pub const NONANTIALIASED_QUALITY: i32 = 0;
    pub const ANTIALIASED_QUALITY: i32 = 0;
    pub const CLEARTYPE_QUALITY: i32 = 0;
};

pub const COLORREF = extern struct {
    Value: u32,
};

pub const SIZE = extern struct {
    cx: i32,
    cy: i32,
};

pub const DWRITE_UNDERLINE = extern struct {
    width: f32,
    thickness: f32,
    offset: f32,
    runHeight: f32,
    readingDirection: i32,
    flowDirection: i32,
    localeName: PWSTR,
    measuringMode: i32,
};

pub const DWRITE_STRIKETHROUGH = extern struct {
    width: f32,
    thickness: f32,
    offset: f32,
    readingDirection: i32,
    flowDirection: i32,
    localeName: PWSTR,
    measuringMode: i32,
};

pub const IDWritePixelSnapping = extern struct {
    pub const IID = GUID{ .data1 = 0xeaf3a2da, .data2 = 0xecf4, .data3 = 0x4d24, .data4 = .{ 0xb6, 0x44, 0xb3, 0x4f, 0x68, 0x42, 0x02, 0x4b } };
    lpVtbl: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        IsPixelSnappingDisabled: *const fn (*anyopaque, *void, *BOOL) callconv(.winapi) HRESULT,
        GetCurrentTransform: *const fn (*anyopaque, *void, *?*anyopaque) callconv(.winapi) HRESULT,
        GetPixelsPerDip: *const fn (*anyopaque, *void, *f32) callconv(.winapi) HRESULT,
    };
    pub const Requires_IUnknown = true; // requires IUnknown
    pub fn release(self: *@This()) void { comRelease(self); }
    pub fn queryInterface(self: *@This(), comptime T: type) !*T { return comQueryInterface(self, T); }
    pub fn AddRef(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.AddRef(); }
    pub fn Release(self: *@This()) !void { const base = try self.queryInterface(IUnknown); _ = try base.Release(); }
    pub fn isPixelSnappingDisabled(self: *@This(), clientDrawingContext: *void, isDisabled: *BOOL) !void { try hrCheck(self.lpVtbl.IsPixelSnappingDisabled(self, clientDrawingContext, isDisabled)); }
    pub fn IsPixelSnappingDisabled(self: *@This(), clientDrawingContext: *void, isDisabled: *BOOL) !void { try self.isPixelSnappingDisabled(clientDrawingContext, isDisabled); }
    pub fn getCurrentTransform(self: *@This(), clientDrawingContext: *void, transform: *?*anyopaque) !void { try hrCheck(self.lpVtbl.GetCurrentTransform(self, clientDrawingContext, transform)); }
    pub fn GetCurrentTransform(self: *@This(), clientDrawingContext: *void, transform: *?*anyopaque) !void { try self.getCurrentTransform(clientDrawingContext, transform); }
    pub fn getPixelsPerDip(self: *@This(), clientDrawingContext: *void, pixelsPerDip: *f32) !void { try hrCheck(self.lpVtbl.GetPixelsPerDip(self, clientDrawingContext, pixelsPerDip)); }
    pub fn GetPixelsPerDip(self: *@This(), clientDrawingContext: *void, pixelsPerDip: *f32) !void { try self.getPixelsPerDip(clientDrawingContext, pixelsPerDip); }
};

pub const DWRITE_LINE_BREAKPOINT = extern struct {
    _bitfield: u8,
};

pub const DWRITE_SCRIPT_SHAPES = struct {
    pub const DWRITE_SCRIPT_SHAPES_DEFAULT: i32 = 0;
    pub const DWRITE_SCRIPT_SHAPES_NO_VISUAL: i32 = 1;
};

pub const DWRITE_COLOR_F = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

