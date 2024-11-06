const std = @import("std");
const gl = @import("gl");
const os = @import("../os/winapi.zig");
const parent = @import("../rgfw.zig");
const common = @import("common.zig");

const Window = parent.Window;
const Event = parent.Event;
const Monitor = parent.Monitor;
const Area = parent.math.Area;
const Point = parent.math.Point;
const Rect = parent.math.Rect;

const mouseIconSrc = [11]u32{
    os.OCR_NORMAL,
    os.OCR_NORMAL,
    os.OCR_IBEAM,
    os.OCR_CROSS,
    os.OCR_HAND,
    os.OCR_SIZEWE,
    os.OCR_SIZENS,
    os.OCR_SIZENWSE,
    os.OCR_SIZENESW,
    os.OCR_SIZEALL,
    os.OCR_NO,
};

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

const WGL_CONTEXT_MAJOR_VERSION_ARB: i32 = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB: i32 = 0x2092;
const WGL_CONTEXT_PROFILE_MASK_ARB: i32 = 0x9126;

const WGL_CONTEXT_CORE_PROFILE_BIT_ARB: i32 = 0x00000001;
const WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB: i32 = 0x00000002;

var wglinstance: ?os.HMODULE = null;
var RGFW_XInput_dll: ?os.HMODULE = null;

const WglChoosePixelFormatARB = ?*const fn (?os.HDC, [*c]const i32, [*c]const f32, u32, [*c]i32, [*c]u32) callconv(os.WINAPI) i32;
var wglChoosePixelFormatARB: WglChoosePixelFormatARB = null;

const WglCreateContextAttribsARB = ?*const fn (?os.HDC, ?os.HGLRC, [*c]const i32) callconv(os.WINAPI) ?os.HGLRC;
var wglCreateContextAttribsARB: WglCreateContextAttribsARB = null;

var XInputGetStateSRC: ?*const fn (os.DWORD, *os.STATE) callconv(os.WINAPI) os.DWORD = null;
var XInputGetKeystrokeSRC: ?*const fn (os.DWORD, os.DWORD, *os.XINPUT_KEYSTROKE) callconv(os.WINAPI) os.DWORD = null;

var gl_procs: gl.ProcTable = undefined;

