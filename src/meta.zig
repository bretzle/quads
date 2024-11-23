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

pub const TraitFn = fn (type) bool;
pub fn is(comptime id: std.builtin.TypeId) TraitFn {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            return id == @typeInfo(T);
        }
    };
    return comptime Closure.trait;
}

pub fn isPtrTo(comptime id: std.builtin.TypeId) TraitFn {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            if (!comptime isSingleItemPtr(T)) return false;
            return id == @typeInfo(std.meta.Child(T));
        }
    };
    return Closure.trait;
}

pub fn isSingleItemPtr(comptime T: type) bool {
    if (comptime is(.pointer)(T)) {
        return @typeInfo(T).pointer.size == .One;
    }
    return false;
}

pub fn isStringArray(comptime T: type) bool {
    if (!is(.array)(T) and !isPtrTo(.array)(T)) {
        return false;
    }
    return std.meta.Elem(T) == u8;
}
