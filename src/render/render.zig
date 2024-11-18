const std = @import("std");
const gl = @import("gl");
const types = @import("types.zig");
const descriptions = @import("descriptions.zig");
const quads = @import("../quads.zig");

const Pool = @import("../Pool.zig").Pool;
const RenderCache = @import("RenderCache.zig");

const assert = std.debug.assert;

pub const text = @import("text.zig");

pub usingnamespace types;
pub usingnamespace descriptions;

var procs: gl.ProcTable = undefined;

var cache = RenderCache.create();
var pip_cache: types.RenderState = undefined;
var vao: u32 = undefined;
var cur_bindings: types.BufferBindings = undefined;

var image_cache: Pool(types.Image, GlImage) = undefined;
var pass_cache: Pool(types.Pass, GlPass) = undefined;
var buffer_cache: Pool(types.Buffer, GlBuffer) = undefined;
var shader_cache: Pool(types.ShaderProgram, GLShaderProgram) = undefined;

var in_pass: bool = false;
var frame_index: u32 = 1;
var cur_pass_h: i32 = 0;

// TODO: this feels a little bit janky, storing just the index buffer offset here
var cur_ib_offset: i32 = 0;

pub fn init(allocator: std.mem.Allocator, desc: descriptions.RendererDesc) !void {
    image_cache = try .init(allocator, desc.pool_sizes.texture);
    pass_cache = try .init(allocator, desc.pool_sizes.offscreen_pass);
    buffer_cache = try .init(allocator, desc.pool_sizes.buffers);
    shader_cache = try .init(allocator, desc.pool_sizes.shaders);

    assert(procs.init(desc.loader.?));
    gl.makeProcTableCurrent(&procs);

    pip_cache = .{};
    setRenderState(.{});

    gl.GenVertexArrays(1, @ptrCast(&vao));
    cache.bindVertexArray(vao);
}

pub fn deinit() void {
    // TODO destroy items in cache too!
    image_cache.deinit();
    pass_cache.deinit();
    buffer_cache.deinit();
    shader_cache.deinit();
}

