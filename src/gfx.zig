const std = @import("std");
const rgfw = @import("rgfw.zig");
const math = @import("math.zig");
const render = @import("backend/gl.zig");
const help = @import("backend/help.zig");

const Rect = math.Rect;
const Area = math.Area;
const Window = rgfw.Window;

pub const Vec2f = [2]f32;
pub const Vec2i = [2]i32;

pub const Vec3i = [3]i32;
pub const Vec3f = [3]f32;

pub const Vec4i = [4]i32;
pub const Vec4f = [4]f32;

pub const MAX_BATCHES = 16;
pub const MAX_VERTS = 128;

pub const Color = extern struct {
    a: u8 = 0,
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,
};

pub const DrawType = enum(u32) {
    points = 0x0000,
    lines = 0x0001,
    line_loop = 0x0002,
    line_strip = 0x0003,
    triangles = 0x0004,
    triangle_strip = 0x0005,
    triangle_fan = 0x0006,
    quads = 0x0007,

    // these are to ensure GL_DEPTH_TEST is disabled when they're being rendered
    points_2d = 0x0010,
    lines_2d = 0x0011,
    line_loop_2d = 0x0012,
    line_strip_2d = 0x0013,
    triangles_2d = 0x0014,
    triangle_strip_2d = 0x0015,
    triangle_fan_2d = 0x0016,

    triangles_2d_blend = 0x0114,
};

pub const RenderInfo = struct {
    batches: std.ArrayListUnmanaged(Batch) = .{},
    data: std.MultiArrayList(Vertex) = .{},

    const Batch = struct { start: usize, len: usize, typ: DrawType, tex: u32, line_width: f32 };
    const Vertex = struct { pos: [3]f32, uv: [2]f32, color: [4]f32 };
};

var renderInfo: RenderInfo = .{};
pub var args: struct {
    texture: u32 = 1,
    current_rect: Rect = .{},
    rotate: Vec3f = .{ 0, 0, 0 },
    fill: bool = true,
    center: Vec3f = .{ -1, -1, -1 },
    line_width: f32 = 1,
    program: u32 = 0,
} = .{};

pub fn init(allocator: std.mem.Allocator, window: *Window) !void {
    args.current_rect = .{ .w = window.r.w, .h = window.r.h };

    try renderInfo.batches.ensureTotalCapacity(allocator, MAX_BATCHES);
    try renderInfo.data.ensureTotalCapacity(allocator, MAX_VERTS);

    render.init(window.r.w, window.r.h);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    render.deinit();
    renderInfo.batches.deinit(allocator);
    renderInfo.data.deinit(allocator);
}

pub fn updateSize(r: Area) void {
    args.current_rect = .{ .w = @intCast(r.w), .h = @intCast(r.h) };
    render.viewport(0, 0, @intCast(r.w), @intCast(r.h));
}

pub fn clear(c: Color) void {
    render.clear(
        @as(f32, @floatFromInt(c.r)) / 255.0,
        @as(f32, @floatFromInt(c.g)) / 255.0,
        @as(f32, @floatFromInt(c.b)) / 255.0,
        @as(f32, @floatFromInt(c.a)) / 255.0,
    );
    render.draw(&renderInfo);
}

pub fn drawTriangle(tri: [3]Vec2i, c: Color) void {
    drawTriangleF(.{ help.cast2(tri[0]), help.cast2(tri[1]), help.cast2(tri[2]) }, c);
}

pub fn drawTriangleF(tri: [3]Vec2f, c: Color) void {
    if (!args.fill) unreachable;

    const center = help.getWorldPoint(tri[2][0], (tri[2][1] + tri[0][1]) / 2.0, 0);
    const matrix = help.getDrawMatrix(center);

    const points = [3]Vec3f{
        help.getFinalPoint(&matrix, tri[0][0], tri[0][1], 0.0),
        help.getFinalPoint(&matrix, tri[1][0], tri[1][1], 0.0),
        help.getFinalPoint(&matrix, tri[2][0], tri[2][1], 0.0),
    };

    const coords = [3]Vec2f{
        .{ 0.0, 1.0 },
        .{ 1.0, 1.0 },
        .{ if ((tri[2][0] - tri[0][0]) / tri[1][0] < 1) (tri[2][0] - tri[0][0]) / tri[1][0] else 0, 0.0 },
    };

    geometry(.triangles_2d, &points, &coords, c);
}

pub fn drawRect(rect: Vec4i, c: Color) void {
    drawRectF(help.cast4(rect), c);
}

pub fn drawRectF(rect: Vec4f, c: Color) void {
    if (!args.fill) unreachable;

    const center = help.getWorldPoint(rect[0] + (rect[2] / 2), rect[1] + (rect[3] / 2), 0);
    const matrix = help.getDrawMatrix(center);

    const points = [6]Vec3f{
        help.getFinalPoint(&matrix, rect[0], rect[1], 0),
        help.getFinalPoint(&matrix, rect[0], rect[1] + rect[3], 0),
        help.getFinalPoint(&matrix, rect[0] + rect[2], rect[1], 0),

        help.getFinalPoint(&matrix, rect[0] + rect[2], rect[1] + rect[3], 0),
        help.getFinalPoint(&matrix, rect[0] + rect[2], rect[1], 0),
        help.getFinalPoint(&matrix, rect[0], rect[1] + rect[3], 0),
    };

    const coords = [6]Vec2f{
        .{ 0.0, 0.0 },
        .{ 0.0, 1.0 },
        .{ 1.0, 0.0 },
        .{ 1.0, 1.0 },
        .{ 1.0, 0.0 },
        .{ 0.0, 1.0 },
    };

    geometry(.triangles_2d, &points, &coords, c);
}

pub fn geometry(typ: DrawType, points: []const Vec3f, texPoints: []const Vec2f, c: Color) void {
    if (renderInfo.batches.items.len + 1 >= MAX_BATCHES or renderInfo.data.len + points.len >= MAX_VERTS) {
        render.draw(&renderInfo);
    }

    var batch: *RenderInfo.Batch = undefined;

    if (renderInfo.batches.items.len == 0 or
        renderInfo.batches.items[renderInfo.batches.items.len - 1].tex != args.texture or
        renderInfo.batches.items[renderInfo.batches.items.len - 1].line_width != args.line_width or
        renderInfo.batches.items[renderInfo.batches.items.len - 1].typ != typ or
        renderInfo.batches.items[renderInfo.batches.items.len - 1].typ != .triangle_fan_2d)
    {
        batch = renderInfo.batches.addOneAssumeCapacity();
        batch.* = .{
            .start = renderInfo.data.len,
            .len = 0,
            .typ = typ,
            .tex = args.texture,
            .line_width = args.line_width,
        };
    } else {
        batch = &renderInfo.batches.items[renderInfo.batches.items.len - 1];
    }

    batch.len += points.len;

    const color = [4]f32{
        @as(f32, @floatFromInt(c.r)) / 255.0,
        @as(f32, @floatFromInt(c.g)) / 255.0,
        @as(f32, @floatFromInt(c.b)) / 255.0,
        @as(f32, @floatFromInt(c.a)) / 255.0,
    };

    for (points, texPoints) |pos, uv| {
        // TODO: gradient
        renderInfo.data.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .color = color });
    }
}

pub const createTexture = render.createTexture;
pub const rgb = help.rgb;
