const std = @import("std");
const winit = @import("../winit.zig");
const os = @import("../os/winapi.zig");
const meta = @import("quads").meta;

const log = std.log.scoped(.quads);

const class_name = @typeName(@This());
var helper_window: os.HWND = undefined;
var wglinstance: ?os.HMODULE = null;

var wgl: struct {
    swapIntervalEXT: ?*const fn (i32) callconv(os.WINAPI) os.BOOL = null,
} = .{};

pub fn init(options: winit.InitOptions) !void {
    const instance = os.GetModuleHandleA(null);
    const class = os.WNDCLASSEXA{
        .lpfnWndProc = windowProc,
        .hInstance = instance,
        .lpszClassName = class_name,
    };

    if (os.RegisterClassExA(&class) == 0) return error.backend_failure;

    helper_window = os.CreateWindowExA(
        0,
        class_name,
        "helper",
        0,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        null,
        null,
        instance,
        null,
    ) orelse return error.backend_failure;
    errdefer _ = os.DestroyWindow(helper_window);

    _ = os.SetWindowLongPtrA(helper_window, os.GWLP_WNDPROC, @intCast(@intFromPtr(&helperWindowProc)));

    // TODO register raw input
    // TODO register joystick
    // TODO init audio

    if (options.opengl) {
        wglinstance = os.LoadLibraryA("opengl32.dll");

        const dc = os.GetDC(helper_window);
        defer _ = os.ReleaseDC(helper_window, dc);

        var pfd = os.PIXELFORMATDESCRIPTOR{
            .nVersion = 1,
            .dwFlags = os.PFD_DRAW_TO_WINDOW | os.PFD_SUPPORT_OPENGL | os.PFD_DOUBLEBUFFER,
            .iPixelType = os.PFD_TYPE_RGBA,
            .cColorBits = 24,
        };
        _ = os.SetPixelFormat(dc, os.ChoosePixelFormat(dc, &pfd), &pfd);

        const temp_rc = os.wglCreateContext(dc);
        defer _ = os.wglDeleteContext(temp_rc);
        _ = os.wglMakeCurrent(dc, temp_rc);

        if (os.wglGetProcAddress("wglGetExtensionsStringARB")) |proc| {
            const getExtensionsStringARB: *const fn (?os.HDC) callconv(os.WINAPI) ?[*:0]const u8 = @ptrCast(proc);
            if (getExtensionsStringARB(dc)) |extensions| {
                var iter = std.mem.tokenizeScalar(u8, std.mem.sliceTo(extensions, 0), ' ');
                while (iter.next()) |name| {
                    if (std.mem.eql(u8, name, "WGL_EXT_swap_control")) {
                        wgl.swapIntervalEXT = @ptrCast(os.wglGetProcAddress("wglSwapIntervalEXT"));
                    }
                }
            }
        }
    }
}

pub fn deinit() void {
    _ = os.DestroyWindow(helper_window);
    _ = os.FreeLibrary(wglinstance);
}

pub fn run(comptime func: anytype, args: anytype) !void {
    var msg: os.MSG = undefined;
    while (true) {
        while (os.PeekMessageA(&msg, null, 0, 0, os.PM_REMOVE) != 0) {
            _ = os.TranslateMessage(&msg);
            _ = os.DispatchMessageA(&msg);
        }

        const ret = if (@typeInfo(meta.ReturnType(@TypeOf(func))) == .error_union)
            try @call(.auto, func, args)
        else
            @call(.auto, func, args);
        if (!ret) return;

        // TODO aduio
    }
}

pub fn glGetProcAddress(name: [*c]const u8) ?*anyopaque {
    const proc: ?*anyopaque = os.wglGetProcAddress(name);
    if (proc != null) return proc;
    return os.GetProcAddress(wglinstance, name);
}

//#region window

events: std.fifo.LinearFifo(winit.Event, .Dynamic),
window: os.HWND,
cursor: os.HCURSOR,
cursor_mode: winit.CursorMode,

