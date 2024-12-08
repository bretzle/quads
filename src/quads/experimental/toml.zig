const std = @import("std");
const meta = @import("../meta.zig");
const toolkit = @import("parser.zig");
const testing = @import("../testing.zig");
const tm = toolkit.matchers;

const TokenType = enum {
    whitespace,
    key,
    @"=",
    string,
    boolean,
    integer2,
    integer8,
    integer10,
    integer16,
    float,
    table,
};

const Pattern = toolkit.Pattern(TokenType);

const Tokenizer = toolkit.Tokenizer(TokenType, &[_]Pattern{
    Pattern.create(.whitespace, tm.whitespace),
    Pattern.create(.@"=", tm.literal("=")),

    Pattern.create(.boolean, tm.literal("true")),
    Pattern.create(.boolean, tm.word("false")),

    Pattern.create(.float, tm.sequenceOf(.{ tm.numberOfBase(10), tm.literal("."), tm.numberOfBase(10) })),
    Pattern.create(.float, tm.sequenceOf(.{ tm.literal("-"), tm.numberOfBase(10), tm.literal("."), tm.numberOfBase(10) })),

    Pattern.create(.integer2, tm.sequenceOf(.{ tm.literal("0b"), tm.numberOfBase(2) })),
    Pattern.create(.integer8, tm.sequenceOf(.{ tm.literal("0o"), tm.numberOfBase(8) })),
    Pattern.create(.integer16, tm.sequenceOf(.{ tm.literal("0x"), tm.numberOfBase(16) })),

    Pattern.create(.integer10, tm.numberOfBase(10)),
    Pattern.create(.integer10, tm.sequenceOf(.{ tm.literal("-"), tm.numberOfBase(10) })),

    Pattern.create(.string, tm.literal("\"\"")),
    Pattern.create(.string, tm.sequenceOf(.{ tm.literal("\""), tm.takeNoneOf("\""), tm.literal("\"") })),

    Pattern.create(.table, tm.sequenceOf(.{ tm.literal("["), tm.identifier, tm.literal("]") })),

    Pattern.create(.key, tm.identifier),
});

const ParserCore = toolkit.Parser(Tokenizer, .{.whitespace});

const ruleset = toolkit.RuleSet(TokenType);

const Table = std.StringHashMap(TomlValue);

const TomlValue = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
    float: f64,
    table: Table,
};

pub fn parseRaw(allocator: std.mem.Allocator, contents: []const u8) !Table {
    var table = Table.init(allocator);

    var tokenizer = Tokenizer.create(contents, null);
    var parser = Parser{ .core = ParserCore.create(&tokenizer), .parent = &table, .table = &table };

    try parser.acceptTomlExpression();

    if (try parser.core.peek() != null) unreachable;

    return table;
}

pub fn parse(comptime T: type, allocator: std.mem.Allocator, contents: []const u8) !T {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();
    var raw = try parseRaw(alloc, contents);
    var table = &raw;

    var output = std.mem.zeroInit(T, .{});
    inline for (@typeInfo(T).@"struct".fields) |field| {
        try parseValue(field.type, &@field(output, field.name), &table, field.name);
    }
    return output;
}

fn parseValue(comptime T: type, output: *T, table: **Table, comptime name: []const u8) !void {
    var toml = table.*.get(name) orelse return error.NotFound;
    switch (@typeInfo(T)) {
        .bool => output.* = toml.boolean,
        .int, .float => {
            output.* = switch (toml) {
                .integer => meta.cast(T, i64, toml.integer),
                .float => meta.cast(T, f64, toml.float),
                else => unreachable,
            };
        },
        .pointer => {
            meta.compileAssert(T == []const u8, "only string slices supported", .{});
            output.* = try table.*.allocator.dupe(u8, toml.string);
        },
        .@"struct" => {
            table.* = &toml.table;
            inline for (@typeInfo(T).@"struct".fields) |field| {
                try parseValue(field.type, &@field(output, field.name), table, field.name);
            }
        },
        else => meta.compileError("unsupported type: {s}", .{@typeName(T)}),
    }
}

