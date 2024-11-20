const std = @import("std");
const quads = @import("quads");

const gfx = quads.gfx;

pub const std_options = std.Options{
    .logFn = quads.logFn,
};

const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    try quads.init(allocator, .{});

    var window = try quads.createWindow(.{ .title = "basic mq" });

    try window.createContext(.{});
    window.makeContextCurrent();
    window.swapInterval(1);

    try gfx.init(allocator, .{ .loader = quads.glGetProcAddress });

    try gfx.text.init();

    const indices = [3]u16{ 0, 1, 2 };
    const vertices = [3]Vertex{
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0, 1 } },
        .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0, 1 } },
        .{ .pos = .{ 0.0, 0.5 }, .color = .{ 0, 0, 1, 1 } },
    };

    const vertex_buffer = gfx.createBuffer(Vertex, .{ .typ = .vertex, .usage = .immutable, .content = &vertices });
    const index_buffer = gfx.createBuffer(u16, .{ .typ = .index, .usage = .immutable, .content = &indices });

    const bindings = gfx.Bindings.create(index_buffer, &.{vertex_buffer});

    const shader = try gfx.createShader(vertex, fragment, .{});

    const pipeline = gfx.createPipeline(shader, .{});

    try quads.run(loop, .{ &window, pipeline, bindings });
}

fn loop(window: *quads.Window, pipeline: gfx.PipelineId, bindings: gfx.Bindings) bool {
    while (window.getEvent()) |ev| {
        // std.debug.print("{any}\n", .{ev});
        switch (ev) {
            .close => {
                defer _ = gpa.deinit();
                quads.deinit();
                window.destroy();
                gfx.deinit();
                return false;
            },
            .framebuffer => |s| gfx.canvas_size = s,
            else => {},
        }
    }

    gfx.text.write("Hello, world!", 20, 20, 2);

    gfx.beginDefaultPass(null);
    gfx.applyPipeline(pipeline);
    gfx.applyBindings(bindings);
    gfx.draw(0, 3, 1);
    gfx.endRenderPass();

    gfx.text.render();

    gfx.commitFrame();

    window.swapBuffers();
    return true;
}

const vertex =
    \\#version 100
    \\
    \\attribute vec2 in_pos;
    \\attribute vec4 in_color;
    \\varying lowp vec4 color;
    \\
    \\void main() {
    \\  gl_Position = vec4(in_pos, 0, 1);
    \\  color = in_color;
    \\}
;

const fragment =
    \\#version 100
    \\
    \\varying lowp vec4 color;
    \\
    \\void main() {
    \\  gl_FragColor = color;
    \\}
;
