const std = @import("std");
const g = @import("gl");

pub var canvas_size: [2]u16 = undefined;

pub const BufferId = enum(u16) { invalid, _ };
pub const ShaderId = enum(u16) { invalid, _ };
pub const ProgramId = enum(u16) { invalid, _ };
pub const PipelineId = enum(u16) { invalid, _ };
pub const PassId = enum(u16) { invalid, _ };
pub const TextureId = enum(u16) { invalid, _ };

pub const BufferType = enum {
    vertex,
    index,

    pub fn gl(self: BufferType) u32 {
        return switch (self) {
            .vertex => g.ARRAY_BUFFER,
            .index => g.ELEMENT_ARRAY_BUFFER,
        };
    }
};

pub const BufferUsage = enum {
    immutable,
    dynamic,
    stream,

    pub fn gl(self: BufferUsage) u32 {
        return switch (self) {
            .immutable => g.STATIC_DRAW,
            .dynamic => g.DYNAMIC_DRAW,
            .stream => g.STREAM_DRAW,
        };
    }
};

pub const UniformType = enum {
    float1,
    float2,
    float3,
    float4,
    int1,
    int2,
    int3,
    int4,
    mat4,

    pub fn size(self: UniformType) u32 {
        return switch (self) {
            .float1 => 4,
            .float2 => 8,
            .float3 => 12,
            .float4 => 16,
            .int1 => 4,
            .int2 => 8,
            .int3 => 12,
            .int4 => 16,
            .mat4 => 64,
        };
    }
};

pub const VertexStep = enum { per_vertex, per_instance };

pub const CullFace = enum { nothing, front, back };

pub const FrontFaceOrder = enum { clockwise, counter_clockwise };

pub const Comparison = enum {
    never,
    less,
    equal,
    lessorequal,
    greater,
    notequal,
    greaterorequal,
    always,

    pub fn gl(self: Comparison) u32 {
        return switch (self) {
            .never => g.NEVER,
            .less => g.LESS,
            .equal => g.EQUAL,
            .lessorequal => g.LEQUAL,
            .greater => g.GREATER,
            .notequal => g.NOTEQUAL,
            .greaterorequal => g.GEQUAL,
            .always => g.ALWAYS,
        };
    }
};

pub const Equation = enum {
    add,
    subtract,
    reverse_subtract,

    pub fn gl(self: Equation) u32 {
        return switch (self) {
            .add => g.FUNC_ADD,
            .subtract => g.FUNC_SUBTRACT,
            .reverse_subtract => g.FUNC_REVERSE_SUBTRACT,
        };
    }
};

pub const BlendValue = enum { source_color, source_alpha, destination_color, destination_alpha };

pub const BlendFactor = union(enum) {
    zero,
    one,
    value: BlendValue,
    one_minus_value: BlendValue,
    source_alpha_saturate,

    pub fn gl(self: BlendFactor) u32 {
        return switch (self) {
            .zero => g.ZERO,
            .one => g.ONE,
            .value => |x| switch (x) {
                .source_color => g.SRC_COLOR,
                .source_alpha => g.SRC_ALPHA,
                .destination_color => g.DST_COLOR,
                .destination_alpha => g.DST_ALPHA,
            },
            .one_minus_value => |x| switch (x) {
                .source_color => g.ONE_MINUS_SRC_COLOR,
                .source_alpha => g.ONE_MINUS_SRC_ALPHA,
                .destination_color => g.ONE_MINUS_DST_COLOR,
                .destination_alpha => g.ONE_MINUS_DST_ALPHA,
            },
            .source_alpha_saturate => g.SRC_ALPHA_SATURATE,
        };
    }
};

pub const BlendState = struct {
    equation: Equation,
    sfactor: BlendFactor,
    dfactor: BlendFactor,
};

pub const StencilOp = enum {
    keep,
    zero,
    replace,
    incrementclamp,
    decrementclamp,
    invert,
    incrementwrap,
    decrementwrap,

    pub fn gl(self: StencilOp) u32 {
        return switch (self) {
            .keep => g.KEEP,
            .zero => g.ZERO,
            .replace => g.REPLACE,
            .incrementclamp => g.INCR,
            .decrementclamp => g.DECR,
            .invert => g.INVERT,
            .incrementwrap => g.INCR_WRAP,
            .decrementwrap => g.DECR_WRAP,
        };
    }
};

