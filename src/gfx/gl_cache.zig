const std = @import("std");
const gl = @import("gl");
const gfx = @import("types.zig");

const CachedTexture = struct {
    target: u32 = 0,
    texture: u32 = 0,
};

const Self = @This();

stored_index_buffer: u32 = 0,
stored_index_type: ?u32 = null,
stored_vertex_buffer: u32 = 0,
stored_target: u32 = 0,
stored_texture: u32 = 0,
index_buffer: u32 = 0,
index_type: ?u32 = null,
vertex_buffer: u32 = 0,

cur_pipeline: ?gfx.PipelineId = null,
cur_pass: ?gfx.PassId = null,
color_blend: ?gfx.BlendState = null,
alpha_blend: ?gfx.BlendState = null,
stencil: ?gfx.StencilState = null,
color_write: gfx.ColorMask = .{ true, true, true, true },
cull_face: gfx.CullFace = .nothing,

textures: [12]CachedTexture = [_]CachedTexture{.{}} ** 12,

pub fn bindBuffer(self: *Self, gl_target: u32, buffer: u32, index_type: ?u32) void {
    if (gl_target == gl.ARRAY_BUFFER) {
        if (self.vertex_buffer != buffer) {
            self.vertex_buffer = buffer;
            gl.BindBuffer(gl_target, buffer);
        }
    } else {
        if (self.index_buffer != buffer) {
            self.index_buffer = buffer;
            gl.BindBuffer(gl_target, buffer);
        }
        self.index_type = index_type;
    }
}

pub fn storeBufferBinding(self: *Self, gl_target: u32) void {
    if (gl_target == gl.ARRAY_BUFFER) {
        self.stored_vertex_buffer = self.vertex_buffer;
    } else {
        self.stored_index_buffer = self.index_buffer;
        self.stored_index_type = self.index_type;
    }
}

pub fn restoreBufferBinding(self: *Self, gl_target: u32) void {
    if (gl_target == gl.ARRAY_BUFFER) {
        if (self.stored_vertex_buffer != 0) {
            self.bindBuffer(gl_target, self.stored_vertex_buffer, null);
            self.stored_vertex_buffer = 0;
        }
    } else {
        if (self.stored_index_buffer != 0) {
            self.bindBuffer(gl_target, self.stored_index_buffer, self.stored_index_type);
            self.stored_index_buffer = 0;
        }
    }
}

pub fn clearBufferBindings(self: *Self) void {
    self.bindBuffer(gl.ARRAY_BUFFER, 0, null);
    self.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0, null);

    self.vertex_buffer = 0;
    self.index_buffer = 0;
}

pub fn bindTexture(self: *Self, slot: u32, target: u32, texture: u32) void {
    gl.ActiveTexture(gl.TEXTURE0 + slot);
    if (self.textures[slot].target != target or self.textures[slot].texture != texture) {
        const targ = if (target == 0) gl.TEXTURE_2D else target;
        gl.BindTexture(targ, texture);
        self.textures[slot] = .{ .target = targ, .texture = texture };
    }
}

pub fn storeTextureBinding(self: *Self, slot: u32) void {
    self.stored_target = self.textures[slot].target;
    self.stored_texture = self.textures[slot].texture;
}

pub fn restoreTextureBinding(self: *Self, slot: u32) void {
    self.bindTexture(slot, self.stored_target, self.stored_texture);
}

pub fn clearTextureBindings(self: *Self) void {
    for (0..12) |i| {
        if (self.textures[i].texture != 0) {
            self.bindTexture(@truncate(i), self.textures[i].target, 0);
            self.textures[i] = .{};
        }
    }
}

pub fn setCullFace(self: *Self, cull_face: gfx.CullFace) void {
    if (self.cull_face == cull_face) return;
    self.cull_face = cull_face;

    switch (cull_face) {
        .nothing => gl.Disable(gl.CULL_FACE),
        .front => {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.FRONT);
        },
        .back => {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
        },
    }
}

pub fn setBlend(self: *Self, color_blend: ?gfx.BlendState, alpha_blend: ?gfx.BlendState) void {
    std.debug.assert(!(color_blend == null and alpha_blend != null));
    if (std.meta.eql(self.color_blend, color_blend) and std.meta.eql(self.alpha_blend, alpha_blend)) return;

    if (color_blend) |color| {
        if (self.color_blend == null) {
            gl.Enable(gl.BLEND);
        }

        if (alpha_blend) |alpha| {
            gl.BlendFuncSeparate(color.sfactor.gl(), color.dfactor.gl(), alpha.sfactor.gl(), alpha.dfactor.gl());
            gl.BlendEquationSeparate(color.equation.gl(), alpha.equation.gl());
        } else {
            gl.BlendFunc(color.sfactor.gl(), color.dfactor.gl());
            gl.BlendEquationSeparate(color.equation.gl(), color.equation.gl());
        }
    } else if (self.color_blend != null) {
        gl.Disable(gl.BLEND);
    }

    self.color_blend = color_blend;
    self.alpha_blend = alpha_blend;
}

pub fn setStencil(self: *Self, stencil_test: ?gfx.StencilState) void {
    if (std.meta.eql(self.stencil, stencil_test)) return;

    if (stencil_test) |stencil| {
        if (self.stencil == null) {
            gl.Enable(gl.STENCIL_TEST);
        }

        const front = &stencil.front;
        gl.StencilOpSeparate(gl.FRONT, front.fail_op.gl(), front.depth_fail_op.gl(), front.pass_op.gl());
        gl.StencilFuncSeparate(gl.FRONT, front.test_func.gl(), front.test_ref, front.test_mask);
        gl.StencilMaskSeparate(gl.FRONT, front.write_mask);

        const back = &stencil.back;
        gl.StencilOpSeparate(gl.BACK, back.fail_op.gl(), back.depth_fail_op.gl(), back.pass_op.gl());
        gl.StencilFuncSeparate(gl.BACK, back.test_func.gl(), back.test_ref, back.test_mask);
        gl.StencilMaskSeparate(gl.BACK, back.write_mask);
    } else if (self.stencil != null) {
        gl.Disable(gl.STENCIL_TEST);
    }

    self.stencil = stencil_test;
}

pub fn setColorWrite(self: *Self, color_write: gfx.ColorMask) void {
    if (std.mem.eql(bool, &self.color_write, &color_write)) return;

    const r, const g, const b, const a = color_write;
    gl.ColorMask(@intFromBool(r), @intFromBool(g), @intFromBool(b), @intFromBool(a));
    self.color_write = color_write;
}