pub fn setRenderState(state: types.RenderState) void {
    // depth
    if (state.depth.enabled != pip_cache.depth.enabled) {
        if (state.depth.enabled) gl.Enable(gl.DEPTH_TEST) else gl.Disable(gl.DEPTH_TEST);
        gl.DepthMask(if (state.depth.enabled) gl.TRUE else gl.FALSE);
        pip_cache.depth.enabled = state.depth.enabled;
    }

    if (state.depth.compare_func != pip_cache.depth.compare_func) {
        gl.DepthFunc(translate.compareFuncToGl(state.depth.compare_func));
        pip_cache.depth.compare_func = state.depth.compare_func;
    }

    // stencil
    if (state.stencil.enabled != pip_cache.stencil.enabled) {
        if (state.stencil.enabled) gl.Enable(gl.STENCIL_TEST) else gl.Disable(gl.STENCIL_TEST);
        pip_cache.stencil.enabled = state.stencil.enabled;
    }

    if (state.stencil.write_mask != pip_cache.stencil.write_mask) {
        gl.StencilMask(state.stencil.write_mask);
        pip_cache.stencil.write_mask = state.stencil.write_mask;
    }

    if (state.stencil.compare_func != pip_cache.stencil.compare_func or
        state.stencil.read_mask != pip_cache.stencil.read_mask or
        state.stencil.ref != pip_cache.stencil.ref)
    {
        gl.StencilFunc(translate.compareFuncToGl(state.stencil.compare_func), (state.stencil.ref), (state.stencil.read_mask));
        pip_cache.stencil.compare_func = state.stencil.compare_func;
        pip_cache.stencil.ref = state.stencil.ref;
        pip_cache.stencil.read_mask = state.stencil.read_mask;
    }

    if (state.stencil.fail_op != pip_cache.stencil.fail_op or
        state.stencil.depth_fail_op != pip_cache.stencil.depth_fail_op or
        state.stencil.pass_op != pip_cache.stencil.pass_op)
    {
        gl.StencilOp(translate.stencilOpToGl(state.stencil.fail_op), translate.stencilOpToGl(state.stencil.depth_fail_op), translate.stencilOpToGl(state.stencil.pass_op));
        pip_cache.stencil.fail_op = state.stencil.fail_op;
        pip_cache.stencil.depth_fail_op = state.stencil.depth_fail_op;
        pip_cache.stencil.pass_op = state.stencil.pass_op;
    }

    // blend
    if (state.blend.enabled != pip_cache.blend.enabled) {
        if (state.blend.enabled) gl.Enable(gl.BLEND) else gl.Disable(gl.BLEND);
        pip_cache.blend.enabled = state.blend.enabled;
    }

    if (state.blend.src_factor_rgb != pip_cache.blend.src_factor_rgb or
        state.blend.dst_factor_rgb != pip_cache.blend.dst_factor_rgb or
        state.blend.src_factor_alpha != pip_cache.blend.src_factor_alpha or
        state.blend.dst_factor_alpha != pip_cache.blend.dst_factor_alpha)
    {
        gl.BlendFuncSeparate(translate.blendFactorToGl(state.blend.src_factor_rgb), translate.blendFactorToGl(state.blend.dst_factor_rgb), translate.blendFactorToGl(state.blend.src_factor_alpha), translate.blendFactorToGl(state.blend.dst_factor_alpha));
        pip_cache.blend.src_factor_rgb = state.blend.src_factor_rgb;
        pip_cache.blend.dst_factor_rgb = state.blend.dst_factor_rgb;
        pip_cache.blend.src_factor_alpha = state.blend.src_factor_alpha;
        pip_cache.blend.dst_factor_alpha = state.blend.dst_factor_alpha;
    }

    if (state.blend.op_rgb != pip_cache.blend.op_rgb or state.blend.op_alpha != pip_cache.blend.op_alpha) {
        gl.BlendEquationSeparate(translate.blendOpToGl(state.blend.op_rgb), translate.blendOpToGl(state.blend.op_alpha));
        pip_cache.blend.op_rgb = state.blend.op_rgb;
        pip_cache.blend.op_alpha = state.blend.op_alpha;
    }

    if (state.blend.color_write_mask != pip_cache.blend.color_write_mask) {
        const r = (@intFromEnum(state.blend.color_write_mask) & @intFromEnum(types.ColorMask.r)) != 0;
        const g = (@intFromEnum(state.blend.color_write_mask) & @intFromEnum(types.ColorMask.g)) != 0;
        const b = (@intFromEnum(state.blend.color_write_mask) & @intFromEnum(types.ColorMask.b)) != 0;
        const a = (@intFromEnum(state.blend.color_write_mask) & @intFromEnum(types.ColorMask.a)) != 0;
        gl.ColorMask(if (r) 1 else 0, if (g) 1 else 0, if (b) 1 else 0, if (a) 1 else 0);
        pip_cache.blend.color_write_mask = state.blend.color_write_mask;
    }

    if (std.math.approxEqAbs(f32, state.blend.color[0], pip_cache.blend.color[0], 0.0001) or
        std.math.approxEqAbs(f32, state.blend.color[1], pip_cache.blend.color[1], 0.0001) or
        std.math.approxEqAbs(f32, state.blend.color[2], pip_cache.blend.color[2], 0.0001) or
        std.math.approxEqAbs(f32, state.blend.color[3], pip_cache.blend.color[3], 0.0001))
    {
        gl.BlendColor(state.blend.color[0], state.blend.color[1], state.blend.color[2], state.blend.color[3]);
        pip_cache.blend.color = state.blend.color;
    }

    // scissor
    if (state.scissor != pip_cache.scissor) {
        if (state.scissor) gl.Enable(gl.SCISSOR_TEST) else gl.Disable(gl.SCISSOR_TEST);
        pip_cache.scissor = state.scissor;
    }

    // cull mode
    if (state.cull_mode != pip_cache.cull_mode) {
        if (state.cull_mode == .none) gl.Enable(gl.CULL_FACE) else gl.Disable(gl.CULL_FACE);
        switch (state.cull_mode) {
            .front => gl.CullFace(gl.FRONT),
            .back => gl.CullFace(gl.BACK),
            else => {},
        }
        pip_cache.cull_mode = state.cull_mode;
    }

    // face winding
    if (state.face_winding != pip_cache.face_winding) {
        gl.FrontFace(if (state.face_winding == .ccw) gl.CCW else gl.CW);
        pip_cache.face_winding = state.face_winding;
    }
}

pub fn viewport(x: i32, y: i32, width: i32, height: i32) void {
    assert(in_pass);
    cache.viewport(x, y, width, height);
}

//#region image

