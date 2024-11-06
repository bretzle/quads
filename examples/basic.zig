const std = @import("std");
const rgfw = @import("rgfw");
const gl = rgfw.gl;

const allocator = std.heap.page_allocator;

const icon = [4 * 3 * 3]u8{ 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF };

pub fn main() !void {
    const win = try rgfw.Window.create(allocator, "name", .{ .x = 500, .y = 500, .w = 500, .h = 500 }, .{ .center = true });
    defer win.close(allocator);

    win.makeCurrent();

    win.setMinSize(.{ .w = 100, .h = 100 });
    win.setMaxSize(.{ .w = 1000, .h = 1000 });

    win.setIcon(&icon, .{ .w = 3, .h = 3 }, 4);
    win.setMouse(&icon, .{ .w = 3, .h = 3 }, 4);

    var running = true;
    while (running) {
        while (win.checkEvent()) |ev| {
            if (ev.typ == .quit) running = false;

            // std.debug.print("{any}\n", .{ev});
        }

        gl.ClearColor(0x00, 0x00, 0x00, 0xFF);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        win.swapBuffers();
    }
}
