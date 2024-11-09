const std = @import("std");
const gfx = @import("common.zig");
const low = @import("renderer_low.zig");
const math = @import("../math.zig");
const time = @import("../rgfw.zig").time;

const Mat4 = math.Mat4;

const max_vertices = 10000;
const max_indices = 5000;

pub const Vec2f = [2]f32;
pub const Vec3f = [3]f32;

/// [r, g, b, a]
pub const Color = [4]u8;

pub const Vertex = extern struct {
    pos: Vec3f,
    uv: Vec2f,
    color: Color,
};

pub const DrawMode = enum { triangles };

const DrawCall = struct {
    vertices_count: usize = 0,
    indices_count: usize = 0,
    vertices_start: usize = 0,
    indices_start: usize = 0,

    clip: ?[4]i32 = null,
    viewport: ?[4]i32 = null,
    texture: ?gfx.TextureId,

    model: Mat4,

    draw_mode: DrawMode,
    pipeline: usize,
    uniforms: ?std.ArrayList(u8),
    render_pass: ?gfx.PassId,
    capture: bool = false,
};

const GlState = struct {
    const Self = @This();

    texture: ?gfx.TextureId = null,
    draw_mode: DrawMode = .triangles,
    clip: ?[4]i32 = null,
    viewport: ?[4]i32 = null,
    model_stack: std.ArrayList(Mat4),
    pipeline: ?usize = null,
    depth_test_enable: bool = false,

    break_batching: bool = false,
    // snapshotter: MagicSnapshotter,

    render_pass: ?gfx.PassId = null,
    capture: bool = false,

    fn model(self: *const Self) Mat4 {
        return self.model_stack.getLast();
    }
};

const UniformType = struct {
    name: []const u8,
    uniform_type: gfx.UniformType,
    byte_offset: usize,
    byte_size: usize,
};

const PipelineExt = struct {
    pipeline: gfx.PipelineId,
    wants_screen_texture: bool,
};

const PipelineStorage = struct {
    const Self = @This();

    pipelines: std.BoundedArray(PipelineExt, 32),

    fn create() !Self {
        const shader = try low.newShader(vertex, fragment, .{
            .images = &.{ "Texture", "_ScreenTexture" },
            .uniforms = &.{
                .{ .name = "Projection", .typ = .mat4 },
                .{ .name = "Model", .typ = .mat4 },
                .{ .name = "_Time", .typ = .float4 },
            },
        });

        var params = gfx.PipelineParams{
            .color_blend = .{
                .equation = .add,
                .sfactor = .{ .value = .source_alpha },
                .dfactor = .{ .one_minus_value = .source_alpha },
            },
        };

        var self = Self{ .pipelines = .{} };

        params.primitive_type = .triangles;
        try self.makePipeline(shader, params, false);

        std.debug.assert(self.pipelines.len == 1);

        return self;
    }

    fn makePipeline(self: *Self, shader: gfx.ShaderId, params: gfx.PipelineParams, wants_screen_texture: bool) !void {
        const pipeline = try low.newPipeline(&.{.{}}, &.{
            .{ .name = "position", .format = .float3 },
            .{ .name = "texcoord", .format = .float2 },
            .{ .name = "color0", .format = .byte4 },
        }, shader, params);

        self.pipelines.appendAssumeCapacity(.{
            .pipeline = pipeline,
            .wants_screen_texture = wants_screen_texture,
        });
    }

    fn get(_: *const Self, mode: DrawMode, depth: bool) usize {
        if (mode == .triangles and !depth) {
            return 0;
        } else {
            unreachable;
        }
    }
};

var pipelines: PipelineStorage = undefined;

var draw_calls: std.ArrayList(DrawCall) = undefined;
var draw_calls_bindings: std.ArrayList(gfx.Bindings) = undefined;
var draw_calls_count: usize = 0;

var state: GlState = undefined;
var start_time: u64 = 0;

