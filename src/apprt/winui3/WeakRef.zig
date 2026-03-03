const std = @import("std");
const winrt = @import("winrt.zig");
const com = @import("com.zig");

/// A lightweight wrapper around WinRT IWeakReference to make it type-safe.
pub fn WeakRef(comptime T: type) type {
    return struct {
        const Self = @This();

        ref: ?*com.IWeakReference = null,

        pub const empty: Self = .{};

        /// Set the weak reference to the given object.
        pub fn set(self: *Self, v_: ?*T) !void {
            if (self.ref) |r| _ = r.release();
            self.ref = null;

            if (v_) |v| {
                const source = try v.queryInterface(com.IWeakReferenceSource);
                defer source.release();
                self.ref = try source.getWeakReference();
            }
        }

        /// Get a strong reference to the object, or null if it has been finalized.
        pub fn get(self: *Self) !?*T {
            const r = self.ref orelse return null;
            return try r.resolve(T);
        }

        pub fn deinit(self: *Self) void {
            if (self.ref) |r| _ = r.release();
            self.ref = null;
        }
    };
}

test "WeakRef basic functionality" {
    const testing = std.testing;

    // Initialize WinRT for the test thread
    try winrt.hrCheck(winrt.RoInitialize(winrt.RO_INIT_SINGLETHREADED));
    defer winrt.RoUninitialize();

    // To test WeakRef, we need a real WinRT object that supports IWeakReferenceSource.
    // Most WinUI 3 controls do.
    const class_name = try winrt.hstring("Microsoft.UI.Xaml.Controls.TabView");
    defer winrt.deleteHString(class_name);
    
    // Note: This requires full WinUI 3 runtime to be active, 
    // which might be hard in a pure unit test.
    // For now, we just verify the structure compiles and handles nulls.
    var ref: WeakRef(com.ITabView) = .empty;
    defer ref.deinit();

    try testing.expect((try ref.get()) == null);
}
