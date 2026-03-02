const std = @import("std");

const pe = @import("pe.zig");
const metadata = @import("metadata.zig");
const tables = @import("tables.zig");
const streams = @import("streams.zig");
const emit = @import("emit.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // argv0
    const winmd_path = args.next() orelse return usage();

    var iface_names: std.ArrayList([]const u8) = .empty;
    defer iface_names.deinit(allocator);
    while (args.next()) |name| {
        try iface_names.append(allocator, name);
    }
    if (iface_names.items.len == 0) return usage();

    const data = try std.fs.cwd().readFileAlloc(allocator, winmd_path, std.math.maxInt(usize));
    defer allocator.free(data);

    const pe_info = try pe.parse(allocator, data);
    const md_info = try metadata.parse(allocator, pe_info);

    const table_stream = md_info.getStream("#~") orelse return error.MissingTableStream;
    const strings_stream = md_info.getStream("#Strings") orelse return error.MissingStringsStream;
    const blob_stream = md_info.getStream("#Blob") orelse return error.MissingBlobStream;
    const guid_stream = md_info.getStream("#GUID") orelse return error.MissingGuidStream;

    const table_info = try tables.parse(table_stream.data);
    const heaps = streams.Heaps{
        .strings = strings_stream.data,
        .blob = blob_stream.data,
        .guid = guid_stream.data,
    };
    const ctx = emit.Context{
        .table_info = table_info,
        .heaps = heaps,
    };

    var stdout_buf: [64 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    for (iface_names.items, 0..) |name, idx| {
        if (idx != 0) try stdout.writeAll("\n");
        try emit.emitInterface(allocator, stdout, ctx, winmd_path, name);
    }
    stdout_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
}

fn usage() !void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    try stderr.writeAll(
        \\Usage: winmd2zig <path.winmd> <Interface> [<Interface>...]
        \\Example: winmd2zig Microsoft.UI.Xaml.winmd IWindow ITabView IApplicationStatics
        \\
    );
    stderr_writer.end() catch |err| switch (err) {
        error.FileTooBig => {},
        else => return err,
    };
    return error.InvalidArguments;
}

pub const MainError = error{
    MissingTableStream,
    MissingStringsStream,
    MissingBlobStream,
    MissingGuidStream,
    InvalidArguments,
};

test "imports compile" {
    _ = pe;
    _ = metadata;
    _ = tables;
    _ = streams;
    _ = emit;
}