rect: os.RECT = .{},
left_shift: bool = false,
right_shift: bool = false,
surrogate: u16 = 0,

dc: ?os.HDC = null,
rc: ?os.HGLRC = null,

pub fn createWindow(options: winit.WindowOptions) !*@This() {
    const self = try winit.allocator.create(@This());
    errdefer winit.allocator.destroy(self);

    const style = os.WS_OVERLAPPEDWINDOW;
    const size = clientToWindow(options.size, style);
    const window = os.CreateWindowExA(
        0,
        class_name,
        options.title,
        style,
        os.CW_USEDEFAULT,
        os.CW_USEDEFAULT,
        size.width,
        size.height,
        null,
        null,
        os.GetModuleHandleA(null),
        null,
    ) orelse return error.backend_failure;

    _ = os.DwmSetWindowAttribute(window, os.DWMWA_USE_IMMERSIVE_DARK_MODE, &@as(i32, 1), @sizeOf(i32));
    _ = os.DwmSetWindowAttribute(window, os.DWMWA_WINDOW_CORNER_PREFERENCE, &@as(i32, 3), @sizeOf(i32));

    self.* = .{
        .events = .init(winit.allocator),
        .window = window,
        .cursor = os.LoadCursorA(null, os.IDC_ARROW).?,
        .cursor_mode = options.cursor_mode,
    };
    _ = os.SetWindowLongPtrA(window, os.GWLP_USERDATA, @bitCast(@intFromPtr(self)));

    const dpi: f32 = @floatFromInt(os.GetDpiForWindow(window));
    const scale = dpi / os.USER_DEFAULT_SCREEN_DPI;
    self.pushEvent(.{ .scale = scale });

    const size_scaled = options.size.multiply(scale / options.scale);
    self.setSize(size_scaled);

    self.setMode(options.mode);
    if (options.cursor != .arrow) self.setCursor(options.cursor);

    self.pushEvent(.create);

    return self;
}

pub fn destroy(self: *@This()) void {
    if (winit.init_options.opengl) {
        _ = os.wglDeleteContext(self.rc);
        _ = os.ReleaseDC(self.window, self.dc);
    }
    _ = os.DestroyWindow(self.window);
    self.events.deinit();
    winit.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?winit.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: [:0]const u8) void {
    _ = os.SetWindowTextA(self.window, title);
}

pub fn setSize(self: *@This(), client_size: winit.Size) void {
    const style: u32 = @intCast(os.GetWindowLongPtrA(self.window, os.GWL_STYLE));
    const size = clientToWindow(client_size, style);
    _ = os.SetWindowPos(self.window, null, 0, 0, size.width, size.height, os.SWP_NOMOVE | os.SWP_NOZORDER);
}

pub fn setMode(self: *@This(), mode: winit.WindowMode) void {
    switch (mode) {
        .normal, .maximized => if (self.isFullscreen()) {
            _ = os.SetWindowLongPtrA(self.window, os.GWL_STYLE, os.WS_OVERLAPPEDWINDOW);
            _ = os.SetWindowPos(
                self.window,
                null,
                self.rect.left,
                self.rect.top,
                self.rect.right - self.rect.left,
                self.rect.bottom - self.rect.top,
                os.SWP_FRAMECHANGED | os.SWP_NOZORDER,
            );
        },
        .fullscreen => {
            const monitor = os.MonitorFromWindow(self.window, os.MONITOR_DEFAULTTONEAREST);
            var info = os.MONITORINFO{};
            _ = os.GetMonitorInfoA(monitor, &info);
            _ = os.SetWindowLongPtrA(self.window, os.GWL_STYLE, os.WS_POPUP);
            _ = os.SetWindowPos(
                self.window,
                null,
                info.rcMonitor.left,
                info.rcMonitor.top,
                info.rcMonitor.right - info.rcMonitor.left,
                info.rcMonitor.bottom - info.rcMonitor.top,
                os.SWP_FRAMECHANGED | os.SWP_NOZORDER,
            );
        },
    }

    switch (mode) {
        .normal, .fullscreen => _ = os.ShowWindow(self.window, os.SW_RESTORE),
        .maximized => _ = os.ShowWindow(self.window, os.SW_MAXIMIZE),
    }
}

