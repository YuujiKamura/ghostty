const std = @import("std");
const tables = @import("tables.zig");
const streams = @import("streams.zig");
const coded = @import("coded_index.zig");

pub const Context = struct {
    table_info: tables.Info,
    heaps: streams.Heaps,
};

pub fn emitInterface(
    allocator: std.mem.Allocator,
    writer: anytype,
    ctx: Context,
    source_path: []const u8,
    interface_name: []const u8,
) !void {
    const type_row = try findTypeDefRow(ctx, interface_name);
    const type_def = try ctx.table_info.readTypeDef(type_row);
    const ns = try ctx.heaps.getString(type_def.type_namespace);
    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ ns, interface_name });
    defer allocator.free(full_name);

    const guid = try extractGuid(ctx, type_row);

    const method_range = try methodRange(ctx.table_info, type_row);
    var method_names: std.ArrayList([]const u8) = .empty;
    defer method_names.deinit(allocator);
    var i = method_range.start;
    while (i < method_range.end_exclusive) : (i += 1) {
        const m = try ctx.table_info.readMethodDef(i);
        try method_names.append(allocator, try ctx.heaps.getString(m.name));
    }

    try writer.print("// Auto-generated from {s}\n", .{source_path});
    try writer.print("// DO NOT EDIT — regenerate with: winmd2zig {s} {s}\n", .{ source_path, interface_name });
    try writer.print("pub const {s} = extern struct {{\n", .{interface_name});
    try writer.print("    // WinMD: {s}\n", .{full_name});
    const blob_hex = try formatGuidBlobHex(allocator, guid);
    defer allocator.free(blob_hex);
    try writer.print("    // Blob: 01 00 {s}\n", .{blob_hex});

    try writer.writeAll("    pub const IID = GUID{ ");
    try writer.print(".Data1 = 0x{x:0>8}, .Data2 = 0x{x:0>4}, .Data3 = 0x{x:0>4},\n", .{
        std.mem.readInt(u32, guid[0..4], .little),
        std.mem.readInt(u16, guid[4..6], .little),
        std.mem.readInt(u16, guid[6..8], .little),
    });
    try writer.writeAll("        .Data4 = .{ ");
    for (guid[8..], 0..) |b, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.print("0x{x:0>2}", .{b});
    }
    try writer.writeAll(" } };\n\n");

    try writer.writeAll("    lpVtbl: *const VTable,\n\n");
    try writer.writeAll("    const VTable = extern struct {\n");
    try writer.writeAll("        // IUnknown (slots 0-2)\n");
    try writer.writeAll("        QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,\n");
    try writer.writeAll("        AddRef: *const fn (*anyopaque) callconv(.winapi) u32,\n");
    try writer.writeAll("        Release: *const fn (*anyopaque) callconv(.winapi) u32,\n");
    try writer.writeAll("        // IInspectable (slots 3-5)\n");
    try writer.writeAll("        GetIids: VtblPlaceholder,\n");
    try writer.writeAll("        GetRuntimeClassName: VtblPlaceholder,\n");
    try writer.writeAll("        GetTrustLevel: VtblPlaceholder,\n");

    const start_slot: u32 = 6;
    const end_slot: u32 = start_slot + @as(u32, @intCast(method_names.items.len)) - 1;
    if (method_names.items.len > 0) {
        var seen = std.StringHashMap(u32).init(allocator);
        defer seen.deinit();
        try writer.print("        // {s} (slots {d}-{d})\n", .{ interface_name, start_slot, end_slot });
        for (method_names.items, 0..) |name, idx| {
            const prev = seen.get(name) orelse 0;
            const next_count = prev + 1;
            try seen.put(name, next_count);
            if (next_count == 1) {
                try writer.print("        {s}: VtblPlaceholder, // {d}\n", .{
                    name,
                    start_slot + @as(u32, @intCast(idx)),
                });
            } else {
                const unique = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ name, next_count });
                defer allocator.free(unique);
                try writer.print("        {s}: VtblPlaceholder, // {d}\n", .{
                    unique,
                    start_slot + @as(u32, @intCast(idx)),
                });
            }
        }
    } else {
        try writer.print("        // {s} (slots 6-5)\n", .{interface_name});
    }
    try writer.writeAll("    };\n\n");
    try writer.print("    pub fn release(self: *{s}) void {{\n", .{interface_name});
    try writer.writeAll("        _ = self.lpVtbl.Release(@ptrCast(self));\n");
    try writer.writeAll("    }\n");
    try writer.writeAll("};\n");
}

