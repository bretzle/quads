const std = @import("std");
const meta = @import("meta.zig");

// Re-expose these as-is so that more cases can rely on quads.testing exclusively.
// Else, it's a pain to have both std.testing and quads.testing in a test.
pub const expect = std.testing.expect;
pub const expectFmt = std.testing.expectFmt;
pub const expectError = std.testing.expectError;
pub const expectEqualSlices = std.testing.expectEqualSlices;
pub const expectEqualStrings = std.testing.expectEqualStrings;
pub const expectEqualSentinel = std.testing.expectEqualSentinel;
pub const expectApproxEqAbs = std.testing.expectApproxEqAbs;
pub const expectApproxEqRel = std.testing.expectApproxEqRel;

pub const allocator = std.testing.allocator;
pub var arena = std.heap.ArenaAllocator.init(allocator);

pub fn reset() void {
    _ = arena.reset(.free_all);
}

// std.testing.expectEqual won't coerce expected to actual, which is a problem
// when expected is frequently a comptime.
// https://github.com/ziglang/zig/issues/4437
pub fn expectEqual(expected: anytype, actual: anytype) !void {
    switch (@typeInfo(@TypeOf(actual))) {
        .array => |arr| if (arr.child == u8) {
            return std.testing.expectEqualStrings(expected, &actual);
        },
        .pointer => |ptr| if (ptr.child == u8) {
            return std.testing.expectEqualStrings(expected, actual);
        } else if (comptime meta.isStringArray(ptr.child)) {
            return std.testing.expectEqualStrings(expected, actual);
        } else if (ptr.child == []u8 or ptr.child == []const u8) {
            return expectStrings(expected, actual);
        },
        .@"struct" => |structType| {
            inline for (structType.fields) |field| {
                try expectEqual(@field(expected, field.name), @field(actual, field.name));
            }
            return;
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values");
            }
            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);
            try expectEqual(expectedTag, actualTag);

            inline for (std.meta.fields(@TypeOf(actual))) |fld| {
                if (std.mem.eql(u8, fld.name, @tagName(actualTag))) {
                    try expectEqual(@field(expected, fld.name), @field(actual, fld.name));
                    return;
                }
            }
            unreachable;
        },
        else => {},
    }
    return std.testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}

fn expectStrings(expected: []const []const u8, actual: anytype) !void {
    try expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| {
        try std.testing.expectEqualStrings(e, a);
    }
}

pub fn expectDelta(expected: anytype, actual: anytype, delta: anytype) !void {
    var diff = expected - actual;
    if (diff < 0) {
        diff = -diff;
    }
    if (diff <= delta) {
        return;
    }

    print("Expected {} to be within {} of {}. Actual diff: {}", .{ expected, delta, actual, diff });
    return error.NotWithinDelta;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        meta.compileError(fmt, args);
    } else {
        std.debug.print(fmt, args);
    }
}