pub fn setCursor(self: *@This(), shape: winit.Cursor) void {
    self.cursor = os.LoadCursorA(null, switch (shape) {
        .arrow => os.IDC_ARROW,
        .arrow_busy => os.IDC_APPSTARTING,
        .busy => os.IDC_WAIT,
        .text => os.IDC_IBEAM,
        .hand => os.IDC_HAND,
        .crosshair => os.IDC_CROSS,
        .forbidden => os.IDC_NO,
        .move => os.IDC_SIZEALL,
        .size_ns => os.IDC_SIZENS,
        .size_ew => os.IDC_SIZEWE,
        .size_nesw => os.IDC_SIZENESW,
        .size_nwse => os.IDC_SIZENWSE,
    }) orelse unreachable;

    // trigger WM_SETCURSOR
    var pos: os.POINT = undefined;
    _ = os.GetCursorPos(&pos);
    _ = os.SetCursorPos(pos.x, pos.y);
}

pub fn setCursorMode(self: *@This(), mode: winit.CursorMode) void {
    self.cursor_mode = mode;
    if (mode == .relative) {
        self.clipCursor();
    } else {
        _ = os.ClipCursor(null);
    }

    // trigger WM_SETCURSOR
    var pos: os.POINT = undefined;
    _ = os.GetCursorPos(&pos);
    _ = os.SetCursorPos(pos.x, pos.y);
}

pub fn requestAttention(_: *@This()) void {
    @panic("TODO");
}

pub fn createContext(self: *@This(), options: winit.ContextOptions) !void {
    self.dc = os.GetDC(self.window);
    var pfd = os.PIXELFORMATDESCRIPTOR{
        .nVersion = 1,
        .dwFlags = os.PFD_DRAW_TO_WINDOW | os.PFD_SUPPORT_OPENGL,
        .iPixelType = os.PFD_TYPE_RGBA,
        .cRedBits = options.red_bits,
        .cGreenBits = options.green_bits,
        .cBlueBits = options.blue_bits,
        .cAlphaBits = options.alpha_bits,
        .cColorBits = options.red_bits + options.green_bits + options.blue_bits,
        .cStencilBits = options.stencil_bits,
        .cDepthBits = options.depth_bits,
    };
    if (options.doublebuffer) pfd.dwFlags |= os.PFD_DOUBLEBUFFER;
    _ = os.SetPixelFormat(self.dc, os.ChoosePixelFormat(self.dc, &pfd), &pfd);
    self.rc = os.wglCreateContext(self.dc) orelse return error.backend_failure;
}

pub fn makeContextCurrent(self: *@This()) void {
    _ = os.wglMakeCurrent(self.dc, self.rc);
}

pub fn swapBuffers(self: *@This()) void {
    _ = os.SwapBuffers(self.dc);
}

pub fn swapInterval(_: *@This(), interval: i32) void {
    if (wgl.swapIntervalEXT) |swapIntervalEXT| {
        _ = swapIntervalEXT(interval);
    }
}

//#endregion

//#region callbacks

