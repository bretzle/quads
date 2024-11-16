const std = @import("std");
const quads = @import("../quads.zig");
const os = @import("../os/winapi.zig");
const meta = @import("../meta.zig");

const class_name = @typeName(@This());
var helper_window: os.HWND = undefined;
var wglinstance: ?os.HMODULE = null;

var wgl: struct {
    swapIntervalEXT: ?*const fn (i32) callconv(os.WINAPI) os.BOOL = null,
} = .{};

pub fn init(options: quads.InitOptions) !void {
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

events: std.fifo.LinearFifo(quads.Event, .Dynamic),
window: os.HWND,
cursor: os.HCURSOR,
cursor_mode: quads.CursorMode,

dc: ?os.HDC = null,
rc: ?os.HGLRC = null,

pub fn createWindow(options: quads.WindowOptions) !*@This() {
    const self = try quads.allocator.create(@This());
    errdefer quads.allocator.destroy(self);

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
        .events = .init(quads.allocator),
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
    if (quads.init_options.opengl) {
        _ = os.wglDeleteContext(self.rc);
        _ = os.ReleaseDC(self.window, self.dc);
    }
    _ = os.DestroyWindow(self.window);
    self.events.deinit();
    quads.allocator.destroy(self);
}

pub fn getEvent(self: *@This()) ?quads.Event {
    return self.events.readItem();
}

pub fn setTitle(self: *@This(), title: [:0]const u8) void {
    _ = os.SetWindowTextA(self.window, title);
}

pub fn setSize(self: *@This(), client_size: quads.Size) void {
    const style: u32 = @intCast(os.GetWindowLongPtrA(self.window, os.GWL_STYLE));
    const size = clientToWindow(client_size, style);
    _ = os.SetWindowPos(self.window, null, 0, 0, size.width, size.height, os.SWP_NOMOVE | os.SWP_NOZORDER);
}

pub fn setMode(self: *@This(), mode: quads.WindowMode) void {
    // TODO handle fullscreen
    switch (mode) {
        .normal, .maximized => {},
        .fullscreen => {},
    }

    switch (mode) {
        .normal, .fullscreen => _ = os.ShowWindow(self.window, os.SW_RESTORE),
        .maximized => _ = os.ShowWindow(self.window, os.SW_MAXIMIZE),
    }
}

pub fn setCursor(self: *@This(), shape: quads.Cursor) void {
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

pub fn setCursorMode(self: *@This(), mode: quads.CursorMode) void {
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

pub fn requestAttention(self: *@This()) void {
    _ = self;
    // TODO
}

pub fn createContext(self: *@This(), options: quads.ContextOptions) !void {
    _ = options; // TODO

    self.dc = os.GetDC(self.window);
    var pfd = os.PIXELFORMATDESCRIPTOR{
        .nVersion = 1,
        .dwFlags = os.PFD_DRAW_TO_WINDOW | os.PFD_SUPPORT_OPENGL | os.PFD_DOUBLEBUFFER,
        .iPixelType = os.PFD_TYPE_RGBA,
        .cColorBits = 24,
    };
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
        else => return os.DefWindowProcA(window, msg, wParam, lParam),
    }

    return 0;
}

fn helperWindowProc(window: os.HWND, msg: u32, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    return os.DefWindowProcA(window, msg, wParam, lParam);
}

//#endregion

//#region helpers

inline fn pushEvent(self: *@This(), event: quads.Event) void {
    self.events.writeItem(event) catch {};
}

fn clientToWindow(size: quads.Size, style: u32) quads.Size {
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

//#endregion
