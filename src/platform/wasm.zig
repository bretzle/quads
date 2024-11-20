const std = @import("std");
const quads = @import("../quads.zig");
const meta = @import("../meta.zig");
const log = std.log.scoped(.quads);

const Runnable = @import("../closure.zig").Runnable(bool);

const js = struct {
    extern "quads" fn write(ptr: [*]const u8, len: usize) void;
    extern "quads" fn flush() void;
    extern "quads" fn createContext() void;
    extern "quads" fn shift() u32;
    extern "quads" fn shiftFloat() f32;
};

pub fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const impl = struct {
        fn write(_: void, bytes: []const u8) !usize {
            js.write(bytes.ptr, bytes.len);
            return bytes.len;
        }
    };

    const writer = comptime std.io.GenericWriter(void, error{}, impl.write){ .context = {} };
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    writer.print(level.asText() ++ prefix ++ format ++ "\n", args) catch {};
    js.flush();
}

pub fn init(_: quads.InitOptions) !void {
    // noop
}

pub fn deinit() void {
    // noop
}

var loop: Runnable = undefined;

pub fn run(comptime func: anytype, args: anytype) !void {
    loop = Runnable.create(std.heap.wasm_allocator, func, args) catch unreachable;
}

pub fn glGetProcAddress(comptime name: [*c]const u8) ?*anyopaque {
    const zname = comptime std.mem.span(name);
    return if (@hasDecl(gl, zname)) @constCast(&@field(gl, zname)) else null;
}

//#region window

pub fn createWindow(options: quads.WindowOptions) !*@This() {
    var self = @This(){};
    self.setCursor(options.cursor);
    self.setCursorMode(options.cursor_mode);
    return &self;
}

pub fn destroy(_: *@This()) void {
    log.err("TODO: destroy", .{});
    unreachable;
}

