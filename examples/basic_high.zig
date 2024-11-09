const std = @import("std");
const rgfw = @import("rgfw");
const gfx = rgfw.gfx.high;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    const win = try rgfw.Window.create(allocator, "name", .{ .x = 500, .y = 500, .w = 500, .h = 500 }, .{ .center = true });
    defer win.close(allocator);

    win.makeCurrent();

    try gfx.init(allocator, .{ win.r.w, win.r.h });
    defer gfx.deinit();

    while (!win.shouldClose()) {
        while (win.checkEvent()) |ev| {
            if (ev.typ == .window_resized) gfx.canvas_size = .{ @intCast(win.r.w), @intCast(win.r.h) };
        }

        gfx.beginFrame();

        gfx.drawTriangle(.{ 121, 374 }, .{ 241, 125 }, .{ 362, 374 }, .{ 255, 0, 0, 255 });

        gfx.endFrame();

        win.swapBuffers();
    }
}