const GlImage = struct {
    tid: u32,
    width: i32,
    height: i32,
    depth: bool,
    stencil: bool,
};

pub fn createImage(desc: descriptions.ImageDesc) types.Image {
    var img = std.mem.zeroes(GlImage);
    img.width = desc.width;
    img.height = desc.height;

    if (desc.pixel_format == .depth_stencil) {
        assert(desc.usage == .immutable);
        gl.GenRenderbuffers(1, @ptrCast(&img.tid));
        gl.BindRenderbuffer(gl.RENDERBUFFER, img.tid);
        gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, desc.width, desc.height);
        img.depth = true;
        img.stencil = true;
    } else if (desc.pixel_format == .stencil) {
        assert(desc.usage == .immutable);
        gl.GenRenderbuffers(1, @ptrCast(&img.tid));
        gl.BindRenderbuffer(gl.RENDERBUFFER, img.tid);
        gl.RenderbufferStorage(gl.RENDERBUFFER, gl.STENCIL_INDEX8, desc.width, desc.height);
        img.stencil = true;
    } else {
        gl.GenTextures(1, @ptrCast(&img.tid));
        cache.bindImage(img.tid, 0);

        const wrap_u: i32 = if (desc.wrap_u == .clamp) gl.CLAMP_TO_EDGE else gl.REPEAT;
        const wrap_v: i32 = if (desc.wrap_v == .clamp) gl.CLAMP_TO_EDGE else gl.REPEAT;
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap_u);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap_v);

        const filter_min: i32 = if (desc.min_filter == .nearest) gl.NEAREST else gl.LINEAR;
        const filter_mag: i32 = if (desc.mag_filter == .nearest) gl.NEAREST else gl.LINEAR;
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter_min);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter_mag);

        const internal_format, const format, const pixel_type = translate.pixelFormat(desc.pixel_format);

        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_A, gl.RED);

        if (desc.content) |content| {
            gl.TexImage2D(gl.TEXTURE_2D, 0, internal_format, desc.width, desc.height, 0, format, pixel_type, content);
        } else {
            gl.TexImage2D(gl.TEXTURE_2D, 0, internal_format, desc.width, desc.height, 0, format, pixel_type, null);
        }

        cache.bindImage(0, 0);
    }

    return image_cache.add(img);
}

//#endregion

//#region pass

const GlPass = struct {
    framebuffer_tid: u32 = 0,
    color_atts: [4]types.Image = [_]types.Image{.invalid} ** 4,
    num_color_atts: usize = 1,
    depth_stencil_img: ?types.Image = null,
};

pub fn beginDefaultPass(action: types.ClearCommand, size: quads.Size) void {
    assert(!in_pass);
    in_pass = true;
    beginDefaultOrOffscreenPass(.invalid, action, size);
}

pub fn beginPass(pass: types.Pass, action: types.ClearCommand) void {
    assert(!in_pass);
    in_pass = true;
    beginDefaultOrOffscreenPass(pass, action, .{ .width = 0xFFFF, .height = 0xFFFF });
}

pub fn endPass() void {
    assert(in_pass);
    in_pass = false;
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
}

pub fn commitFrame() void {
    assert(!in_pass);
    frame_index += 1;

    checkErr();
}

