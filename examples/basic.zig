const std = @import("std");
const rgfw = @import("rgfw");
const gfx = rgfw.gfx;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
};

pub fn main() !void {
    const win = try rgfw.Window.create(allocator, "name", .{ .x = 500, .y = 500, .w = 500, .h = 500 }, .{ .center = true });
    defer win.close(allocator);

    win.makeCurrent();

    gfx.init(allocator, .{ win.r.w, win.r.h });
    defer gfx.deinit();

    const indices = [3]u16{ 0, 1, 2 };
    const vertices = [3]Vertex{
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0, 1 } },
        .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0, 1 } },
        .{ .pos = .{ 0.0, 0.5 }, .color = .{ 0, 0, 1, 1 } },
    };

    const vertex_buffer = gfx.newBuffer(.vertex, .immutable, &vertices);
    const index_buffer = gfx.newBuffer(.index, .immutable, &indices);

    const bindings = gfx.Bindings{
        .vertex_buffers = .{ vertex_buffer, .invalid, .invalid, .invalid },
        .index_buffer = index_buffer,
    };

    const shader = try gfx.newShader(vertex, fragment, .{});

    const pipeline = try gfx.newPipeline(
        &.{.{}},
        &.{
            .{ .name = "in_pos", .format = .float2 },
            .{ .name = "in_color", .format = .float4 },
        },
        shader,
        .{},
    );

    while (!win.shouldClose()) {
        while (win.checkEvent()) |ev| {
            if (ev.typ == .window_resized) gfx.canvas_size = .{ @intCast(win.r.w), @intCast(win.r.h) };
        }

        gfx.beginDefaultPass(null);

        gfx.applyPipeline(pipeline);
        gfx.applyBindings(&bindings);
        gfx.draw(0, 3, 1);
        gfx.endRenderPass();

        gfx.commitFrame();

        win.swapBuffers();
    }
}

const vertex =
    \\#version 330
    \\
    \\in vec2 in_pos;
    \\in vec4 in_color;
    \\out vec4 color;
    \\
    \\void main() {
    \\  gl_Position = vec4(in_pos, 0, 1);
    \\  color = in_color;
    \\}
;

const fragment =
    \\#version 330
    \\
    \\in vec4 color;
    \\
    \\void main() {
    \\  gl_FragColor = color;
    \\}
;
