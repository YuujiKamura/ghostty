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

const dw = @import("dwrite_generated.zig");

// --- Windows types ---
const BOOL = dw.BOOL;
const HRESULT = dw.HRESULT;
const GUID = dw.GUID;

// --- DirectWrite constants ---
const DWRITE_FACTORY_TYPE_SHARED: u32 = 0;
const DWRITE_FONT_WEIGHT_BOLD: u32 = 700;
const DWRITE_FONT_STYLE_NORMAL: u32 = 0;
const DWRITE_FONT_STYLE_OBLIQUE: u32 = 1;
const DWRITE_FONT_STYLE_ITALIC: u32 = 2;
const DWRITE_INFORMATIONAL_STRING_FULL_NAME: u32 = 16;
const DWRITE_FONT_STRETCH_MEDIUM: u32 = 5;

// --- GUIDs ---
const IID_IDWriteLocalFontFileLoader = dw.IDWriteLocalFontFileLoader.IID;
const IID_IDWriteFactory2 = dw.IDWriteFactory2.IID;

// --- Win32 imports ---
extern "kernel32" fn GetUserDefaultLocaleName(
    lpLocaleName: [*]u16,
    cchLocaleName: c_int,
) callconv(.winapi) c_int;

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

const IDWriteFactory = dw.IDWriteFactory;
const IDWriteFontCollection = dw.IDWriteFontCollection;
const IDWriteFontFamily = dw.IDWriteFontFamily;
const IDWriteFont = dw.IDWriteFont;
const IDWriteFontFace = dw.IDWriteFontFace;
const IDWriteFontFile = dw.IDWriteFontFile;
const IDWriteFontFileLoader = dw.IDWriteFontFileLoader;
const IDWriteLocalFontFileLoader = dw.IDWriteLocalFontFileLoader;
const IDWriteLocalizedStrings = dw.IDWriteLocalizedStrings;
const IDWriteFactory2 = dw.IDWriteFactory2;
const IDWriteFontFallback = dw.IDWriteFontFallback;
const IDWriteTextAnalysisSource = dw.IDWriteTextAnalysisSource;