fn beginDefaultOrOffscreenPass(offscreen_pass: types.Pass, action: types.ClearCommand, size: quads.Size) void {
    var num_color_atts: usize = 1;

    const width: i32 = @as(i16, @bitCast(size.width));
    const height: i32 = @as(i16, @bitCast(size.height));

    if (offscreen_pass != .invalid) {
        const pass = pass_cache.get(offscreen_pass);
        const img = image_cache.get(pass.color_atts[0]);
        gl.BindFramebuffer(gl.FRAMEBUFFER, pass.framebuffer_tid);
        gl.Viewport(0, 0, img.width, img.height);
        cur_pass_h = img.height;
        num_color_atts = pass.num_color_atts;
    } else {
        gl.Viewport(0, 0, width, height);
        cur_pass_h = height;
    }

    var clear_mask: u32 = 0;
    if (action.colors[0].clear) {
        clear_mask |= gl.COLOR_BUFFER_BIT;
        gl.ClearColor(action.colors[0].color[0], action.colors[0].color[1], action.colors[0].color[2], action.colors[0].color[3]);
    }
    if (action.clear_stencil) {
        clear_mask |= gl.STENCIL_BUFFER_BIT;
        if (pip_cache.stencil.write_mask != 0xFF) {
            pip_cache.stencil.write_mask = 0xFF;
            gl.StencilMask(0xFF);
        }
    }
    if (action.clear_depth) {
        clear_mask |= gl.DEPTH_BUFFER_BIT;
        if (!pip_cache.depth.enabled) {
            pip_cache.depth.enabled = true;
            gl.Enable(gl.DEPTH_TEST);
            gl.DepthMask(gl.TRUE);
        }
    }

    if (num_color_atts == 1) {
        if (action.colors[0].clear) gl.ClearColor(action.colors[0].color[0], action.colors[0].color[1], action.colors[0].color[2], action.colors[0].color[3]);
        if (action.clear_stencil) gl.ClearStencil(action.stencil);
        if (action.clear_depth) gl.ClearDepth(action.depth);
        if (clear_mask != 0) gl.Clear(clear_mask);
    } else {
        for (action.colors, 0..) |color_action, i| {
            const index: c_int = @as(c_int, @intCast(i));

            if (color_action.clear) gl.ClearBufferfv(gl.COLOR, index, &color_action.color);

            if (action.clear_depth and action.clear_stencil) {
                gl.ClearBufferfi(gl.DEPTH_STENCIL, index, @as(f32, @floatCast(action.depth)), action.stencil);
            } else if (action.clear_depth) {
                gl.ClearBufferfv(gl.DEPTH, index, @ptrCast(&@as(f32, @floatCast(action.depth))));
            } else if (action.clear_stencil) {
                gl.ClearBufferiv(gl.STENCIL, index, @ptrCast(&@as(i32, action.stencil)));
            }
        }
    }
}

//#endregion

//#region buffer

const GlBuffer = struct {
    vbo: u32 = 0,
    stream: bool = false,
    size: u32 = 0,
    append_frame_index: u32 = 0,
    append_pos: u32 = 0,
    append_overflow: bool = false,
    index_buffer_type: u32 = 0,
    vert_buffer_step_func: u32 = 0,
    setVertexAttributes: ?*const fn (attr_index: *u32, step_func: u32, vertex_buffer_offset: u32) void = null,
};

