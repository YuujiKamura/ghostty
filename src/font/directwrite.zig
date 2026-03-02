//! DirectWrite-based font discovery for Windows.
//!
//! Used when the freetype backend is selected on Windows, providing
//! font enumeration and discovery through the DirectWrite API while
//! still using FreeType for rendering.
const DirectWrite = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const font = @import("main.zig");
const options = font.options;
const DeferredFace = font.DeferredFace;
const Face = font.Face;
const Variation = font.face.Variation;
const Collection = font.Collection;
const Descriptor = @import("discovery.zig").Descriptor;

const log = std.log.scoped(.discovery);

// --- Windows types ---
const BOOL = c_int;
const HRESULT = c_long;
const GUID = std.os.windows.GUID;

// --- DirectWrite constants ---
const DWRITE_FACTORY_TYPE_SHARED: u32 = 0;
const DWRITE_FONT_WEIGHT_BOLD: u32 = 700;
const DWRITE_FONT_STYLE_NORMAL: u32 = 0;
const DWRITE_FONT_STYLE_OBLIQUE: u32 = 1;
const DWRITE_FONT_STYLE_ITALIC: u32 = 2;
const DWRITE_INFORMATIONAL_STRING_FULL_NAME: u32 = 16;

// --- GUIDs ---
const IID_IDWriteFactory = GUID{
    .Data1 = 0xb859ee5a,
    .Data2 = 0xd838,
    .Data3 = 0x4b5b,
    .Data4 = .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 },
};

const IID_IDWriteLocalFontFileLoader = GUID{
    .Data1 = 0xb2d9f3ec,
    .Data2 = 0xc9fe,
    .Data3 = 0x4a11,
    .Data4 = .{ 0xa2, 0xec, 0xd8, 0x62, 0x08, 0xf7, 0xc0, 0xa2 },
};

// --- DWriteCreateFactory ---
extern "dwrite" fn DWriteCreateFactory(
    factory_type: u32,
    riid: *const GUID,
    factory: *?*anyopaque,
) callconv(.winapi) HRESULT;

// ============================================================================
// COM Interface Definitions
//
// Each interface is an extern struct whose first field is a pointer to
// its vtable.  Vtable entries use *anyopaque for the self parameter to
// avoid circular-type issues.  Convenience methods cast and forward.
//
// IMPORTANT: vtable slot order MUST match dwrite.h exactly.
// ============================================================================

// Placeholder for vtable slots we don't call.
const VtblPlaceholder = *const anyopaque;

const IDWriteFactory = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFactory (slots 3-23)
        GetSystemFontCollection: *const fn (*anyopaque, *?*IDWriteFontCollection, BOOL) callconv(.winapi) HRESULT,
        CreateCustomFontCollection: VtblPlaceholder,
        RegisterFontCollectionLoader: VtblPlaceholder,
        UnregisterFontCollectionLoader: VtblPlaceholder,
        CreateFontFileReference: VtblPlaceholder,
        CreateCustomFontFileReference: VtblPlaceholder,
        CreateFontFace: VtblPlaceholder,
        CreateRenderingParams: VtblPlaceholder,
        CreateMonitorRenderingParams: VtblPlaceholder,
        CreateCustomRenderingParams: VtblPlaceholder,
        RegisterFontFileLoader: VtblPlaceholder,
        UnregisterFontFileLoader: VtblPlaceholder,
        CreateTextFormat: VtblPlaceholder,
        CreateTypography: VtblPlaceholder,
        GetGdiInterop: VtblPlaceholder,
        CreateTextLayout: VtblPlaceholder,
        CreateGdiCompatibleTextLayout: VtblPlaceholder,
        CreateEllipsisTrimmingSign: VtblPlaceholder,
        CreateTextAnalyzer: VtblPlaceholder,
        CreateNumberSubstitution: VtblPlaceholder,
        CreateGlyphRunAnalysis: VtblPlaceholder,
    };

    fn release(self: *IDWriteFactory) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getSystemFontCollection(self: *IDWriteFactory) !*IDWriteFontCollection {
        var collection: ?*IDWriteFontCollection = null;
        const hr = self.lpVtbl.GetSystemFontCollection(@ptrCast(self), &collection, 0);
        if (hr < 0) return error.DWriteError;
        return collection orelse error.DWriteError;
    }
};

