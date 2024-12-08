const std = @import("std");
const quads = @import("quads");
const bench = quads.experimental.benchmark;

pub fn main() !void {
    try bench.run(struct {
        // The functions will be benchmarked with the following inputs.
        // If not present, then it is assumed that the functions  take no input.
        pub const args = [_]struct { []const u8, []const u8 }{
            .{ "block=16", &([_]u8{ 1, 10, 100 } ** 16) },
            .{ "block=32", &([_]u8{ 1, 10, 100 } ** 32) },
            .{ "block=64", &([_]u8{ 1, 10, 100 } ** 64) },
            .{ "block=128", &([_]u8{ 1, 10, 100 } ** 128) },
            .{ "block=256", &([_]u8{ 1, 10, 100 } ** 256) },
            .{ "block=512", &([_]u8{ 1, 10, 100 } ** 512) },
        };

        // How many iterations to run each benchmark.
        // If not present then a default will be used.
        pub const min_iterations = 1000;
        pub const max_iterations = 100000;

        pub fn sum_slice(slice: []const u8) u64 {
            var res: u64 = 0;
            for (slice) |item|
                res += item;

            return res;
        }

        pub fn sum_reader(slice: []const u8) u64 {
            var stream = std.io.fixedBufferStream(slice);
            var reader = &stream.reader();
            var res: u64 = 0;
            while (reader.readByte()) |c| {
                res += c;
            } else |_| {}

            return res;
        }
    });

    try bench.run(struct {
        pub const args = [_]struct { []const u8, type }{
            .{ "vec4f16", @Vector(4, f16) },
            .{ "vec4f32", @Vector(4, f32) },
            .{ "vec4f64", @Vector(4, f64) },
            .{ "vec8f16", @Vector(8, f16) },
            .{ "vec8f32", @Vector(8, f32) },
            .{ "vec8f64", @Vector(8, f64) },
            .{ "vec16f16", @Vector(16, f16) },
            .{ "vec16f32", @Vector(16, f32) },
            .{ "vec16f64", @Vector(16, f64) },
        };

        pub fn sum_vectors(comptime T: type) T {
            const info = @typeInfo(T).vector;
            const one: T = @splat(@as(info.child, 1));
            const vecs = [1]T{one} ** 512;

            var res = one;
            for (vecs) |vec| {
                res += vec;
            }
            return res;
        }
    });
}