const initFormatAttribs = &[_]i32{
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

fn WndProc(hWnd: os.HWND, message: os.UINT, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    switch (message) {
        os.WM_MOVE => {
            common.eventWindow.r.x = os.LOWORD(lParam);
            common.eventWindow.r.y = os.HIWORD(lParam);
            common.eventWindow.src.window = hWnd;
        },
        os.WM_SIZE => {
            common.eventWindow.r.w = os.LOWORD(lParam);
            common.eventWindow.r.h = os.HIWORD(lParam);
            common.eventWindow.src.window = hWnd;
        },
        else => {},
    }

    return os.DefWindowProcA(hWnd, message, wParam, lParam);
}

fn loadXInput() void {
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

fn checkXInput(_: *Window, e: *Event) i32 {
    const INPUT_DEADZONE: i16 = @intFromFloat(0.24 * 0x7FFF);

    for (0..4) |i| {
        var keystroke: os.XINPUT_KEYSTROKE = undefined;

        if (XInputGetKeystrokeSRC == null) return 0;

        const result = XInputGetKeystrokeSRC.?(@truncate(i), 0, &keystroke);

        if ((keystroke.Flags & os.XINPUT_KEYSTROKE_REPEAT) == 0 and result != os.ERROR_EMPTY) {
            if (result != 0) return 0;
            if (keystroke.VirtualKey > 0x5815) continue;

            e.typ = if (keystroke.Flags & os.XINPUT_KEYSTROKE_KEYDOWN != 0) .js_button_pressed else .js_button_released;
            e.joy_button = common.xinput2RGFW[keystroke.VirtualKey - 0x5800];
            common.jsPressed[i].set(e.joy_button, keystroke.Flags & os.XINPUT_KEYSTROKE_KEYDOWN == 0);

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

fn loadHandleImage(_: *Window, src: []const u8, a: Area, icon: bool) os.HICON {
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

pub const WindowSrc = struct {
    window: ?os.HWND,
    hdc: os.HDC,
    hOffset: u32,
    ctx: os.HGLRC,
    maxSize: Area,
    minSize: Area,

    pub fn checkEvent(win: *Window) ?*Event {
        if (win.event.typ == .quit) return null;

        var msg: os.MSG = undefined;

        if (common.eventWindow.src.window == win.src.window) {
            if (common.eventWindow.r.x != -1) {
                win.r.x = common.eventWindow.r.x;
                win.r.y = common.eventWindow.r.y;
                win.event.typ = .window_moved;
                parent.callbacks.windowMoveCallback(win, win.r);
            }
            if (common.eventWindow.r.w != -1) {
                win.r.w = common.eventWindow.r.w;
                win.r.h = common.eventWindow.r.h;
                win.event.typ = .window_resized;
                parent.callbacks.windowResizeCallback(win, win.r);
            }
            common.eventWindow.src.window = null;
            common.eventWindow.r = .{ .x = -1, .y = -1, .w = -1, .h = -1 };
            return &win.event;
        }

        // const drop = struct {
        //     var static: HDROP = @import("std").mem.zeroes(HDROP);
        // };
        // _ = &drop;
        if (win.event.typ == .dnd_init) {
            todo("dnd init", @src());
            //     if (win.event.droppedFilesCount != 0) {
            //         var i: u32 = undefined;
            //         _ = &i;
            //         {
            //             i = 0;
            //             while (i < win.event.droppedFilesCount) : (i +%= 1) {
            //                 win.event.droppedFiles[i][@as(c_uint, @intCast(@as(c_int, 0)))] = '\x00';
            //             }
            //         }
            //     }
            //     win.event.droppedFilesCount = 0;
            //     win.event.droppedFilesCount = DragQueryFileW(drop.static, @as(c_uint, 4294967295), null, 0);
            //     var i: u32 = undefined;
            //     _ = &i;
            //     {
            //         i = 0;
            //         while (i < win.event.droppedFilesCount) : (i +%= 1) {
            //             const length: UINT = DragQueryFileW(drop.static, i, null, 0);
            //             _ = &length;
            //             var buffer: [*c]WCHAR = @as([*c]WCHAR, @ptrCast(@alignCast(calloc(@as(usize, @bitCast(@as(c_ulonglong, length))) +% @as(usize, @bitCast(@as(c_longlong, @as(c_int, 1)))), @sizeOf(WCHAR)))));
            //             _ = &buffer;
            //             _ = DragQueryFileW(drop.static, i, buffer, length +% 1);
            //             _ = strncpy(win.event.droppedFiles[i], createUTF8FromWideStringWin32(buffer), @as(c_ulonglong, @bitCast(@as(c_longlong, @as(c_int, 260)))));
            //             (blk: {
            //                 const tmp = @as(c_int, 260) - @as(c_int, 1);
            //                 if (tmp >= 0) break :blk win.event.droppedFiles[i] + @as(usize, @intCast(tmp)) else break :blk win.event.droppedFiles[i] - ~@as(usize, @bitCast(@as(isize, @intCast(tmp)) +% -1));
            //             }).* = '\x00';
            //             free(@as(?*anyopaque, @ptrCast(buffer)));
            //         }
            //     }
            //     DragFinish(drop.static);
            //     RGFW_dndCallback.?(win, win.event.droppedFiles, win.event.droppedFilesCount);
            //     win.event.typ = @as(u32, @bitCast(RGFW_dnd));
            //     return &win.event;
        }

        win.event.in_focus = os.GetForegroundWindow() == win.src.window;

        if (checkXInput(win, &win.event) != 0) return &win.event;

        const keyboardState = struct {
            var static: [256]u8 = .{0} ** 256;
        };

        if (os.PeekMessageA(&msg, win.src.window, 0, 0, os.PM_REMOVE) != 0) {
            switch (msg.message) {
                os.WM_CLOSE, os.WM_QUIT => {
                    parent.callbacks.windowQuitCallback(win);
                    win.event.typ = .quit;
                },
                os.WM_ACTIVATE => {
                    win.event.in_focus = os.LOWORD(msg.wParam) == os.WA_INACTIVE;

                    if (win.event.in_focus) {
                        win.event.typ = .focus_in;
                        parent.callbacks.focusCallback(win, true);
                    } else {
                        win.event.typ = .focus_out;
                        parent.callbacks.focusCallback(win, false);
                    }
                },
                os.WM_PAINT => {
                    win.event.typ = .window_refresh;
                    parent.callbacks.windowRefreshCallback(win);
                },
                os.WM_MOUSELEAVE => {
                    win.event.typ = .mouse_leave;
                    win._winArgs.mouse_left = true;
                    parent.callbacks.mouseNotifyCallBack(win, win.event.point, false);
                },
                os.WM_KEYUP, os.WM_KEYDOWN => {
                    win.event.keycode = common.apiKeyCodeToRGFW(@truncate(msg.wParam));

                    common.keyboard[@intFromEnum(win.event.keycode)].prev = parent.isPressed(win, win.event.keycode);

                    const keyName = struct {
                        var static: [16]u8 = @import("std").mem.zeroes([16]u8);
                    };

                    _ = os.GetKeyNameTextA(@truncate(msg.lParam), @ptrCast(&keyName.static), 16);

                    if ((os.GetKeyState(os.VK_CAPITAL) & 0x0001 == 0 and os.GetKeyState(os.VK_SHIFT) & 0x8000 == 0) or
                        (os.GetKeyState(os.VK_CAPITAL) & 0x0001 != 0 and os.GetKeyState(os.VK_SHIFT) & 0x8000 != 0))
                    {
                        _ = os.CharLowerBuffA(@ptrCast(&keyName.static), 16);
                    }

                    common.updateLockState(win, os.GetKeyState(os.VK_CAPITAL) & 0x0001 != 0, os.GetKeyState(os.VK_NUMLOCK) & 0x0001 != 0);

                    win.event.keyName = keyName.static;

                    if (parent.isPressed(win, .shift_l)) {
                        _ = os.ToAscii(@truncate(msg.wParam), os.MapVirtualKeyA(@truncate(msg.wParam), os.MAPVK_VK_TO_CHAR), @ptrCast(&keyboardState.static), @alignCast(@ptrCast(&win.event.keyName)), 0);
                    }

                    win.event.typ = if (msg.message == os.WM_KEYUP) .key_released else .key_pressed;
                    common.keyboard[@intFromEnum(win.event.keycode)].current = msg.message == os.WM_KEYDOWN;
                    parent.callbacks.keyCallback(win, win.event.keycode, std.mem.sliceTo(&win.event.keyName, 0), win.event.lockState, false);
                },
                os.WM_MOUSEMOVE => if (!win._winArgs.hold_mouse) {
                    win.event.typ = .mouse_pos_changed;
                    win.event.point.x = os.GET_X_LPARAM(msg.lParam);
                    win.event.point.y = os.GET_Y_LPARAM(msg.lParam);
                    parent.callbacks.mousePosCallback(win, win.event.point);

                    if (win._winArgs.mouse_left) {
                        win._winArgs.mouse_left = !win._winArgs.mouse_left;
                        win.event.typ = .mouse_enter;
                        parent.callbacks.mouseNotifyCallBack(win, win.event.point, true);
                    }
                },
                os.WM_INPUT => if (win._winArgs.hold_mouse) {
                    todo("raw input", @src());
                },
                os.WM_LBUTTONDOWN => {
                    win.event.button = .left;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = true;
                    win.event.typ = .mouse_button_pressed;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, true);
                },
                os.WM_RBUTTONDOWN => {
                    win.event.button = .right;
                    win.event.typ = .mouse_button_pressed;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = true;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, true);
                },
                os.WM_MBUTTONDOWN => {
                    win.event.button = .middle;
                    win.event.typ = .mouse_button_pressed;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = true;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, true);
                },
                os.WM_MOUSEWHEEL => {
                    win.event.button = if (msg.wParam > 0) .scroll_up else .scroll_down;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = true;
                    win.event.scroll = @as(f64, @floatFromInt(os.HIWORD(msg.wParam))) / 120.0;
                    win.event.typ = .mouse_button_pressed;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, true);
                },
                os.WM_LBUTTONUP => {
                    win.event.button = .left;
                    win.event.typ = .mouse_button_released;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = false;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, false);
                },
                os.WM_RBUTTONUP => {
                    win.event.button = .right;
                    win.event.typ = .mouse_button_released;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = false;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, false);
                },
                os.WM_MBUTTONUP => {
                    win.event.button = .middle;
                    win.event.typ = .mouse_button_released;
                    common.mouseButtons.getPtr(win.event.button).prev = common.mouseButtons.get(win.event.button).current;
                    common.mouseButtons.getPtr(win.event.button).current = false;
                    parent.callbacks.mouseButtonCallback(win, win.event.button, win.event.scroll, false);
                },
                os.WM_DROPFILES => {
                    // win.event.typ = @as(u32, @bitCast(RGFW_dnd_init));
                    // drop.static = @as(HDROP, @ptrFromInt(msg.wParam));
                    // var pt: POINT = undefined;
                    // _ = &pt;
                    // _ = DragQueryPoint(drop.static, &pt);
                    // win.event.point.x = @as(i32, @bitCast(@as(c_int, @truncate(pt.x))));
                    // win.event.point.y = @as(i32, @bitCast(@as(c_int, @truncate(pt.y))));
                    // RGFW_dndInitCallback.?(win, win.event.point);
                },
                os.WM_GETMINMAXINFO => if (win.src.maxSize.w != 0 or win.src.maxSize.h != 0) {
                    const mmi: *os.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(msg.lParam)));
                    mmi.ptMinTrackSize.x = @bitCast(win.src.minSize.w);
                    mmi.ptMinTrackSize.y = @bitCast(win.src.minSize.h);
                    mmi.ptMaxTrackSize.x = @bitCast(win.src.maxSize.w);
                    mmi.ptMaxTrackSize.y = @bitCast(win.src.maxSize.h);
                    return null;
                },
                else => win.event.typ = .none,
            }
            _ = os.TranslateMessage(&msg);
            _ = os.DispatchMessageA(&msg);
        } else {
            win.event.typ = .none;
        }

        if (os.IsWindow(win.src.window) == 0) {
            win.event.typ = .quit;
            parent.callbacks.windowQuitCallback(win);
        }

        return if (win.event.typ != .none) &win.event else null;
    }

    pub fn eventWait(_: *Window, wait: parent.Wait) void {
        _ = os.MsgWaitForMultipleObjects(0, null, 0, @intCast(@as(i32, @intFromEnum(wait)) * 1000), os.QS_ALLINPUT);
    }

    pub fn close(win: *Window, allocator: std.mem.Allocator) void {
        if (win == common.root) {
            if (RGFW_XInput_dll != null) {
                _ = os.FreeLibrary(RGFW_XInput_dll);
                RGFW_XInput_dll = null;
            }
            if (wglinstance != null) {
                _ = os.FreeLibrary(wglinstance);
                wglinstance = null;
            }
            common.root = null;
        }

        _ = os.wglDeleteContext(win.src.ctx);
        _ = os.DeleteDC(win.src.hdc);
        _ = os.DestroyWindow(win.src.window);

        for (0..parent.max_drops) |i| {
            allocator.free(win.event.droppedFiles[i]);
        }
        allocator.free(win.event.droppedFiles);

        allocator.destroy(win);
    }

    pub fn init(win: *Window, name: [:0]const u8, args: parent.WindowOptions) void {
        if (RGFW_XInput_dll == null) loadXInput();
        if (wglinstance == null) wglinstance = os.LoadLibraryA("opengl32.dll");

        common.eventWindow.r = .{ .x = -1, .y = -1, .w = -1, .h = -1 };
        common.eventWindow.src.window = null;

        win.src.maxSize = .{ .w = 0, .h = 0 };
        win.src.minSize = .{ .w = 0, .h = 0 };

        const inh = os.GetModuleHandleA(null) orelse unreachable;

        const class = os.WNDCLASSEXA{
            .lpszClassName = name,
            .hInstance = inh,
            .hCursor = os.LoadCursorA(null, os.IDC_ARROW),
            .lpfnWndProc = WndProc,
        };
        _ = os.RegisterClassExA(&class);

        var window_style: os.DWORD = os.WS_CLIPSIBLINGS | os.WS_CLIPCHILDREN;
        var windowRect: os.RECT = undefined;
        var clientRect: os.RECT = undefined;

        if (!args.no_border) {
            window_style |= os.WS_CAPTION | os.WS_SYSMENU | os.WS_BORDER | os.WS_MINIMIZEBOX;

            if (!args.no_resize) {
                window_style |= os.WS_SIZEBOX | os.WS_MAXIMIZEBOX | os.WS_THICKFRAME;
            }
        } else {
            window_style |= os.WS_POPUP | os.WS_VISIBLE | os.WS_SYSMENU | os.WS_MINIMIZEBOX;
        }

        const dummyWin = os.CreateWindowExA(
            0,
            class.lpszClassName,
            name,
            window_style,
            win.r.x,
            win.r.y,
            win.r.w,
            win.r.h,
            null,
            null,
            inh,
            null,
        ) orelse unreachable;

        _ = os.GetWindowRect(dummyWin, &windowRect);
        _ = os.GetClientRect(dummyWin, &clientRect);

        win.src.hOffset = @intCast((windowRect.bottom - windowRect.top) - (clientRect.bottom - clientRect.top));
        win.src.window = os.CreateWindowExA(
            0,
            class.lpszClassName,
            name,
            window_style,
            win.r.x,
            win.r.y,
            win.r.w,
            win.r.h +% @as(i32, @intCast(win.src.hOffset)),
            null,
            null,
            inh,
            null,
        );

        if (args.allow_dnd) {
            win._winArgs.allow_dnd = true;
            // RGFW_window_setDND(win, true);
            todo("set dnd", @src());
        }
        win.src.hdc = os.GetDC(win.src.window) orelse unreachable;

        if (!args.no_init_api) {
            const dummy_dc = os.GetDC(dummyWin) orelse unreachable;

            var pfd_flags: u32 = os.PFD_DRAW_TO_WINDOW | os.PFD_SUPPORT_OPENGL;
            pfd_flags |= os.PFD_DOUBLEBUFFER;

            var pfd = os.PIXELFORMATDESCRIPTOR{
                .nVersion = 1,
                .dwFlags = pfd_flags,
                .cColorBits = 24,
                .cAlphaBits = 8,
                .cDepthBits = 32,
                .cStencilBits = 8,
            };

            const pixel_format = os.ChoosePixelFormat(dummy_dc, &pfd);
            _ = os.SetPixelFormat(dummy_dc, pixel_format, &pfd);

            const dummy_context = os.wglCreateContext(dummy_dc);
            _ = os.wglMakeCurrent(dummy_dc, dummy_context);

            if (wglChoosePixelFormatARB == null) {
                wglCreateContextAttribsARB = @ptrCast(os.wglGetProcAddress("wglCreateContextAttribsARB"));
                wglChoosePixelFormatARB = @ptrCast(os.wglGetProcAddress("wglChoosePixelFormatARB"));
            }

            _ = os.wglMakeCurrent(dummy_dc, null);
            _ = os.wglDeleteContext(dummy_context);
            _ = os.ReleaseDC(dummyWin, dummy_dc);

            if (wglCreateContextAttribsARB != null) {
                pfd = os.PIXELFORMATDESCRIPTOR{
                    .nVersion = 1,
                    .dwFlags = pfd_flags,
                    .cColorBits = 32,
                    .cRedBits = 8,
                    .cGreenBits = 24,
                    .cGreenShift = 8,
                };

                if (args.opengl_software) {
                    pfd.dwFlags |= os.PFD_GENERIC_FORMAT | os.PFD_GENERIC_ACCELERATED;
                }

                if (wglChoosePixelFormatARB != null) {
                    const pixel_format_attribs = initFormatAttribs;

                    var pixel_format_1: i32 = undefined;
                    var num_formats: u32 = undefined;
                    _ = wglChoosePixelFormatARB.?(win.src.hdc, @ptrCast(pixel_format_attribs), null, 1, @ptrCast(&pixel_format_1), @ptrCast(&num_formats));
                    if (num_formats == 0) {
                        std.debug.print("Failed to create a pixel format for WGL.\n", .{});
                    }

                    _ = os.DescribePixelFormat(win.src.hdc, pixel_format_1, @sizeOf(os.PIXELFORMATDESCRIPTOR), @ptrCast(&pfd));
                    if (os.SetPixelFormat(win.src.hdc, pixel_format_1, &pfd) == 0) {
                        std.debug.print("Failed to set the WGL pixel format.\n", .{});
                    }
                }

                const profile_mask = switch (gl.info.profile orelse comptime unreachable) {
                    .core => WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                    .compatibility => WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB,
                    else => comptime unreachable,
                };

                const ctx_attribs = [_]i32{
                    WGL_CONTEXT_PROFILE_MASK_ARB,  profile_mask,
                    WGL_CONTEXT_MAJOR_VERSION_ARB, gl.info.version_major,
                    WGL_CONTEXT_MINOR_VERSION_ARB, gl.info.version_minor,
                    0,
                };

                win.src.ctx = wglCreateContextAttribsARB.?(win.src.hdc, null, &ctx_attribs) orelse unreachable;
            } else {
                std.debug.print("Failed to create an accelerated OpenGL Context\n", .{});

                const pixel_format_ = os.ChoosePixelFormat(win.src.hdc, &pfd);
                _ = os.SetPixelFormat(win.src.hdc, pixel_format_, &pfd);

                win.src.ctx = os.wglCreateContext(win.src.hdc) orelse unreachable;
            }

            _ = os.wglMakeCurrent(win.src.hdc, win.src.ctx);
        }

        if (!args.no_init_api) {
            _ = os.ReleaseDC(win.src.window, win.src.hdc);
            win.src.hdc = os.GetDC(win.src.window) orelse unreachable;
            _ = os.wglMakeCurrent(win.src.hdc, win.src.ctx);

            std.debug.assert(gl_procs.init(getProcAddress));
        }

        _ = os.DestroyWindow(dummyWin);

        if (args.scale_to_monitor) {
            win.scaleToMonitor();
        }

        if (args.center) {
            const screenR = parent.getScreenSize();
            win.move(.{ .x = @intCast((screenR.w - @as(u32, @intCast(win.r.w))) / 2), .y = @intCast((screenR.h - @as(u32, @intCast(win.r.h))) / 2) });
        }

        if (args.hide_mouse) {
            win.showMouse(false);
        }

        _ = os.ShowWindow(win.src.window, os.SW_SHOWNORMAL);

        if (common.root == null) {
            common.root = win;
        } else {
            // _ = wglShareLists(RGFW_root.src.ctx, win.src.ctx);
            unreachable;
        }
    }

    pub fn move(win: *Window) void {
        _ = os.SetWindowPos(win.src.window, null, win.r.x, win.r.y, 0, 0, os.SWP_NOSIZE);
    }

    pub fn resize(win: *Window) void {
        _ = os.SetWindowPos(win.src.window, null, 0, 0, win.r.w, @bitCast(@as(u32, @intCast(win.r.h)) +% win.src.hOffset), os.SWP_NOMOVE);
    }

    pub fn minimize(win: *Window) void {
        _ = os.ShowWindow(win.src.window, os.SW_MINIMIZE);
    }

    pub fn restore(win: *Window) void {
        _ = os.ShowWindow(win.src.window, os.SW_RESTORE);
    }

    pub fn setBorder(win: *Window, border: bool) void {
        const style = os.GetWindowLongA(win.src.window, os.GWL_STYLE);

        if (border) {
            _ = os.SetWindowLongA(win.src.window, os.GWL_STYLE, style | os.WS_OVERLAPPEDWINDOW);
            _ = os.SetWindowPos(win.src.window, null, 0, 0, 0, 0, os.SWP_NOZORDER | os.SWP_FRAMECHANGED | os.SWP_SHOWWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE);
        } else {
            _ = os.SetWindowLongA(win.src.window, os.GWL_STYLE, style & ~@as(i32, os.WS_OVERLAPPEDWINDOW));
            _ = os.SetWindowPos(win.src.window, null, 0, 0, 0, 0, os.SWP_NOZORDER | os.SWP_FRAMECHANGED | os.SWP_SHOWWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE);
        }
    }

    pub fn setDND(win: *Window, allow: bool) void {
        os.DragAcceptFiles(win.src.window, @intFromBool(allow));
    }

    pub fn setName(win: *Window, name: [:0]const u8) void {
        _ = os.SetWindowTextA(win.src.window, name);
    }

    pub fn setIcon(win: *Window, src: []const u8, a: Area, _: i32) void {
        const handle = loadHandleImage(win, src, a, true);

        _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HICON, @bitCast(@intFromPtr(handle)));
        _ = os.DestroyIcon(handle);
    }

    pub fn setMouse(win: *Window, image: []const u8, a: Area, _: i32) void {
        const cursor: os.HCURSOR = @ptrCast(loadHandleImage(win, image, a, false));

        _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HCURSOR, @bitCast(@intFromPtr(cursor)));
        _ = os.SetCursor(cursor);
        _ = os.DestroyCursor(cursor);
    }

    pub fn setMouseStandard(win: *Window, mouse: parent.MouseIcons) void {
        const icon = os.MAKEINTRESOURCEA(mouseIconSrc[@intFromEnum(mouse)]);

        _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HCURSOR, @bitCast(@intFromPtr(os.LoadCursorA(null, icon))));
        _ = os.SetCursor(os.LoadCursorA(null, icon));
    }

    pub fn hide(win: *Window) void {
        _ = os.ShowWindow(win.src.window, os.SW_HIDE);
    }

    pub fn show(win: *Window) void {
        _ = os.ShowWindow(win.src.window, os.SW_RESTORE);
    }

    pub fn getMousePoint(win: *Window) Point {
        var p: os.POINT = undefined;
        _ = os.GetCursorPos(&p);
        _ = os.ScreenToClient(win.src.window orelse unreachable, &p);

        return .{ .x = p.x, .y = p.y };
    }

    pub fn moveMouse(_: *Window, p: Point) void {
        _ = os.SetCursorPos(p.x, p.y);
    }

    pub fn isFullscreen(win: *Window) bool {
        var placement = os.WINDOWPLACEMENT{};
        _ = os.GetWindowPlacement(win.src.window, &placement);
        return placement.showCmd == os.SW_SHOWMAXIMIZED;
    }

    pub fn isHidden(win: *Window) bool {
        return os.IsWindowVisible(win.src.window) == 0 and !isMinimized(win);
    }

    pub fn isMinimized(win: *Window) bool {
        var placement = os.WINDOWPLACEMENT{};
        _ = os.GetWindowPlacement(win.src.window, &placement);
        return placement.showCmd == os.SW_SHOWMINIMIZED;
    }

    pub fn isMaximized(win: *Window) bool {
        var placement = os.WINDOWPLACEMENT{};
        _ = os.GetWindowPlacement(win.src.window, &placement);
        return placement.showCmd == os.SW_SHOWMAXIMIZED;
    }

    pub fn getMonitor(win: *Window) Monitor {
        const src = os.MonitorFromWindow(win.src.window, os.MONITOR_DEFAULTTOPRIMARY);
        return monitor.CreateMonitor(src);
    }

    pub fn swapBuffers(win: *Window) void {
        if (!win._winArgs.no_cpu_render) {}

        if (!win._winArgs.no_gpu_render) {
            _ = os.SwapBuffers(win.src.hdc);
        }
    }

    pub fn swapInterval(_: *Window, interval: i32) void {
        const PFNWGLSWAPINTERVALEXTPROC = ?*const fn (i32) callconv(.C) os.BOOL;

        const wglSwapIntervalEXT = struct {
            var static: PFNWGLSWAPINTERVALEXTPROC = null;
        };

        const loadSwapFunc = struct {
            var static: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(@as(c_int, 1)));
        };

        if (loadSwapFunc.static == null) {
            std.debug.print("wglSwapIntervalEXT not supported\n", .{});
            return;
        }

        if (wglSwapIntervalEXT.static == null) {
            loadSwapFunc.static = @ptrCast(os.wglGetProcAddress("wglSwapIntervalEXT"));
            wglSwapIntervalEXT.static = @ptrCast(@alignCast(loadSwapFunc.static));
        }

        if (wglSwapIntervalEXT.static.?(interval) == 0) {
            std.debug.print("Failed to set swap interval\n", .{});
        }
    }
};