const IDWriteFontCollection = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontCollection (slots 3-6)
        GetFontFamilyCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFontFamily: *const fn (*anyopaque, u32, *?*IDWriteFontFamily) callconv(.winapi) HRESULT,
        FindFamilyName: *const fn (*anyopaque, [*:0]const u16, *u32, *BOOL) callconv(.winapi) HRESULT,
        GetFontFromFontFace: VtblPlaceholder,
    };

    fn release(self: *IDWriteFontCollection) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getFontFamilyCount(self: *IDWriteFontCollection) u32 {
        return self.lpVtbl.GetFontFamilyCount(@ptrCast(self));
    }

    fn getFontFamily(self: *IDWriteFontCollection, index: u32) !*IDWriteFontFamily {
        var family: ?*IDWriteFontFamily = null;
        const hr = self.lpVtbl.GetFontFamily(@ptrCast(self), index, &family);
        if (hr < 0) return error.DWriteError;
        return family orelse error.DWriteError;
    }

    fn findFamilyName(self: *IDWriteFontCollection, name: [*:0]const u16) !?u32 {
        var index: u32 = 0;
        var exists: BOOL = 0;
        const hr = self.lpVtbl.FindFamilyName(@ptrCast(self), name, &index, &exists);
        if (hr < 0) return error.DWriteError;
        return if (exists != 0) index else null;
    }
};

// IDWriteFontFamily inherits IDWriteFontList inherits IUnknown
const IDWriteFontFamily = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontList (slots 3-5)
        GetFontCollection: VtblPlaceholder,
        GetFontCount: *const fn (*anyopaque) callconv(.winapi) u32,
        GetFont: *const fn (*anyopaque, u32, *?*IDWriteFont) callconv(.winapi) HRESULT,
        // IDWriteFontFamily (slot 6)
        GetFamilyNames: *const fn (*anyopaque, *?*IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
    };

    fn release(self: *IDWriteFontFamily) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getFontCount(self: *IDWriteFontFamily) u32 {
        return self.lpVtbl.GetFontCount(@ptrCast(self));
    }

    fn getFont(self: *IDWriteFontFamily, index: u32) !*IDWriteFont {
        var f: ?*IDWriteFont = null;
        const hr = self.lpVtbl.GetFont(@ptrCast(self), index, &f);
        if (hr < 0) return error.DWriteError;
        return f orelse error.DWriteError;
    }

    fn getFamilyNames(self: *IDWriteFontFamily) !*IDWriteLocalizedStrings {
        var names: ?*IDWriteLocalizedStrings = null;
        const hr = self.lpVtbl.GetFamilyNames(@ptrCast(self), &names);
        if (hr < 0) return error.DWriteError;
        return names orelse error.DWriteError;
    }
};

