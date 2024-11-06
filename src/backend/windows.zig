const std = @import("std");
const os = @import("../winapi.zig");
const parent = @import("../rgfw.zig");

const Window = parent.Window;
const Event = parent.Event;
const Monitor = parent.Monitor;
const MonitorInfo = parent.MonitorInfo;
const Area = parent.Area;
const Point = parent.Point;

const WGL_DRAW_TO_WINDOW_ARB: i32 = 0x2001;
const WGL_ACCELERATION_ARB: i32 = 0x2003;
const WGL_SUPPORT_OPENGL_ARB: i32 = 0x2010;
const WGL_DOUBLE_BUFFER_ARB: i32 = 0x2011;
const WGL_STEREO_ARB: i32 = 0x2012;
const WGL_PIXEL_TYPE_ARB: i32 = 0x2013;
const WGL_COLOR_BITS_ARB: i32 = 0x2014;
const WGL_RED_BITS_ARB: i32 = 0x2015;
const WGL_GREEN_BITS_ARB: i32 = 0x2017;
const WGL_BLUE_BITS_ARB: i32 = 0x2019;
const WGL_ALPHA_BITS_ARB: i32 = 0x201B;
const WGL_DEPTH_BITS_ARB: i32 = 0x2022;
const WGL_STENCIL_BITS_ARB: i32 = 0x2023;
const WGL_AUX_BUFFERS_ARB: i32 = 0x2024;

const WGL_FULL_ACCELERATION_ARB: i32 = 0x2027;
const WGL_TYPE_RGBA_ARB: i32 = 0x202B;

const WGL_SAMPLE_BUFFERS_ARB: i32 = 0x2041;
const WGL_SAMPLES_ARB: i32 = 0x2042;

const WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB: i32 = 0x20A9;

pub const WGL_CONTEXT_MAJOR_VERSION_ARB: i32 = 0x2091;
pub const WGL_CONTEXT_MINOR_VERSION_ARB: i32 = 0x2092;
pub const WGL_CONTEXT_PROFILE_MASK_ARB: i32 = 0x9126;

pub const WGL_CONTEXT_CORE_PROFILE_BIT_ARB: i32 = 0x00000001;
pub const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB: i32 = 0x00000002;

pub var wglinstance: ?os.HMODULE = null;
pub var RGFW_XInput_dll: ?os.HMODULE = null;

const WglChoosePixelFormatARB = ?*const fn (?os.HDC, [*c]const i32, [*c]const f32, u32, [*c]i32, [*c]u32) callconv(os.WINAPI) i32;
pub var wglChoosePixelFormatARB: WglChoosePixelFormatARB = null;

const WglCreateContextAttribsARB = ?*const fn (?os.HDC, ?os.HGLRC, [*c]const i32) callconv(os.WINAPI) ?os.HGLRC;
pub var wglCreateContextAttribsARB: WglCreateContextAttribsARB = null;

var XInputGetStateSRC: ?*const fn (os.DWORD, *os.STATE) callconv(os.WINAPI) os.DWORD = null;
var XInputGetKeystrokeSRC: ?*const fn (os.DWORD, os.DWORD, *os.XINPUT_KEYSTROKE) callconv(os.WINAPI) os.DWORD = null;

pub fn RGFW_initFormatAttribs(useSoftware: bool) []const i32 {
    _ = useSoftware;

    return &[_]i32{
        WGL_DRAW_TO_WINDOW_ARB, 1,
        WGL_ACCELERATION_ARB,   WGL_FULL_ACCELERATION_ARB,
        WGL_SUPPORT_OPENGL_ARB, 1,
        WGL_DOUBLE_BUFFER_ARB,  1,
        WGL_PIXEL_TYPE_ARB,     WGL_TYPE_RGBA_ARB,
        WGL_RED_BITS_ARB,       8,
        WGL_GREEN_BITS_ARB,     8,
        WGL_BLUE_BITS_ARB,      8,
        WGL_ALPHA_BITS_ARB,     8,
        WGL_DEPTH_BITS_ARB,     24,
        WGL_STENCIL_BITS_ARB,   8,
        WGL_SAMPLE_BUFFERS_ARB, 1,
        WGL_SAMPLES_ARB,        4,
        WGL_COLOR_BITS_ARB,     32,
        WGL_STEREO_ARB,         0,
        WGL_AUX_BUFFERS_ARB,    0,
        0,
    };
}