var white_texture: gfx.TextureId = .invalid;
var batch_vertex_buffer: std.ArrayList(Vertex) = undefined;
var batch_index_buffer: std.ArrayList(u16) = undefined;

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator, size: [2]i32) !void {
    arena = std.heap.ArenaAllocator.init(alloc);
    allocator = arena.allocator();

    low.init(allocator, size);

    white_texture = low.newTextureFromBytes(1, 1, .rgba8, &.{ 255, 255, 255, 255 });
    pipelines = try PipelineStorage.create();
    state = .{ .model_stack = try std.ArrayList(Mat4).initCapacity(allocator, 1) };
    state.model_stack.appendAssumeCapacity(Mat4.identity);
    draw_calls = std.ArrayList(DrawCall).init(allocator);
    draw_calls_bindings = std.ArrayList(gfx.Bindings).init(allocator);
    start_time = time.getTime();

    batch_vertex_buffer = std.ArrayList(Vertex).init(allocator);
    batch_index_buffer = std.ArrayList(u16).init(allocator);
}

pub fn deinit() void {
    low.deinit();
    arena.deinit();
}

pub fn beginFrame() void {
    low.clear(.{ 0, 0, 0, 0 }, null, null);
    reset();
}

pub fn endFrame() void {
    const matrix = Mat4.ortho(0, @floatFromInt(gfx.canvas_size[0]), @floatFromInt(gfx.canvas_size[1]), 0, -1, 1);
    draw(matrix);
    low.commitFrame();
}

pub fn reset() void {
    state.clip = null;
    state.texture = null;
    state.model_stack.items.len = 1;
    draw_calls_count = 0;
}

pub fn draw(projection: Mat4) void {
    for (0..draw_calls.items.len - draw_calls_bindings.items.len) |_| {
        const vbuf = low.newBuffer(.vertex, .stream, .{ Vertex, max_vertices });
        const ibuf = low.newBuffer(.index, .stream, .{ u16, max_indices });
        const bind = gfx.Bindings{
            .vertex_buffers = .{ vbuf, .invalid, .invalid, .invalid },
            .index_buffer = ibuf,
            .images = .{ white_texture, white_texture, .invalid, .invalid },
        };

        draw_calls_bindings.append(bind) catch @trap();
    }
    std.debug.assert(draw_calls_bindings.items.len == draw_calls.items.len);

    for (draw_calls.items, draw_calls_bindings.items) |*dc, *binding| {
        const pipe = &pipelines.pipelines.get(dc.pipeline);

        const width, const height = if (dc.render_pass) |_|
            unreachable
        else
            gfx.canvas_size;
        _ = height; // autofix
        _ = width; // autofix

        // TODO pipeline.wants_screen_texture

        if (dc.render_pass) |pass|
            low.beginPass(pass, .nothing)
        else
            low.beginDefaultPass(.nothing);

        low.bufferUpdate(binding.vertex_buffers[0], batch_vertex_buffer.items[dc.vertices_start..][0..dc.vertices_count]);
        low.bufferUpdate(binding.index_buffer, batch_index_buffer.items[dc.indices_start..][0..dc.indices_count]);

        binding.images.?[0] = white_texture;
        binding.images.?[1] = white_texture; // TODO: screen texture
        // TODO extra textures

        low.applyPipeline(pipe.pipeline);
        // TODO viewport
        // TODO clip
        low.applyBindings(binding);

        // TODO extra uniforms
        const uni: extern struct {
            projection: Mat4,
            model: Mat4,
        } = .{
            .projection = projection,
            .model = dc.model,
        };
        low.applyUniforms(&uni);

        low.draw(0, @intCast(dc.indices_count), 1);
        low.endRenderPass();

        if (dc.capture) unreachable;

        dc.vertices_count = 0;
        dc.indices_count = 0;
        dc.vertices_start = 0;
        dc.indices_start = 0;
    }

    draw_calls_count = 0;
    batch_index_buffer.items.len = 0;
    batch_vertex_buffer.items.len = 0;
}

pub fn setTexture(tex: ?void) void {
    if (tex) |_| {
        unreachable;
    }
}

pub fn setDrawMode(mode: DrawMode) void {
    state.draw_mode = mode;
}