const IDWriteFont = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFont (slots 3-13)
        GetFontFamily: *const fn (*anyopaque, *?*IDWriteFontFamily) callconv(.winapi) HRESULT,
        GetWeight: *const fn (*anyopaque) callconv(.winapi) u32,
        GetStretch: VtblPlaceholder,
        GetStyle: *const fn (*anyopaque) callconv(.winapi) u32,
        IsSymbolFont: VtblPlaceholder,
        GetFaceNames: *const fn (*anyopaque, *?*IDWriteLocalizedStrings) callconv(.winapi) HRESULT,
        GetInformationalStrings: *const fn (*anyopaque, u32, *?*IDWriteLocalizedStrings, *BOOL) callconv(.winapi) HRESULT,
        GetSimulations: VtblPlaceholder,
        GetMetrics: VtblPlaceholder,
        HasCharacter: *const fn (*anyopaque, u32, *BOOL) callconv(.winapi) HRESULT,
        CreateFontFace: *const fn (*anyopaque, *?*IDWriteFontFace) callconv(.winapi) HRESULT,
    };

    fn addRef(self: *IDWriteFont) u32 {
        return self.lpVtbl.AddRef(@ptrCast(self));
    }

    fn release(self: *IDWriteFont) u32 {
        return self.lpVtbl.Release(@ptrCast(self));
    }

    fn getWeight(self: *IDWriteFont) u32 {
        return self.lpVtbl.GetWeight(@ptrCast(self));
    }

    fn getStyle(self: *IDWriteFont) u32 {
        return self.lpVtbl.GetStyle(@ptrCast(self));
    }

    fn hasCharacter(self: *IDWriteFont, cp: u32) bool {
        var exists: BOOL = 0;
        const hr = self.lpVtbl.HasCharacter(@ptrCast(self), cp, &exists);
        return hr >= 0 and exists != 0;
    }

    fn createFontFace(self: *IDWriteFont) !*IDWriteFontFace {
        var face: ?*IDWriteFontFace = null;
        const hr = self.lpVtbl.CreateFontFace(@ptrCast(self), &face);
        if (hr < 0) return error.DWriteError;
        return face orelse error.DWriteError;
    }

    fn getFontFamily(self: *IDWriteFont) !*IDWriteFontFamily {
        var family: ?*IDWriteFontFamily = null;
        const hr = self.lpVtbl.GetFontFamily(@ptrCast(self), &family);
        if (hr < 0) return error.DWriteError;
        return family orelse error.DWriteError;
    }

    fn getFaceNames(self: *IDWriteFont) !*IDWriteLocalizedStrings {
        var names: ?*IDWriteLocalizedStrings = null;
        const hr = self.lpVtbl.GetFaceNames(@ptrCast(self), &names);
        if (hr < 0) return error.DWriteError;
        return names orelse error.DWriteError;
    }

    fn getInformationalStrings(
        self: *IDWriteFont,
        string_id: u32,
    ) ?*IDWriteLocalizedStrings {
        var names: ?*IDWriteLocalizedStrings = null;
        var exists: BOOL = 0;
        const hr = self.lpVtbl.GetInformationalStrings(@ptrCast(self), string_id, &names, &exists);
        if (hr < 0 or exists == 0) return null;
        return names;
    }
};

const IDWriteFontFace = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontFace (slots 3-17)
        GetType: VtblPlaceholder,
        GetFiles: *const fn (*anyopaque, *u32, ?*?*IDWriteFontFile) callconv(.winapi) HRESULT,
        GetIndex: *const fn (*anyopaque) callconv(.winapi) u32,
        GetSimulations: VtblPlaceholder,
        IsSymbolFont: VtblPlaceholder,
        GetMetrics: VtblPlaceholder,
        GetGlyphCount: VtblPlaceholder,
        GetDesignGlyphMetrics: VtblPlaceholder,
        GetGlyphIndices: VtblPlaceholder,
        TryGetFontTable: VtblPlaceholder,
        ReleaseFontTable: VtblPlaceholder,
        GetGlyphRunOutline: VtblPlaceholder,
        GetRecommendedRenderingMode: VtblPlaceholder,
        GetGdiCompatibleMetrics: VtblPlaceholder,
        GetGdiCompatibleGlyphMetrics: VtblPlaceholder,
    };

    fn release(self: *IDWriteFontFace) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getIndex(self: *IDWriteFontFace) u32 {
        return self.lpVtbl.GetIndex(@ptrCast(self));
    }

    fn getFiles(self: *IDWriteFontFace) !*IDWriteFontFile {
        var num_files: u32 = 0;
        var hr = self.lpVtbl.GetFiles(@ptrCast(self), &num_files, null);
        if (hr < 0 or num_files == 0) return error.FontHasNoFile;

        var font_file: ?*IDWriteFontFile = null;
        num_files = 1;
        hr = self.lpVtbl.GetFiles(@ptrCast(self), &num_files, &font_file);
        if (hr < 0) return error.DWriteError;
        return font_file orelse error.DWriteError;
    }
};