pub fn getProcAddress(procname: [*c]const u8) ?*anyopaque {
    const proc: ?*anyopaque = os.wglGetProcAddress(procname);
    if (proc != null) return proc;

    return os.GetProcAddress(wglinstance, procname);
}

fn todo(msg: []const u8, loc: std.builtin.SourceLocation) void {
    std.debug.print("TODO: {s} '{s}' ({s}:{})\n", .{ msg, loc.fn_name, loc.file, loc.line });
}

pub fn getScreenSize() Area {
    return .{
        .w = @intCast(os.GetDeviceCaps(os.GetDC(null), os.HORZRES)),
        .h = @intCast(os.GetDeviceCaps(os.GetDC(null), os.VERTRES)),
    };
}

pub fn stopCheckEvents() void {
    _ = os.PostMessageA(common.root.?.src.window, 0, 0, 0);
}

pub fn getGlobalMousePoint() Point {
    var p: os.POINT = undefined;
    _ = os.GetCursorPos(&p);
    return .{ .x = p.x, .y = p.y };
}

pub fn makeCurrent_OpenGL(win: *Window) void {
    _ = os.wglMakeCurrent(win.src.hdc, win.src.ctx);
    gl.makeProcTableCurrent(&gl_procs);
}

pub fn captureCursor(win: *Window, _: Rect) void {
    var clipRect: os.RECT = undefined;
    _ = os.GetClientRect(win.src.window, &clipRect);
    _ = os.ClientToScreen(win.src.window, @ptrCast(&clipRect.left));
    _ = os.ClientToScreen(win.src.window, @ptrCast(&clipRect.right));
    _ = os.ClipCursor(&clipRect);

    const id = os.RAWINPUTDEVICE{
        .usUsagePage = 0x01,
        .usUsage = 0x02,
        .dwFlags = 0,
        .hwndTarget = win.src.window,
    };

    _ = os.RegisterRawInputDevices(@ptrCast(&id), 1, @sizeOf(os.RAWINPUTDEVICE));
}

