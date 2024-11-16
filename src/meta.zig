const std = @import("std");

pub fn compileError(comptime format: []const u8, comptime args: anytype) void {
    @compileError(std.fmt.comptimePrint(format, args));
}

pub fn compileAssert(comptime ok: bool, comptime format: []const u8, comptime args: anytype) void {
    if (!ok) compileError(format, args);
}

pub fn isVector(comptime T: type) void {
    if (@typeInfo(T) != .vector) compileError("Expected a Vector got {}", .{T});
}

pub inline fn cast(comptime T: type, comptime U: type, data: U) T {
    if (T == U) return data;

    return switch (@typeInfo(T)) {
        .Int => switch (@typeInfo(U)) {
            .Int => @intCast(data),
            .Float => @intFromFloat(data),
            else => comptime unreachable,
        },
        .Float => switch (@typeInfo(U)) {
            .Int => @floatFromInt(data),
            .Float => @floatCast(data),
            else => comptime unreachable,
        },
        else => comptime unreachable,
    };
}

pub fn ReturnType(comptime T: type) type {
    return @typeInfo(T).@"fn".return_type.?;
}

pub fn BaseReturnType(comptime T: type) type {
    return switch (@typeInfo(ReturnType(T))) {
        .error_union => |x| x.payload,
        else => ReturnType(T),
    };
}

// TODO: dont use a hash map. these pools *probably* wont have that many items, so an array *should* be cheaper
//       or better yet a _real_ pool impl. see: https://floooh.github.io/2018/06/17/handles-vs-pointers.html
pub fn SimplePool(comptime T: type, comptime Handle: type) type {
    compileAssert(@typeInfo(Handle) == .@"enum", "Handle must be an enum", .{});
    compileAssert(@typeInfo(Handle).@"enum".tag_type == u32, "Handle must be backed by u32", .{});

    const Context = struct {
        pub fn hash(_: @This(), key: Handle) u64 {
            return @intFromEnum(key);
        }

        pub fn eql(_: @This(), a: Handle, b: Handle) bool {
            return a == b;
        }
    };

    const Map = std.HashMap(Handle, T, Context, 80);

    return struct {
        id: u32 = 1,
        resources: Map,

        pub fn create(allocator: std.mem.Allocator) @This() {
            return .{ .resources = Map.init(allocator) };
        }

        pub fn add(self: *@This(), resource: T) Handle {
            self.resources.put(@enumFromInt(self.id), resource) catch @trap();
            self.id += 1;
            return @enumFromInt(self.id - 1);
        }

        pub fn remove(self: *@This(), id: Handle) T {
            const ret = self.resources.get(id) orelse @trap();
            self.resources.remove(id);
            return ret;
        }

        pub fn get(self: *@This(), key: Handle) *T {
            return self.resources.getPtr(key) orelse @trap();
        }
    };
}
