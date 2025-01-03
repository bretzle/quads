const std = @import("std");
const winit = @import("winit");
const gfx = @import("gfx");

pub const std_options = std.Options{
    .logFn = winit.logFn,
};

const Vertex = extern struct {
    pos: [2]f32,
    color: [4]f32,
};

const Color = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0xFF,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    try winit.init(allocator, .{});

    var window = try winit.createWindow(.{ .title = "basic mq" });

    try window.createContext(.{});
    window.makeContextCurrent();
    window.swapInterval(1);

    window.setIcon(std.mem.asBytes(&[4]Color{
        .{ .r = 0xFF },
        .{ .g = 0xFF },
        .{ .b = 0xFF },
        .{},
    }), .{ .width = 2, .height = 2 });

    try gfx.init(allocator, .{ .loader = winit.glGetProcAddress });

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

    try winit.run(loop, .{ &window, pipeline, bindings });
}

fn loop(window: *winit.Window, pipeline: gfx.PipelineId, bindings: gfx.Bindings) bool {
    while (window.getEvent()) |ev| {
        // std.debug.print("{any}\n", .{ev});
        switch (ev) {
            .close => {
                defer _ = gpa.deinit();
                winit.deinit();
                window.destroy();
                gfx.deinit();
                return false;
            },
            .framebuffer => |s| gfx.canvas_size = .{ s.width, s.height },
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
