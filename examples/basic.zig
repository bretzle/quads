const std = @import("std");
const quads = @import("quads");

const gfx = quads.render;

const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();

    try quads.init(allocator, .{});
    defer quads.deinit();

    var window = try quads.createWindow(.{ .title = "basic" });
    defer window.destroy();

    try window.createContext(.{});
    window.makeContextCurrent();
    window.swapInterval(1);

    try gfx.init(allocator, .{ .loader = quads.glGetProcAddress });
    defer gfx.deinit();

    try gfx.text.init();

    const indices = [3]u16{ 0, 1, 2 };
    const vertices = [3]Vertex{
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0, 1 } },
        .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0, 1 } },
        .{ .pos = .{ 0.0, 0.5 }, .color = .{ 0, 0, 1, 1 } },
    };

    const index_buffer = gfx.createBuffer(u16, gfx.BufferDesc(u16){
        .type = .index,
        .usage = .immutable,
        .content = &indices,
    });
    const vertex_buffer = gfx.createBuffer(Vertex, gfx.BufferDesc(Vertex){
        .type = .vertex,
        .usage = .immutable,
        .content = &vertices,
    });

    const shader = gfx.createShaderProgram(void, void, .{
        .vertex = vertex,
        .fragment = fragment,
    });

    const bindings = gfx.BufferBindings.create(index_buffer, &.{vertex_buffer});

    try quads.run(loop, .{ &window, shader, bindings });
}

fn loop(window: *quads.Window, shader: gfx.ShaderProgram, bindings: gfx.BufferBindings) bool {
    while (window.getEvent()) |ev| {
        switch (ev) {
            .close => return false,
            else => {},
        }
    }

    gfx.text.write("Hello, world!", 20, 20, 2);

    gfx.beginDefaultPass(.{}, .{ .width = 640, .height = 480 });
    gfx.useShaderProgram(shader);
    gfx.applyBindings(bindings);
    gfx.draw(0, 3, 1);
    gfx.endPass();

    gfx.text.render();

    gfx.commitFrame();

    window.swapBuffers();
    return true;
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