pub fn geometry(vertices: []const Vertex, indices: []const u16) void {
    std.debug.assert(vertices.len < max_vertices and indices.len < max_indices);

    const pip = state.pipeline orelse pipelines.get(state.draw_mode, state.depth_test_enable);

    const previous_dc_ix: ?usize = if (draw_calls_count == 0) null else draw_calls_count - 1;
    const previous_dc: ?*DrawCall = if (previous_dc_ix) |idx| &draw_calls.items[idx] else null;

    if (previous_dc == null or
        previous_dc.?.texture != state.texture or
        !std.meta.eql(previous_dc.?.clip, state.clip) or
        !std.meta.eql(previous_dc.?.viewport, state.viewport) or
        !std.meta.eql(previous_dc.?.model, state.model()) or
        previous_dc.?.pipeline != pip or
        previous_dc.?.render_pass != state.render_pass or
        previous_dc.?.draw_mode != state.draw_mode or
        previous_dc.?.vertices_count >= max_vertices - vertices.len or
        previous_dc.?.indices_count >= max_indices - indices.len or
        previous_dc.?.capture != state.capture or
        state.break_batching)
    {
        const uniforms = if (state.pipeline) |_| unreachable else null;

        if (draw_calls_count >= draw_calls.items.len) {
            draw_calls.append(.{
                .texture = state.texture,
                .model = state.model(),
                .draw_mode = state.draw_mode,
                .pipeline = pip,
                .uniforms = uniforms,
                .render_pass = state.render_pass,
            }) catch @trap();
        }

        draw_calls.items[draw_calls_count].texture = state.texture;
        draw_calls.items[draw_calls_count].uniforms = uniforms;
        draw_calls.items[draw_calls_count].vertices_count = 0;
        draw_calls.items[draw_calls_count].indices_count = 0;
        draw_calls.items[draw_calls_count].clip = state.clip;
        draw_calls.items[draw_calls_count].viewport = state.viewport;
        draw_calls.items[draw_calls_count].model = state.model();
        draw_calls.items[draw_calls_count].pipeline = pip;
        draw_calls.items[draw_calls_count].render_pass = state.render_pass;
        draw_calls.items[draw_calls_count].capture = state.capture;
        draw_calls.items[draw_calls_count].indices_start = batch_index_buffer.items.len;
        draw_calls.items[draw_calls_count].vertices_start = batch_vertex_buffer.items.len;

        draw_calls_count += 1;
        state.break_batching = false;
    }

    const dc = &draw_calls.items[draw_calls_count - 1];

    batch_vertex_buffer.appendSlice(vertices) catch @trap();
    batch_index_buffer.appendSlice(indices) catch @trap();

    dc.vertices_count += vertices.len;
    dc.indices_count += indices.len;
    dc.texture = state.texture;
}

pub fn drawTriangle(v1: Vec2f, v2: Vec2f, v3: Vec2f, c: Color) void {
    const indices = [3]u16{ 0, 1, 2 };
    const vertices = [3]Vertex{
        .{ .pos = .{ v1[0], v1[1], 0 }, .uv = .{ 0, 0 }, .color = c },
        .{ .pos = .{ v2[0], v2[1], 0 }, .uv = .{ 0, 0 }, .color = c },
        .{ .pos = .{ v3[0], v3[1], 0 }, .uv = .{ 0, 0 }, .color = c },
    };

    setTexture(null);
    setDrawMode(.triangles);
    geometry(&vertices, &indices);
}

const vertex =
    \\#version 330
    \\in vec3 position;
    \\in vec2 texcoord;
    \\in vec4 color0;
    \\
    \\out vec2 uv;
    \\out vec4 color;
    \\
    \\uniform mat4 Model;
    \\uniform mat4 Projection;
    \\
    \\void main() {
    \\    gl_Position = Projection * Model * vec4(position, 1);
    \\    color = color0 / 255.0;
    \\    uv = texcoord;
    \\}
;

const fragment =
    \\#version 330
    \\in vec4 color;
    \\in vec2 uv;
    \\
    \\uniform sampler2D Texture;
    \\
    \\void main() {
    \\    gl_FragColor = color * texture2D(Texture, uv) ;
    \\}
;