const IDWriteFontFile = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontFile (slots 3-5)
        GetReferenceKey: *const fn (*anyopaque, *?*const anyopaque, *u32) callconv(.winapi) HRESULT,
        GetLoader: *const fn (*anyopaque, *?*IDWriteFontFileLoader) callconv(.winapi) HRESULT,
        Analyze: VtblPlaceholder,
    };

    fn release(self: *IDWriteFontFile) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getReferenceKey(self: *IDWriteFontFile) !struct { key: *const anyopaque, size: u32 } {
        var key: ?*const anyopaque = null;
        var size: u32 = 0;
        const hr = self.lpVtbl.GetReferenceKey(@ptrCast(self), &key, &size);
        if (hr < 0) return error.DWriteError;
        return .{ .key = key orelse return error.DWriteError, .size = size };
    }

    fn getLoader(self: *IDWriteFontFile) !*IDWriteFontFileLoader {
        var loader: ?*IDWriteFontFileLoader = null;
        const hr = self.lpVtbl.GetLoader(@ptrCast(self), &loader);
        if (hr < 0) return error.DWriteError;
        return loader orelse error.DWriteError;
    }
};

const IDWriteFontFileLoader = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontFileLoader (slot 3)
        CreateStreamFromKey: VtblPlaceholder,
    };

    fn release(self: *IDWriteFontFileLoader) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn queryInterfaceLocalLoader(self: *IDWriteFontFileLoader) ?*IDWriteLocalFontFileLoader {
        var local_loader: ?*anyopaque = null;
        const hr = self.lpVtbl.QueryInterface(@ptrCast(self), &IID_IDWriteLocalFontFileLoader, &local_loader);
        if (hr < 0 or local_loader == null) return null;
        return @ptrCast(@alignCast(local_loader.?));
    }
};

const IDWriteLocalFontFileLoader = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteFontFileLoader (slot 3)
        CreateStreamFromKey: VtblPlaceholder,
        // IDWriteLocalFontFileLoader (slots 4-6)
        GetFilePathLengthFromKey: *const fn (*anyopaque, ?*const anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        GetFilePathFromKey: *const fn (*anyopaque, ?*const anyopaque, u32, [*]u16, u32) callconv(.winapi) HRESULT,
        GetLastWriteTimeFromKey: VtblPlaceholder,
    };

    fn release(self: *IDWriteLocalFontFileLoader) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    fn getFilePath(
        self: *IDWriteLocalFontFileLoader,
        key: *const anyopaque,
        key_size: u32,
        buf: []u16,
    ) ![]const u16 {
        var path_len: u32 = 0;
        var hr = self.lpVtbl.GetFilePathLengthFromKey(@ptrCast(self), key, key_size, &path_len);
        if (hr < 0) return error.DWriteError;
        if (path_len + 1 > buf.len) return error.FontPathTooLong;
        hr = self.lpVtbl.GetFilePathFromKey(@ptrCast(self), key, key_size, buf.ptr, path_len + 1);
        if (hr < 0) return error.DWriteError;
        return buf[0..path_len];
    }
};

const IDWriteLocalizedStrings = extern struct {
    lpVtbl: *const VTable,

    const VTable = extern struct {
        // IUnknown (slots 0-2)
        QueryInterface: VtblPlaceholder,
        AddRef: VtblPlaceholder,
        Release: *const fn (*anyopaque) callconv(.winapi) u32,
        // IDWriteLocalizedStrings (slots 3-8)
        GetCount: VtblPlaceholder,
        FindLocaleName: VtblPlaceholder,
        GetLocaleNameLength: VtblPlaceholder,
        GetLocaleName: VtblPlaceholder,
        GetStringLength: *const fn (*anyopaque, u32, *u32) callconv(.winapi) HRESULT,
        GetString: *const fn (*anyopaque, u32, [*]u16, u32) callconv(.winapi) HRESULT,
    };

    fn release(self: *IDWriteLocalizedStrings) void {
        _ = self.lpVtbl.Release(@ptrCast(self));
    }

    /// Get the string at the given index, converting from UTF-16 to UTF-8.
    fn getString(self: *IDWriteLocalizedStrings, index: u32, buf: []u8) ?[]const u8 {
        var str_len: u32 = 0;
        if (self.lpVtbl.GetStringLength(@ptrCast(self), index, &str_len) < 0) return null;

        var utf16_buf: [512]u16 = undefined;
        if (str_len + 1 > utf16_buf.len) return null;
        if (self.lpVtbl.GetString(@ptrCast(self), index, &utf16_buf, str_len + 1) < 0) return null;

        return utf16ToUtf8(buf, utf16_buf[0..str_len]) catch null;
    }
};