pub fn releaseCursor(_: *Window) void {
    _ = os.ClipCursor(null);
    const id = os.RAWINPUTDEVICE{
        .usUsagePage = 0x01,
        .usUsage = 0x02,
        .dwFlags = 0x01,
        .hwndTarget = null,
    };
    _ = os.RegisterRawInputDevices(@ptrCast(&id), 1, @sizeOf(os.RAWINPUTDEVICE));
}

pub const time = struct {
    var frequency = os.LARGE_INTEGER{ .QuadPart = 0 };

    pub fn getTime() u64 {
        const freq = initTimer();

        var counter: os.LARGE_INTEGER = undefined;
        _ = os.QueryPerformanceCounter(&counter);
        return @intFromFloat(@as(f64, @floatFromInt(counter.QuadPart)) / @as(f64, @floatFromInt(freq.QuadPart)));
    }

    pub fn getTimeNS() u64 {
        const freq = initTimer();

        var counter: os.LARGE_INTEGER = undefined;
        _ = os.QueryPerformanceCounter(&counter);

        return @as(u64, @intFromFloat((@as(f64, @floatFromInt(counter.QuadPart)) * 1e9) / @as(f64, @floatFromInt(freq.QuadPart))));
    }

    pub fn sleep(ms: u64) void {
        os.Sleep(@truncate(ms));
    }

    fn initTimer() os.LARGE_INTEGER {
        if (frequency.QuadPart == 0) {
            _ = os.timeBeginPeriod(1);
            _ = os.QueryPerformanceFrequency(&frequency);
        }

        return frequency;
    }
};

