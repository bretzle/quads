const std = @import("std");
const builtin = @import("builtin");
const gfx = @import("common.zig");
const gl = @import("gl");
const meta = @import("../meta.zig");

const Cache = @import("gl_cache.zig");
const Pool = @import("../Pool.zig").Pool;

const assert = std.debug.assert;

const GlBuffer = struct {
    raw: u32,
    typ: gfx.BufferType,
    size: usize,
    index_type: ?u32,
    vert_buffer_step_func: u32 = 0,
    setVertexAttributes: ?*const fn (attr_index: *u32, step_func: u32, vertex_buffer_offset: u32) void = null,
};

const GlUniform = struct {
    loc: i32,
    typ: gfx.UniformType,
    array_count: i32,
};

const GlShader = struct {
    program: gfx.ProgramId,
    uniforms: [8]GlUniform,
};

const GlPipeline = struct {
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

var shaders: Pool(gfx.ShaderId, GlShader) = undefined;
var pipelines: Pool(gfx.PipelineId, GlPipeline) = undefined;
var passes: Pool(gfx.PassId, GlRenderPass) = undefined;
var buffers: Pool(gfx.BufferId, GlBuffer) = undefined;
var textures: Pool(gfx.TextureId, GlTexture) = undefined;
var cache: Cache = .{};

var default_framebuffer: u32 = 0;

var allocator: std.mem.Allocator = undefined;

var gl_procs: gl.ProcTable = undefined;

pub fn init(alloc: std.mem.Allocator, desc: gfx.Config) !void {
    assert(gl_procs.init(desc.loader));
    gl.makeProcTableCurrent(&gl_procs);

    gl.GetIntegerv(gl.FRAMEBUFFER_BINDING, @ptrCast(&default_framebuffer));

    var vao: u32 = 0;
    gl.GenVertexArrays(1, @ptrCast(&vao));
    gl.BindVertexArray(vao);

    allocator = alloc;
    shaders = try Pool(gfx.ShaderId, GlShader).init(allocator, desc.shaders);
    pipelines = try Pool(gfx.PipelineId, GlPipeline).init(allocator, desc.pipelines);
    passes = try Pool(gfx.PassId, GlRenderPass).init(allocator, desc.passes);
    buffers = try Pool(gfx.BufferId, GlBuffer).init(allocator, desc.buffers);
    textures = try Pool(gfx.TextureId, GlTexture).init(allocator, desc.textures);
}

pub fn deinit() void {
    // TODO free underlying resources
    pipelines.deinit();
    shaders.deinit();
    passes.deinit();
    buffers.deinit();
    textures.deinit();
}

pub fn newBuffer(comptime T: type, desc: gfx.BufferDesc(T)) gfx.BufferId {
    const typ = desc.typ.gl();
    const usage = desc.usage.gl();

    const size = desc.getSize();
    const element_size = @sizeOf(T);

    const index_type: ?u32 = switch (desc.typ) {
        .vertex => null,
        .index => blk: {
            assert(T == u8 or T == u16 or T == u32);
            break :blk element_size;
        },
    };

    var raw: u32 = undefined;
    gl.GenBuffers(1, @ptrCast(&raw));
    cache.storeBufferBinding(typ);
    cache.bindBuffer(typ, raw, index_type);

    gl.BufferData(typ, @intCast(size), @ptrCast(desc.content), usage);

    cache.restoreBufferBinding(typ);

    return buffers.add(.{
        .raw = raw,
        .typ = desc.typ,
        .size = size,
        .index_type = index_type,
        .vert_buffer_step_func = if (desc.step_func == .per_vertex) 0 else 1,
        .setVertexAttributes = if (@typeInfo(T) == .@"struct") createVertexAttrFn(T) else null,
    });
}

pub fn updateBuffer(comptime T: type, buffer: gfx.BufferId, data: []const T) void {
    const buf = buffers.get(buffer);

    const elem_size = @sizeOf(T);
    const size = data.len * elem_size;

    assert(size <= buf.size);
    if (buf.typ == .index) {
        assert(buf.index_type != null);
        assert(elem_size == buf.index_type.?);
    }

    const gl_target = buf.typ.gl();
    cache.storeBufferBinding(gl_target);
    cache.bindBuffer(gl_target, buf.raw, buf.index_type);
    gl.BufferSubData(gl_target, 0, @intCast(size), @ptrCast(data));
    cache.restoreBufferBinding(gl_target);
}

pub fn newShader(vertex: [:0]const u8, fragment: [:0]const u8, details: gfx.ShaderMeta) !gfx.ShaderId {
    const vshader = try loadShader(gl.VERTEX_SHADER, vertex);
    const fshader = try loadShader(gl.FRAGMENT_SHADER, fragment);

    const program = gl.CreateProgram();
    gl.AttachShader(program, @intFromEnum(vshader));
    gl.AttachShader(program, @intFromEnum(fshader));
    gl.LinkProgram(program);

    // delete shaders
    gl.DeleteShader(@intFromEnum(vshader));
    gl.DeleteShader(@intFromEnum(fshader));

    var link_status: i32 = 0;
    gl.GetProgramiv(program, gl.LINK_STATUS, &link_status);
    if (link_status == 0) {
        unreachable;
    }

    gl.UseProgram(program);

    if (details.images.len > 0) {
        var slot: i32 = 0;
        for (details.images) |img| {
            const loc = gl.GetUniformLocation(program, @ptrCast(img));
            if (loc != -1) {
                gl.Uniform1i(loc, slot);
                slot += 1;
            } else {
                std.debug.print("Could not find uniform for image [{s}]!\n", .{img});
            }
        }
    }

    var uniforms: [8]GlUniform = undefined;
    if (details.uniforms.len > 0) {
        for (details.uniforms, 0..) |u, i| {
            uniforms[i] = .{
                .loc = gl.GetUniformLocation(program, @ptrCast(u.name)),
                .typ = u.typ,
                .array_count = @intCast(u.array_count),
            };
        }
    }

    return shaders.add(.{
        .program = @enumFromInt(program),
        .uniforms = uniforms,
    });
}

pub fn newPipeline(shader: gfx.ShaderId, params: gfx.PipelineParams) gfx.PipelineId {
    return pipelines.add(.{
        .shader = shader,
        .params = params,
    });
}

pub fn newRenderTexture(params: gfx.TextureParams) gfx.TextureId {
    return newTexture(.render_target, params, {});
}

pub fn newTextureFromBytes(width: u32, height: u32, format: gfx.TextureFormat, bytes: []const u8) gfx.TextureId {
    assert(width * height * format.bytes() == bytes.len);

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
        assert(params.kind == .texture_2d);
        assert(params.format.size(params.width, params.height) == source.len);
    }

    if (access != .render_target) {
        assert(params.sample_count == 0);
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

    if (params.format == .alpha) {
        gl.TexParameteri(kind, gl.TEXTURE_SWIZZLE_A, gl.RED);
    }

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

pub fn updateTexture(texture: gfx.TextureId, bytes: []const u8) void {
    const params = textures.get(texture).params;
    updateTexturePart(texture, 0, 0, params.width, params.height, bytes);
}

pub fn updateTexturePart(texture: gfx.TextureId, x: i32, y: i32, width: u32, height: u32, bytes: []const u8) void {
    const tex = textures.get(texture);

    assert(tex.params.format.size(width, height) == bytes.len);
    assert(@as(u32, @bitCast(x)) +% width <= tex.params.width);
    assert(@as(u32, @bitCast(y)) +% height <= tex.params.height);

    cache.storeTextureBinding(0);
    cache.bindTexture(0, tex.params.kind.gl(), tex.raw);

    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
    if (tex.params.format == .alpha) {
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_A, gl.RED);
    }

    _, const format, const pixel_type = tex.params.format.gl();

    gl.TexSubImage2D(gl.TEXTURE_2D, 0, x, y, @intCast(width), @intCast(height), format, pixel_type, @ptrCast(bytes));

    cache.restoreTextureBinding(0);
}

pub fn newRenderPass(color_img: gfx.TextureId, depth_img: ?gfx.TextureId) !gfx.PassId {
    return newRenderPassMrt(&.{color_img}, null, depth_img);
}

pub fn newRenderPassMrt(color_img: []const gfx.TextureId, resolve_img: ?[]const gfx.TextureId, depth_img: ?gfx.TextureId) !gfx.PassId {
    assert(color_img.len != 0 or depth_img != null);

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
        w = gfx.canvas_size.width;
        h = gfx.canvas_size.height;
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

pub fn applyBindings(bindings: gfx.Bindings) void {
    if (bindings.index_buffer != .invalid) {
        const buffer = buffers.get(bindings.index_buffer);
        cache.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer.raw, buffer.index_type);
    }

    var vert_attr_index: u32 = 0;
    for (bindings.vertex_buffers, 0..) |vbuf, i| {
        if (vbuf == .invalid) break;

        const buffer = buffers.get(vbuf);
        if (buffer.setVertexAttributes) |setter| {
            cache.bindBuffer(gl.ARRAY_BUFFER, buffer.raw, buffer.index_type);
            setter(&vert_attr_index, buffer.vert_buffer_step_func, bindings.vertex_buffer_offsets[i]);
        }
    }

    for (bindings.images, 0..) |image, i| {
        if (image == .invalid) break;
        const texture = textures.get(image);
        cache.bindTexture(@truncate(i), texture.params.kind.gl(), texture.raw);
    }
}

pub fn applyUniforms(comptime T: type, data: *const T) void {
    meta.compileAssert(@typeInfo(T) == .@"struct", "T must be a struct", .{});

    const pipeline = pipelines.get(cache.cur_pipeline.?);
    const shader = shaders.get(pipeline.shader);

    inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
        const uni = shader.uniforms[i];
        const dataf: [*]const f32 = @ptrCast(&@field(data, field.name));
        const datai: [*]const i32 = @ptrCast(&@field(data, field.name));

        switch (uni.typ) {
            .float1 => gl.Uniform1fv(uni.loc, uni.array_count, dataf),
            .float2 => gl.Uniform2fv(uni.loc, uni.array_count, dataf),
            .float3 => gl.Uniform3fv(uni.loc, uni.array_count, dataf),
            .float4 => gl.Uniform4fv(uni.loc, uni.array_count, dataf),
            .int1 => gl.Uniform1iv(uni.loc, uni.array_count, datai),
            .int2 => gl.Uniform2iv(uni.loc, uni.array_count, datai),
            .int3 => gl.Uniform3iv(uni.loc, uni.array_count, datai),
            .int4 => gl.Uniform4iv(uni.loc, uni.array_count, datai),
            .mat4 => gl.UniformMatrix4fv(uni.loc, uni.array_count, 0, dataf),
        }
    }
}