fn findTypeDefRow(ctx: Context, interface_name: []const u8) !u32 {
    const dot_index = std.mem.lastIndexOfScalar(u8, interface_name, '.');
    const want_ns = if (dot_index) |i| interface_name[0..i] else null;
    const want_name = if (dot_index) |i| interface_name[i + 1 ..] else interface_name;

    const t = ctx.table_info.getTable(.TypeDef);
    var row: u32 = 1;
    while (row <= t.row_count) : (row += 1) {
        const td = try ctx.table_info.readTypeDef(row);
        const name = try ctx.heaps.getString(td.type_name);
        if (!std.mem.eql(u8, name, want_name)) continue;
        if (want_ns) |ns| {
            const actual_ns = try ctx.heaps.getString(td.type_namespace);
            if (!std.mem.eql(u8, actual_ns, ns)) continue;
        }
        return row;
    }
    return error.InterfaceNotFound;
}

const MethodRange = struct {
    start: u32,
    end_exclusive: u32,
};

fn methodRange(info: tables.Info, type_row: u32) !MethodRange {
    const td = try info.readTypeDef(type_row);
    const method_table = info.getTable(.MethodDef);
    const start = td.method_list;
    var end_exclusive: u32 = method_table.row_count + 1;
    var next_row = type_row + 1;
    while (next_row <= info.getTable(.TypeDef).row_count) : (next_row += 1) {
        const next = try info.readTypeDef(next_row);
        if (next.method_list > start) {
            end_exclusive = next.method_list;
            break;
        }
    }
    return .{ .start = start, .end_exclusive = end_exclusive };
}

fn extractGuid(ctx: Context, type_row: u32) ![16]u8 {
    const ca_table = ctx.table_info.getTable(.CustomAttribute);
    var row: u32 = 1;
    while (row <= ca_table.row_count) : (row += 1) {
        const ca = try ctx.table_info.readCustomAttribute(row);
        const parent = try coded.decodeHasCustomAttribute(ca.parent);
        if (parent.table != .TypeDef or parent.row != type_row) continue;

        const ca_type = try coded.decodeCustomAttributeType(ca.ca_type);
        if (ca_type.table != .MemberRef) continue;
        const mr = try ctx.table_info.readMemberRef(ca_type.row);
        const member_name = try ctx.heaps.getString(mr.name);
        if (!std.mem.eql(u8, member_name, ".ctor")) continue;

        const class_decoded = decodeMemberRefParent(mr.class) catch continue;
        if (class_decoded.table != .TypeRef) continue;
        const tref = try ctx.table_info.readTypeRef(class_decoded.row);
        const tref_name = try ctx.heaps.getString(tref.type_name);
        const tref_ns = try ctx.heaps.getString(tref.type_namespace);
        if (!std.mem.eql(u8, tref_name, "GuidAttribute")) continue;
        if (!std.mem.eql(u8, tref_ns, "Windows.Foundation.Metadata") and
            !std.mem.eql(u8, tref_ns, "System.Runtime.InteropServices"))
        {
            continue;
        }

        const blob = try ctx.heaps.getBlob(ca.value);
        if (blob.len < 20) return error.InvalidGuidBlob;
        if (blob[0] != 0x01 or blob[1] != 0x00) return error.InvalidGuidBlob;
        return blob[2..18].*;
    }
    return error.MissingGuidAttribute;
}

fn decodeMemberRefParent(raw: u32) coded.IndexError!coded.Decoded {
    const tag = raw & 0x7;
    const row = raw >> 3;
    return switch (tag) {
        0 => .{ .table = .TypeDef, .row = row },
        1 => .{ .table = .TypeRef, .row = row },
        2 => .{ .table = .ModuleRef, .row = row },
        3 => .{ .table = .MethodDef, .row = row },
        4 => .{ .table = .TypeSpec, .row = row },
        else => error.InvalidTag,
    };
}

fn formatGuidBlobHex(allocator: std.mem.Allocator, guid: [16]u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (guid, 0..) |b, idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.writer(allocator).print("{x:0>2}", .{b});
    }
    return try out.toOwnedSlice(allocator);
}
