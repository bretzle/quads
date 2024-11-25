const std = @import("std");
const meta = @import("../meta.zig");

const Decl = std.builtin.Type.Declaration;

pub fn run(comptime Bench: type) !void {
    meta.compileAssert(@typeInfo(Bench) == .@"struct", "Bench must be a struct", .{});

    const args = if (@hasDecl(Bench, "args")) Bench.args else [_]struct { []const u8, void }{"0"{}};
    const min_iterations = if (@hasDecl(Bench, "min_iterations")) Bench.min_iterations else 10000;
    const max_iterations = if (@hasDecl(Bench, "max_iterations")) Bench.max_iterations else 100000;
    const max_time = 500 * std.time.ns_per_ms;

    const functions = comptime blk: {
        var res: []const Decl = &[_]Decl{};

        for (@typeInfo(Bench).@"struct".decls) |decl| {
            if (@typeInfo(@TypeOf(@field(Bench, decl.name))) != .@"fn") continue;
            res = res ++ [_]Decl{decl};
        }

        break :blk res;
    };

    meta.compileAssert(functions.len != 0, "no benchmarks to run!", .{});

    const min_width = blk: {
        const writer = std.io.null_writer;
        var res = [_]u64{ 0, 0, 0, 0, 0, 0 };
        res = try printBenchmark(
            writer,
            res,
            "Benchmark",
            formatter("{s}", ""),
            formatter("{s}", "Iterations"),
            formatter("{s}", "Min(ns)"),
            formatter("{s}", "Max(ns)"),
            formatter("{s}", "Variance"),
            formatter("{s}", "Mean(ns)"),
        );

        inline for (functions) |f| {
            inline for (0..args.len) |i| {
                const max = std.math.maxInt(u32);
                const arg_name = formatter("{s}", args[i][0]);
                res = try printBenchmark(writer, res, f.name, arg_name, max, max, max, max, max);
            }
        }

        break :blk res;
    };

    var _stderr = std.io.bufferedWriter(std.io.getStdErr().writer());
    const stderr = _stderr.writer();

    try stderr.writeAll("\n");
    _ = try printBenchmark(
        stderr,
        min_width,
        "Benchmark",
        formatter("{s}", ""),
        formatter("{s}", "Iterations"),
        formatter("{s}", "Min(ns)"),
        formatter("{s}", "Max(ns)"),
        formatter("{s}", "Variance"),
        formatter("{s}", "Mean(ns)"),
    );
    try stderr.writeAll("\n");
    for (min_width) |w| {
        try stderr.writeByteNTimes('-', w);
    }
    try stderr.writeByteNTimes('-', min_width.len - 1);
    try stderr.writeAll("\n");
    try stderr.context.flush();

    var timer = try std.time.Timer.start();
    inline for (functions) |def| {
        inline for (args, 0..) |arg, index| {
            var runtimes: [max_iterations]u64 = undefined;
            var min: u64 = std.math.maxInt(u64);
            var max: u64 = 0;
            var runtime_sum: u128 = 0;

            var i: usize = 0;
            while (i < min_iterations or (i < max_iterations and runtime_sum < max_time)) : (i += 1) {
                timer.reset();

                const res = switch (@TypeOf(arg)) {
                    void => @field(Bench, def.name)(),
                    else => @field(Bench, def.name)(arg[1]),
                };

                runtimes[i] = timer.read();
                runtime_sum += runtimes[i];
                if (runtimes[i] < min) min = runtimes[i];
                if (runtimes[i] > max) max = runtimes[i];

                switch (@TypeOf(res)) {
                    void => {},
                    else => std.mem.doNotOptimizeAway(&res),
                }
            }

            const runtime_mean: u64 = @intCast(runtime_sum / i);

            var d_sq_sum: u128 = 0;
            for (runtimes[0..i]) |runtime| {
                const d = @as(i64, @intCast(@as(i128, @intCast(runtime)) - runtime_mean));
                d_sq_sum += @as(u64, @intCast(d * d));
            }
            const variance = d_sq_sum / i;

            const arg_name = formatter("{s}", args[index][0]);
            _ = try printBenchmark(stderr, min_width, def.name, arg_name, i, min, max, variance, runtime_mean);

            try stderr.writeAll("\n");
            try stderr.context.flush();
        }
    }
}

fn printBenchmark(writer: anytype, min_widths: [6]u64, func_name: []const u8, arg_name: anytype, iterations: anytype, min_runtime: anytype, max_runtime: anytype, variance: anytype, mean_runtime: anytype) ![6]u64 {
    const arg_len = std.fmt.count("{}", .{arg_name});
    const name_len = try alignedPrint(writer, .left, min_widths[0], "{s}{s}{}{s}", .{ func_name, "("[0..@intFromBool(arg_len != 0)], arg_name, ")"[0..@intFromBool(arg_len != 0)] });
    try writer.writeAll(" ");
    const it_len = try alignedPrint(writer, .right, min_widths[1], "{}", .{iterations});
    try writer.writeAll(" ");
    const min_runtime_len = try alignedPrint(writer, .right, min_widths[2], "{}", .{min_runtime});
    try writer.writeAll(" ");
    const max_runtime_len = try alignedPrint(writer, .right, min_widths[3], "{}", .{max_runtime});
    try writer.writeAll(" ");
    const variance_len = try alignedPrint(writer, .right, min_widths[4], "{}", .{variance});
    try writer.writeAll(" ");
    const mean_runtime_len = try alignedPrint(writer, .right, min_widths[5], "{}", .{mean_runtime});

    return [_]u64{ name_len, it_len, min_runtime_len, max_runtime_len, variance_len, mean_runtime_len };
}

fn formatter(comptime fmt_str: []const u8, value: anytype) Formatter(fmt_str, @TypeOf(value)) {
    return .{ .value = value };
}

fn Formatter(comptime fmt_str: []const u8, comptime T: type) type {
    return struct {
        value: T,

        pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try std.fmt.format(writer, fmt_str, .{self.value});
        }
    };
}

fn alignedPrint(writer: anytype, dir: enum { left, right }, width: u64, comptime fmt: []const u8, args: anytype) !u64 {
    const value_len = std.fmt.count(fmt, args);

    var cow = std.io.countingWriter(writer);
    if (dir == .right) {
        try cow.writer().writeByteNTimes(' ', width -| value_len);
    }
    try cow.writer().print(fmt, args);
    if (dir == .left) {
        try cow.writer().writeByteNTimes(' ', width -| value_len);
    }

    return cow.bytes_written;
}