// ============================================================================
// UTF conversion helpers
// ============================================================================

fn utf16ToUtf8(dest: []u8, src: []const u16) ![]const u8 {
    var dest_i: usize = 0;
    var src_i: usize = 0;
    while (src_i < src.len) {
        const cp: u21 = blk: {
            const high = src[src_i];
            if (high >= 0xD800 and high <= 0xDBFF) {
                src_i += 1;
                if (src_i >= src.len) return error.InvalidUtf16;
                const low = src[src_i];
                if (low < 0xDC00 or low > 0xDFFF) return error.InvalidUtf16;
                break :blk @as(u21, high - 0xD800) * 0x400 + @as(u21, low - 0xDC00) + 0x10000;
            } else if (high >= 0xDC00 and high <= 0xDFFF) {
                return error.InvalidUtf16;
            } else {
                break :blk @as(u21, high);
            }
        };
        src_i += 1;
        const len = std.unicode.utf8CodepointSequenceLength(cp) catch return error.InvalidUtf16;
        if (dest_i + len > dest.len) return error.BufferTooSmall;
        _ = std.unicode.utf8Encode(cp, dest[dest_i..][0..len]) catch return error.InvalidUtf16;
        dest_i += len;
    }
    return dest[0..dest_i];
}

fn utf8ToUtf16Le(dest: []u16, src: []const u8) !struct { str: [*:0]const u16, len: usize } {
    var dest_i: usize = 0;
    const view = std.unicode.Utf8View.initUnchecked(src);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (cp < 0x10000) {
            if (dest_i >= dest.len) return error.BufferTooSmall;
            dest[dest_i] = @intCast(cp);
            dest_i += 1;
        } else {
            if (dest_i + 1 >= dest.len) return error.BufferTooSmall;
            const shifted: u21 = cp - 0x10000;
            dest[dest_i] = @intCast(0xD800 + (shifted >> 10));
            dest[dest_i + 1] = @intCast(0xDC00 + @as(u16, @truncate(shifted & 0x3FF)));
            dest_i += 2;
        }
    }
    if (dest_i >= dest.len) return error.BufferTooSmall;
    dest[dest_i] = 0; // null-terminate
    return .{ .str = @ptrCast(dest.ptr), .len = dest_i };
}

// ============================================================================
// DirectWriteFace — stored in DeferredFace.dw
// ============================================================================

pub const DirectWriteFace = struct {
    dw_font: *IDWriteFont,
    variations: []const Variation,

    pub fn deinit(self: *DirectWriteFace) void {
        _ = self.dw_font.release();
        self.* = undefined;
    }

    pub fn hasCodepoint(self: DirectWriteFace, cp: u32) bool {
        return self.dw_font.hasCharacter(cp);
    }

    pub fn familyName(self: DirectWriteFace, buf: []u8) []const u8 {
        const family = self.dw_font.getFontFamily() catch return "";
        defer _ = family.release();

        const names = family.getFamilyNames() catch return "";
        defer names.release();

        return names.getString(0, buf) orelse "";
    }

    pub fn name(self: DirectWriteFace, buf: []u8) []const u8 {
        // Try FULL_NAME informational string first
        if (self.dw_font.getInformationalStrings(DWRITE_INFORMATIONAL_STRING_FULL_NAME)) |names| {
            defer names.release();
            if (names.getString(0, buf)) |s| if (s.len > 0) return s;
        }

        // Build "Family Style" from family name + face name
        const family_str = self.familyName(buf);
        const family_len = family_str.len;

        const face_names = self.dw_font.getFaceNames() catch return family_str;
        defer face_names.release();
        const style_str = face_names.getString(0, buf[family_len..]) orelse return family_str;

        if (style_str.len == 0) return family_str;
        if (family_len == 0) return style_str;

        // Insert space between family and style (shift style right by 1)
        if (family_len + 1 + style_str.len > buf.len) return family_str;
        std.mem.copyBackwards(u8, buf[family_len + 1 ..], buf[family_len .. family_len + style_str.len]);
        buf[family_len] = ' ';
        return buf[0 .. family_len + 1 + style_str.len];
    }

    pub fn load(
        self: *DirectWriteFace,
        lib: font.Library,
        opts: font.face.Options,
    ) !Face {
        // IDWriteFont → CreateFontFace → IDWriteFontFace
        const font_face = try self.dw_font.createFontFace();
        defer font_face.release();

        const face_index = font_face.getIndex();

        // IDWriteFontFace → GetFiles → IDWriteFontFile
        const font_file = try font_face.getFiles();
        defer font_file.release();

        // IDWriteFontFile → GetReferenceKey
        const ref = try font_file.getReferenceKey();

        // IDWriteFontFile → GetLoader → IDWriteFontFileLoader
        var loader = try font_file.getLoader();
        defer loader.release();

        // QI for IDWriteLocalFontFileLoader
        const local_loader = loader.queryInterfaceLocalLoader() orelse
            return error.FontNotLocal;
        defer local_loader.release();

        // GetFilePathFromKey → UTF-16 path
        var path_buf_w: [std.fs.max_path_bytes]u16 = undefined;
        const path_w = try local_loader.getFilePath(ref.key, ref.size, &path_buf_w);

        // UTF-16 → UTF-8
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path_utf8 = try utf16ToUtf8(&path_buf, path_w);
        if (path_utf8.len >= path_buf.len) return error.FontPathTooLong;
        path_buf[path_utf8.len] = 0;
        const path_z: [:0]const u8 = path_buf[0..path_utf8.len :0];

        var face = try Face.initFile(lib, path_z, @intCast(face_index), opts);
        errdefer face.deinit();
        try face.setVariations(self.variations, opts);
        return face;
    }
};