pub fn createBuffer(comptime T: type, desc: descriptions.BufferDesc(T)) types.Buffer {
    var buffer = GlBuffer{
        .stream = desc.usage == .stream,
        .vert_buffer_step_func = if (desc.step_func == .per_vertex) 0 else 1,
        .size = desc.getSize(),
    };

    if (@typeInfo(T) == .@"struct") {
        buffer.setVertexAttributes = struct {
            fn cb(attr_index: *u32, step_func: u32, vertex_buffer_offset: u32) void {
                inline for (@typeInfo(T).@"struct".fields, 0..) |field, i| {
                    const offset: usize = if (i + vertex_buffer_offset == 0) 0 else vertex_buffer_offset + @offsetOf(T, field.name);

                    switch (@typeInfo(field.type)) {
                        .int => |type_info| {
                            if (type_info.signedness == .signed) {
                                comptime unreachable;
                            } else {
                                switch (type_info.bits) {
                                    32 => {
                                        // u32 is color
                                        gl.VertexAttribPointer(attr_index.*, 4, gl.UNSIGNED_BYTE, gl.TRUE, @sizeOf(T), offset);
                                        gl.EnableVertexAttribArray(attr_index.*);
                                        gl.VertexAttribDivisor(attr_index.*, step_func);
                                        attr_index.* += 1;
                                    },
                                    else => comptime unreachable,
                                }
                            }
                        },
                        .float => {
                            gl.VertexAttribPointer(i, 1, gl.FLOAT, gl.FALSE, @sizeOf(T), offset);
                            gl.EnableVertexAttribArray(i);
                        },
                        .array => |arr| {
                            switch (@typeInfo(arr.child)) {
                                .int => unreachable,
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
                        .@"struct" => |type_info| {
                            const field_type = type_info.fields[0].type;
                            assert(@sizeOf(field_type) == 4);

                            switch (@typeInfo(field_type)) {
                                .float => {
                                    switch (type_info.fields.len) {
                                        2, 3, 4 => {
                                            gl.VertexAttribPointer(attr_index.*, type_info.fields.len, gl.FLOAT, gl.FALSE, @sizeOf(T), offset);
                                            gl.EnableVertexAttribArray(attr_index.*);
                                            gl.VertexAttribDivisor(attr_index.*, step_func);
                                            attr_index.* += 1;
                                        },
                                        else => comptime unreachable,
                                    }
                                },
                                else => comptime unreachable,
                            }
                        },
                        else => comptime unreachable,
                    }
                }
            }
        }.cb;
    } else {
        buffer.index_buffer_type = if (T == u16) gl.UNSIGNED_SHORT else gl.UNSIGNED_INT;
    }

    const buffer_kind: u32 = if (desc.type == .index) gl.ELEMENT_ARRAY_BUFFER else gl.ARRAY_BUFFER;
    gl.GenBuffers(1, @ptrCast(&buffer.vbo));
    cache.bindBuffer(buffer_kind, buffer.vbo);

    const usage: u32 = switch (desc.usage) {
        .stream => gl.STREAM_DRAW,
        .immutable => gl.STATIC_DRAW,
        .dynamic => gl.DYNAMIC_DRAW,
    };

    gl.BufferData(buffer_kind, @intCast(buffer.size), @ptrCast(desc.content), usage);
    return buffer_cache.add(buffer);
}

pub fn updateBuffer(comptime T: type, buffer: types.Buffer, data: []const T) void {
    const buf = buffer_cache.get(buffer);
    cache.bindBuffer(gl.ARRAY_BUFFER, buf.vbo);

    // orphan the buffer for streamed so we can reset our append_pos and overflow state
    if (buf.stream) {
        gl.BufferData(gl.ARRAY_BUFFER, @intCast(data.len * @sizeOf(T)), null, gl.STREAM_DRAW);
        buf.append_pos = 0;
        buf.append_overflow = false;
    }

    gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(data.len * @sizeOf(T)), data.ptr);
}

//#endregion

//#region shader

const GLShaderProgram = struct {
    program: u32,
    vs_uniform_cache: [16]i32 = [_]i32{-1} ** 16,
    fs_uniform_cache: [16]i32 = [_]i32{-1} ** 16,
};

pub fn createShaderProgram(comptime VertUniformT: type, comptime FragUniformT: type, desc: descriptions.ShaderDesc) types.ShaderProgram {
    assert(@typeInfo(VertUniformT) == .@"struct" or VertUniformT == void);
    assert(@typeInfo(FragUniformT) == .@"struct" or FragUniformT == void);

    const vertex_shader = compileShader(gl.VERTEX_SHADER, desc.vertex);
    const frag_shader = compileShader(gl.FRAGMENT_SHADER, desc.fragment);

    if (vertex_shader == 0 and frag_shader == 0) return .invalid;

    const id = gl.CreateProgram();
    gl.AttachShader(id, vertex_shader);
    gl.AttachShader(id, frag_shader);
    gl.LinkProgram(id);
    gl.DeleteShader(vertex_shader);
    gl.DeleteShader(frag_shader);

    if (!checkProgramError(id)) {
        gl.DeleteProgram(id);
        return .invalid;
    }

    var shader = GLShaderProgram{ .program = id };

    // store currently bound program and rebind when done
    var cur_prog: i32 = 0;
    gl.GetIntegerv(gl.CURRENT_PROGRAM, @ptrCast(&cur_prog));
    gl.UseProgram(id);

    // resolve all images to their bound locations
    inline for (.{ VertUniformT, FragUniformT }) |UniformT| {
        if (UniformT == void) continue;
        if (@hasDecl(UniformT, "metadata") and @hasField(@TypeOf(UniformT.metadata), "images")) {
            var image_slot: i32 = 0;
            inline for (@field(UniformT.metadata, "images")) |img| {
                const loc = gl.GetUniformLocation(id, img);
                if (loc != -1) {
                    gl.Uniform1i(loc, image_slot);
                    image_slot += 1;
                } else {
                    std.debug.print("Could not find uniform for image [{s}]!\n", .{img});
                }
            }
        }
    }

    // fetch and cache all uniforms from our metadata.uniforms fields for both the vert and frag types
    inline for (.{ VertUniformT, FragUniformT }, 0..) |UniformT, j| {
        if (UniformT == void) continue;
        var uniform_cache = if (j == 0) &shader.vs_uniform_cache else &shader.fs_uniform_cache;
        if (@hasDecl(UniformT, "metadata") and @hasField(@TypeOf(UniformT.metadata), "uniforms")) {
            const uniforms = @field(UniformT.metadata, "uniforms");
            inline for (@typeInfo(@TypeOf(uniforms)).@"struct".fields, 0..) |field, i| {
                uniform_cache[i] = gl.GetUniformLocation(id, field.name ++ "\x00");
                if (@import("builtin").mode == .Debug and uniform_cache[i] == -1) std.debug.print("Uniform [{s}] not found!\n", .{field.name});
            }
        } else {
            // cache a uniform for each struct fields. It is prefered to use the `metadata` approach above but this path is supported as well.
            inline for (@typeInfo(UniformT).@"struct".fields, 0..) |field, i| {
                uniform_cache[i] = gl.GetUniformLocation(id, field.name ++ "\x00");
                if (@import("builtin").mode == .Debug and uniform_cache[i] == -1) std.debug.print("Uniform [{s}] not found!\n", .{field.name});
            }
        }
    }

    gl.UseProgram(@as(u32, @intCast(cur_prog)));

    return shader_cache.add(shader);
}

pub fn useShaderProgram(shader: types.ShaderProgram) void {
    const shdr = shader_cache.get(shader);
    cache.useShaderProgram(shdr.program);
}

pub fn setShaderProgramUniformBlock(comptime UniformT: type, shader: types.ShaderProgram, stage: types.ShaderStage, value: *const UniformT) void {
    assert(in_pass);
    assert(@typeInfo(UniformT) == .@"struct");
    const shdr = shader_cache.get(shader);

    // in debug builds ensure the shader we are setting the uniform on is bound
    if (@import("builtin").mode == .Debug) {
        var cur_prog: i32 = 0;
        gl.GetIntegerv(gl.CURRENT_PROGRAM, @ptrCast(&cur_prog));
        assert(cur_prog == shdr.program);
    }

    // choose the right uniform cache
    const uniform_cache = if (stage == .vertex) shdr.vs_uniform_cache else shdr.fs_uniform_cache;

    if (@hasDecl(UniformT, "metadata") and @hasField(@TypeOf(UniformT.metadata), "uniforms")) {
        const uniforms = @field(UniformT.metadata, "uniforms");
        inline for (@typeInfo(@TypeOf(uniforms)).@"struct".fields, 0..) |field, i| {
            const location = uniform_cache[i];
            const uni = @field(UniformT.metadata.uniforms, field.name);

            // we only support f32s so just get a pointer to the struct reinterpreted as an []f32
            const f32_slice = std.mem.bytesAsSlice(f32, std.mem.asBytes(value));
            switch (uni.type) {
                .float1 => gl.Uniform1fv(location, uni.array_count, f32_slice.ptr),
                .float2 => gl.Uniform2fv(location, uni.array_count, f32_slice.ptr),
                .float3 => gl.Uniform3fv(location, uni.array_count, f32_slice.ptr),
                .float4 => gl.Uniform4fv(location, uni.array_count, f32_slice.ptr),
                .mat4 => gl.UniformMatrix4fv(location, uni.array_count, 0, f32_slice.ptr),
                else => comptime unreachable,
            }
        }
    } else {
        comptime unreachable;
        // set all the fields of the struct as uniforms. It is prefered to use the `metadata` approach above.
        inline for (@typeInfo(UniformT).Struct.fields, 0..) |field, i| {
            const location = uniform_cache[i];
            if (location > -1) {
                switch (@typeInfo(field.field_type)) {
                    .Float => gl.Uniform1f(location, @field(value, field.name)),
                    .Int => gl.Uniform1i(location, @field(value, field.name)),
                    .Struct => |type_info| {
                        // special case for matrix, which is often "struct { data[n] }". We also support vec2/3/4
                        switch (@typeInfo(type_info.fields[0].field_type)) {
                            .array => |array_ti| {
                                const struct_value = @field(value, field.name);
                                const array_value = &@field(struct_value, type_info.fields[0].name);
                                switch (array_ti.len) {
                                    6 => gl.UniformMatrix3x2fv(location, 1, gl.FALSE, array_value),
                                    9 => gl.UniformMatrix3fv(location, 1, gl.FALSE, array_value),
                                    else => @compileError("Structs with array fields must be 6/9 elements: " ++ @typeName(field.field_type)),
                                }
                            },
                            .float => {
                                const struct_value = @field(value, field.name);
                                const struct_field_value = &@field(struct_value, type_info.fields[0].name);
                                switch (type_info.fields.len) {
                                    2 => gl.Uniform2fv(location, 1, struct_field_value),
                                    3 => gl.Uniform3fv(location, 1, struct_field_value),
                                    4 => gl.Uniform4fv(location, 1, struct_field_value),
                                    else => @compileError("Structs of f32 must be 2/3/4 elements: " ++ @typeName(field.field_type)),
                                }
                            },
                            else => @compileError("Structs of f32 must be 2/3/4 elements: " ++ @typeName(field.field_type)),
                        }
                    },
                    .array => |array_type_info| {
                        var array_value = @field(value, field.name);
                        switch (@typeInfo(array_type_info.child)) {
                            .int => |type_info| {
                                assert(type_info.bits == 32);
                                gl.Uniform1iv(location, @intCast(array_type_info.len), &array_value);
                            },
                            .float => |type_info| {
                                assert(type_info.bits == 32);
                                gl.Uniform1fv(location, @intCast(array_type_info.len), &array_value);
                            },
                            .@"struct" => @panic("array of structs not supported"),
                            else => comptime unreachable,
                        }
                    },
                    else => @compileError("Need support for uniform type: " ++ @typeName(field.field_type)),
                }
            }
        }
    }
}

fn compileShader(stage: u32, src: [:0]const u8) u32 {
    const shader = gl.CreateShader(stage);
    var shader_src = src;
    gl.ShaderSource(shader, 1, @ptrCast(&shader_src), null);
    gl.CompileShader(shader);

    if (!checkShaderError(shader)) {
        gl.DeleteShader(shader);
        return 0;
    }
    return shader;
}

fn checkShaderError(shader: u32) bool {
    var status: i32 = gl.FALSE;
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &status);
    if (status != gl.TRUE) {
        var buf: [2048]u8 = undefined;
        var total_len: i32 = -1;
        gl.GetShaderInfoLog(shader, 2048, &total_len, buf[0..]);
        if (total_len == -1) {
            // the length of the infolog seems to not be set when a GL context isn't set (so when the window isn't created)
            unreachable;
        }

        std.debug.print("shader compilation error:\n{s}", .{buf[0..@as(usize, @intCast(total_len))]});
        return false;
    }
    return true;
}

