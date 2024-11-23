const std = @import("std");
const testing = @import("testing.zig");

const Args = @This();

exe: []const u8 = "",
tail: [][]const u8 = &.{},
list: [][]const u8 = &.{},

arena: *std.heap.ArenaAllocator,
lookup: std.StringHashMap([]const u8),

pub fn parse(allocator: std.mem.Allocator) !Args {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);

    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();

    var it = try std.process.argsWithAllocator(arena.allocator());
    return fromIterator(arena, &it);
}

pub fn fromIterator(arena: *std.heap.ArenaAllocator, it: anytype) !Args {
    const allocator = arena.allocator();
    var list = std.ArrayList([]const u8).init(allocator);
    var lookup = std.StringHashMap([]const u8).init(allocator);

    const exe = blk: {
        const first = it.next() orelse return .{
            .arena = arena,
            .lookup = lookup,
        };
        const exe = try allocator.dupe(u8, first);
        try list.append(exe);
        break :blk exe;
    };

    while (it.next()) |arg| {
        try list.append(try allocator.dupe(u8, arg));
    }

    var i: usize = 1;
    var tail_start: usize = 1;

    const items = list.items;
    while (i < items.len) {
        const arg = items[i];

        if (arg.len == 1 or arg[0] != '-') break;

        if (arg[1] == '-') {
            const key, const value = parsePair(arg[2..], items, &i);
            try lookup.put(key, value);
        } else {
            const key, const value = parsePair(arg[1..], items, &i);
            for (0..key.len - 1) |j| {
                try lookup.put(key[j .. j + 1], "");
            }
            try lookup.put(key[key.len - 1 ..], value);
        }

        tail_start = i;
    }

    return .{
        .exe = exe,
        .tail = list.items[tail_start..],
        .list = list.items,
        .arena = arena,
        .lookup = lookup,
    };
}

pub fn deinit(self: *const Args) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
}

pub fn contains(self: *const Args, name: []const u8) bool {
    return self.lookup.contains(name);
}

pub fn get(self: *const Args, name: []const u8) ?[]const u8 {
    return self.lookup.get(name);
}

pub fn count(self: *const Args) u32 {
    return self.lookup.count();
}

// returns .{ key, value }
fn parsePair(key: []const u8, items: [][]const u8, i: *usize) [2][]const u8 {
    const item_index = i.*;
    if (std.mem.indexOfScalarPos(u8, key, 0, '=')) |pos| {
        // this parameter is in the form of --key=value, or -k=value
        // we just skip the key
        i.* = item_index + 1;

        return .{ key[0..pos], key[pos + 1 ..] };
    }

    if (item_index == items.len - 1 or items[item_index + 1][0] == '-') {
        // our key is at the end of the arguments OR
        // the next argument starts with a '-'. This means this key has no value

        // we just skip the key
        i.* = item_index + 1;

        return .{ key, "" };
    }

    // skip the current key, and the next arg (which is our value)
    i.* = item_index + 2;
    return .{ key, items[item_index + 1] };
}

test "Args: empty" {
    const args = testParse(&.{});
    defer args.deinit();

    try testing.expectEqual("", args.exe);
    try testing.expectEqual(0, args.count());
    try testing.expectEqual(0, args.list.len);
    try testing.expectEqual(0, args.tail.len);
}

test "Args: exe only" {
    const input = [_][]const u8{"/tmp/exe"};
    const args = testParse(&input);
    defer args.deinit();

    try testing.expectEqual("/tmp/exe", args.exe);
    try testing.expectEqual(0, args.count());
    try testing.expectEqual(0, args.tail.len);
    try testing.expectEqual(&input, args.list);
}

