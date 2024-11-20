const std = @import("std");

pub fn Runnable(comptime Ret: type) type {
    return struct {
        ptr: *anyopaque,
        runFn: *const fn (ptr: *anyopaque) Ret,

        pub fn create(allocator: std.mem.Allocator, comptime func: anytype, args: anytype) !@This() {
            const Closure = struct {
                args: std.meta.ArgsTuple(@TypeOf(func)),

                fn run(ptr: *anyopaque) Ret {
                    const c: *@This() = @ptrCast(@alignCast(ptr));
                    return @call(.auto, func, c.args);
                }
            };

            const closure = try allocator.create(Closure);
            closure.* = .{
                .args = args,
            };

            return .{
                .ptr = closure,
                .runFn = Closure.run,
            };
        }
    };
}