pub fn WndProc(hWnd: os.HWND, message: os.UINT, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    switch (message) {
        os.WM_MOVE => {
            parent.RGFW_eventWindow.r.x = os.LOWORD(lParam);
            parent.RGFW_eventWindow.r.y = os.HIWORD(lParam);
            parent.RGFW_eventWindow.src.window = hWnd;
        },
        os.WM_SIZE => {
            parent.RGFW_eventWindow.r.w = os.LOWORD(lParam);
            parent.RGFW_eventWindow.r.h = os.HIWORD(lParam);
            parent.RGFW_eventWindow.src.window = hWnd;
        },
        else => {},
    }

    return os.DefWindowProcA(hWnd, message, wParam, lParam);
}

pub fn loadXInput() void {
    const names = [_][:0]const u8{
        "xinput1_4.dll",
        "xinput1_3.dll",
        "xinput9_1_0.dll",
        "xinput1_2.dll",
        "xinput1_1.dll",
    };

    for (names) |name| {
        RGFW_XInput_dll = os.LoadLibraryA(name);
        if (RGFW_XInput_dll) |_| {
            XInputGetStateSRC = @ptrCast(os.GetProcAddress(RGFW_XInput_dll, "XInputGetState"));
            XInputGetKeystrokeSRC = @ptrCast(os.GetProcAddress(RGFW_XInput_dll, "XInputGetKeystroke"));

            if (XInputGetStateSRC == null or XInputGetKeystrokeSRC == null)
                std.debug.print("Failed to load XInputGetState\n", .{})
            else
                break;
        }
    }
}

pub fn checkXInput(_: *Window, e: *Event) i32 {
    const INPUT_DEADZONE: i16 = @intFromFloat(0.24 * 0x7FFF);

    for (0..4) |i| {
        var keystroke: os.XINPUT_KEYSTROKE = undefined;

        if (XInputGetKeystrokeSRC == null) return 0;

        const result = XInputGetKeystrokeSRC.?(@truncate(i), 0, &keystroke);

        if ((keystroke.Flags & os.XINPUT_KEYSTROKE_REPEAT) == 0 and result != os.ERROR_EMPTY) {
            if (result != 0) return 0;
            if (keystroke.VirtualKey > 0x5815) continue;

            e.typ = if (keystroke.Flags & os.XINPUT_KEYSTROKE_KEYDOWN != 0) .js_button_pressed else .js_button_released;
            e.joy_button = parent.RGFW_xinput2RGFW[keystroke.VirtualKey - 0x5800];
            parent.RGFW_jsPressed[i].set(e.joy_button, keystroke.Flags & os.XINPUT_KEYSTROKE_KEYDOWN == 0);

            return 1;
        }

        var state: os.STATE = undefined;

        if (XInputGetStateSRC == null or XInputGetStateSRC.?(@truncate(i), &state) == os.ERROR_DEVICE_NOT_CONNECTED) return 0;

        if ((state.Gamepad.sThumbLX < INPUT_DEADZONE and state.Gamepad.sThumbLX > -INPUT_DEADZONE) and
            (state.Gamepad.sThumbLY < INPUT_DEADZONE and state.Gamepad.sThumbLY > -INPUT_DEADZONE))
        {
            state.Gamepad.sThumbLX = 0;
            state.Gamepad.sThumbLY = 0;
        }

        if ((state.Gamepad.sThumbRX < INPUT_DEADZONE and state.Gamepad.sThumbRX > -INPUT_DEADZONE) and
            (state.Gamepad.sThumbRY < INPUT_DEADZONE and state.Gamepad.sThumbRY > -INPUT_DEADZONE))
        {
            state.Gamepad.sThumbRX = 0;
            state.Gamepad.sThumbRY = 0;
        }

        e.axisesCount = 2;
        const axis1 = Point{ .x = state.Gamepad.sThumbLX, .y = state.Gamepad.sThumbLY };
        const axis2 = Point{ .x = state.Gamepad.sThumbRX, .y = state.Gamepad.sThumbRY };

        if (axis1.x != e.axis[0].x or axis1.y != e.axis[0].y or axis2.x != e.axis[1].x or axis2.y != e.axis[1].y) {
            e.typ = .js_axis_move;
            e.axis = .{ axis1, axis2 };

            return 1;
        }

        e.axis = .{ axis1, axis2 };
    }

    return 0;
}

