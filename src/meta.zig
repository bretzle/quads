const std = @import("std");

pub fn compileError(comptime format: []const u8, comptime args: anytype) void {
    @compileError(std.fmt.comptimePrint(format, args));
}

pub fn compileAssert(comptime ok: bool, comptime format: []const u8, comptime args: anytype) void {
    if (!ok) compileError(format, args);
}

pub fn isVector(comptime T: type) void {
    if (@typeInfo(T) != .Vector) compileError("Expected a Vector got {}", .{T});
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
