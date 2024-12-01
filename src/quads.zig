const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .windows => @import("platform/windows.zig"),
    .freestanding => @import("platform/wasm.zig"),
    else => unreachable,
};

pub const meta = @import("meta.zig");
pub const math = @import("math.zig");
pub const gfx = @import("gfx/gfx.zig");
pub const image = @import("image.zig");
pub const testing = @import("testing.zig");

pub const experimental = struct {
    pub const schrift = @import("experimental/schrift.zig");
    pub const parser = @import("experimental/parser.zig");
    pub const toml = @import("experimental/toml.zig");
    pub const benchmark = @import("experimental/benchmark.zig");
    pub const ttf = @import("experimental/font/ttf.zig");
};

pub const Args = @import("Args.zig");

pub const logFn = if (@hasDecl(platform, "logFn")) platform.logFn else std.log.defaultLog;

pub var allocator: std.mem.Allocator = undefined;
pub var init_options: InitOptions = undefined;

pub const InitOptions = struct {
    opengl: bool = true,
};

pub fn init(alloc: std.mem.Allocator, options: InitOptions) !void {
    allocator = alloc;
    init_options = options;
    try platform.init(options);
}

pub fn deinit() void {
    platform.deinit();
}

/// Begins the main loop, which continues as long as `func` returns true
///
/// `func` must return `bool` or `!bool`
pub fn run(comptime func: anytype, args: anytype) !void {
    meta.compileAssert(@typeInfo(@TypeOf(func)) == .@"fn", "func must be a function", .{});
    meta.compileAssert(meta.BaseReturnType(@TypeOf(func)) == bool, "func must return `bool` or `!bool`", .{});
    return platform.run(func, args);
}

pub const glGetProcAddress = platform.glGetProcAddress;

pub fn setClipboardText(text: []const u8) void {
    _ = text; // autofix
    // TODO
}

pub fn getClipboardText(alloc: std.mem.Allocator) ?[]u8 {
    _ = alloc; // autofix
    return null; // TODO
}

pub const Size = struct {
    width: u16,
    height: u16,

    pub fn multiply(self: Size, scale: f32) Size {
        const width: f32 = @floatFromInt(self.width);
        const height: f32 = @floatFromInt(self.height);
        return .{ .width = @intFromFloat(width * scale), .height = @intFromFloat(height * scale) };
    }
};

pub const WindowOptions = struct {
    title: [:0]const u8 = "quads",
    size: Size = .{ .width = 640, .height = 480 },
    scale: f32 = 1,
    mode: WindowMode = .normal,
    cursor: Cursor = .arrow,
    cursor_mode: CursorMode = .normal,
};

pub fn createWindow(options: WindowOptions) !Window {
    return .{ .backend = try platform.createWindow(options) };
}

pub const Window = struct {
    backend: *platform,

    pub fn destroy(self: *Window) void {
        self.backend.destroy();
    }

    pub fn getEvent(self: *Window) ?Event {
        return self.backend.getEvent();
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        self.backend.setTitle(title);
    }

    pub fn setSize(self: *Window, size: Size) void {
        self.backend.setSize(size);
    }

    pub fn setMode(self: *Window, mode: WindowMode) void {
        self.backend.setMode(mode);
    }

    pub fn setCursor(self: *Window, cursor: Cursor) void {
        self.backend.setCursor(cursor);
    }

    pub fn setCursorMode(self: *Window, mode: CursorMode) void {
        self.backend.setCursorMode(mode);
    }

    pub fn requestAttention(self: *Window) void {
        self.backend.requestAttention();
    }

    pub fn createContext(self: *Window, options: ContextOptions) !void {
        std.debug.assert(init_options.opengl);
        return self.backend.createContext(options);
    }

    /// May be called on any thread.
    pub fn makeContextCurrent(self: *Window) void {
        self.backend.makeContextCurrent();
    }

    pub fn swapBuffers(self: *Window) void {
        self.backend.swapBuffers();
    }

    /// Must be called on the thread where the context is current.
    pub fn swapInterval(self: *Window, interval: i32) void {
        self.backend.swapInterval(interval);
    }
};

pub const EventType = enum {
    close,
    create,
    focused,
    unfocused,
    draw,
    size,
    framebuffer,
    scale,
    mode,
    char,
    button_press,
    button_release,
    mouse,
    mouse_relative,
    scroll_vertical,
    scroll_horizontal,
};

pub const Event = union(EventType) {
    close,
    create,
    focused,
    unfocused,
    draw,
    size: Size,
    framebuffer: Size,
    scale: f32,
    mode: WindowMode,
    char: u21,
    button_press: Button,
    button_release: Button,
    mouse: struct { x: u16, y: u16 },
    mouse_relative: struct { x: i16, y: i16 },
    scroll_vertical: f32,
    scroll_horizontal: f32,
};

pub const WindowMode = enum { normal, maximized, fullscreen };

pub const Cursor = enum { arrow, arrow_busy, busy, text, hand, crosshair, forbidden, move, size_ns, size_ew, size_nesw, size_nwse };

pub const CursorMode = enum { normal, hidden, relative };

pub const ContextOptions = struct {
    doublebuffer: bool = true,
    red_bits: u8 = 8,
    green_bits: u8 = 8,
    blue_bits: u8 = 8,
    alpha_bits: u8 = 8,
    depth_bits: u8 = 24,
    stencil_bits: u8 = 8,
    samples: u8 = 0,
};

pub const Button = enum {
    mouse_left,
    mouse_right,
    mouse_middle,
    mouse_back,
    mouse_forward,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    enter,
    escape,
    backspace,
    tab,
    space,
    minus,
    equals,
    left_bracket,
    right_bracket,
    backslash,
    semicolon,
    apostrophe,
    grave,
    comma,
    dot,
    slash,
    caps_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    print_screen,
    scroll_lock,
    pause,
    insert,
    home,
    page_up,
    delete,
    end,
    page_down,
    right,
    left,
    down,
    up,
    num_lock,
    kp_slash,
    kp_star,
    kp_minus,
    kp_plus,
    kp_enter,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_0,
    kp_dot,
    iso_backslash,
    application,
    kp_equals,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    kp_comma,
    international1,
    international2,
    international3,
    international4,
    international5,
    lang1,
    lang2,
    left_control,
    left_shift,
    left_alt,
    left_gui,
    right_control,
    right_shift,
    right_alt,
    right_gui,
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