pub fn GetMonitorByHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
    const info: *MonitorInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));
    if (info.hMonitor == hMonitor) return 0;

    info.iIndex += 1;
    return 1;
}

pub fn win32CreateMonitor(src: ?os.HMONITOR) Monitor {
    var monitor: Monitor = undefined;
    var monitorInfo = os.MONITORINFO{};

    _ = os.GetMonitorInfoA(src, &monitorInfo);

    var info = MonitorInfo{ .hMonitor = src };

    if (os.EnumDisplayMonitors(null, null, &GetMonitorByHandle, @bitCast(@intFromPtr(&info))) != 0) {
        var dd = os.DISPLAY_DEVICEA{};

        var deviceIndex: u32 = 0;
        while (os.EnumDisplayDevicesA(null, deviceIndex, &dd, 0) != 0) : (deviceIndex += 1) {
            const deviceName = dd.DeviceName;

            if (os.EnumDisplayDevicesA(@ptrCast(&deviceName), info.iIndex, &dd, 0) != 0) {
                @memcpy(monitor.name[0..32], dd.DeviceName[0..]);
                break;
            }
        }
    }

    monitor.rect.x = monitorInfo.rcWork.left;
    monitor.rect.y = monitorInfo.rcWork.top;
    monitor.rect.w = monitorInfo.rcWork.right - monitorInfo.rcWork.left;
    monitor.rect.h = monitorInfo.rcWork.bottom - monitorInfo.rcWork.top;

    const hdc = os.GetDC(null);

    const ppiX: f32 = @floatFromInt(os.GetDeviceCaps(hdc, os.LOGPIXELSX));
    const ppiY: f32 = @floatFromInt(os.GetDeviceCaps(hdc, os.LOGPIXELSY));
    _ = os.ReleaseDC(null, hdc);

    monitor.physW = @as(f32, @floatFromInt(os.GetSystemMetrics(os.SM_CYSCREEN))) / ppiX;
    monitor.physH = @as(f32, @floatFromInt(os.GetSystemMetrics(os.SM_CXSCREEN))) / ppiY;

    return monitor;
}

pub fn GetMonitorHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
    const info: *MonitorInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));

    if (info.iIndex >= 6) return 0;

    parent.RGFW_monitors[info.iIndex] = win32CreateMonitor(hMonitor);
    info.iIndex += 1;

    return 1;
}

pub fn RGFW_loadHandleImage(_: *Window, src: []const u8, a: Area, icon: bool) os.HICON {
    const bi = os.BITMAPV5HEADER{
        .bV5Width = @bitCast(a.w),
        .bV5Height = -@as(i32, @bitCast(a.h)),
        .bV5Planes = 1,
        .bV5BitCount = 32,
        .bV5Compression = 3,
        .bV5RedMask = 0x00ff0000,
        .bV5GreenMask = 0x0000ff00,
        .bV5BlueMask = 0x000000ff,
        .bV5AlphaMask = 0xff000000,
    };

    var target: [*]u8 = undefined;
    var source: [*]const u8 = src.ptr;

    const dc = os.GetDC(null);
    const color = os.CreateDIBSection(dc, @ptrCast(&bi), os.DIB_RGB_COLORS, @ptrCast(&target), null, 0);
    _ = os.ReleaseDC(null, dc);

    const mask = os.CreateBitmap(@bitCast(a.w), @bitCast(a.h), 1, 1, null);

    for (0..(a.w * a.h)) |_| {
        target[0] = source[2];
        target[1] = source[1];
        target[2] = source[0];
        target[3] = source[3];
        target += 4;
        source += 4;
    }

    var ii = os.ICONINFO{
        .fIcon = @intFromBool(icon),
        .xHotspot = 0,
        .yHotspot = 0,
        .hbmMask = mask,
        .hbmColor = color,
    };

    const handle = os.CreateIconIndirect(&ii);

    _ = os.DeleteObject(@ptrCast(color));
    _ = os.DeleteObject(@ptrCast(mask));

    return handle;
}

pub fn RGFW_win32_initTimer() os.LARGE_INTEGER {
    const frequency = struct {
        var static = os.LARGE_INTEGER{ .QuadPart = 0 };
    };

    if (frequency.static.QuadPart == 0) {
        _ = os.timeBeginPeriod(1);
        _ = os.QueryPerformanceFrequency(&frequency.static);
    }

    return frequency.static;
}
