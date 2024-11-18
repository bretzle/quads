const std = @import("std");

pub const Image = enum(u16) { invalid, _ };
pub const ShaderProgram = enum(u16) { invalid, _ };
pub const Pass = enum(u16) { invalid, _ };
pub const Buffer = enum(u16) { invalid, _ };

pub const UniformType = enum { float1, float2, float3, float4 };

pub const TextureFilter = enum { nearest, linear };

pub const TextureWrap = enum { clamp, repeat };

// TODO add more
pub const PixelFormat = enum { rgba8, stencil, depth_stencil, alpha };

pub const Usage = enum { immutable, dynamic, stream };

pub const BufferType = enum { vertex, index };

pub const ShaderStage = enum { fragment, vertex };

pub const PrimitiveType = enum { points, line_strip, lines, triangle_strip, triangles };

pub const ElementType = enum { u8, u16, u32 };

pub const CompareFunc = enum {
    never,
    less,
    equal,
    less_equal,
    greater,
    not_equal,
    greater_equal,
    always,
};

pub const StencilOp = enum {
    keep,
    zero,
    replace,
    incr_clamp,
    decr_clamp,
    invert,
    incr_wrap,
    decr_wrap,
};

pub const BlendFactor = enum {
    zero,
    one,
    src_color,
    one_minus_src_color,
    src_alpha,
    one_minus_src_alpha,
    dst_color,
    one_minus_dst_color,
    dst_alpha,
    one_minus_dst_alpha,
    src_alpha_saturated,
    blend_color,
    one_minus_blend_color,
    blend_alpha,
    one_minus_blend_alpha,
};

pub const CullMode = enum { none, front, back };

pub const FaceWinding = enum { ccw, cw };

pub const BlendOp = enum { add, subtract, reverse_subtract };

pub const ColorMask = enum(u32) {
    none,
    r = (1 << 0),
    g = (1 << 1),
    b = (1 << 2),
    a = (1 << 3),
    rgb = 0x7,
    rgba = 0xF,
};

pub const RenderState = struct {
    const Depth = struct {
        enabled: bool = false,
        compare_func: CompareFunc = .always,
    };

    const Stencil = struct {
        enabled: bool = true,
        write_mask: u8 = 0xFF, // glStencilMask
        fail_op: StencilOp = .keep, // glStencilOp
        depth_fail_op: StencilOp = .keep, // glStencilOp
        pass_op: StencilOp = .replace, // glStencilOp
        compare_func: CompareFunc = .always, // glStencilFunc
        ref: u8 = 0, // glStencilFunc
        read_mask: u8 = 0xFF, // glStencilFunc
    };

    const Blend = struct {
        enabled: bool = true,
        src_factor_rgb: BlendFactor = .src_alpha,
        dst_factor_rgb: BlendFactor = .one_minus_src_alpha,
        op_rgb: BlendOp = .add,
        src_factor_alpha: BlendFactor = .one,
        dst_factor_alpha: BlendFactor = .one_minus_src_alpha,
        op_alpha: BlendOp = .add,
        color_write_mask: ColorMask = .rgba,
        color: [4]f32 = [_]f32{ 0, 0, 0, 0 },
    };

    depth: Depth = .{},
    stencil: Stencil = .{},
    blend: Blend = .{},
    scissor: bool = false,
    cull_mode: CullMode = .none,
    face_winding: FaceWinding = .ccw,
};

pub const ClearCommand = struct {
    pub const ColorAttachmentAction = struct {
        clear: bool = true,
        color: [4]f32 = [_]f32{ 0, 0, 0, 1 },
    };

    colors: [4]ColorAttachmentAction = [_]ColorAttachmentAction{.{}} ** 4,
    clear_stencil: bool = false,
    stencil: u8 = 0,
    clear_depth: bool = false,
    depth: f64 = 1,

    pub const nothing = ClearCommand{
        .colors = [_]ColorAttachmentAction{.{ .clear = false }} ** 4,
    };
};

pub const BufferBindings = struct {
    index_buffer: Buffer,
    vert_buffers: [4]Buffer,
    index_buffer_offset: u32 = 0,
    vertex_buffer_offsets: [4]u32 = [_]u32{0} ** 4,
    images: [8]Image = [_]Image{.invalid} ** 8,

    pub fn create(index_buffer: Buffer, vert_buffers: []const Buffer) BufferBindings {
        var vbuffers: [4]Buffer = [_]Buffer{.invalid} ** 4;
        for (vert_buffers, 0..) |vb, i| vbuffers[i] = vb;

        return .{
            .index_buffer = index_buffer,
            .vert_buffers = vbuffers,
        };
    }

    pub fn bindImage(self: *BufferBindings, slot: u32, image: Image) void {
        self.images[slot] = image;
    }

    pub fn eq(self: BufferBindings, other: BufferBindings) bool {
        return self.index_buffer == other.index_buffer and
            std.mem.eql(Buffer, &self.vert_buffers, &other.vert_buffers) and
            std.mem.eql(u32, &self.vertex_buffer_offsets, &other.vertex_buffer_offsets) and
            std.mem.eql(Image, &self.images, &other.images);
    }
};