pub fn getEvent(_: *@This()) ?quads.Event {
    const event: quads.EventType = @enumFromInt(js.shift());
    return switch (event) {
        .close => null, // never sent, EventType 0 is reused to indicate empty queue
        .create => .create,
        .focused => .focused,
        .unfocused => .unfocused,
        .size => .{ .size = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .framebuffer => .{ .framebuffer = .{ .width = @intCast(js.shift()), .height = @intCast(js.shift()) } },
        .scale => .{ .scale = js.shiftFloat() },
        .char => .{ .char = @intCast(js.shift()) },
        .button_press => .{ .button_press = @enumFromInt(js.shift()) },
        .button_release => .{ .button_release = @enumFromInt(js.shift()) },
        .mouse => .{ .mouse = .{ .x = @intCast(js.shift()), .y = @intCast(js.shift()) } },
        .scroll_vertical => .{ .scroll_vertical = js.shiftFloat() },
        .scroll_horizontal => .{ .scroll_horizontal = js.shiftFloat() },
        else => unreachable,
    };
}

pub fn setTitle(_: *@This(), title: [:0]const u8) void {
    log.err("TODO: setTitle", .{});
    _ = title; // autofix
    unreachable;
}

pub fn setSize(_: *@This(), client_size: quads.Size) void {
    log.err("TODO: setSize", .{});
    _ = client_size; // autofix
    unreachable;
}

pub fn setMode(_: *@This(), mode: quads.WindowMode) void {
    log.err("TODO: setMode", .{});
    _ = mode; // autofix
    unreachable;
}

pub fn setCursor(_: *@This(), shape: quads.Cursor) void {
    log.err("TODO: setCursor", .{});
    _ = shape; // autofix
}

pub fn setCursorMode(_: *@This(), mode: quads.CursorMode) void {
    log.err("TODO: setCursorMode", .{});
    _ = mode; // autofix
}

pub fn requestAttention(_: *@This()) void {
    log.err("TODO: requestAttention", .{});
    unreachable;
}

pub fn createContext(_: *@This(), _: quads.ContextOptions) !void {
    js.createContext();
}

pub fn makeContextCurrent(_: *@This()) void {}

pub fn swapBuffers(_: *@This()) void {}

pub fn swapInterval(_: *@This(), _: i32) void {}

//#endregion

const gl = struct {
    extern "quads" fn glActiveTexture(u32) void;
    extern "quads" fn glAttachShader(u32, u32) void;
    extern "quads" fn glBindAttribLocation(u32, u32, [*c]const u8) void;
    extern "quads" fn glBindBuffer(u32, u32) void;
    extern "quads" fn glBindVertexArray(u32) void;
    extern "quads" fn glBindFramebuffer(u32, u32) void;
    extern "quads" fn glBindRenderbuffer(u32, u32) void;
    extern "quads" fn glBindTexture(u32, u32) void;
    extern "quads" fn glBlendColor(f32, f32, f32, f32) void;
    extern "quads" fn glBlendEquation(u32) void;
    extern "quads" fn glBlendEquationSeparate(u32, u32) void;
    extern "quads" fn glBlendFunc(u32, u32) void;
    extern "quads" fn glBlendFuncSeparate(u32, u32, u32, u32) void;
    extern "quads" fn glBufferData(u32, isize, ?*const anyopaque, u32) void;
    extern "quads" fn glBufferSubData(u32, isize, isize, ?*const anyopaque) void;
    extern "quads" fn glCheckFramebufferStatus(u32) u32;
    extern "quads" fn glClear(u32) void;
    extern "quads" fn glClearColor(f32, f32, f32, f32) void;
    extern "quads" fn glClearDepthf(f32) void;
    extern "quads" fn glClearStencil(i32) void;
    extern "quads" fn glColorMask(u8, u8, u8, u8) void;
    extern "quads" fn glCompileShader(u32) void;
    extern "quads" fn glCompressedTexImage2D(u32, i32, u32, i32, i32, i32, i32, ?*const anyopaque) void;
    extern "quads" fn glCompressedTexSubImage2D(u32, i32, i32, i32, i32, i32, u32, i32, ?*const anyopaque) void;
    extern "quads" fn glCopyTexImage2D(u32, i32, u32, i32, i32, i32, i32, i32) void;
    extern "quads" fn glCopyTexSubImage2D(u32, i32, i32, i32, i32, i32, i32, i32) void;
    extern "quads" fn glCreateProgram() u32;
    extern "quads" fn glCreateShader(u32) u32;
    extern "quads" fn glCullFace(u32) void;
    extern "quads" fn glDeleteBuffers(i32, [*c]const u32) void;
    extern "quads" fn glDeleteFramebuffers(i32, [*c]const u32) void;
    extern "quads" fn glDeleteProgram(u32) void;
    extern "quads" fn glDeleteRenderbuffers(i32, [*c]const u32) void;
    extern "quads" fn glDeleteShader(u32) void;
    extern "quads" fn glDeleteTextures(i32, [*c]const u32) void;
    extern "quads" fn glDepthFunc(u32) void;
    extern "quads" fn glDepthMask(u8) void;
    extern "quads" fn glDepthRangef(f32, f32) void;
    extern "quads" fn glDetachShader(u32, u32) void;
    extern "quads" fn glDisable(u32) void;
    extern "quads" fn glDisableVertexAttribArray(u32) void;
    extern "quads" fn glDrawArrays(u32, i32, i32) void;
    extern "quads" fn glDrawElements(u32, i32, u32, ?*const anyopaque) void;
    extern "quads" fn glDrawElementsInstanced(mode: u32, count: i32, typ: u32, indices: ?*const anyopaque, instance_count: i32) void;
    extern "quads" fn glEnable(u32) void;
    extern "quads" fn glEnableVertexAttribArray(u32) void;
    extern "quads" fn glVertexAttribDivisor(u32, u32) void;
    extern "quads" fn glFinish() void;
    extern "quads" fn glFlush() void;
    extern "quads" fn glFramebufferRenderbuffer(u32, u32, u32, u32) void;
    extern "quads" fn glFramebufferTexture2D(u32, u32, u32, u32, i32) void;
    extern "quads" fn glFrontFace(u32) void;
    extern "quads" fn glGenBuffers(i32, [*c]u32) void;
    extern "quads" fn glGenVertexArrays(i32, [*c]u32) void;
    extern "quads" fn glGenerateMipmap(u32) void;
    extern "quads" fn glGenFramebuffers(i32, [*c]u32) void;
    extern "quads" fn glGenRenderbuffers(i32, [*c]u32) void;
    extern "quads" fn glGenTextures(i32, [*c]u32) void;
    extern "quads" fn glGetActiveAttrib(u32, u32, i32, [*c]i32, [*c]i32, [*c]u32, [*c]u8) void;
    extern "quads" fn glGetActiveUniform(u32, u32, i32, [*c]i32, [*c]i32, [*c]u32, [*c]u8) void;
    extern "quads" fn glGetAttachedShaders(u32, i32, [*c]i32, [*c]u32) void;
    extern "quads" fn glGetAttribLocation(u32, [*c]const u8) i32;
    extern "quads" fn glGetBooleanv(u32, [*c]u8) void;
    extern "quads" fn glGetBufferParameteriv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetError() u32;
    extern "quads" fn glGetFloatv(u32, [*c]f32) void;
    extern "quads" fn glGetFramebufferAttachmentParameteriv(u32, u32, u32, [*c]i32) void;
    extern "quads" fn glGetIntegerv(u32, [*c]i32) void;
    extern "quads" fn glGetProgramiv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetProgramInfoLog(u32, i32, [*c]i32, [*c]u8) void;
    extern "quads" fn glGetRenderbufferParameteriv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetShaderiv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetShaderInfoLog(u32, i32, [*c]i32, [*c]u8) void;
    extern "quads" fn glGetShaderPrecisionFormat(u32, u32, [*c]i32, [*c]i32) void;
    extern "quads" fn glGetShaderSource(u32, i32, [*c]i32, [*c]u8) void;
    extern "quads" fn glGetString(u32) u8;
    extern "quads" fn glGetTexParameterfv(u32, u32, [*c]f32) void;
    extern "quads" fn glGetTexParameteriv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetUniformfv(u32, i32, [*c]f32) void;
    extern "quads" fn glGetUniformiv(u32, i32, [*c]i32) void;
    extern "quads" fn glGetUniformLocation(u32, [*c]const u8) i32;
    extern "quads" fn glGetVertexAttribfv(u32, u32, [*c]f32) void;
    extern "quads" fn glGetVertexAttribiv(u32, u32, [*c]i32) void;
    extern "quads" fn glGetVertexAttribPointerv(u32, u32, ?*?*anyopaque) void;
    extern "quads" fn glHint(u32, u32) void;
    extern "quads" fn glIsBuffer(u32) u8;
    extern "quads" fn glIsEnabled(u32) u8;
    extern "quads" fn glIsFramebuffer(u32) u8;
    extern "quads" fn glIsProgram(u32) u8;
    extern "quads" fn glIsRenderbuffer(u32) u8;
    extern "quads" fn glIsShader(u32) u8;
    extern "quads" fn glIsTexture(u32) u8;
    extern "quads" fn glLineWidth(f32) void;
    extern "quads" fn glLinkProgram(u32) void;
    extern "quads" fn glPixelStorei(u32, i32) void;
    extern "quads" fn glPolygonOffset(f32, f32) void;
    extern "quads" fn glReadPixels(i32, i32, i32, i32, u32, u32, ?*anyopaque) void;
    extern "quads" fn glRenderbufferStorage(u32, u32, i32, i32) void;
    extern "quads" fn glSampleCoverage(f32, u8) void;
    extern "quads" fn glScissor(i32, i32, i32, i32) void;
    extern "quads" fn glShaderSource(u32, i32, [*c]const [*c]const u8, [*c]const i32) void;
    extern "quads" fn glStencilFunc(u32, i32, u32) void;
    extern "quads" fn glStencilFuncSeparate(u32, u32, i32, u32) void;
    extern "quads" fn glStencilMask(u32) void;
    extern "quads" fn glStencilMaskSeparate(u32, u32) void;
    extern "quads" fn glStencilOp(u32, u32, u32) void;
    extern "quads" fn glStencilOpSeparate(u32, u32, u32, u32) void;
    extern "quads" fn glTexImage2D(u32, i32, i32, i32, i32, i32, u32, u32, ?*const anyopaque) void;
    extern "quads" fn glTexParameterf(u32, u32, f32) void;
    extern "quads" fn glTexParameteri(u32, u32, i32) void;
    extern "quads" fn glTexSubImage2D(u32, i32, i32, i32, i32, i32, u32, u32, ?*const anyopaque) void;
    extern "quads" fn glUniform1f(i32, f32) void;
    extern "quads" fn glUniform1fv(i32, i32, [*c]const f32) void;
    extern "quads" fn glUniform1i(i32, i32) void;
    extern "quads" fn glUniform1iv(i32, i32, [*c]const i32) void;
    extern "quads" fn glUniform2f(i32, f32, f32) void;
    extern "quads" fn glUniform2fv(i32, i32, [*c]const f32) void;
    extern "quads" fn glUniform2i(i32, i32, i32) void;
    extern "quads" fn glUniform2iv(i32, i32, [*c]const i32) void;
    extern "quads" fn glUniform3f(i32, f32, f32, f32) void;
    extern "quads" fn glUniform3fv(i32, i32, [*c]const f32) void;
    extern "quads" fn glUniform3i(i32, i32, i32, i32) void;
    extern "quads" fn glUniform3iv(i32, i32, [*c]const i32) void;
    extern "quads" fn glUniform4f(i32, f32, f32, f32, f32) void;
    extern "quads" fn glUniform4fv(i32, i32, [*c]const f32) void;
    extern "quads" fn glUniform4i(i32, i32, i32, i32, i32) void;
    extern "quads" fn glUniform4iv(i32, i32, [*c]const i32) void;
    extern "quads" fn glUniformMatrix2fv(i32, i32, u8, [*c]const f32) void;
    extern "quads" fn glUniformMatrix3fv(i32, i32, u8, [*c]const f32) void;
    extern "quads" fn glUniformMatrix4fv(i32, i32, u8, [*c]const f32) void;
    extern "quads" fn glUseProgram(u32) void;
    extern "quads" fn glValidateProgram(u32) void;
    extern "quads" fn glVertexAttrib1f(u32, f32) void;
    extern "quads" fn glVertexAttrib1fv(u32, [*c]const f32) void;
    extern "quads" fn glVertexAttrib2f(u32, f32, f32) void;
    extern "quads" fn glVertexAttrib2fv(u32, [*c]const f32) void;
    extern "quads" fn glVertexAttrib3f(u32, f32, f32, f32) void;
    extern "quads" fn glVertexAttrib3fv(u32, [*c]const f32) void;
    extern "quads" fn glVertexAttrib4f(u32, f32, f32, f32, f32) void;
    extern "quads" fn glVertexAttrib4fv(u32, [*c]const f32) void;
    extern "quads" fn glVertexAttribPointer(u32, i32, u32, u8, i32, ?*const anyopaque) void;
    extern "quads" fn glViewport(i32, i32, i32, i32) void;

    fn glClearDepth(val: f64) void {
        glClearDepthf(@floatCast(val));
    }
};

export fn quadsLoop() bool {
    return loop.runFn(loop.ptr);
}
