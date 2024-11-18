const std = @import("std");
const gl = @import("gl");

const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn changed(self: *Rect, x: i32, y: i32, w: i32, h: i32) bool {
        if (self.w != w or self.h != h or self.x != x or self.y != y) {
            self.x = x;
            self.y = y;
            self.w = w;
            self.h = h;
            return true;
        }

        return false;
    }
};

const RenderCache = @This();

vao: u32 = 0,
vbo: u32 = 0,
ebo: u32 = 0,
shader: u32 = 0,
viewport_rect: Rect = .{},
scissor_rect: Rect = .{},
textures: [8]c_uint = [_]c_uint{0} ** 8,

pub fn create() RenderCache {
    return .{};
}

pub fn bindVertexArray(self: *RenderCache, vao: u32) void {
    if (self.vao != vao) {
        self.vao = vao;
        gl.BindVertexArray(vao);
    }
}

pub fn invalidateVertexArray(self: *RenderCache, vao: u32) void {
    if (self.vao == vao) {
        self.vao = 0;
        gl.BindVertexArray(0);
    }
}

pub fn bindBuffer(self: *RenderCache, target: u32, buffer: u32) void {
    std.debug.assert(target == gl.ELEMENT_ARRAY_BUFFER or target == gl.ARRAY_BUFFER);

    if (target == gl.ELEMENT_ARRAY_BUFFER) {
        if (self.ebo != buffer) {
            self.ebo = buffer;
            gl.BindBuffer(target, buffer);
        }
    } else {
        if (self.vbo != buffer) {
            self.vbo = buffer;
            gl.BindBuffer(target, buffer);
        }
    }
}

/// forces a bind whether bound or not. Needed for creating Vertex Array Objects
pub fn forceBindBuffer(self: *RenderCache, target: u32, buffer: u32) void {
    std.debug.assert(target == gl.ELEMENT_ARRAY_BUFFER or target == gl.ARRAY_BUFFER);

    if (target == gl.ELEMENT_ARRAY_BUFFER) {
        self.ebo = buffer;
        gl.BindBuffer(target, buffer);
    } else {
        self.vbo = buffer;
        gl.BindBuffer(target, buffer);
    }
}

pub fn invalidateBuffer(self: *RenderCache, buffer: u32) void {
    if (self.ebo == buffer) {
        self.ebo = 0;
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
    }
    if (self.vbo == buffer) {
        self.vbo = 0;
        gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    }
}

pub fn bindImage(self: *RenderCache, tid: c_uint, slot: c_uint) void {
    if (self.textures[slot] != tid) {
        self.textures[slot] = tid;
        gl.ActiveTexture(gl.TEXTURE0 + slot);
        gl.BindTexture(gl.TEXTURE_2D, tid);
    }
}

pub fn invalidateTexture(self: *RenderCache, tid: c_uint) void {
    for (self.textures, 0..) |_, i| {
        if (self.textures[i] == tid) {
            self.textures[i] = 0;
            gl.ActiveTexture(gl.TEXTURE0 + @as(c_uint, @intCast(i)));
            gl.BindTexture(gl.TEXTURE_2D, tid);
        }
    }
}

pub fn useShaderProgram(self: *RenderCache, program: u32) void {
    if (self.shader != program) {
        self.shader = program;
        gl.UseProgram(program);
    }
}

pub fn invalidateProgram(self: *RenderCache, program: u32) void {
    if (self.shader == program) {
        self.shader = 0;
        gl.UseProgram(0);
    }
}

pub fn viewport(self: *RenderCache, x: i32, y: i32, width: i32, height: i32) void {
    if (self.viewport_rect.changed(x, y, width, height)) {
        gl.Viewport(x, y, width, height);
    }
}

pub fn scissor(self: *RenderCache, x: i32, y: i32, width: i32, height: i32, cur_pass_h: i32) void {
    if (self.scissor_rect.changed(x, y, width, height)) {
        const y_tl = cur_pass_h - (y + height);
        gl.Scissor(x, y_tl, width, height);
    }
}
