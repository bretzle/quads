const std = @import("std");
const gfx = @import("common.zig");
const gl = @import("gl");
const meta = @import("../meta.zig");

const Cache = @import("gl_cache.zig");

const GlBuffer = struct {
    raw: u32,
    typ: gfx.BufferType,
    size: usize,
    index_type: ?u32,
};

const GlUniform = struct {
    loc: ?i32,
    typ: gfx.UniformType,
    array_count: i32,
};

const GlImage = struct {
    loc: ?i32,
};

const GlShader = struct {
    program: gfx.ProgramId,
    images: []const GlImage,
    uniforms: []const GlUniform,
};

pub const GlVertexAttribute = struct {
    attr_loc: u32,
    size: i32,
    typ: u32,
    offset: i64,
    stride: i32,
    buffer_index: usize,
    divisor: i32,
    gl_pass_as_float: bool,
};

const GlPipeline = struct {
    layout: []const ?GlVertexAttribute,
    shader: gfx.ShaderId,
    params: gfx.PipelineParams,
};

const GlTexture = struct {
    raw: u32,
    params: gfx.TextureParams,
};

const GlRenderPass = struct {
    gl_fb: u32,
    color_textures: []const gfx.TextureId,
    resolves: ?void,
    depth_texture: ?gfx.TextureId,
};

var shaders: meta.SimplePool(GlShader, gfx.ShaderId) = undefined;
var pipelines: meta.SimplePool(GlPipeline, gfx.PipelineId) = undefined;
var passes: meta.SimplePool(GlRenderPass, gfx.PassId) = undefined;
var buffers: meta.SimplePool(GlBuffer, gfx.BufferId) = undefined;
var textures: meta.SimplePool(GlTexture, gfx.TextureId) = undefined;
var cache: Cache = .{};

var default_framebuffer: u32 = 0;

pub var canvas_size: [2]i32 = undefined;

var arena: std.heap.ArenaAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

var gl_procs: gl.ProcTable = undefined;

pub fn init(alloc: std.mem.Allocator, size: [2]i32) void {
    std.debug.assert(gl_procs.init(@import("../rgfw.zig").getProcAddress));
    gl.makeProcTableCurrent(&gl_procs);

    gl.GetIntegerv(gl.FRAMEBUFFER_BINDING, @ptrCast(&default_framebuffer));

    var vao: u32 = 0;
    gl.GenVertexArrays(1, @ptrCast(&vao));
    gl.BindVertexArray(vao);

    canvas_size = size;
    arena = std.heap.ArenaAllocator.init(alloc);
    allocator = arena.allocator();
    shaders = meta.SimplePool(GlShader, gfx.ShaderId).create(allocator);
    pipelines = meta.SimplePool(GlPipeline, gfx.PipelineId).create(allocator);
    passes = meta.SimplePool(GlRenderPass, gfx.PassId).create(allocator);
    buffers = meta.SimplePool(GlBuffer, gfx.BufferId).create(allocator);
    textures = meta.SimplePool(GlTexture, gfx.TextureId).create(allocator);
}

pub fn deinit() void {
    arena.deinit();
}

pub fn newBuffer(typ: gfx.BufferType, usage: gfx.BufferUsage, data: anytype) gfx.BufferId {
    const gl_target = typ.gl();
    const gl_usage = usage.gl();

    var bytes: ?[]const u8 = null;
    const size: usize, const element_size: usize = switch (@typeInfo(@TypeOf(data))) {
        .Pointer => |info| blk: {
            meta.compileAssert(info.size == .One or info.size == .Slice, "data should be a slice got: {s}", .{@typeName(@TypeOf(data))});

            bytes = std.mem.sliceAsBytes(data);
            break :blk .{ bytes.?.len, bytes.?.len / data.len };
        },
        else => @compileError("unsupported: " ++ @typeName(@TypeOf(data))),
    };

    const index_type: ?u32 = switch (typ) {
        .index => switch (element_size) {
            1, 2, 4 => @truncate(element_size),
            else => unreachable,
        },
        .vertex => null,
    };

    var raw: u32 = undefined;
    gl.GenBuffers(1, @ptrCast(&raw));
    cache.storeBufferBinding(gl_target);
    cache.bindBuffer(gl_target, raw, index_type);

    gl.BufferData(gl_target, @intCast(size), null, gl_usage);
    if (bytes) |b| {
        gl.BufferSubData(gl_target, 0, @intCast(size), @ptrCast(b));
    }

    cache.restoreBufferBinding(gl_target);

    return buffers.add(.{
        .raw = raw,
        .typ = typ,
        .size = size,
        .index_type = index_type,
    });
}