pub const monitor = struct {
    const MonitorInfo = struct { iIndex: u32 = 0, hMonitor: ?os.HMONITOR = null };

    pub fn get() []const Monitor {
        var info = MonitorInfo{ .iIndex = 0, .hMonitor = undefined };

        while (os.EnumDisplayMonitors(null, null, GetMonitorHandle, @bitCast(@intFromPtr(&info))) != 0) {}

        return &common.monitors;
    }

    pub fn primary() Monitor {
        return CreateMonitor(os.MonitorFromPoint(.{}, os.MONITOR_DEFAULTTOPRIMARY));
    }

    fn GetMonitorByHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
        const info: *MonitorInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));
        if (info.hMonitor == hMonitor) return 0;

        info.iIndex += 1;
        return 1;
    }

    fn CreateMonitor(src: ?os.HMONITOR) Monitor {
        var mon: Monitor = undefined;
        var minfo = os.MONITORINFO{};

        _ = os.GetMonitorInfoA(src, &minfo);

        var info = MonitorInfo{ .hMonitor = src };

        if (os.EnumDisplayMonitors(null, null, &GetMonitorByHandle, @bitCast(@intFromPtr(&info))) != 0) {
            var dd = os.DISPLAY_DEVICEA{};

            var deviceIndex: u32 = 0;
            while (os.EnumDisplayDevicesA(null, deviceIndex, &dd, 0) != 0) : (deviceIndex += 1) {
                const deviceName = dd.DeviceName;

                if (os.EnumDisplayDevicesA(@ptrCast(&deviceName), info.iIndex, &dd, 0) != 0) {
                    @memcpy(mon.name[0..32], dd.DeviceName[0..]);
                    break;
                }
            }
        }

        mon.rect.x = minfo.rcWork.left;
        mon.rect.y = minfo.rcWork.top;
        mon.rect.w = minfo.rcWork.right - minfo.rcWork.left;
        mon.rect.h = minfo.rcWork.bottom - minfo.rcWork.top;

        const hdc = os.GetDC(null);

        const ppiX: f32 = @floatFromInt(os.GetDeviceCaps(hdc, os.LOGPIXELSX));
        const ppiY: f32 = @floatFromInt(os.GetDeviceCaps(hdc, os.LOGPIXELSY));
        _ = os.ReleaseDC(null, hdc);

        mon.phys[0] = @as(f32, @floatFromInt(os.GetSystemMetrics(os.SM_CYSCREEN))) / ppiX;
        mon.phys[1] = @as(f32, @floatFromInt(os.GetSystemMetrics(os.SM_CXSCREEN))) / ppiY;

        return mon;
    }

    fn GetMonitorHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
        const info: *MonitorInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));

        if (info.iIndex >= 6) return 0;

        common.monitors[info.iIndex] = CreateMonitor(hMonitor);
        info.iIndex += 1;

        return 1;
    }
};