fn checkProgramError(shader: u32) bool {
    var status: i32 = gl.FALSE;
    gl.GetProgramiv(shader, gl.LINK_STATUS, &status);
    if (status != gl.TRUE) {
        var buf: [2048]u8 = undefined;
        var total_len: i32 = -1;
        gl.GetProgramInfoLog(shader, 2048, &total_len, buf[0..]);
        if (total_len == -1) {
            // the length of the infolog seems to not be set when a GL context isn't set (so when the window isn't created)
            unreachable;
        }

        std.debug.print("program link error:\n{s}", .{buf[0..@as(usize, @intCast(total_len))]});
        return false;
    }
    return true;
}

//#endregion

//#region bindings and drawing

pub fn applyBindings(bindings: types.BufferBindings) void {
    std.debug.assert(in_pass);
    cur_bindings = bindings;

    if (bindings.index_buffer != .invalid) {
        const ibuffer = buffer_cache.get(bindings.index_buffer);
        cache.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibuffer.vbo);
        cur_ib_offset = @intCast(bindings.index_buffer_offset);
    }

    var vert_attr_index: u32 = 0;
    for (bindings.vert_buffers, 0..) |buff, i| {
        if (buff == .invalid) break;

        const vbuffer = buffer_cache.get(buff);
        if (vbuffer.setVertexAttributes) |setter| {
            cache.bindBuffer(gl.ARRAY_BUFFER, vbuffer.vbo);
            setter(&vert_attr_index, vbuffer.vert_buffer_step_func, bindings.vertex_buffer_offsets[i]);
        }
    }

    // bind images
    for (bindings.images, 0..) |image, slot| {
        const tid = if (image == .invalid) 0 else image_cache.get(image).tid;
        cache.bindImage(tid, @intCast(slot));
    }
}