pub fn newShader(vertex: [:0]const u8, fragment: [:0]const u8, details: gfx.ShaderMeta) !gfx.ShaderId {
    const vshader = try loadShader(gl.VERTEX_SHADER, vertex);
    const fshader = try loadShader(gl.FRAGMENT_SHADER, fragment);

    const program = gl.CreateProgram();
    gl.AttachShader(program, @intFromEnum(vshader));
    gl.AttachShader(program, @intFromEnum(fshader));
    gl.LinkProgram(program);

    // delete shaders
    gl.DetachShader(program, @intFromEnum(vshader));
    gl.DeleteShader(@intFromEnum(vshader));
    gl.DeleteShader(@intFromEnum(fshader));

    var link_status: i32 = 0;
    gl.GetProgramiv(program, gl.LINK_STATUS, &link_status);
    if (link_status == 0) {
        unreachable;
    }

    gl.UseProgram(program);

    var images: []GlImage = &.{};
    if (details.images.len > 0) {
        images = try allocator.alloc(GlImage, details.images.len);
        for (details.images, 0..) |img, i| {
            images[i] = .{ .loc = getUniformLocation(program, img) };
        }
    }

    var uniforms: []GlUniform = &.{};
    if (details.uniforms.len > 0) {
        uniforms = try allocator.alloc(GlUniform, details.uniforms.len);
        for (details.uniforms, 0..) |u, i| {
            uniforms[i] = .{
                .loc = getUniformLocation(program, u.name),
                .typ = u.typ,
                .array_count = @intCast(u.array_count),
            };
        }
    }

    return shaders.add(.{
        .program = @enumFromInt(program),
        .images = images,
        .uniforms = uniforms,
    });
}

pub fn newPipeline(buffer_layout: []const gfx.BufferLayout, attributes: []const gfx.VertexAttribute, shader: gfx.ShaderId, params: gfx.PipelineParams) !gfx.PipelineId {
    const BufferCacheData = struct {
        stride: i32 = 0,
        offset: i64 = 0,
    };

    const program = shaders.get(shader).program;
    const buffer_cache = try allocator.alloc(BufferCacheData, buffer_layout.len);
    defer allocator.free(buffer_cache);

    @memset(buffer_cache, .{});

    var attributes_len: usize = 0;
    for (attributes) |attr| {
        const layout = &buffer_layout[attr.buffer_index];
        const bcache = &buffer_cache[attr.buffer_index];

        if (layout.stride == 0) {
            bcache.stride += attr.format.sizeBytes();
        } else {
            bcache.stride = layout.stride;
        }

        attributes_len += switch (attr.format) {
            .mat4 => 4,
            else => 1,
        };

        std.debug.assert(bcache.stride <= 255);
    }

    const vertex_layout = try allocator.alloc(?GlVertexAttribute, attributes_len);
    @memset(vertex_layout, null);

    for (attributes) |attr| {
        const buffer_data = &buffer_cache[attr.buffer_index];
        const layout = &buffer_layout[attr.buffer_index];

        const name = attr.name;
        const _attr_loc = gl.GetAttribLocation(@intFromEnum(program), @ptrCast(name));
        const attr_loc: ?i32 = if (_attr_loc == -1) null else _attr_loc;
        const divisor: i32 = if (layout.step_func == .per_vertex) 0 else layout.step_rate;

        var attributes_count: usize = 1;
        var format = attr.format;

        if (format == .mat4) {
            format = .float4;
            attributes_count = 4;
        }

        for (0..attributes_count) |i| {
            if (attr_loc) |_loc| {
                const loc = @as(u32, @intCast(_loc)) + @as(u32, @truncate(i));

                const va = GlVertexAttribute{
                    .attr_loc = loc,
                    .size = format.components(),
                    .typ = format.gl(),
                    .offset = buffer_data.offset,
                    .stride = buffer_data.stride,
                    .buffer_index = attr.buffer_index,
                    .divisor = divisor,
                    .gl_pass_as_float = attr.pass_as_float,
                };

                std.debug.assert(loc < vertex_layout.len);

                vertex_layout[loc] = va;
            }
            buffer_data.offset += format.sizeBytes();
        }
    }

    return pipelines.add(.{
        .layout = vertex_layout,
        .shader = shader,
        .params = params,
    });
}

