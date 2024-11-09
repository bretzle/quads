const std = @import("std");
const rgfw = @import("rgfw");
// const gl = rgfw.gl;
const gfx = rgfw.gfx;

const allocator = std.heap.page_allocator;

const icon = [4 * 3 * 3]u8{ 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF };

pub fn main() !void {
    const win = try rgfw.Window.create(allocator, "name", .{ .x = 500, .y = 500, .w = 500, .h = 500 }, .{ .center = true });
    defer win.close(allocator);

    win.makeCurrent();

    try gfx.init(allocator, win);
    defer gfx.deinit(allocator);

    // win.setMinSize(.{ .w = 100, .h = 100 });
    // win.setMaxSize(.{ .w = 1000, .h = 1000 });

    // win.setIcon(&icon, .{ .w = 3, .h = 3 }, 4);
    // win.setMouse(&icon, .{ .w = 3, .h = 3 }, 4);

    const tex = gfx.createTexture(&icon, .{ .w = 3, .h = 3 }, 4);

    var running = true;
    while (running) {
        while (win.checkEvent()) |ev| {
            switch (ev.typ) {
                .quit => running = false,
                .window_resized => gfx.updateSize(.{ .w = @intCast(win.r.w), .h = @intCast(win.r.h) }),
                else => {},
            }
        }

        gfx.drawTriangle(
            .{
                .{ 20, win.r.h - 20 },
                .{ win.r.w - 20, win.r.h - 20 },
                .{ @divTrunc(win.r.w - 40, 2), 20 },
            },
            gfx.rgb(255, 255, 0),
        );

        gfx.args.texture = tex;
        gfx.drawRect(.{ 0, 0, 30, 300 }, gfx.rgb(255, 255, 255));
        gfx.args.texture = 1;

        gfx.clear(gfx.rgb(0, 0, 0));
        win.swapBuffers();
    }
}
