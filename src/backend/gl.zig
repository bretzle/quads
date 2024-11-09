const std = @import("std");
const gl = @import("gl");
const math = @import("../math.zig");
const gfx = @import("../gfx.zig");
const rgfw = @import("../rgfw.zig");

const ProgramInfo = struct {
    vShader: u32 = 0,
    fShader: u32 = 0,
    program: u32 = 0,
};

const GlInfo = struct {
    program: ProgramInfo = .{},
    defaultTex: u32 = 0,
    vao: u32 = 0,
    vbo: u32 = 0,
    tbo: u32 = 0,
    cbo: u32 = 0,
};

const defaultVShaderCode =
    \\#version 330
    \\
    \\in vec3 vertexPosition;
    \\in vec2 vertexTexCoord;
    \\in vec4 vertexColor;
    \\out vec2 fragTexCoord;
    \\out vec4 fragColor;
    \\
    \\void main() {
    \\    fragTexCoord = vertexTexCoord;
    \\    fragColor = vertexColor;
    \\    gl_Position = vec4(vertexPosition, 1.0);
    \\}
;

const defaultFShaderCode =
    \\#version 330
    \\
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\out vec4 finalColor;
    \\
    \\uniform sampler2D texture0;
    \\
    \\void main() {
    \\    finalColor = texture(texture0, fragTexCoord) * fragColor;
    \\}
;

var gl_procs: gl.ProcTable = undefined;
var glInfo: GlInfo = .{};

pub fn init(width: i32, height: i32) void {
    std.debug.assert(gl_procs.init(rgfw.getProcAddress));
    gl.makeProcTableCurrent(&gl_procs);

    viewport(0, 0, width, height);

    gl.GenVertexArrays(1, @ptrCast(&glInfo.vao));
    gl.BindVertexArray(glInfo.vao);

    gl.GenBuffers(1, @ptrCast(&glInfo.vbo));
    gl.GenBuffers(1, @ptrCast(&glInfo.tbo));
    gl.GenBuffers(1, @ptrCast(&glInfo.cbo));

    glInfo.program = createProgram(defaultVShaderCode, defaultFShaderCode, "vertexPosition", "vertexTexCoord", "vertexColor");

    gl.BindVertexArray(glInfo.vao);

    // Quads - Vertex buffers binding and attributes enable
    // Vertex position buffer (shader-location = 0)
    gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.vbo);
    gl.BufferData(gl.ARRAY_BUFFER, gfx.MAX_VERTS * 3 * 4 * @sizeOf(f32), null, gl.DYNAMIC_DRAW);
    gl.EnableVertexAttribArray(0);
    gl.VertexAttribPointer(0, 3, gl.FLOAT, 0, 0, 0);

    // Vertex texcoord buffer (shader-location = 1)
    gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.tbo);
    gl.BufferData(gl.ARRAY_BUFFER, gfx.MAX_VERTS * 2 * 4 * @sizeOf(f32), null, gl.DYNAMIC_DRAW);
    gl.EnableVertexAttribArray(1);
    gl.VertexAttribPointer(1, 2, gl.FLOAT, 0, 0, 0);

    // Vertex color buffer (shader-location = 3)
    gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.cbo);
    gl.BufferData(gl.ARRAY_BUFFER, gfx.MAX_VERTS * 4 * @sizeOf(f32), null, gl.DYNAMIC_DRAW);
    gl.EnableVertexAttribArray(2);
    gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.TRUE, 0, 0);

    if (glInfo.vao != 0) gl.BindVertexArray(0);

    // load default texture
    const white = [4]u8{ 255, 255, 255, 255 };
    glInfo.defaultTex = createTexture(&white, .{ .w = 1, .h = 1 }, 4);
}