pub fn newRenderTexture(params: gfx.TextureParams) gfx.TextureId {
    return newTexture(.render_target, params, {});
}

pub fn newTextureFromBytes(width: u32, height: u32, format: gfx.TextureFormat, bytes: []const u8) gfx.TextureId {
    std.debug.assert(width * height * format.bytes() == bytes.len);

    const params = gfx.TextureParams{
        .width = width,
        .height = height,
        .format = format,
    };

    return newTexture(.static, params, bytes);
}

pub fn newTexture(access: gfx.TextureAccess, params: gfx.TextureParams, source: anytype) gfx.TextureId {
    const T = @TypeOf(source);
    meta.compileAssert(T == void or T == []const u8, "todo", .{});

    if (T == []u8 or T == []const u8) {
        std.debug.assert(params.kind == .texture_2d);
        std.debug.assert(params.format.size(params.width, params.height) == source.len);
    }

    if (access != .render_target) {
        std.debug.assert(params.sample_count == 0);
    }

    const kind = params.kind.gl();
    const internal_format, const format, const pixel_type = params.format.gl();

    if (access == .render_target and params.sample_count != 0) {
        @panic("1");
    }

    cache.storeTextureBinding(0);

    var texture: u32 = 0;
    gl.GenTextures(1, @ptrCast(&texture));
    cache.bindTexture(0, kind, texture);
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);

    switch (T) {
        void => {
            gl.TexImage2D(
                gl.TEXTURE_2D,
                0,
                @intCast(internal_format),
                @intCast(params.width),
                @intCast(params.height),
                0,
                format,
                pixel_type,
                null,
            );
        },
        []u8, []const u8 => {
            gl.TexImage2D(
                gl.TEXTURE_2D,
                0,
                @intCast(internal_format),
                @intCast(params.width),
                @intCast(params.height),
                0,
                format,
                pixel_type,
                @ptrCast(source),
            );
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    }

    const wrap = params.wrap.gl();
    const min_filter = params.min_filter.filter(params.mipmap_filter);
    const mag_filter = params.mag_filter.gl();

    gl.TexParameteri(kind, gl.TEXTURE_WRAP_S, @intCast(wrap));
    gl.TexParameteri(kind, gl.TEXTURE_WRAP_T, @intCast(wrap));
    gl.TexParameteri(kind, gl.TEXTURE_MIN_FILTER, @intCast(min_filter));
    gl.TexParameteri(kind, gl.TEXTURE_MAG_FILTER, @intCast(mag_filter));

    cache.restoreTextureBinding(0);

    return textures.add(.{
        .raw = texture,
        .params = params,
    });
}

pub fn newRenderPass(color_img: gfx.TextureId, depth_img: ?gfx.TextureId) !gfx.PassId {
    return newRenderPassMrt(&.{color_img}, null, depth_img);
}

pub fn newRenderPassMrt(color_img: []const gfx.TextureId, resolve_img: ?[]const gfx.TextureId, depth_img: ?gfx.TextureId) !gfx.PassId {
    std.debug.assert(color_img.len != 0 or depth_img != null);

    var gl_fb: u32 = 0;
    const resolves = null;

    gl.GenFramebuffers(1, @ptrCast(&gl_fb));
    gl.BindFramebuffer(gl.FRAMEBUFFER, gl_fb);

    for (color_img, 0..) |img, i| {
        const texture = textures.get(img);
        if (texture.params.sample_count != 0) {
            gl.FramebufferRenderbuffer(
                gl.FRAMEBUFFER,
                gl.COLOR_ATTACHMENT0 + @as(u32, @truncate(i)),
                gl.RENDERBUFFER,
                texture.raw,
            );
        } else {
            gl.FramebufferTexture2D(
                gl.FRAMEBUFFER,
                gl.COLOR_ATTACHMENT0 + @as(u32, @truncate(i)),
                gl.TEXTURE_2D,
                texture.raw,
                0,
            );
        }
    }

    if (depth_img) |img| {
        const texture = textures.get(img);
        if (texture.params.sample_count != 0) {
            gl.FramebufferRenderbuffer(
                gl.FRAMEBUFFER,
                gl.DEPTH_ATTACHMENT,
                gl.RENDERBUFFER,
                texture.raw,
            );
        } else {
            gl.FramebufferTexture2D(
                gl.FRAMEBUFFER,
                gl.DEPTH_ATTACHMENT,
                gl.TEXTURE_2D,
                texture.raw,
                0,
            );
        }
    }

    if (color_img.len > 1) {
        @panic("5");
    }

    if (resolve_img) |_| {
        @panic("6");
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, default_framebuffer);

    return passes.add(.{
        .gl_fb = gl_fb,
        .color_textures = try allocator.dupe(gfx.TextureId, color_img),
        .resolves = resolves,
        .depth_texture = depth_img,
    });
}