/// Minimal IDWriteTextAnalysisSource implementation for MapCharacters.
const SimpleTextAnalysisSource = struct {
    // COM vtable pointer — MUST be the first field so that
    // @ptrCast(*SimpleTextAnalysisSource) == @ptrCast(*IDWriteTextAnalysisSource).
    lpVtbl: *const IDWriteTextAnalysisSource.VTable,
    text: [*]const u16,
    text_len: u32,
    locale: [*:0]const u16,

    const VTable = IDWriteTextAnalysisSource.VTable;

    const vtbl_instance = VTable{
        .QueryInterface = &queryInterface,
        .AddRef = &addRef,
        .Release = &release,
        .GetTextAtPosition = &getTextAtPosition,
        .GetTextBeforePosition = &getTextBeforePosition,
        .GetParagraphReadingDirection = &getParagraphReadingDirection,
        .GetLocaleName = &getLocaleName,
        .GetNumberSubstitution = &getNumberSubstitution,
    };

    fn init(text: [*]const u16, text_len: u32, locale: [*:0]const u16) SimpleTextAnalysisSource {
        return .{
            .lpVtbl = &vtbl_instance,
            .text = text,
            .text_len = text_len,
            .locale = locale,
        };
    }

    fn queryInterface(_: *anyopaque, _: *const GUID, _: *?*anyopaque) callconv(.winapi) HRESULT {
        return @as(HRESULT, @bitCast(@as(u32, 0x80004002))); // E_NOINTERFACE
    }
    fn addRef(_: *anyopaque) callconv(.winapi) u32 {
        return 1;
    }
    fn release(_: *anyopaque) callconv(.winapi) u32 {
        return 1;
    }
    fn getTextAtPosition(self_raw: *anyopaque, pos: u32, text_out: *?*anyopaque, len_out: *u32) callconv(.winapi) HRESULT {
        const self: *const SimpleTextAnalysisSource = @ptrCast(@alignCast(self_raw));
        if (pos >= self.text_len) {
            text_out.* = null;
            len_out.* = 0;
        } else {
            text_out.* = @ptrCast(@constCast(self.text + pos));
            len_out.* = self.text_len - pos;
        }
        return 0; // S_OK
    }
    fn getTextBeforePosition(self_raw: *anyopaque, pos: u32, text_out: *?*anyopaque, len_out: *u32) callconv(.winapi) HRESULT {
        const self: *const SimpleTextAnalysisSource = @ptrCast(@alignCast(self_raw));
        if (pos == 0 or pos > self.text_len) {
            text_out.* = null;
            len_out.* = 0;
        } else {
            text_out.* = @ptrCast(@constCast(self.text));
            len_out.* = pos;
        }
        return 0;
    }
    fn getParagraphReadingDirection(_: *anyopaque) callconv(.winapi) i32 {
        return 0; // DWRITE_READING_DIRECTION_LEFT_TO_RIGHT
    }
    fn getLocaleName(self_raw: *anyopaque, _: u32, len_out: *u32, locale_out: *?*anyopaque) callconv(.winapi) HRESULT {
        const self: *const SimpleTextAnalysisSource = @ptrCast(@alignCast(self_raw));
        locale_out.* = @ptrCast(@constCast(self.locale));
        len_out.* = self.text_len;
        return 0;
    }
    fn getNumberSubstitution(_: *anyopaque, _: u32, len_out: *u32, subst_out: *?*anyopaque) callconv(.winapi) HRESULT {
        len_out.* = 0;
        subst_out.* = null;
        return 0;
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

fn getString(names: *IDWriteLocalizedStrings, index: u32, buf: []u8) ?[]const u8 {
    var str_len: u32 = 0;
    names.getStringLength(index, &str_len) catch return null;

    var utf16_buf: [512]u16 = undefined;
    if (str_len + 1 > utf16_buf.len) return null;
    names.getString(index, @ptrCast(&utf16_buf), str_len + 1) catch return null;

    return utf16ToUtf8(buf, utf16_buf[0..str_len]) catch null;
}

// ============================================================================
// DirectWriteFace — stored in DeferredFace.dw
// ============================================================================

pub const DirectWriteFace = struct {
    dw_font: *IDWriteFont,
    variations: []const Variation,

    pub fn deinit(self: *DirectWriteFace) void {
        self.dw_font.release();
        self.* = undefined;
    }

    pub fn hasCodepoint(self: DirectWriteFace, cp: u32) bool {
        var exists: BOOL = 0;
        self.dw_font.hasCharacter(cp, &exists) catch {};
        return exists != 0;
    }

    pub fn familyName(self: DirectWriteFace, buf: []u8) []const u8 {
        var family_raw: ?*anyopaque = null;
        self.dw_font.getFontFamily(&family_raw) catch return "";
        if (family_raw == null) return "";
        const family: *IDWriteFontFamily = @ptrCast(@alignCast(family_raw.?));
        defer family.release();

        var names_raw: ?*anyopaque = null;
        family.getFamilyNames(&names_raw) catch return "";
        if (names_raw == null) return "";
        const names: *IDWriteLocalizedStrings = @ptrCast(@alignCast(names_raw.?));
        defer names.release();

        return getString(names, 0, buf) orelse "";
    }

    pub fn name(self: DirectWriteFace, buf: []u8) []const u8 {
        // Try FULL_NAME informational string first
        var names_raw: ?*anyopaque = null;
        var exists: BOOL = 0;
        self.dw_font.getInformationalStrings(@intCast(DWRITE_INFORMATIONAL_STRING_FULL_NAME), &names_raw, &exists) catch {};
        if (exists != 0 and names_raw != null) {
            const names: *IDWriteLocalizedStrings = @ptrCast(@alignCast(names_raw.?));
            defer names.release();
            if (getString(names, 0, buf)) |s| if (s.len > 0) return s;
        }

        // Build "Family Style" from family name + face name
        const family_str = self.familyName(buf);
        const family_len = family_str.len;

        var face_names_raw: ?*anyopaque = null;
        self.dw_font.getFaceNames(&face_names_raw) catch return family_str;
        if (face_names_raw == null) return family_str;
        const face_names: *IDWriteLocalizedStrings = @ptrCast(@alignCast(face_names_raw.?));
        defer face_names.release();
        const style_str = getString(face_names, 0, buf[family_len..]) orelse return family_str;

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
        var font_face_raw: ?*anyopaque = null;
        try self.dw_font.createFontFace(&font_face_raw);
        const font_face: *IDWriteFontFace = @ptrCast(@alignCast(font_face_raw.?));
        defer font_face.release();

        const face_index = font_face.lpVtbl.GetIndex(font_face);

        // IDWriteFontFace → GetFiles → IDWriteFontFile
        var num_files: u32 = 1;
        var font_file_raw: ?*anyopaque = null;
        try font_face.getFiles(&num_files, &font_file_raw);
        if (font_file_raw == null) return error.FontHasNoFile;
        const font_file: *IDWriteFontFile = @ptrCast(@alignCast(font_file_raw.?));
        defer font_file.release();

        // IDWriteFontFile → GetReferenceKey
        var ref_key: ?*anyopaque = null;
        var ref_size: u32 = 0;
        try font_file.getReferenceKey(&ref_key, &ref_size);

        // IDWriteFontFile → GetLoader → IDWriteFontFileLoader
        var loader_raw: ?*anyopaque = null;
        try font_file.getLoader(&loader_raw);
        const loader: *IDWriteFontFileLoader = @ptrCast(@alignCast(loader_raw.?));
        defer loader.release();

        // QI for IDWriteLocalFontFileLoader
        const local_loader = loader.queryInterface(IDWriteLocalFontFileLoader) catch
            return error.FontNotLocal;
        defer local_loader.release();

        // GetFilePathFromKey → UTF-16 path
        var path_len: u32 = 0;
        try local_loader.getFilePathLengthFromKey(@ptrCast(ref_key.?), ref_size, &path_len);
        var path_buf_w: [std.fs.max_path_bytes]u16 = undefined;
        if (path_len + 1 > path_buf_w.len) return error.FontPathTooLong;
        try local_loader.getFilePathFromKey(@ptrCast(ref_key.?), ref_size, @ptrCast(&path_buf_w), path_len + 1);
        const path_w = path_buf_w[0..path_len];

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
// DeferredFace switch-arm delegates
//
// UPSTREAM-SHARED-OK: minimize footprint only, preserves upstream tagged-union
// architecture (#239). Each helper makes the freetype switch arm in
// DeferredFace.zig a single-line delegation, reducing per-callsite footprint
// against upstream merges.
// ============================================================================

pub fn deferredDeinit(face: *?DirectWriteFace) void {
    if (face.*) |*f| f.deinit();
}

pub fn deferredFamilyName(face: ?DirectWriteFace, buf: []u8) ![]const u8 {
    if (face) |f| return f.familyName(buf);
    return "";
}

pub fn deferredName(face: ?DirectWriteFace, buf: []u8) ![]const u8 {
    if (face) |f| return f.name(buf);
    return "";
}

pub fn deferredLoad(face: *?DirectWriteFace, lib: font.Library, opts: font.face.Options) !Face {
    if (face.*) |*f| return f.load(lib, opts);
    unreachable;
}

pub fn deferredHasCodepoint(face: ?DirectWriteFace, cp: u32) bool {
    if (face) |f| return f.hasCodepoint(cp);
    return false;
}

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
        _ = dw_font.lpVtbl.AddRef(dw_font); // DeferredFace gets its own reference
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
factory2: ?*IDWriteFactory2,
collection: *IDWriteFontCollection,
font_fallback: ?*IDWriteFontFallback,

pub fn init() DirectWrite {
    var factory_raw: ?*anyopaque = null;
    const hr = DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        &IDWriteFactory.IID,
        &factory_raw,
    );

    if (hr < 0 or factory_raw == null) {
        log.err("DWriteCreateFactory failed: hr=0x{x}", .{@as(u32, @bitCast(hr))});
        @panic("failed to create DirectWrite factory");
    }

    const factory: *IDWriteFactory = @ptrCast(@alignCast(factory_raw.?));
    var collection_raw: ?*anyopaque = null;
    factory.getSystemFontCollection(&collection_raw, 0) catch {
        log.err("GetSystemFontCollection failed", .{});
        @panic("failed to get system font collection");
    };
    const collection: *IDWriteFontCollection = @ptrCast(@alignCast(collection_raw.?));

    // Try to get IDWriteFactory2 for system font fallback (Windows 8.1+)
    const factory2 = factory.queryInterface(IDWriteFactory2) catch null;

    var font_fallback: ?*IDWriteFontFallback = null;
    if (factory2) |f2| {
        var fb_raw: ?*anyopaque = null;
        f2.getSystemFontFallback(&fb_raw) catch {};
        if (fb_raw) |raw| font_fallback = @ptrCast(@alignCast(raw));
    }

    return .{
        .factory = factory,
        .factory2 = factory2,
        .collection = collection,
        .font_fallback = font_fallback,
    };
}

pub fn deinit(self: *DirectWrite) void {
    if (self.font_fallback) |fb| fb.release();
    if (self.factory2) |f2| f2.release();
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
        var family_index: u32 = 0;
        var exists: BOOL = 0;
        self.collection.findFamilyName(@ptrCast(@constCast(conv.str)), &family_index, &exists) catch {};
        if (exists != 0) {
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

/// Discover a fallback font. Uses IDWriteFontFallback::MapCharacters
/// when available (Windows 8.1+) for locale-aware CJK font selection,
/// falling back to brute-force search on older systems.
pub fn discoverFallback(
    self: *const DirectWrite,
    alloc: Allocator,
    collection: *Collection,
    desc: Descriptor,
) !DiscoverIterator {
    _ = collection;

    // Use MapCharacters for locale-aware fallback when possible.
    if (desc.codepoint > 0) map_chars: {
        const fb = self.font_fallback orelse break :map_chars;

        // Encode codepoint as UTF-16
        var text_buf: [3]u16 = undefined;
        var text_len: u32 = undefined;
        if (desc.codepoint >= 0x10000) {
            const shifted: u21 = @intCast(desc.codepoint - 0x10000);
            text_buf[0] = @intCast(0xD800 + (shifted >> 10));
            text_buf[1] = @intCast(0xDC00 + @as(u16, @truncate(shifted & 0x3FF)));
            text_buf[2] = 0;
            text_len = 2;
        } else {
            text_buf[0] = @intCast(desc.codepoint);
            text_buf[1] = 0;
            text_len = 1;
        }

        // Get system locale
        var locale_buf: [85]u16 = undefined; // LOCALE_NAME_MAX_LENGTH = 85
        const locale_len = GetUserDefaultLocaleName(&locale_buf, 85);
        if (locale_len <= 0) break :map_chars;
        locale_buf[@intCast(locale_len - 1)] = 0; // ensure null-terminated

        // Create analysis source
        var source = SimpleTextAnalysisSource.init(
            &text_buf,
            text_len,
            @ptrCast(&locale_buf),
        );

        const base_family = comptime std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI");

        var mapped_length: u32 = 0;
        var mapped_font_raw: ?*anyopaque = null;
        var scale: f32 = 1.0;
        const result = fb.mapCharacters(
            @ptrCast(&source),
            0,
            text_len,
            self.collection,
            @ptrCast(@constCast(base_family)),
            if (desc.bold) DWRITE_FONT_WEIGHT_BOLD else 400,
            if (desc.italic) DWRITE_FONT_STYLE_ITALIC else DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_MEDIUM,
            &mapped_length,
            &mapped_font_raw,
            &scale,
        );
        result catch break :map_chars;

        if (mapped_font_raw == null) break :map_chars;
        const mapped_font: *IDWriteFont = @ptrCast(@alignCast(mapped_font_raw.?));

        const list = try alloc.alloc(*IDWriteFont, 1);
        list[0] = mapped_font;

        return .{
            .alloc = alloc,
            .fonts = list,
            .variations = desc.variations,
            .i = 0,
        };
    }

    // Fallback: brute-force codepoint search
    return try self.discover(alloc, desc);
}

// --- Private helpers ---

fn enumerateAll(
    self: *const DirectWrite,
    alloc: Allocator,
    desc: Descriptor,
    results: *std.ArrayList(*IDWriteFont),
) !void {
    const family_count = self.collection.lpVtbl.GetFontFamilyCount(self.collection);
    for (0..family_count) |fi| {
        var family_raw: ?*anyopaque = null;
        self.collection.getFontFamily(@intCast(fi), &family_raw) catch continue;
        if (family_raw == null) continue;
        const family: *IDWriteFontFamily = @ptrCast(@alignCast(family_raw.?));
        defer family.release();

        const count = family.lpVtbl.GetFontCount(family);
        for (0..count) |i| {
            var dw_font_raw: ?*anyopaque = null;
            if (family.lpVtbl.GetFont(family, @intCast(i), &dw_font_raw) < 0) continue;
            if (dw_font_raw == null) continue;
            const dw_font: *IDWriteFont = @ptrCast(@alignCast(dw_font_raw.?));
            errdefer dw_font.release();

            if (!fontMatchesDesc(dw_font, desc)) {
                dw_font.release();
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
    var family_raw: ?*anyopaque = null;
    self.collection.getFontFamily(family_index, &family_raw) catch return;
    if (family_raw == null) return;
    const family: *IDWriteFontFamily = @ptrCast(@alignCast(family_raw.?));
    defer family.release();

    const count = family.lpVtbl.GetFontCount(family);
    for (0..count) |i| {
        var dw_font_raw: ?*anyopaque = null;
        if (family.lpVtbl.GetFont(family, @intCast(i), &dw_font_raw) < 0) continue;
        if (dw_font_raw == null) continue;
        const dw_font: *IDWriteFont = @ptrCast(@alignCast(dw_font_raw.?));
        errdefer dw_font.release();

        if (!fontMatchesDesc(dw_font, desc)) {
            dw_font.release();
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
    const family_count = self.collection.lpVtbl.GetFontFamilyCount(self.collection);
    for (0..family_count) |fi| {
        var family_raw: ?*anyopaque = null;
        self.collection.getFontFamily(@intCast(fi), &family_raw) catch continue;
        if (family_raw == null) continue;
        const family: *IDWriteFontFamily = @ptrCast(@alignCast(family_raw.?));
        defer family.release();

        // Check first font in family for the codepoint
        var first_font_raw: ?*anyopaque = null;
        if (family.lpVtbl.GetFont(family, 0, &first_font_raw) < 0) continue;
        if (first_font_raw == null) continue;
        const first_font: *IDWriteFont = @ptrCast(@alignCast(first_font_raw.?));
        var exists: BOOL = 0;
        first_font.hasCharacter(desc.codepoint, &exists) catch {};
        first_font.release();
        if (exists == 0) continue;

        // This family has the codepoint - collect matching fonts
        const count = family.lpVtbl.GetFontCount(family);
        for (0..count) |i| {
            var dw_font_raw: ?*anyopaque = null;
            if (family.lpVtbl.GetFont(family, @intCast(i), &dw_font_raw) < 0) continue;
            if (dw_font_raw == null) continue;
            const dw_font: *IDWriteFont = @ptrCast(@alignCast(dw_font_raw.?));
            errdefer dw_font.release();

            if (!fontMatchesDesc(dw_font, desc)) {
                dw_font.release();
                continue;
            }

            // Verify the specific font also has the codepoint
            if (desc.codepoint > 0) {
                var dw_exists: BOOL = 0;
                dw_font.hasCharacter(desc.codepoint, &dw_exists) catch {};
                if (dw_exists == 0) {
                    dw_font.release();
                    continue;
                }
            }

            try results.append(alloc, dw_font);

            // For codepoint fallback, one match per family is enough
            if (desc.family == null) break;
        }
    }
}

fn fontMatchesDesc(dw_font: *IDWriteFont, desc: Descriptor) bool {
    // Filter by bold
    const weight = dw_font.lpVtbl.GetWeight(dw_font);
    if (desc.bold) {
        if (weight < DWRITE_FONT_WEIGHT_BOLD) return false;
    } else {
        if (weight >= DWRITE_FONT_WEIGHT_BOLD) return false;
    }

    // Filter by italic
    const style = dw_font.lpVtbl.GetStyle(dw_font);
    if (desc.italic) {
        if (style == DWRITE_FONT_STYLE_NORMAL) return false;
    } else {
        if (style != DWRITE_FONT_STYLE_NORMAL) return false;
    }

    // Note: desc.monospace is not filtered here. Fontconfig also doesn't
    // hard-filter monospace (just prefers it via pattern scoring).
    // Proper monospace detection requires IDWriteFont1::GetPanose() or
    // creating a font face to check metrics, both of which are expensive.
    // The caller typically sets a family name for monospace fonts anyway.

    return true;
}