pub fn deinit() void {
    // Unbind everything
    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);

    // Unload all vertex buffers data
    gl.BindVertexArray(glInfo.vao);
    gl.DisableVertexAttribArray(0);
    gl.DisableVertexAttribArray(1);
    gl.DisableVertexAttribArray(2);
    gl.DisableVertexAttribArray(3);
    gl.BindVertexArray(0);

    // Delete VBOs from GPU (VRAM)
    gl.DeleteBuffers(1, @ptrCast(&glInfo.vbo));
    gl.DeleteBuffers(1, @ptrCast(&glInfo.tbo));
    gl.DeleteBuffers(1, @ptrCast(&glInfo.cbo));

    gl.DeleteVertexArrays(1, @ptrCast(&glInfo.vao));

    deleteProgram(glInfo.program);

    // Unload default texture
    gl.DeleteTextures(1, @ptrCast(&glInfo.defaultTex));
}

pub fn createProgram(VShaderCode: [:0]const u8, FShaderCode: [:0]const u8, posName: [:0]const u8, texName: [:0]const u8, colorName: [:0]const u8) ProgramInfo {
    const vShader = gl.CreateShader(gl.VERTEX_SHADER);
    gl.ShaderSource(vShader, 1, @ptrCast(&VShaderCode), null);
    gl.CompileShader(vShader);
    debugShader(vShader, "Vertex", "compile");

    const fShader = gl.CreateShader(gl.FRAGMENT_SHADER);
    gl.ShaderSource(fShader, 1, @ptrCast(&FShaderCode), null);
    gl.CompileShader(fShader);
    debugShader(fShader, "Fragment", "compile");

    const program = gl.CreateProgram();
    gl.AttachShader(program, vShader);
    gl.AttachShader(program, fShader);

    gl.BindAttribLocation(program, 0, posName);
    gl.BindAttribLocation(program, 1, texName);
    gl.BindAttribLocation(program, 2, colorName);

    gl.LinkProgram(program);

    return .{
        .vShader = vShader,
        .fShader = fShader,
        .program = program,
    };
}

fn debugShader(src: u32, shader: []const u8, action: []const u8) void {
    var status: i32 = 0;
    if (action[0] == 'l')
        gl.GetProgramiv(src, gl.LINK_STATUS, &status)
    else
        gl.GetShaderiv(src, gl.COMPILE_STATUS, &status);

    if (status == 0) {
        var buf: [1024]u8 = .{0} ** 1024;
        gl.GetShaderInfoLog(src, buf.len, null, &buf);
        std.debug.panic("{s} Shader failed to {s} - {s}", .{ shader, action, buf });
    }
}

pub fn deleteProgram(program: ProgramInfo) void {
    gl.UseProgram(0);

    gl.DetachShader(program.program, program.vShader);
    gl.DetachShader(program.program, program.fShader);
    gl.DeleteShader(program.vShader);
    gl.DeleteShader(program.fShader);

    gl.DeleteProgram(program.program);
}

pub fn createTexture(bitmap: []const u8, memsize: math.Area, channels: u8) u32 {
    var id: u32 = 0;

    gl.BindTexture(gl.TEXTURE_2D, 0);
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.GenTextures(1, @ptrCast(&id));
    gl.BindTexture(gl.TEXTURE_2D, id);

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    gl.PixelStorei(gl.UNPACK_ROW_LENGTH, @intCast(memsize.w));

    const c: i32 = switch (channels) {
        1 => gl.RED,
        2 => gl.RG,
        3 => gl.RGB,
        4 => gl.RGBA,
        else => unreachable,
    };

    gl.TexImage2D(gl.TEXTURE_2D, 0, c, @intCast(memsize.w), @intCast(memsize.h), 0, @intCast(c), gl.UNSIGNED_BYTE, @ptrCast(bitmap));

    gl.BindTexture(gl.TEXTURE_2D, 0);

    return id;
}

