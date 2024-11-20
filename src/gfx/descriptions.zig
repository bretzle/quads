const std = @import("std");
const builtin = @import("builtin");
pub const types = @import("types.zig");

const LoaderFn = @TypeOf(@import("../quads.zig").glGetProcAddress);

pub const Config = struct {
    loader: LoaderFn,

    shaders: u8 = 16,
    pipelines: u8 = 8,
    passes: u8 = 8,
    buffers: u8 = 16,
    textures: u8 = 16,
};

pub const Bindings = struct {
    index_buffer: types.BufferId,
    vertex_buffers: [4]types.BufferId,
    vertex_buffer_offsets: [4]u32 = [_]u32{0} ** 4,
    images: [8]types.TextureId = [_]types.TextureId{.invalid} ** 8,

    pub fn create(index_buffer: types.BufferId, vert_buffers: []const types.BufferId) Bindings {
        var vbuffers: [4]types.BufferId = [_]types.BufferId{.invalid} ** 4;
        for (vert_buffers, 0..) |vb, i| vbuffers[i] = vb;

        return .{
            .index_buffer = index_buffer,
            .vertex_buffers = vbuffers,
        };
    }
};

pub fn BufferDesc(comptime T: type) type {
    return struct {
        typ: types.BufferType,
        usage: types.BufferUsage,
        step_func: types.VertexStep = .per_vertex,
        size: u32 = 0,
        content: ?[]const T = null,

        pub fn getSize(self: @This()) u32 {
            std.debug.assert(self.usage != .immutable or self.content != null);
            std.debug.assert(self.size > 0 or self.content != null);

            if (self.content) |data| return @intCast(data.len * @sizeOf(T));
            return self.size;
        }
    };
}

pub const UniformDesc = struct {
    name: [:0]const u8,
    typ: types.UniformType,
    array_count: usize = 1,
};

pub const ShaderDesc = struct {
    images: []const []const u8 = &.{},
    uniforms: []const UniformDesc = &.{},
};

pub const TextureDesc = struct {
    access: types.TextureAccess = .static,
    width: u32,
    height: u32,
    format: types.TextureFormat = .rgba8,
    min_filter: types.FilterMode = .nearest,
    mag_filter: types.FilterMode = .nearest,
    mipmap_filter: types.MipmapFilterMode = .none,
    wrap_u: types.TextureWrap = .clamp,
    wrap_v: types.TextureWrap = .clamp,
    allocate_mipmaps: bool = false,
    sample_count: i32 = 0,
    content: ?*const anyopaque = null,
};
