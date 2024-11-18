const std = @import("std");
const types = @import("types.zig");

pub const RendererDesc = struct {
    const PoolSizes = struct {
        texture: u8 = 64,
        offscreen_pass: u8 = 8,
        buffers: u8 = 16,
        shaders: u8 = 16,
    };

    loader: ?*const fn (name: [*c]const u8) ?*anyopaque = null,
    pool_sizes: PoolSizes = .{},
};

pub const ImageDesc = struct {
    render_target: bool = false,
    width: i32,
    height: i32,
    usage: types.Usage = .immutable,
    pixel_format: types.PixelFormat = .rgba8,
    min_filter: types.TextureFilter = .nearest,
    mag_filter: types.TextureFilter = .nearest,
    wrap_u: types.TextureWrap = .clamp,
    wrap_v: types.TextureWrap = .clamp,
    content: ?*const anyopaque = null,
};

pub const PassDesc = struct {
    color_img: types.Image,
    color_img2: ?types.Image = null,
    color_img3: ?types.Image = null,
    color_img4: ?types.Image = null,
    depth_stencil_img: ?types.Image = null,
};

/// whether the pointer is advanced "per vertex" or "per instance". The latter is used for instanced rendering.
pub const VertexStep = enum {
    per_vertex,
    per_instance,
};

pub fn BufferDesc(comptime T: type) type {
    return struct {
        size: u32 = 0, // either size (for stream buffers) or content (for static/dynamic) must be set
        type: types.BufferType = .vertex,
        usage: types.Usage = .immutable,
        content: ?[]const T = null,
        step_func: VertexStep = .per_vertex, // step function used for instanced drawing

        pub fn getSize(self: @This()) u32 {
            std.debug.assert(self.usage != .immutable or self.content != null);
            std.debug.assert(self.size > 0 or self.content != null);

            if (self.content) |data| return @intCast(data.len * @sizeOf(T));
            return self.size;
        }
    };
}

pub const ShaderDesc = struct {
    vertex: [:0]const u8,
    fragment: [:0]const u8,
};