fn windowProc(window: os.HWND, msg: u32, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    const self = blk: {
        const userdata: usize = @bitCast(os.GetWindowLongPtrA(window, os.GWLP_USERDATA));
        const ptr: ?*@This() = @ptrFromInt(userdata);
        break :blk ptr orelse return os.DefWindowProcA(window, msg, wParam, lParam);
    };

    switch (msg) {
        os.WM_CLOSE => self.pushEvent(.close),
        os.WM_SETCURSOR => {
            if (os.LOWORD(lParam) == os.HTCLIENT) {
                _ = os.SetCursor(self.cursor);
                switch (self.cursor_mode) {
                    .normal => while (os.ShowCursor(1) < 0) {},
                    .hidden, .relative => while (os.ShowCursor(0) >= 0) {},
                }
                return 1;
            } else {
                while (os.ShowCursor(1) < 0) {}
                return os.DefWindowProcA(window, msg, wParam, lParam);
            }
        },
        os.WM_SETFOCUS => {
            self.pushEvent(.focused);
            if (self.cursor_mode == .relative) self.clipCursor();
        },
        os.WM_KILLFOCUS => self.pushEvent(.unfocused),
        os.WM_PAINT => {
            self.pushEvent(.draw);
            _ = os.ValidateRgn(window, null);
        },
        os.WM_SIZE => {
            const size = winit.Size{ .width = os.LOWORD(lParam), .height = os.HIWORD(lParam) };
            if (self.cursor_mode == .relative) {
                self.clipCursor();
            }
            if (wParam == os.SIZE_RESTORED or wParam == os.SIZE_MAXIMIZED) {
                const fullscreen = self.isFullscreen();
                if (wParam == os.SIZE_RESTORED and !fullscreen) {
                    _ = os.GetWindowRect(window, &self.rect);
                }
                self.pushEvent(.{ .mode = if (fullscreen) .fullscreen else if (wParam == os.SIZE_MAXIMIZED) .maximized else .normal });
                self.pushEvent(.{ .size = size });
                self.pushEvent(.{ .framebuffer = size });
            }
        },
        os.WM_DPICHANGED => {
            const dpi: f32 = @floatFromInt(os.LOWORD(wParam));
            const scale = dpi / os.USER_DEFAULT_SCREEN_DPI;
            self.pushEvent(.{ .scale = scale });
        },
        os.WM_CHAR => {
            const char: u16 = @intCast(wParam);
            var chars: []const u16 = undefined;
            if (self.surrogate != 0) {
                chars = &.{ self.surrogate, char };
                self.surrogate = 0;
            } else if (std.unicode.utf16IsHighSurrogate(char)) {
                self.surrogate = char;
                return 0;
            } else {
                chars = &.{char};
            }
            var iter = std.unicode.Utf16LeIterator.init(chars);
            const codepoint = (iter.nextCodepoint() catch return 0).?; // never returns null on first call
            if (codepoint >= ' ') {
                self.pushEvent(.{ .char = codepoint });
            }
        },
        os.WM_KEYDOWN, os.WM_SYSKEYDOWN, os.WM_KEYUP, os.WM_SYSKEYUP => {
            if (wParam == os.VK_PROCESSKEY) {
                return 0;
            }

            if (msg == os.WM_SYSKEYDOWN and wParam == os.VK_F4) {
                self.pushEvent(.close);
            }

            const flags = os.HIWORD(lParam);
            const scancode: u9 = @intCast(flags & 0x1FF);

            if (scancode == 0x1D) {
                // discard spurious left control sent before right alt in some layouts
                var next: os.MSG = undefined;
                if (os.PeekMessageA(&next, window, 0, 0, os.PM_NOREMOVE) != 0 and
                    next.time == os.GetMessageTime() and
                    (os.HIWORD(next.lParam) & (0x1FF | os.KF_UP)) == (0x138 | (flags & os.KF_UP)))
                {
                    return 0;
                }
            }

            if (scancodeToButton(scancode)) |button| {
                if (flags & os.KF_UP == 0) {
                    if (button == .left_shift) self.left_shift = true;
                    if (button == .right_shift) self.right_shift = true;
                    self.pushEvent(.{ .button_press = button });
                } else {
                    self.pushEvent(.{ .button_release = button });
                }
            } else {
                log.warn("unknown scancode 0x{x}", .{scancode});
            }
        },
        os.WM_LBUTTONDOWN, os.WM_LBUTTONUP, os.WM_RBUTTONDOWN, os.WM_RBUTTONUP, os.WM_MBUTTONDOWN, os.WM_MBUTTONUP, os.WM_XBUTTONDOWN, os.WM_XBUTTONUP => {
            const button: winit.Button = switch (msg) {
                os.WM_LBUTTONDOWN, os.WM_LBUTTONUP => .mouse_left,
                os.WM_RBUTTONDOWN, os.WM_RBUTTONUP => .mouse_right,
                os.WM_MBUTTONDOWN, os.WM_MBUTTONUP => .mouse_middle,
                else => if (os.HIWORD(wParam) == os.XBUTTON1) .mouse_back else .mouse_forward,
            };

            switch (msg) {
                os.WM_LBUTTONDOWN, os.WM_MBUTTONDOWN, os.WM_RBUTTONDOWN, os.WM_XBUTTONDOWN => self.pushEvent(.{ .button_press = button }),
                else => self.pushEvent(.{ .button_release = button }),
            }

            return if (msg == os.WM_XBUTTONDOWN or msg == os.WM_XBUTTONUP) 1 else 0;
        },
        os.WM_MOUSEMOVE => if (self.cursor_mode != .relative) self.pushEvent(.{ .mouse = .{ .x = os.LOWORD(lParam), .y = os.HIWORD(lParam) } }),
        os.WM_INPUT => if (self.cursor_mode == .relative) {
            @panic("TODO");
        },
        os.WM_MOUSEWHEEL, os.WM_MOUSEHWHEEL => {
            const delta: f32 = @floatFromInt(@as(i16, @bitCast(os.HIWORD(wParam))));
            const value = delta / os.WHEEL_DELTA;
            self.pushEvent(if (msg == os.WM_MOUSEWHEEL) .{ .scroll_vertical = -value } else .{ .scroll_horizontal = value });
        },
        os.WM_SYSCOMMAND => if (wParam & 0xFFF0 != os.SC_KEYMENU) return os.DefWindowProcA(window, msg, wParam, lParam),
        else => return os.DefWindowProcA(window, msg, wParam, lParam),
    }

    return 0;
}

