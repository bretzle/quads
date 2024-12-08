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
        .int => switch (@typeInfo(U)) {
            .int => @intCast(data),
            .float => @intFromFloat(data),
            else => comptime unreachable,
        },
        .float => switch (@typeInfo(U)) {
            .int => @floatFromInt(data),
            .float => @floatCast(data),
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

pub fn isPtrTo(comptime T: type, comptime id: std.builtin.TypeId) bool {
    if (@typeInfo(T) != .pointer) return false;
    return id == @typeInfo(std.meta.Child(T));
}

pub fn isStringArray(comptime T: type) bool {
    if (@typeInfo(T) != .array and !isPtrTo(T, .array)) return false;
    return std.meta.Elem(T) == u8;
}