pub fn updateTexture(tex: u32, bitmap: []const u8, memsize: math.Area, channels: u8) void {
    gl.BindTexture(gl.TEXTURE_2D, tex);
    gl.PixelStorei(gl.UNPACK_ROW_LENGTH, @intCast(memsize.w));

    const c: i32 = switch (channels) {
        1 => gl.RED,
        2 => gl.RG,
        3 => gl.RGB,
        4 => gl.RGBA,
        else => unreachable,
    };

    gl.TexImage2D(gl.TEXTURE_2D, 0, c, @intCast(memsize.w), @intCast(memsize.h), 0, @intCast(c), gl.UNSIGNED_BYTE, @ptrCast(bitmap));
    gl.BindTexture(gl.TEXTURE_2D, 0);
}

pub fn clear(r: f32, g: f32, b: f32, a: f32) void {
    gl.ClearColor(r, g, b, a);
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
}

pub fn viewport(x: i32, y: i32, w: i32, h: i32) void {
    gl.Viewport(x, y, w, h);
}

pub fn draw(info: *gfx.RenderInfo) void {
    @setCold(true);

    gl.Enable(gl.BLEND);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    if (info.data.len > 0) {
        gl.BindVertexArray(glInfo.vao);

        // Vertex positions buffer
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.vbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(info.data.len * 3 * @sizeOf(f32)), @ptrCast(info.data.items(.pos)));

        // Texture coordinates buffer
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.tbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(info.data.len * 2 * @sizeOf(f32)), @ptrCast(info.data.items(.uv)));

        // Colors buffer
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.cbo);
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, @intCast(info.data.len * 4 * @sizeOf(f32)), @ptrCast(info.data.items(.color)));

        gl.BindVertexArray(0);

        // Set current shader
        if (gfx.args.program != 0)
            gl.UseProgram(gfx.args.program)
        else
            gl.UseProgram(glInfo.program.program);

        gl.BindVertexArray(glInfo.vao);

        // Bind vertex attrib: position (shader-location = 0)
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.vbo);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, 0, 0, 0);
        gl.EnableVertexAttribArray(0);

        // Bind vertex attrib: texcoord (shader-location = 1)
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.tbo);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, 0, 0, 0);
        gl.EnableVertexAttribArray(1);

        // Bind vertex attrib: color (shader-location = 3)
        gl.BindBuffer(gl.ARRAY_BUFFER, glInfo.cbo);
        gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.TRUE, 0, 0);
        gl.EnableVertexAttribArray(2);

        gl.ActiveTexture(gl.TEXTURE0);

        // u32 i;
        for (info.batches.items) |*batch| {
            var mode: u32 = @intFromEnum(batch.typ);

            if (mode > 0x0100) {
                mode -= 0x0100;
            }

            if (mode > 0x0010) {
                mode -= 0x0010;
                gl.Disable(gl.DEPTH_TEST);
                gl.DepthMask(gl.FALSE);
            } else {
                gl.Enable(gl.DEPTH_TEST);
                gl.DepthMask(gl.TRUE);
            }

            // Bind current draw call texture, activated as gl.TEXTURE0 and Bound to sampler2D texture0 by default
            if (batch.tex == 0)
                batch.tex = glInfo.defaultTex;

            gl.BindTexture(gl.TEXTURE_2D, batch.tex);
            gl.LineWidth(batch.line_width);

            if (gfx.args.program != 0)
                gl.UseProgram(gfx.args.program)
            else
                gl.UseProgram(glInfo.program.program);

            gl.DrawArrays(mode, @intCast(batch.start), @intCast(batch.len));

            if (@as(u32, @intFromEnum(batch.typ)) > 0x0010) {
                gl.Enable(gl.DEPTH_TEST);
                gl.DepthMask(gl.TRUE);
            }
        }

        if (glInfo.vao == 0) {
            gl.BindBuffer(gl.ARRAY_BUFFER, 0);
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
        }

        gl.BindTexture(gl.TEXTURE_2D, 0); // Unbind textures

        if (glInfo.vao != 0)
            gl.BindVertexArray(0); // Unbind VAO

        gl.UseProgram(0); // Unbind shader program
    }

    info.batches.items.len = 0;
    info.data.len = 0;
}