// ============================================================================
// DiscoverIterator
// ============================================================================

pub const DiscoverIterator = struct {
    alloc: Allocator,
    fonts: []*IDWriteFont,
    variations: []const Variation,
    i: usize,

    pub fn deinit(self: *DiscoverIterator) void {
        for (self.fonts) |f| _ = f.release();
        self.alloc.free(self.fonts);
        self.* = undefined;
    }

    pub fn next(self: *DiscoverIterator) !?DeferredFace {
        if (self.i >= self.fonts.len) return null;

        const dw_font = self.fonts[self.i];
        _ = dw_font.addRef(); // DeferredFace gets its own reference
        defer self.i += 1;

        return DeferredFace{
            .dw = .{
                .dw_font = dw_font,
                .variations = self.variations,
            },
        };
    }
};

// ============================================================================
// DirectWrite — the Discover implementation
// ============================================================================

factory: *IDWriteFactory,
collection: *IDWriteFontCollection,

pub fn init() DirectWrite {
    var factory_raw: ?*anyopaque = null;
    const hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        &IID_IDWriteFactory,
        &factory_raw,
    );
    if (hr < 0 or factory_raw == null) {
        log.err("DWriteCreateFactory failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        @panic("failed to create DirectWrite factory");
    }

    const factory: *IDWriteFactory = @ptrCast(@alignCast(factory_raw.?));
    const collection = factory.getSystemFontCollection() catch {
        log.err("GetSystemFontCollection failed", .{});
        @panic("failed to get system font collection");
    };

    return .{
        .factory = factory,
        .collection = collection,
    };
}

pub fn deinit(self: *DirectWrite) void {
    self.collection.release();
    self.factory.release();
}

/// Discover fonts from a descriptor.
pub fn discover(
    self: *const DirectWrite,
    alloc: Allocator,
    desc: Descriptor,
) !DiscoverIterator {
    var results: std.ArrayList(*IDWriteFont) = .empty;
    errdefer {
        for (results.items) |f| _ = f.release();
        results.deinit(alloc);
    }

    if (desc.family) |family| {
        // Search by family name
        var name_buf: [256]u16 = undefined;
        const conv = try utf8ToUtf16Le(&name_buf, family);
        if (self.collection.findFamilyName(conv.str) catch null) |family_index| {
            try self.collectFontsFromFamily(alloc, family_index, desc, &results);
        }
    } else if (desc.codepoint > 0) {
        // Search all families for codepoint support
        try self.searchByCodepoint(alloc, desc, &results);
    } else {
        // Enumerate all fonts (filtered by bold/italic/monospace)
        try self.enumerateAll(alloc, desc, &results);
    }

    const fonts = try results.toOwnedSlice(alloc);
    return .{
        .alloc = alloc,
        .fonts = fonts,
        .variations = desc.variations,
        .i = 0,
    };
}