pub fn draw(base_element: i32, element_count: i32, instance_count: i32) void {
    assert(in_pass);

    if (cur_bindings.index_buffer == .invalid) {
        // no index buffer, so we draw non-indexed
        if (instance_count <= 1) {
            gl.DrawArrays(gl.TRIANGLES, base_element, element_count);
        } else {
            gl.DrawArraysInstanced(gl.TRIANGLE_FAN, base_element, element_count, instance_count);
        }
    } else {
        const ibuffer = buffer_cache.get(cur_bindings.index_buffer);

        const i_size: i32 = if (ibuffer.index_buffer_type == gl.UNSIGNED_SHORT) 2 else 4;
        const ib_offset = @as(usize, @intCast(base_element * i_size + cur_ib_offset));

        if (instance_count <= 1) {
            std.debug.print("{} {x} {}\n", .{element_count, ibuffer.index_buffer_type, ib_offset});
            gl.DrawElements(gl.TRIANGLES, element_count, ibuffer.index_buffer_type, ib_offset);
        } else {
            gl.DrawElementsInstanced(gl.TRIANGLES, element_count, ibuffer.index_buffer_type, @ptrFromInt(ib_offset), instance_count);
        }
    }
}

//#endregion

const translate = struct {

    // translations from our enums to OpenGL
    pub fn blendFactorToGl(state: types.BlendFactor) u32 {
        return switch (state) {
            .zero => gl.ZERO,
            .one => gl.ONE,
            .src_color => gl.SRC_COLOR,
            .one_minus_src_color => gl.ONE_MINUS_SRC_COLOR,
            .src_alpha => gl.SRC_ALPHA,
            .one_minus_src_alpha => gl.ONE_MINUS_SRC_ALPHA,
            .dst_color => gl.DST_COLOR,
            .one_minus_dst_color => gl.ONE_MINUS_DST_COLOR,
            .dst_alpha => gl.ALPHA,
            .one_minus_dst_alpha => gl.ONE_MINUS_DST_ALPHA,
            .src_alpha_saturated => gl.SRC_ALPHA_SATURATE,
            .blend_color => gl.CONSTANT_COLOR,
            .one_minus_blend_color => gl.ONE_MINUS_CONSTANT_COLOR,
            .blend_alpha => gl.CONSTANT_ALPHA,
            .one_minus_blend_alpha => gl.ONE_MINUS_CONSTANT_ALPHA,
        };
    }

    pub fn compareFuncToGl(state: types.CompareFunc) u32 {
        return switch (state) {
            .never => gl.NEVER,
            .less => gl.LESS,
            .equal => gl.EQUAL,
            .less_equal => gl.LEQUAL,
            .greater => gl.GREATER,
            .not_equal => gl.NOTEQUAL,
            .greater_equal => gl.GEQUAL,
            .always => gl.ALWAYS,
        };
    }

    pub fn stencilOpToGl(state: types.StencilOp) u32 {
        return switch (state) {
            .keep => gl.KEEP,
            .zero => gl.ZERO,
            .replace => gl.REPLACE,
            .incr_clamp => gl.INCR,
            .decr_clamp => gl.DECR,
            .invert => gl.INVERT,
            .incr_wrap => gl.INCR_WRAP,
            .decr_wrap => gl.DECR_WRAP,
        };
    }

    pub fn blendOpToGl(state: types.BlendOp) u32 {
        return switch (state) {
            .add => gl.FUNC_ADD,
            .subtract => gl.FUNC_SUBTRACT,
            .reverse_subtract => gl.FUNC_REVERSE_SUBTRACT,
        };
    }

    pub fn pixelFormat(self: types.PixelFormat) struct { i32, u32, u32 } {
        return switch (self) {
            // .rgb8 => .{ gl.RGB, gl.RGB, gl.UNSIGNED_BYTE },
            .rgba8 => .{ gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE },
            // .rgb565 => .{ gl.RGB, gl.RGB, gl.UNSIGNED_SHORT_5_6_5 },
            // .rgba16f => .{ gl.RGBA16F, gl.RGBA, gl.FLOAT },
            // .depth => .{ gl.DEPTH_COMPONENT16, gl.DEPTH_COMPONENT, gl.UNSIGNED_SHORT },
            // .depth32 => .{ gl.DEPTH_COMPONENT, gl.DEPTH_COMPONENT, gl.FLOAT },
            .alpha => .{ gl.R8, gl.RED, gl.UNSIGNED_BYTE },
            .stencil => unreachable,
            .depth_stencil => unreachable,
        };
    }
};

fn checkErr() void {
    const err = gl.GetError();
    if (err != gl.NO_ERROR) {
        std.debug.panic("gl err: {x}", .{err});
    }
}