test "Args: simple args" {
    const input = [_][]const u8{ "a binary", "--level", "info", "--silent", "-p", "5432", "-x" };
    const args = testParse(&input);
    defer args.deinit();

    try testing.expectEqual("a binary", args.exe);
    try testing.expectEqual(0, args.tail.len);
    try testing.expectEqual(&input, args.list);

    try testing.expectEqual(4, args.count());
    try testing.expectEqual(true, args.contains("level"));
    try testing.expectEqual("info", args.get("level").?);

    try testing.expectEqual(true, args.contains("silent"));
    try testing.expectEqual("", args.get("silent").?);

    try testing.expectEqual(true, args.contains("p"));
    try testing.expectEqual("5432", args.get("p").?);

    try testing.expectEqual(true, args.contains("x"));
    try testing.expectEqual("", args.get("x").?);
}

test "Args: single character flags" {
    const input = [_][]const u8{ "9001", "-a", "-bc", "-def", "-ghij", "data" };
    const args = testParse(&input);
    defer args.deinit();

    try testing.expectEqual("9001", args.exe);
    try testing.expectEqual(0, args.tail.len);
    try testing.expectEqual(&input, args.list);

    try testing.expectEqual(10, args.count());
    try testing.expectEqual(true, args.contains("a"));
    try testing.expectEqual("", args.get("a").?);
    try testing.expectEqual(true, args.contains("b"));
    try testing.expectEqual("", args.get("b").?);
    try testing.expectEqual(true, args.contains("c"));
    try testing.expectEqual("", args.get("c").?);
    try testing.expectEqual(true, args.contains("d"));
    try testing.expectEqual("", args.get("d").?);
    try testing.expectEqual(true, args.contains("e"));
    try testing.expectEqual("", args.get("e").?);
    try testing.expectEqual(true, args.contains("f"));
    try testing.expectEqual("", args.get("f").?);
    try testing.expectEqual(true, args.contains("g"));
    try testing.expectEqual("", args.get("g").?);
    try testing.expectEqual(true, args.contains("h"));
    try testing.expectEqual("", args.get("h").?);
    try testing.expectEqual(true, args.contains("i"));
    try testing.expectEqual("", args.get("i").?);

    try testing.expectEqual(true, args.contains("j"));
    try testing.expectEqual("data", args.get("j").?);
}

test "Args: simple args with =" {
    const input = [_][]const u8{ "a binary", "--level=error", "-k", "-p=6669" };
    const args = testParse(&input);
    defer args.deinit();

    try testing.expectEqual("a binary", args.exe);
    try testing.expectEqual(0, args.tail.len);
    try testing.expectEqual(&input, args.list);

    try testing.expectEqual(3, args.count());
    try testing.expectEqual(true, args.contains("level"));
    try testing.expectEqual("error", args.get("level").?);

    try testing.expectEqual(true, args.contains("k"));
    try testing.expectEqual("", args.get("k").?);

    try testing.expectEqual(true, args.contains("p"));
    try testing.expectEqual("6669", args.get("p").?);
}

test "Args: tail" {
    const input = [_][]const u8{ "a binary", "-l", "--k", "x", "ts", "-p=6669", "hello" };
    const args = testParse(&input);
    defer args.deinit();

    try testing.expectEqual("a binary", args.exe);
    try testing.expectEqual(&.{ "ts", "-p=6669", "hello" }, args.tail);
    try testing.expectEqual(&input, args.list);

    try testing.expectEqual(2, args.count());
    try testing.expectEqual(true, args.contains("l"));
    try testing.expectEqual("", args.get("l").?);

    try testing.expectEqual(true, args.contains("k"));
    try testing.expectEqual("x", args.get("k").?);
}

fn testParse(args: []const []const u8) Args {
    const arena = testing.allocator.create(std.heap.ArenaAllocator) catch unreachable;
    arena.* = std.heap.ArenaAllocator.init(testing.allocator);

    const it = arena.allocator().create(TestIterator) catch unreachable;
    it.* = .{ .args = args };
    return Args.fromIterator(arena, it) catch unreachable;
}

const TestIterator = struct {
    pos: usize = 0,
    args: []const []const u8,

    fn next(self: *TestIterator) ?[]const u8 {
        const pos = self.pos;
        const args = self.args;
        if (pos == args.len) {
            return null;
        }
        const arg = args[pos];
        self.pos = pos + 1;
        return arg;
    }
};