/// Discover a fallback font. Delegates to discover().
pub fn discoverFallback(
    self: *const DirectWrite,
    alloc: Allocator,
    collection: *Collection,
    desc: Descriptor,
) !DiscoverIterator {
    _ = collection;
    return try self.discover(alloc, desc);
}

// --- Private helpers ---

fn enumerateAll(
    self: *const DirectWrite,
    alloc: Allocator,
    desc: Descriptor,
    results: *std.ArrayList(*IDWriteFont),
) !void {
    const family_count = self.collection.getFontFamilyCount();
    for (0..family_count) |fi| {
        const family = self.collection.getFontFamily(@intCast(fi)) catch continue;
        defer _ = family.release();

        const count = family.getFontCount();
        for (0..count) |i| {
            const dw_font = family.getFont(@intCast(i)) catch continue;
            errdefer _ = dw_font.release();

            if (!fontMatchesDesc(dw_font, desc)) {
                _ = dw_font.release();
                continue;
            }

            try results.append(alloc, dw_font);
        }
    }
}

fn collectFontsFromFamily(
    self: *const DirectWrite,
    alloc: Allocator,
    family_index: u32,
    desc: Descriptor,
    results: *std.ArrayList(*IDWriteFont),
) !void {
    const family = self.collection.getFontFamily(family_index) catch return;
    defer _ = family.release();

    const count = family.getFontCount();
    for (0..count) |i| {
        const dw_font = family.getFont(@intCast(i)) catch continue;
        errdefer _ = dw_font.release();

        if (!fontMatchesDesc(dw_font, desc)) {
            _ = dw_font.release();
            continue;
        }

        try results.append(alloc, dw_font);
    }
}

fn searchByCodepoint(
    self: *const DirectWrite,
    alloc: Allocator,
    desc: Descriptor,
    results: *std.ArrayList(*IDWriteFont),
) !void {
    const family_count = self.collection.getFontFamilyCount();
    for (0..family_count) |fi| {
        const family = self.collection.getFontFamily(@intCast(fi)) catch continue;
        defer _ = family.release();

        // Check first font in family for the codepoint
        const first_font = family.getFont(0) catch continue;
        const has_cp = first_font.hasCharacter(desc.codepoint);
        _ = first_font.release();
        if (!has_cp) continue;

        // This family has the codepoint - collect matching fonts
        const count = family.getFontCount();
        for (0..count) |i| {
            const dw_font = family.getFont(@intCast(i)) catch continue;
            errdefer _ = dw_font.release();

            if (!fontMatchesDesc(dw_font, desc)) {
                _ = dw_font.release();
                continue;
            }

            // Verify the specific font also has the codepoint
            if (desc.codepoint > 0 and !dw_font.hasCharacter(desc.codepoint)) {
                _ = dw_font.release();
                continue;
            }

            try results.append(alloc, dw_font);

            // For codepoint fallback, one match per family is enough
            if (desc.family == null) break;
        }
    }
}

fn fontMatchesDesc(dw_font: *IDWriteFont, desc: Descriptor) bool {
    // Filter by bold
    if (desc.bold) {
        if (dw_font.getWeight() < DWRITE_FONT_WEIGHT_BOLD) return false;
    } else {
        if (dw_font.getWeight() >= DWRITE_FONT_WEIGHT_BOLD) return false;
    }

    // Filter by italic
    if (desc.italic) {
        if (dw_font.getStyle() == DWRITE_FONT_STYLE_NORMAL) return false;
    } else {
        if (dw_font.getStyle() != DWRITE_FONT_STYLE_NORMAL) return false;
    }

    // Note: desc.monospace is not filtered here. Fontconfig also doesn't
    // hard-filter monospace (just prefers it via pattern scoring).
    // Proper monospace detection requires IDWriteFont1::GetPanose() or
    // creating a font face to check metrics, both of which are expensive.
    // The caller typically sets a family name for monospace fonts anyway.

    return true;
}