fn helperWindowProc(window: os.HWND, msg: u32, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    switch (msg) {
        os.WM_INPUT_DEVICE_CHANGE => {
            // TODO
        },
        os.WM_INPUT => {
            // TODO
        },
        else => {},
    }

    return os.DefWindowProcA(window, msg, wParam, lParam);
}

//#endregion

//#region helpers

inline fn pushEvent(self: *@This(), event: winit.Event) void {
    self.events.writeItem(event) catch {};
}

fn clientToWindow(size: winit.Size, style: u32) winit.Size {
    var rect = os.RECT{ .right = size.width, .bottom = size.height };
    _ = os.AdjustWindowRectEx(&rect, style, 0, 0);
    return .{ .width = @intCast(rect.right - rect.left), .height = @intCast(rect.bottom - rect.top) };
}

fn clipCursor(self: *@This()) void {
    var rect: os.RECT = undefined;
    _ = os.GetClientRect(self.window, &rect);
    _ = os.ClientToScreen(self.window, @ptrCast(&rect.left));
    _ = os.ClientToScreen(self.window, @ptrCast(&rect.right));
    _ = os.ClipCursor(&rect);
}

fn isFullscreen(self: *@This()) bool {
    return os.GetWindowLongPtrA(self.window, os.GWL_STYLE) & os.WS_OVERLAPPEDWINDOW != os.WS_OVERLAPPEDWINDOW;
}