pub fn beginDefaultPass(action: ?gfx.PassAction) void {
    beginPass(null, action orelse .{ .clear = .{} });
}

pub fn beginPass(pass: ?gfx.PassId, action: gfx.PassAction) void {
    cache.cur_pass = pass;

    var framebuffer: u32 = undefined;
    var w: i32 = undefined;
    var h: i32 = undefined;

    if (pass) |id| {
        const p = passes.get(id);
        const texture = if (p.color_textures.len > 0) p.color_textures[0] else p.depth_texture.?;
        framebuffer = p.gl_fb;
        w = @intCast(textures.get(texture).params.width);
        h = @intCast(textures.get(texture).params.height);
    } else {
        framebuffer = default_framebuffer;
        w = canvas_size[0];
        h = canvas_size[1];
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.Viewport(0, 0, w, h);
    gl.Scissor(0, 0, w, h);

    switch (action) {
        .nothing => {},
        .clear => |c| clear(c.color, c.depth, c.stencil),
    }
}

pub fn applyPipeline(pipe: gfx.PipelineId) void {
    cache.cur_pipeline = pipe;

    const pipeline = pipelines.get(pipe);
    const shader = shaders.get(pipeline.shader);

    gl.UseProgram(@intFromEnum(shader.program));
    gl.Enable(gl.SCISSOR_TEST);

    if (pipeline.params.depth_write) {
        gl.Enable(gl.DEPTH_TEST);
        gl.DepthFunc(pipeline.params.depth_test.gl());
    } else {
        gl.Disable(gl.DEPTH_TEST);
    }

    gl.FrontFace(switch (pipeline.params.front_face_order) {
        .clockwise => gl.CW,
        .counter_clockwise => gl.CCW,
    });

    cache.setCullFace(pipeline.params.cull_face);
    cache.setBlend(pipeline.params.color_blend, pipeline.params.alpha_blend);

    cache.setStencil(pipeline.params.stencil_test);
    cache.setColorWrite(pipeline.params.color_write);
}

pub fn applyBindings(bindings: *const gfx.Bindings) void {
    const pipeline = pipelines.get(cache.cur_pipeline.?);
    const shader = shaders.get(pipeline.shader);

    for (shader.images, 0..) |img, i| {
        const bind_img = bindings.images.?[i];

        if (img.loc) |loc| {
            const texture = textures.get(bind_img);
            cache.bindTexture(@truncate(i), texture.params.kind.gl(), texture.raw);
            gl.Uniform1i(loc, @intCast(i));
        }
    }

    cache.bindBuffer(
        gl.ELEMENT_ARRAY_BUFFER,
        buffers.get(bindings.index_buffer).raw,
        buffers.get(bindings.index_buffer).index_type,
    );

    for (0..16) |i| {
        const cached_attr = &cache.attributes[i];
        const pip_attr = if (i < pipeline.layout.len) pipeline.layout[i] else null;

        if (pip_attr) |attr| {
            std.debug.assert(attr.buffer_index < bindings.vertex_buffers.len);
            const vb_id = bindings.vertex_buffers[attr.buffer_index];
            const vb = buffers.get(vb_id);

            if (cached_attr.* == null or (!std.meta.eql(attr, cached_attr.*.?.attr) or cached_attr.*.?.raw != vb.raw)) {
                cache.bindBuffer(gl.ARRAY_BUFFER, vb.raw, vb.index_type);

                gl.VertexAttribPointer(@truncate(i), attr.size, attr.typ, 0, attr.stride, @intCast(attr.offset));
                gl.VertexAttribDivisor(@truncate(i), @intCast(attr.divisor));
                gl.EnableVertexAttribArray(@truncate(i));

                cached_attr.* = .{
                    .attr = attr,
                    .raw = vb.raw,
                };
            }
        } else {
            if (cached_attr.* != null) {
                gl.DisableVertexAttribArray(@truncate(i));
                cached_attr.* = null;
            }
        }
    }
}

pub fn applyUniforms(ptr: anytype) void {
    const Ptr = @TypeOf(ptr);
    meta.compileAssert(@typeInfo(Ptr) == .Pointer, "data should be a pointer", .{});
    const T = std.meta.Child(Ptr);
    meta.compileAssert(@typeInfo(T) == .Struct, "data should be a struct pointer", .{});

    const pipeline = pipelines.get(cache.cur_pipeline.?);
    const shader = shaders.get(pipeline.shader);

    var offset: usize = 0;

    for (shader.uniforms) |uniform| {
        // "Uniforms struct does not match shader uniforms layout"
        std.debug.assert(@as(i32, @intCast(offset)) <= @as(i32, @intCast(@sizeOf(T) - uniform.typ.size() / 4)));

        const dataf = @as([*]const f32, @ptrCast(@alignCast(ptr))) + offset;
        const datai = @as([*]const i32, @ptrCast(@alignCast(ptr))) + offset;

        if (uniform.loc) |loc| {
            switch (uniform.typ) {
                .float1 => gl.Uniform1fv(loc, uniform.array_count, dataf),
                .float2 => gl.Uniform2fv(loc, uniform.array_count, dataf),
                .float3 => gl.Uniform3fv(loc, uniform.array_count, dataf),
                .float4 => gl.Uniform4fv(loc, uniform.array_count, dataf),
                .int1 => gl.Uniform1iv(loc, uniform.array_count, datai),
                .int2 => gl.Uniform2iv(loc, uniform.array_count, datai),
                .int3 => gl.Uniform3iv(loc, uniform.array_count, datai),
                .int4 => gl.Uniform4iv(loc, uniform.array_count, datai),
                .mat4 => gl.UniformMatrix4fv(loc, uniform.array_count, 0, dataf),
            }
        }

        offset += uniform.typ.size() / 4 * @as(u32, @intCast(uniform.array_count));
    }
}

pub fn draw(base_element: u32, num_elements: u32, num_instances: i32) void {
    std.debug.assert(cache.cur_pipeline != null);

    const pipeline = pipelines.get(cache.cur_pipeline.?);
    const primitive_type = pipeline.params.primitive_type;
    const index_type = cache.index_type.?;

    gl.DrawElementsInstanced(
        primitive_type.gl(),
        @intCast(num_elements),
        switch (index_type) {
            1 => gl.UNSIGNED_BYTE,
            2 => gl.UNSIGNED_SHORT,
            4 => gl.UNSIGNED_INT,
            else => unreachable,
        },
        @ptrFromInt(index_type * base_element),
        num_instances,
    );
}

pub fn endRenderPass() void {
    if (cache.cur_pass) |id| {
        cache.cur_pass = null;
        const pass = passes.get(id);
        if (pass.resolves) |_| {
            @panic("E");
        }
    }

    gl.BindFramebuffer(gl.FRAMEBUFFER, default_framebuffer);
    cache.bindBuffer(gl.ARRAY_BUFFER, 0, null);
    cache.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0, null);
}