pub const CompareFunc = enum {
    always,
    never,
    less,
    equal,
    lessorequal,
    greater,
    notequal,
    greaterorequal,

    pub fn gl(self: CompareFunc) u32 {
        return switch (self) {
            .always => g.ALWAYS,
            .never => g.NEVER,
            .less => g.LESS,
            .equal => g.EQUAL,
            .lessorequal => g.LEQUAL,
            .greater => g.GREATER,
            .notequal => g.NOTEQUAL,
            .greaterorequal => g.GEQUAL,
        };
    }
};

pub const StencilFaceState = struct {
    fail_op: StencilOp,
    depth_fail_op: StencilOp,
    pass_op: StencilOp,
    test_func: CompareFunc,
    test_ref: i32,
    test_mask: u32,
    write_mask: u32,
};

pub const StencilState = struct {
    front: StencilFaceState,
    back: StencilFaceState,
};

pub const ColorMask = [4]bool;

pub const PrimitiveType = enum {
    triangles,
    lines,
    points,

    pub fn gl(self: PrimitiveType) u32 {
        return switch (self) {
            .triangles => g.TRIANGLES,
            .lines => g.LINES,
            .points => g.POINTS,
        };
    }
};

pub const PipelineParams = struct {
    cull_face: CullFace = .nothing,
    front_face_order: FrontFaceOrder = .counter_clockwise,
    depth_test: Comparison = .always,
    depth_write: bool = false,
    depth_write_offset: ?[2]f32 = null,
    color_blend: ?BlendState = null,
    alpha_blend: ?BlendState = null,
    stencil_test: ?StencilState = null,
    color_write: ColorMask = .{true} ** 4,
    primitive_type: PrimitiveType = .triangles,
};

pub const PassAction = union(enum) {
    nothing,
    clear: struct {
        color: ?[4]f32 = [4]f32{ 0, 0, 0, 0 },
        depth: ?f32 = 1,
        stencil: ?i32 = null,
    },
};

pub const TextureAccess = enum { static, render_target };

pub const TextureFormat = enum {
    rgb8,
    rgba8,
    rgba5551,
    rgb565,
    rgba16f,
    depth,
    depth32,
    alpha,

    pub fn bytes(self: TextureFormat) u32 {
        return switch (self) {
            .rgb8 => 3,
            .rgba8 => 4,
            .rgba5551 => 2,
            .rgb565 => 2,
            .rgba16f => 8,
            .depth => 2,
            .depth32 => 4,
            .alpha => 1,
        };
    }

    pub fn size(self: TextureFormat, width: u32, height: u32) u32 {
        return width * height * self.bytes();
    }

    pub fn gl(self: TextureFormat) [3]u32 {
        return switch (self) {
            .rgb8 => .{ g.RGB, g.RGB, g.UNSIGNED_BYTE },
            .rgba8 => .{ g.RGBA, g.RGBA, g.UNSIGNED_BYTE },
            .rgba5551 => .{ g.RGBA, g.RGBA, g.UNSIGNED_SHORT_1_5_5_5_REV },
            .rgb565 => .{ g.RGB, g.RGB, g.UNSIGNED_SHORT_5_6_5 },
            .rgba16f => .{ g.RGBA16F, g.RGBA, g.FLOAT },
            .depth => .{ g.DEPTH_COMPONENT16, g.DEPTH_COMPONENT, g.UNSIGNED_SHORT },
            .depth32 => .{ g.DEPTH_COMPONENT, g.DEPTH_COMPONENT, g.FLOAT },
            .alpha => .{ g.R8, g.RED, g.UNSIGNED_BYTE },
        };
    }
};

pub const TextureWrap = enum {
    repeat,
    mirror,
    clamp,

    pub fn gl(self: TextureWrap) u32 {
        return switch (self) {
            .repeat => g.REPEAT,
            .mirror => g.MIRRORED_REPEAT,
            .clamp => g.CLAMP_TO_EDGE,
        };
    }
};

pub const FilterMode = enum {
    linear,
    nearest,

    pub fn filter(self: FilterMode, mipmap: MipmapFilterMode) u32 {
        return switch (self) {
            .nearest => switch (mipmap) {
                .none => g.NEAREST,
                .nearest => g.NEAREST_MIPMAP_NEAREST,
                .linear => g.NEAREST_MIPMAP_LINEAR,
            },

            .linear => switch (mipmap) {
                .none => g.LINEAR,
                .nearest => g.LINEAR_MIPMAP_NEAREST,
                .linear => g.LINEAR_MIPMAP_LINEAR,
            },
        };
    }

    pub fn gl(self: FilterMode) u32 {
        return switch (self) {
            .linear => g.LINEAR,
            .nearest => g.NEAREST,
        };
    }
};

pub const MipmapFilterMode = enum { none, linear, nearest };