pub fn draw(base_element: u32, num_elements: u32, num_instances: i32) void {
    assert(cache.cur_pipeline != null);

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

    if (builtin.mode == .Debug) checkError();
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

pub fn applyViewport(x: i32, y: i32, w: i32, h: i32) void {
    gl.Viewport(x, y, w, h);
}

pub fn applyScissor(x: i32, y: i32, w: i32, h: i32) void {
    gl.Scissor(x, y, w, h);
}

pub fn checkError() void {
    const e = gl.GetError();
    if (e != 0) std.debug.panic("gl error: {x}", .{e});
}

//

fn loadShader(shader_type: u32, source: []const u8) !gfx.ShaderId {
    const shader = gl.CreateShader(shader_type);
    assert(shader != 0);

    gl.ShaderSource(shader, 1, @ptrCast(@alignCast(&source)), null);
    gl.CompileShader(shader);

    var compiled: i32 = 0;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &compiled);
    if (compiled == 0) {
        unreachable;
    }

    return @enumFromInt(shader);
}

fn createVertexAttrFn(comptime T: type) fn (attr_index: *u32, step_func: u32, vertex_buffer_offset: u32) void {
    return struct {
        fn cb(attr_index: *u32, step_func: u32, vertex_buffer_offset: u32) void {
            inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
                const offset: usize = if (i + vertex_buffer_offset == 0) 0 else vertex_buffer_offset + @offsetOf(T, field.name);

                switch (@typeInfo(field.type)) {
                    .array => |arr| {
                        switch (@typeInfo(arr.child)) {
                            .int => comptime unreachable, // TODO
                            .float => {
                                assert(arr.child == f32);
                                gl.VertexAttribPointer(attr_index.*, arr.len, gl.FLOAT, gl.FALSE, @sizeOf(T), offset);
                                gl.EnableVertexAttribArray(attr_index.*);
                                gl.VertexAttribDivisor(attr_index.*, step_func);
                                attr_index.* += 1;
                            },
                            else => comptime unreachable,
                        }
                    },
                    .@"struct" => unreachable, // TODO
                    else => comptime unreachable,
                }
            }
        }
    }.cb;
}