pub fn commitFrame() void {
    cache.clearBufferBindings();
    cache.clearTextureBindings();
}

pub fn clear(color: ?[4]f32, depth: ?f32, stencil: ?i32) void {
    var bits: u32 = 0;
    if (color) |c| {
        bits |= gl.COLOR_BUFFER_BIT;
        gl.ClearColor(c[0], c[1], c[2], c[3]);
    }

    if (depth) |v| {
        bits |= gl.DEPTH_BUFFER_BIT;
        gl.ClearDepth(v);
    }

    if (stencil) |v| {
        bits |= gl.STENCIL_BUFFER_BIT;
        gl.ClearStencil(v);
    }

    if (bits != 0) {
        gl.Clear(bits);
    }
}

//

fn getUniformLocation(program: u32, name: []const u8) ?i32 {
    const loc = gl.GetUniformLocation(program, @ptrCast(name));
    return if (loc == -1) null else loc;
}

fn loadShader(shader_type: u32, source: []const u8) !gfx.ShaderId {
    const shader = gl.CreateShader(shader_type);
    std.debug.assert(shader != 0);

    gl.ShaderSource(shader, 1, @ptrCast(@alignCast(&source)), null);
    gl.CompileShader(shader);

    var compiled: i32 = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &compiled);
    if (compiled == 0) {
        unreachable;
    }

    return @enumFromInt(shader);
}
