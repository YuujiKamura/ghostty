const std = @import("std");
const testing = std.testing;

pub fn gActionNameIsValid(name: [:0]const u8) bool {
    if (name.len == 0) return false;

    for (name) |c| switch (c) {
        '-', '.', '0'...'9', 'a'...'z', 'A'...'Z' => continue,
        else => return false,
    };

    return true;
}

pub fn Action(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Callback = *const fn (*T, i32) void;

        name: [:0]const u8,
        callback: Callback,

        pub fn init(comptime name: [:0]const u8, callback: Callback) Self {
            comptime std.debug.assert(gActionNameIsValid(name));
            return .{
                .name = name,
                .callback = callback,
            };
        }
    };
}

pub fn add(
    comptime T: type,
    self: *T,
    map: *MockActionMap(T),
    actions: []const Action(T),
) void {
    for (actions) |entry| map.add(self, entry);
}

pub fn MockActionMap(comptime T: type) type {
    return struct {
        const Self = @This();
        const Entry = struct {
            name: [:0]const u8,
            callback: Action(T).Callback,
            target: *T,
        };

        entries: [8]Entry = undefined,
        len: usize = 0,

        fn add(self: *Self, target: *T, action: Action(T)) void {
            std.debug.assert(self.len < self.entries.len);
            self.entries[self.len] = .{
                .name = action.name,
                .callback = action.callback,
                .target = target,
            };
            self.len += 1;
        }

        fn activate(self: *const Self, name: []const u8, value: i32) bool {
            for (self.entries[0..self.len]) |e| {
                if (std.mem.eql(u8, e.name, name)) {
                    e.callback(e.target, value);
                    return true;
                }
            }
            return false;
        }
    };
}

test "gActionNameIsValid" {
    try testing.expect(gActionNameIsValid("ring-bell"));
    try testing.expect(!gActionNameIsValid("ring_bell"));
}

test "adding actions to an object" {
    const Obj = struct {
        spacing: i32 = 0,
    };

    const callbacks = struct {
        fn setSpacing(self: *Obj, value: i32) void {
            self.spacing = value;
        }
    };

    var obj = Obj{};
    var map = MockActionMap(Obj){};
    const actions = [_]Action(Obj){
        .init("test", callbacks.setSpacing),
    };

    add(Obj, &obj, &map, &actions);
    try testing.expect(map.activate("test", 37));
    try testing.expectEqual(@as(i32, 37), obj.spacing);
}