fn scancodeToButton(scancode: u9) ?winit.Button {
    comptime var table: [0x15D]winit.Button = undefined;
    comptime for (&table, 1..) |*ptr, i| {
        ptr.* = switch (i) {
            0x1 => .escape,
            0x2 => .@"1",
            0x3 => .@"2",
            0x4 => .@"3",
            0x5 => .@"4",
            0x6 => .@"5",
            0x7 => .@"6",
            0x8 => .@"7",
            0x9 => .@"8",
            0xA => .@"9",
            0xB => .@"0",
            0xC => .minus,
            0xD => .equals,
            0xE => .backspace,
            0xF => .tab,
            0x10 => .q,
            0x11 => .w,
            0x12 => .e,
            0x13 => .r,
            0x14 => .t,
            0x15 => .y,
            0x16 => .u,
            0x17 => .i,
            0x18 => .o,
            0x19 => .p,
            0x1A => .left_bracket,
            0x1B => .right_bracket,
            0x1C => .enter,
            0x1D => .left_control,
            0x1E => .a,
            0x1F => .s,
            0x20 => .d,
            0x21 => .f,
            0x22 => .g,
            0x23 => .h,
            0x24 => .j,
            0x25 => .k,
            0x26 => .l,
            0x27 => .semicolon,
            0x28 => .apostrophe,
            0x29 => .grave,
            0x2A => .left_shift,
            0x2B => .backslash,
            0x2C => .z,
            0x2D => .x,
            0x2E => .c,
            0x2F => .v,
            0x30 => .b,
            0x31 => .n,
            0x32 => .m,
            0x33 => .comma,
            0x34 => .dot,
            0x35 => .slash,
            0x36 => .right_shift,
            0x37 => .kp_star,
            0x38 => .left_alt,
            0x39 => .space,
            0x3A => .caps_lock,
            0x3B => .f1,
            0x3C => .f2,
            0x3D => .f3,
            0x3E => .f4,
            0x3F => .f5,
            0x40 => .f6,
            0x41 => .f7,
            0x42 => .f8,
            0x43 => .f9,
            0x44 => .f10,
            0x45 => .pause,
            0x46 => .scroll_lock,
            0x47 => .kp_7,
            0x48 => .kp_8,
            0x49 => .kp_9,
            0x4A => .kp_minus,
            0x4B => .kp_4,
            0x4C => .kp_5,
            0x4D => .kp_6,
            0x4E => .kp_plus,
            0x4F => .kp_1,
            0x50 => .kp_2,
            0x51 => .kp_3,
            0x52 => .kp_0,
            0x53 => .kp_dot,
            0x54 => .print_screen, // sysrq
            0x56 => .iso_backslash,
            0x57 => .f11,
            0x58 => .f12,
            0x59 => .kp_equals,
            0x5B => .left_gui, // sent by touchpad gestures
            0x64 => .f13,
            0x65 => .f14,
            0x66 => .f15,
            0x67 => .f16,
            0x68 => .f17,
            0x69 => .f18,
            0x6A => .f19,
            0x6B => .f20,
            0x6C => .f21,
            0x6D => .f22,
            0x6E => .f23,
            0x70 => .international2,
            0x71 => .lang2,
            0x72 => .lang1,
            0x73 => .international1,
            0x76 => .f24,
            0x79 => .international4,
            0x7B => .international5,
            0x7D => .international3,
            0x7E => .kp_comma,
            0x11C => .kp_enter,
            0x11D => .right_control,
            0x135 => .kp_slash,
            0x136 => .right_shift, // sent by IME
            0x137 => .print_screen,
            0x138 => .right_alt,
            0x145 => .num_lock,
            0x146 => .pause, // break
            0x147 => .home,
            0x148 => .up,
            0x149 => .page_up,
            0x14B => .left,
            0x14D => .right,
            0x14F => .end,
            0x150 => .down,
            0x151 => .page_down,
            0x152 => .insert,
            0x153 => .delete,
            0x15B => .left_gui,
            0x15C => .right_gui,
            0x15D => .application,
            else => .mouse_left,
        };
    };
    return if (scancode > 0 and scancode <= table.len and table[scancode - 1] != .mouse_left) table[scancode - 1] else null;
}

//#endregion