const Parser = struct {
    const Self = @This();

    core: ParserCore,
    parent: *Table,
    table: *Table,

    fn acceptTomlExpression(self: *Self) !void {
        while (try self.core.peek() != null)
            try self.acceptExpression();
    }

    // expression =  ws [ comment ]
    // expression =/ ws keyval ws [ comment ]
    // expression =/ ws table ws [ comment ]
    fn acceptExpression(self: *Self) !void {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const token = try self.core.accept(comptime ruleset.oneOf(.{ .key, .table }));

        switch (token.typ) {
            .key => {
                _ = try self.core.accept(comptime ruleset.is(.@"="));
                const value = try self.acceptValue();
                try self.table.put(token.text, value);
            },
            .table => {
                const name = token.text[1 .. token.text.len - 1];
                const allocator = self.parent.allocator;
                const newTable = Table.init(allocator);
                try self.parent.put(name, .{ .table = newTable });
                self.table = &(self.parent.getPtr(name) orelse unreachable).table;
            },
            else => unreachable,
        }
    }

    // val = string / boolean / array / inline-table / date-time / float / integer
    fn acceptValue(self: *Self) !TomlValue {
        const state = self.core.saveState();
        errdefer self.core.restoreState(state);

        const token = try self.core.accept(comptime ruleset.oneOf(.{
            .string,
            .boolean,
            .integer2,
            .integer8,
            .integer10,
            .integer16,
            .float,
            .table,
        }));

        return switch (token.typ) {
            .string => .{ .string = token.text[1 .. token.text.len - 1] },
            .boolean => .{ .boolean = std.mem.eql(u8, "true", token.text) },
            .integer2 => .{ .integer = try std.fmt.parseInt(i64, token.text[2..], 2) },
            .integer8 => .{ .integer = try std.fmt.parseInt(i64, token.text[2..], 8) },
            .integer10 => .{ .integer = try std.fmt.parseInt(i64, token.text, 10) },
            .integer16 => .{ .integer = try std.fmt.parseInt(i64, token.text[2..], 16) },
            .float => .{ .float = try std.fmt.parseFloat(f64, token.text) },
            else => unreachable,
        };
    }
};

test "simple kv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const contents =
        \\s1 = "bar"
        \\s2 = ""
        \\
        \\b1 = true
        \\b2 = false
        \\
        \\i1 = 10
        \\i2 = -10
        \\i3 = 0b10
        \\i4 = 0o10
        \\i5 = 0x10
        \\
        \\f1 = 10.0
        \\
        \\[foobar]
        \\t1 = 123
    ;
    const output = try parseRaw(arena.allocator(), contents);

    try testing.expectEqual("bar", output.get("s1").?.string);
    try testing.expectEqual("", output.get("s2").?.string);

    try testing.expectEqual(true, output.get("b1").?.boolean);
    try testing.expectEqual(false, output.get("b2").?.boolean);

    try testing.expectEqual(10, output.get("i1").?.integer);
    try testing.expectEqual(-10, output.get("i2").?.integer);
    try testing.expectEqual(2, output.get("i3").?.integer);
    try testing.expectEqual(8, output.get("i4").?.integer);
    try testing.expectEqual(16, output.get("i5").?.integer);

    try testing.expectEqual(10, output.get("f1").?.float);

    try testing.expectEqual(123, output.get("foobar").?.table.get("t1").?.integer);
}

test "cargo.toml" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const contents =
        \\[package]
        \\name = "temp2"
        \\version = "0.1.0"
        \\edition = "2021"
        \\
        \\[dependencies]
        \\
    ;
    const output = try parseRaw(arena.allocator(), contents);

    const package = output.get("package").?.table;
    const dependencies = output.get("dependencies").?.table;

    try testing.expectEqual("temp2", package.get("name").?.string);
    try testing.expectEqual("0.1.0", package.get("version").?.string);
    try testing.expectEqual("2021", package.get("edition").?.string);

    try testing.expect(dependencies.count() == 0);
}

test parse {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const contents =
        \\s1 = "bar"
        \\s2 = ""
        \\
        \\b1 = true
        \\b2 = false
        \\
        \\i1 = 10
        \\i2 = -10
        \\i3 = 0b10
        \\i4 = 0o10
        \\i5 = 0x10
        \\
        \\f1 = 10.0
        \\
        \\[foobar]
        \\t1 = 123
    ;

    const Output = struct {
        s1: []const u8 = "bar",
        s2: []const u8 = "",

        b1: bool = true,
        b2: bool = false,

        i1: i32 = 10,
        i2: i32 = -10,
        i3: i32 = 0b10,
        i4: i32 = 0o10,
        i5: i32 = 0x10,

        f1: f32 = 10.0,

        foobar: struct {
            t1: u32 = 123,
        } = .{},
    };

    const out = try parse(Output, arena.allocator(), contents);
    try testing.expectEqual(Output{
        .s1 = "bar",
        .s2 = "",

        .b1 = true,
        .b2 = false,

        .i1 = 10,
        .i2 = -10,
        .i3 = 0b10,
        .i4 = 0o10,
        .i5 = 0x10,

        .f1 = 10.0,

        .foobar = .{ .t1 = 123 },
    }, out);
}
