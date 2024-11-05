const std = @import("std");
const os = @import("winapi.zig");

pub const gl = @import("gl");

pub const EventType = enum {
    none,
    key_pressed,
    key_released,
    mouse_button_pressed,
    mouse_button_released,
    mouse_pos_changed,
    js_button_pressed,
    js_button_released,
    js_axis_move,
    window_moved,
    window_resized,
    focus_in,
    focus_out,
    mouse_enter,
    mouse_leave,
    window_refresh,
    quit,
    dnd,
    dnd_init,
};

pub const RGFW_joystick_codes = u8;
pub const RGFW_JS_A: c_int = 0;
pub const RGFW_JS_B: c_int = 1;
pub const RGFW_JS_Y: c_int = 2;
pub const RGFW_JS_X: c_int = 3;
pub const RGFW_JS_START: c_int = 9;
pub const RGFW_JS_SELECT: c_int = 8;
pub const RGFW_JS_HOME: c_int = 10;
pub const RGFW_JS_UP: c_int = 13;
pub const RGFW_JS_DOWN: c_int = 14;
pub const RGFW_JS_LEFT: c_int = 15;
pub const RGFW_JS_RIGHT: c_int = 16;
pub const RGFW_JS_L1: c_int = 4;
pub const RGFW_JS_L2: c_int = 5;
pub const RGFW_JS_R1: c_int = 6;
pub const RGFW_JS_R2: c_int = 7;

var gl_procs: gl.ProcTable = undefined;

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,
};
pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
};
pub const Area = struct {
    w: u32 = 0,
    h: u32 = 0,
};

pub const Monitor = struct {
    name: [128]u8,
    rect: Rect,
    scaleX: f32,
    scaleY: f32,
    physW: f32,
    physH: f32,
};

pub fn getMonitors() []const Monitor {
    var info = RGFW_mInfo{ .iIndex = 0, .hMonitor = undefined };

    while (os.EnumDisplayMonitors(null, null, GetMonitorHandle, @bitCast(@intFromPtr(&info))) != 0) {}

    return &RGFW_monitors;
}

pub fn getPrimaryMonitor() Monitor {
    return win32CreateMonitor(os.MonitorFromPoint(.{}, os.MONITOR_DEFAULTTOPRIMARY));
}

// TODO turn into union
pub const Event = struct {
    keyName: [16]u8,
    droppedFiles: [][]u8,
    droppedFilesCount: u32,
    typ: EventType,
    point: Point = .{},
    keyCode: u8,
    repeat: bool,
    inFocus: bool,
    lockState: u8,
    button: u8,
    scroll: f64,
    joystick: u16,
    axisesCount: u8,
    axis: [2]Point,
    frameTime: u64,
    frameTime2: u64,
};

pub const WindowSrc = struct {
    window: ?os.HWND,
    hdc: os.HDC,
    hOffset: u32,
    ctx: os.HGLRC,
    maxSize: Area,
    minSize: Area,
};

pub const Window = struct {
    src: WindowSrc,
    userPtr: ?*anyopaque,
    event: Event,
    r: Rect,
    _lastMousePoint: Point,
    _winArgs: WindowOptions,
};

pub fn setClassName(name: [:0]const u8) void {
    RGFW_className = name;
}

pub fn setBufferSize(size: Area) void {
    RGFW_bufferSize = size;
}

fn todo(msg: []const u8, loc: std.builtin.SourceLocation) void {
    std.debug.print("TODO: {s} '{s}' ({s}:{})\n", .{ msg, loc.fn_name, loc.file, loc.line });
}

var wglinstance: ?os.HMODULE = null;
var RGFW_XInput_dll: ?os.HMODULE = null;

var RGFW_eventWindow: Window = undefined;

const WglChoosePixelFormatARB = ?*const fn (?os.HDC, [*c]const i32, [*c]const f32, u32, [*c]i32, [*c]u32) callconv(os.WINAPI) i32;
var wglChoosePixelFormatARB: WglChoosePixelFormatARB = null;

const WglCreateContextAttribsARB = ?*const fn (?os.HDC, ?os.HGLRC, [*c]const i32) callconv(os.WINAPI) ?os.HGLRC;
var wglCreateContextAttribsARB: WglCreateContextAttribsARB = null;

pub fn createWindow(allocator: std.mem.Allocator, name: [:0]const u8, rect: Rect, args: WindowOptions) !*Window {
    if (RGFW_XInput_dll == null) loadXInput();
    if (wglinstance == null) wglinstance = os.LoadLibraryA("opengl32.dll");

    RGFW_eventWindow.r = .{ .x = -1, .y = -1, .w = -1, .h = -1 };
    RGFW_eventWindow.src.window = null;

    const win = try RGFW_window_basic_init(allocator, rect, args);

    win.src.maxSize = .{ .w = 0, .h = 0 };
    win.src.minSize = .{ .w = 0, .h = 0 };

    const inh = os.GetModuleHandleA(null) orelse unreachable;

    if (RGFW_className == null) RGFW_className = name;
    const class = os.WNDCLASSEXA{
        .lpszClassName = RGFW_className.?,
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
                const pixel_format_attribs = RGFW_initFormatAttribs(args.opengl_software);

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
    RGFW_init_buffer(win);

    if (args.scale_to_monitor) {
        window_scaleToMonitor(win);
    }

    if (args.center) {
        const screenR = getScreenSize();
        window_move(win, .{ .x = @intCast((screenR.w - @as(u32, @intCast(win.r.w))) / 2), .y = @intCast((screenR.h - @as(u32, @intCast(win.r.h))) / 2) });
    }

    if (args.hide_mouse) {
        // RGFW_window_showMouse(win, 0);
        todo("hide mouse", @src());
    }

    _ = os.ShowWindow(win.src.window, os.SW_SHOWNORMAL);

    if (RGFW_root == null) {
        RGFW_root = win;
    } else {
        // _ = wglShareLists(RGFW_root.src.ctx, win.src.ctx);
        unreachable;
    }

    return win;
}

pub fn getScreenSize() Area {
    return .{
        .w = @intCast(os.GetDeviceCaps(os.GetDC(null), os.HORZRES)),
        .h = @intCast(os.GetDeviceCaps(os.GetDC(null), os.VERTRES)),
    };
}

pub fn window_checkEvent(win: *Window) ?*Event {
    if (win.event.typ == .quit) return null;

    var msg: os.MSG = undefined;

    if (RGFW_eventWindow.src.window == win.src.window) {
        if (RGFW_eventWindow.r.x != -1) {
            win.r.x = RGFW_eventWindow.r.x;
            win.r.y = RGFW_eventWindow.r.y;
            win.event.typ = .window_moved;
            RGFW_windowMoveCallback(win, win.r);
        }
        if (RGFW_eventWindow.r.w != -1) {
            win.r.w = RGFW_eventWindow.r.w;
            win.r.h = RGFW_eventWindow.r.h;
            win.event.typ = .window_resized;
            RGFW_windowResizeCallback(win, win.r);
        }
        RGFW_eventWindow.src.window = null;
        RGFW_eventWindow.r = .{ .x = -1, .y = -1, .w = -1, .h = -1 };
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

    win.event.inFocus = os.GetForegroundWindow() == win.src.window;

    if (checkXInput(win, &win.event) != 0) return &win.event;

    const keyboardState = struct {
        var static: [256]u8 = .{0} ** 256;
    };

    if (os.PeekMessageA(&msg, win.src.window, 0, 0, os.PM_REMOVE) != 0) {
        switch (msg.message) {
            os.WM_CLOSE, os.WM_QUIT => {
                RGFW_windowQuitCallback(win);
                win.event.typ = .quit;
            },
            os.WM_ACTIVATE => {
                win.event.inFocus = os.LOWORD(msg.wParam) == os.WA_INACTIVE;

                if (win.event.inFocus) {
                    win.event.typ = .focus_in;
                    RGFW_focusCallback(win, true);
                } else {
                    win.event.typ = .focus_out;
                    RGFW_focusCallback(win, false);
                }
            },
            os.WM_PAINT => {
                win.event.typ = .window_refresh;
                RGFW_windowRefreshCallback(win);
            },
            os.WM_MOUSELEAVE => {
                win.event.typ = .mouse_leave;
                win._winArgs.mouse_left = true;
                RGFW_mouseNotifyCallBack(win, win.event.point, false);
            },
            os.WM_KEYUP, os.WM_KEYDOWN => {
                win.event.keyCode = @truncate(RGFW_apiKeyCodeToRGFW(@truncate(msg.wParam)));

                RGFW_keyboard[win.event.keyCode].prev = isPressed(win, @enumFromInt(win.event.keyCode));

                const keyName = struct {
                    var static: [16]u8 = @import("std").mem.zeroes([16]u8);
                };

                _ = os.GetKeyNameTextA(@truncate(msg.lParam), @ptrCast(&keyName.static), 16);

                if ((os.GetKeyState(os.VK_CAPITAL) & 0x0001 == 0 and os.GetKeyState(os.VK_SHIFT) & 0x8000 == 0) or
                    (os.GetKeyState(os.VK_CAPITAL) & 0x0001 != 0 and os.GetKeyState(os.VK_SHIFT) & 0x8000 != 0))
                {
                    _ = os.CharLowerBuffA(@ptrCast(&keyName.static), 16);
                }

                RGFW_updateLockState(win, os.GetKeyState(os.VK_CAPITAL) & 0x0001 != 0, os.GetKeyState(os.VK_NUMLOCK) & 0x0001 != 0);

                win.event.keyName = keyName.static;

                if (isPressed(win, .shift_l)) {
                    _ = os.ToAscii(@truncate(msg.wParam), os.MapVirtualKeyA(@truncate(msg.wParam), os.MAPVK_VK_TO_CHAR), @ptrCast(&keyboardState.static), @alignCast(@ptrCast(&win.event.keyName)), 0);
                }

                win.event.typ = if (msg.message == os.WM_KEYUP) .key_released else .key_pressed;
                RGFW_keyboard[win.event.keyCode].current = msg.message == os.WM_KEYDOWN;
                RGFW_keyCallback(win, win.event.keyCode, std.mem.sliceTo(&win.event.keyName, 0), win.event.lockState, false);
            },
            os.WM_MOUSEMOVE => if (!win._winArgs.hold_mouse) {
                win.event.typ = .mouse_pos_changed;
                win.event.point.x = os.GET_X_LPARAM(msg.lParam);
                win.event.point.y = os.GET_Y_LPARAM(msg.lParam);
                RGFW_mousePosCallback(win, win.event.point);

                if (win._winArgs.mouse_left) {
                    win._winArgs.mouse_left = !win._winArgs.mouse_left;
                    win.event.typ = .mouse_enter;
                    RGFW_mouseNotifyCallBack(win, win.event.point, true);
                }
            },
            os.WM_INPUT => if (win._winArgs.hold_mouse) {
                todo("raw input", @src());
            },
            os.WM_LBUTTONDOWN => {
                win.event.button = 1;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = true;
                win.event.typ = .mouse_button_pressed;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, true);
            },
            os.WM_RBUTTONDOWN => {
                win.event.button = 3;
                win.event.typ = .mouse_button_pressed;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = true;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, true);
            },
            os.WM_MBUTTONDOWN => {
                win.event.button = 2;
                win.event.typ = .mouse_button_pressed;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = true;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, true);
            },
            os.WM_MOUSEWHEEL => {
                win.event.button = if (msg.wParam > 0) 4 else 5;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = true;
                win.event.scroll = @as(f64, @floatFromInt(os.HIWORD(msg.wParam))) / 120.0;
                win.event.typ = .mouse_button_pressed;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, true);
            },
            os.WM_LBUTTONUP => {
                win.event.button = 1;
                win.event.typ = .mouse_button_released;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = false;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, false);
            },
            os.WM_RBUTTONUP => {
                win.event.button = 3;
                win.event.typ = .mouse_button_released;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = false;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, false);
            },
            os.WM_MBUTTONUP => {
                win.event.button = 2;
                win.event.typ = .mouse_button_released;
                RGFW_mouseButtons[win.event.button].prev = RGFW_mouseButtons[win.event.button].current;
                RGFW_mouseButtons[win.event.button].current = false;
                RGFW_mouseButtonCallback(win, win.event.button, win.event.scroll, false);
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
        RGFW_windowQuitCallback(win);
    }

    return if (win.event.typ != .none) &win.event else null;
}

pub const RGFW_eventWait = i32;
pub const RGFW_NEXT: c_int = -1;
pub const RGFW_NO_WAIT: c_int = 0;

pub fn window_eventWait(_: *Window, waitMS: i32) void {
    _ = os.MsgWaitForMultipleObjects(0, null, 0, @intCast(waitMS * 1000), os.QS_ALLINPUT);
}

pub fn RGFW_window_checkEvents(win: *Window, waitMS: i32) void {
    window_eventWait(win, waitMS);
    while ((window_checkEvent(win) != null) and !window_shouldClose(win)) {
        if (win.event.typ == .quit) return;
    }
}

pub fn RGFW_stopCheckEvents() void {
    _ = os.PostMessageA(RGFW_root.?.src.window, 0, 0, 0);
}

pub fn window_close(allocator: std.mem.Allocator, win: *Window) void {
    if (win == RGFW_root) {
        if (RGFW_XInput_dll != null) {
            _ = os.FreeLibrary(RGFW_XInput_dll);
            RGFW_XInput_dll = null;
        }
        if (wglinstance != null) {
            _ = os.FreeLibrary(wglinstance);
            wglinstance = null;
        }
        RGFW_root = null;
    }

    _ = os.wglDeleteContext(win.src.ctx);
    _ = os.DeleteDC(win.src.hdc);
    _ = os.DestroyWindow(win.src.window);

    for (0..max_drops) |i| {
        allocator.free(win.event.droppedFiles[i]);
    }
    allocator.free(win.event.droppedFiles);

    allocator.destroy(win);
}

pub fn window_move(win: *Window, v: Point) void {
    win.r.x = v.x;
    win.r.y = v.y;
    _ = os.SetWindowPos(win.src.window, null, win.r.x, win.r.y, 0, 0, os.SWP_NOSIZE);
}

pub fn window_moveToMonitor(win: *Window, m: Monitor) void {
    window_move(win, .{
        .x = m.rect.x + win.r.x,
        .y = m.rect.y + win.r.y,
    });
}

pub fn window_resize(win: *Window, a: Area) void {
    win.r.w = @intCast(a.w);
    win.r.h = @intCast(a.h);
    _ = os.SetWindowPos(win.src.window, null, 0, 0, win.r.w, @bitCast(@as(u32, @intCast(win.r.h)) +% win.src.hOffset), os.SWP_NOMOVE);
}

pub fn window_setMinSize(win: *Window, a: Area) void {
    win.src.minSize = a;
}

pub fn window_setMaxSize(win: *Window, a: Area) void {
    win.src.maxSize = a;
}

pub fn window_maximize(win: *Window) void {
    const screen = getScreenSize();
    window_move(win, .{});
    window_resize(win, screen);
}

pub fn window_minimize(win: *Window) void {
    _ = os.ShowWindow(win.src.window, os.SW_MINIMIZE);
}

pub fn window_restore(win: *Window) void {
    _ = os.ShowWindow(win.src.window, os.SW_RESTORE);
}

pub fn window_setBorder(win: *Window, border: bool) void {
    const style = os.GetWindowLongA(win.src.window, os.GWL_STYLE);

    if (border) {
        _ = os.SetWindowLongA(win.src.window, os.GWL_STYLE, style | os.WS_OVERLAPPEDWINDOW);
        _ = os.SetWindowPos(win.src.window, null, 0, 0, 0, 0, os.SWP_NOZORDER | os.SWP_FRAMECHANGED | os.SWP_SHOWWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE);
    } else {
        _ = os.SetWindowLongA(win.src.window, os.GWL_STYLE, style & ~@as(i32, os.WS_OVERLAPPEDWINDOW));
        _ = os.SetWindowPos(win.src.window, null, 0, 0, 0, 0, os.SWP_NOZORDER | os.SWP_FRAMECHANGED | os.SWP_SHOWWINDOW | os.SWP_NOMOVE | os.SWP_NOSIZE);
    }
}

pub fn window_setDND(win: *Window, allow: bool) void {
    os.DragAcceptFiles(win.src.window, @intFromBool(allow));
}

pub fn window_setName(win: *Window, name: [:0]const u8) void {
    _ = os.SetWindowTextA(win.src.window, name);
}

pub fn window_setIcon(win: *Window, src: []const u8, a: Area, _: i32) void {
    const handle = RGFW_loadHandleImage(win, src, a, true);

    _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HICON, @bitCast(@intFromPtr(handle)));
    _ = os.DestroyIcon(handle);
}

pub fn window_setMouse(win: *Window, image: []const u8, a: Area, _: i32) void {
    const cursor: os.HCURSOR = @ptrCast(RGFW_loadHandleImage(win, image, a, false));

    _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HCURSOR, @bitCast(@intFromPtr(cursor)));
    _ = os.SetCursor(cursor);
    _ = os.DestroyCursor(cursor);
}

pub fn window_setMouseStandard(win: *Window, mouse: MouseIcons) void {
    const icon = os.MAKEINTRESOURCEA(RGFW_mouseIconSrc[@intFromEnum(mouse)]);

    _ = os.SetClassLongPtrA(win.src.window, os.GCLP_HCURSOR, @bitCast(@intFromPtr(os.LoadCursorA(null, icon))));
    _ = os.SetCursor(os.LoadCursorA(null, icon));
}

pub fn window_setMouseDefault(win: *Window) void {
    window_setMouseStandard(win, .arrow);
}

/// Locks cursor to center of window
pub fn window_mouseHold(win: *Window, _: Area) void {
    if (win._winArgs.hold_mouse) return;

    win._winArgs.hide_mouse = true;
    captureCursor(win, win.r);
    window_moveMouse(win, .{ .x = win.r.x + @divTrunc(win.r.w, 2), .y = win.r.y + @divTrunc(win.r.h, 2) });
}

pub fn window_mouseUnhold(win: *Window) void {
    if (win._winArgs.hold_mouse) {
        win._winArgs.hold_mouse = false;
        releaseCursor(win);
    }
}

pub fn window_hide(win: *Window) void {
    _ = os.ShowWindow(win.src.window, os.SW_HIDE);
}

pub fn window_show(win: *Window) void {
    _ = os.ShowWindow(win.src.window, os.SW_RESTORE);
}

pub fn window_setShouldClose(win: *Window) void {
    win.event.typ = .quit;
    RGFW_windowQuitCallback(win);
}

pub fn getGlobalMousePoint() Point {
    var p: os.POINT = undefined;
    _ = os.GetCursorPos(&p);
    return .{ .x = p.x, .y = p.y };
}

pub fn window_getMousePoint(win: *Window) Point {
    var p: os.POINT = undefined;
    _ = os.GetCursorPos(&p);
    _ = os.ScreenToClient(win.src.window orelse unreachable, &p);

    return .{ .x = p.x, .y = p.y };
}

pub fn RGFW_window_showMouse(win: *Window, show: bool) void {
    if (show) {
        window_setMouseDefault(win);
    } else {
        window_setMouse(win, &.{ 0, 0, 0, 0 }, .{ .w = 1, .h = 1 }, 4);
    }
}

pub fn window_moveMouse(_: *Window, p: Point) void {
    _ = os.SetCursorPos(p.x, p.y);
}

pub fn window_shouldClose(win: *Window) bool {
    return win.event.typ == .quit or isPressed(win, .escape);
}

pub fn window_isFullscreen(win: *Window) bool {
    var placement = os.WINDOWPLACEMENT{};
    _ = os.GetWindowPlacement(win.src.window, &placement);
    return placement.showCmd == os.SW_SHOWMAXIMIZED;
}

pub fn window_isHidden(win: *Window) bool {
    return os.IsWindowVisible(win.src.window) == 0 and !window_isMinimized(win);
}

pub fn window_isMinimized(win: *Window) bool {
    var placement = os.WINDOWPLACEMENT{};
    _ = os.GetWindowPlacement(win.src.window, &placement);
    return placement.showCmd == os.SW_SHOWMINIMIZED;
}

pub fn window_isMaximized(win: *Window) bool {
    var placement = os.WINDOWPLACEMENT{};
    _ = os.GetWindowPlacement(win.src.window, &placement);
    return placement.showCmd == os.SW_SHOWMAXIMIZED;
}

pub fn window_scaleToMonitor(win: *Window) void {
    const monitor = window_getMonitor(win);
    window_resize(win, .{
        .w = @intFromFloat(monitor.scaleX * @as(f32, @floatFromInt(win.r.w))),
        .h = @intFromFloat(monitor.scaleX * @as(f32, @floatFromInt(win.r.h))),
    });
}

pub fn window_getMonitor(win: *Window) Monitor {
    const src = os.MonitorFromWindow(win.src.window, os.MONITOR_DEFAULTTOPRIMARY);
    return win32CreateMonitor(src);
}

/// returns true if the key should be shifted
pub fn shouldShift(keycode: u32, lockState: u8) bool {
    const help = struct {
        inline fn xor(x: bool, y: bool) bool {
            return (x and !y) or (y and !x);
        }
    };

    const caps4caps = (lockState & RGFW_CAPSLOCK != 0) and ((keycode >= @intFromEnum(Key.a)) and (keycode <= @intFromEnum(Key.z)));
    const should_shift = help.xor((RGFW_keyboard[@intFromEnum(Key.shift_l)].current or RGFW_keyboard[@intFromEnum(Key.shift_r)].current), caps4caps);

    return should_shift;
}

pub fn keyCodeToChar(keycode: u32, shift: bool) u8 {
    const map = [99]u8{
        0,    0,    0,    0,    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        '`',  '0',  '1',  '2',  '3', '4', '5', '6', '7', '8', '9', '-', '=', 0,
        '\t', 0,    0,    0,    0,   0,   0,   0,   0,   0,   ' ', 'a', 'b', 'c',
        'd',  'e',  'f',  'g',  'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q',
        'r',  's',  't',  'u',  'v', 'w', 'x', 'y', 'z', '.', ',', '/', '[', ']',
        ';',  '\n', '\'', '\\', 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        0,    '/',  '*',  '-',  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
        '\n',
    };

    const mapCaps = [99]u8{
        0,   0,    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        '~', ')',  '!', '@', '#', '$', '%', '^', '&', '*', '(', '_', '+', 0,
        '0', 0,    0,   0,   0,   0,   0,   0,   0,   0,   ' ', 'A', 'B', 'C',
        'D', 'E',  'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q',
        'R', 'S',  'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '>', '<', '?', '{', '}',
        ':', '\n', '"', '|', 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        0,   '?',  '*', '-', 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
        0,
    };

    return if (shift) mapCaps[keycode] else map[keycode];
}

pub fn keyCodeToCharAuto(keycode: u32, lockState: u8) u8 {
    return keyCodeToChar(keycode, shouldShift(keycode, lockState));
}

pub fn isPressed(win: *Window, key: Key) bool {
    return RGFW_keyboard[@intFromEnum(key)].current and win.event.inFocus;
}

pub fn wasPressed(win: *Window, key: Key) bool {
    return RGFW_keyboard[@intFromEnum(key)].prev and win.event.inFocus;
}

pub fn isHeld(win: *Window, key: Key) bool {
    return isPressed(win, key) and wasPressed(win, key);
}

pub fn isReleased(win: *Window, key: Key) bool {
    return !isPressed(win, key) and wasPressed(win, key);
}

pub fn isClicked(win: *Window, key: Key) bool {
    return wasPressed(win, key) and !isPressed(win, key);
}

pub fn isMousePressed(win: *Window, button: u8) bool {
    return RGFW_mouseButtons[button].current and win.event.inFocus;
}

pub fn wasMousePressed(win: *Window, button: u8) bool {
    return RGFW_mouseButtons[button].prev and win.event.inFocus;
}

pub fn isMouseHeld(win: *Window, button: u8) bool {
    return (isMousePressed(win, button) and wasMousePressed(win, button));
}

pub fn isMouseReleased(win: *Window, button: u8) bool {
    return (!isMousePressed(win, button) and wasMousePressed(win, button));
}

pub const RGFW_windowmovefunc = *const fn (*Window, Rect) void;
pub const RGFW_windowresizefunc = *const fn (*Window, Rect) void;
pub const RGFW_windowquitfunc = *const fn (*Window) void;
pub const RGFW_focusfunc = *const fn (*Window, bool) void;
pub const RGFW_mouseNotifyfunc = *const fn (*Window, Point, bool) void;
pub const RGFW_mouseposfunc = *const fn (*Window, Point) void;
pub const RGFW_dndInitfunc = *const fn (*Window, Point) void;
pub const RGFW_windowrefreshfunc = *const fn (*Window) void;
pub const RGFW_keyfunc = *const fn (*Window, u32, []u8, u8, bool) void;
pub const RGFW_mousebuttonfunc = *const fn (*Window, u8, f64, bool) void;
pub const RGFW_jsButtonfunc = *const fn (*Window, u16, u8, bool) void;
pub const RGFW_jsAxisfunc = *const fn (*Window, u16, []Point, u8) void;
pub const RGFW_dndfunc = *const fn (*Window, [][]u8, u32) void;

pub fn setWindowMoveCallback(func: RGFW_windowmovefunc) ?RGFW_windowmovefunc {
    const prev = if (RGFW_windowMoveCallback == RGFW_windowmovefuncEMPTY) null else RGFW_windowMoveCallback;
    RGFW_windowMoveCallback = func;
    return prev;
}

pub fn setWindowResizeCallback(func: RGFW_windowresizefunc) ?RGFW_windowresizefunc {
    const prev = if (RGFW_windowResizeCallback == RGFW_windowresizefuncEMPTY) null else RGFW_windowResizeCallback;
    RGFW_windowResizeCallback = func;
    return prev;
}

pub fn setWindowQuitCallback(func: RGFW_windowquitfunc) ?RGFW_windowquitfunc {
    const prev = if (RGFW_windowQuitCallback == RGFW_windowquitfuncEMPTY) null else RGFW_windowQuitCallback;
    RGFW_windowQuitCallback = func;
    return prev;
}

pub fn setMousePosCallback(func: RGFW_mouseposfunc) ?RGFW_mouseposfunc {
    const prev = if (RGFW_mousePosCallback == RGFW_mouseposfuncEMPTY) null else RGFW_mousePosCallback;
    RGFW_mousePosCallback = func;
    return prev;
}

pub fn setWindowRefreshCallback(func: RGFW_windowrefreshfunc) ?RGFW_windowrefreshfunc {
    const prev = if (RGFW_windowRefreshCallback == RGFW_windowrefreshfuncEMPTY) null else RGFW_windowRefreshCallback;
    RGFW_windowRefreshCallback = func;
    return prev;
}

pub fn setFocusCallback(func: RGFW_focusfunc) ?RGFW_focusfunc {
    const prev = if (RGFW_focusCallback == RGFW_focusfuncEMPTY) null else RGFW_focusCallback;
    RGFW_focusCallback = func;
    return prev;
}

pub fn setMouseNotifyCallBack(func: RGFW_mouseNotifyfunc) ?RGFW_mouseNotifyfunc {
    const prev = if (RGFW_mouseNotifyCallBack == RGFW_mouseNotifyfuncEMPTY) null else RGFW_mouseNotifyCallBack;
    RGFW_mouseNotifyCallBack = func;
    return prev;
}

pub fn setDndCallback(func: RGFW_dndfunc) ?RGFW_dndfunc {
    const prev = if (RGFW_dndCallback == RGFW_dndfuncEMPTY) null else RGFW_dndCallback;
    RGFW_dndCallback = func;
    return prev;
}

pub fn setDndInitCallback(func: RGFW_dndInitfunc) ?RGFW_dndInitfunc {
    const prev = if (RGFW_dndInitCallback == RGFW_dndInitfuncEMPTY) null else RGFW_dndInitCallback;
    RGFW_dndInitCallback = func;
    return prev;
}

pub fn setKeyCallback(func: RGFW_keyfunc) ?RGFW_keyfunc {
    const prev = if (RGFW_keyCallback == RGFW_keyfuncEMPTY) null else RGFW_keyCallback;
    RGFW_keyCallback = func;
    return prev;
}

pub fn setMouseButtonCallback(func: RGFW_mousebuttonfunc) ?RGFW_mousebuttonfunc {
    const prev = if (RGFW_mouseButtonCallback == RGFW_mousebuttonfuncEMPTY) null else RGFW_mouseButtonCallback;
    RGFW_mouseButtonCallback = func;
    return prev;
}

pub fn setjsButtonCallback(func: RGFW_jsButtonfunc) ?RGFW_jsButtonfunc {
    const prev = if (RGFW_jsButtonCallback == RGFW_jsButtonfuncEMPTY) null else RGFW_jsButtonCallback;
    RGFW_jsButtonCallback = func;
    return prev;
}

pub fn setjsAxisCallback(func: RGFW_jsAxisfunc) ?RGFW_jsAxisfunc {
    const prev = if (RGFW_jsAxisCallback == RGFW_jsAxisfuncEMPTY) null else RGFW_jsAxisCallback;
    RGFW_jsAxisCallback = func;
    return prev;
}

pub fn registerJoystick(win: *Window, _: i32) u16 {
    return registerJoystickF(win, "");
}

pub fn registerJoystickF(_: *Window, _: [:0]const u8) u16 {
    return RGFW_joystickCount - 1;
}

pub fn isPressedJS(_: *Window, controller: u16, button: u8) u32 {
    return RGFW_jsPressed[controller][button];
}

pub fn makeCurrent(win: *Window) void {
    makeCurrent_OpenGL(win);
}

pub fn window_checkFPS(win: *Window, fpsCap: u32) u32 {
    var deltaTime = getTimeNS() - win.event.frameTime;

    var output_fps: u32 = 0;
    const fps: u64 = @intFromFloat(@round(@as(f64, 1e9) / @as(f64, @floatFromInt(deltaTime))));
    output_fps = @truncate(fps);

    if (fpsCap != 0 and fps > fpsCap) {
        const frameTimeNS: u64 = @intFromFloat(1e+9 / @as(f64, @floatFromInt(fpsCap)));
        const sleepTimeMS: u64 = (frameTimeNS - deltaTime) / 1_000_000;

        if (sleepTimeMS > 0) {
            sleep(sleepTimeMS);
            win.event.frameTime = 0;
        }
    }

    win.event.frameTime = getTimeNS();

    if (fpsCap == 0) return output_fps;

    deltaTime = getTimeNS() - win.event.frameTime2;

    output_fps = @intFromFloat(@round(@as(f64, 1e+9) / @as(f64, @floatFromInt(deltaTime))));
    win.event.frameTime2 = getTimeNS();

    return output_fps;
}

pub fn window_swapBuffers(win: *Window) void {
    if (!win._winArgs.no_cpu_render) {}

    if (!win._winArgs.no_gpu_render) {
        _ = os.SwapBuffers(win.src.hdc);
    }
}

pub fn window_swapInterval(_: *Window, interval: i32) void {
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

pub fn getProcAddress(procname: [*c]const u8) ?*anyopaque {
    const proc: ?*anyopaque = os.wglGetProcAddress(procname);
    if (proc != null) return proc;

    return os.GetProcAddress(wglinstance, procname);
}

fn makeCurrent_OpenGL(win: *Window) void {
    _ = os.wglMakeCurrent(win.src.hdc, win.src.ctx);
    gl.makeProcTableCurrent(&gl_procs);
}

pub fn getTime() u64 {
    const frequency = RGFW_win32_initTimer();

    var counter: os.LARGE_INTEGER = undefined;
    _ = os.QueryPerformanceCounter(&counter);
    return @intFromFloat(@as(f64, @floatFromInt(counter.QuadPart)) / @as(f64, @floatFromInt(frequency.QuadPart)));
}

pub fn getTimeNS() u64 {
    const frequency = RGFW_win32_initTimer();

    var counter: os.LARGE_INTEGER = undefined;
    _ = os.QueryPerformanceCounter(&counter);

    return @as(u64, @intFromFloat((@as(f64, @floatFromInt(counter.QuadPart)) * 1e9) / @as(f64, @floatFromInt(frequency.QuadPart))));
}

pub fn sleep(ms: u64) void {
    os.Sleep(@truncate(ms));
}

pub const Key = enum(u8) {
    null = 0,
    escape = 1,
    f1 = 2,
    f2 = 3,
    f3 = 4,
    f4 = 5,
    f5 = 6,
    f6 = 7,
    f7 = 8,
    f8 = 9,
    f9 = 10,
    f10 = 11,
    f11 = 12,
    f12 = 13,
    backtick = 14,
    @"0" = 15,
    @"1" = 16,
    @"2" = 17,
    @"3" = 18,
    @"4" = 19,
    @"5" = 20,
    @"6" = 21,
    @"7" = 22,
    @"8" = 23,
    @"9" = 24,
    minus = 25,
    equals = 26,
    back_space = 27,
    tab = 28,
    caps_lock = 29,
    shift_l = 30,
    control_l = 31,
    alt_l = 32,
    super_l = 33,
    shift_r = 34,
    control_r = 35,
    alt_r = 36,
    super_r = 37,
    space = 38,
    a = 39,
    b = 40,
    c = 41,
    d = 42,
    e = 43,
    f = 44,
    g = 45,
    h = 46,
    i = 47,
    j = 48,
    k = 49,
    l = 50,
    m = 51,
    n = 52,
    o = 53,
    p = 54,
    q = 55,
    r = 56,
    s = 57,
    t = 58,
    u = 59,
    v = 60,
    w = 61,
    x = 62,
    y = 63,
    z = 64,
    period = 65,
    comma = 66,
    slash = 67,
    bracket = 68,
    close_bracket = 69,
    semicolon = 70,
    @"return" = 71,
    quote = 72,
    back_slash = 73,
    up = 74,
    down = 75,
    left = 76,
    right = 77,
    delete = 78,
    insert = 79,
    end = 80,
    home = 81,
    page_up = 82,
    page_down = 83,
    numlock = 84,
    kp_slash = 85,
    multiply = 86,
    kp_minus = 87,
    kp_1 = 88,
    kp_2 = 89,
    kp_3 = 90,
    kp_4 = 91,
    kp_5 = 92,
    kp_6 = 93,
    kp_7 = 94,
    kp_8 = 95,
    kp_9 = 96,
    kp_0 = 97,
    kp_period = 98,
    kp_return = 99,
};

pub const MouseIcons = enum(u8) {
    normal = 0,
    arrow = 1,
    ibeam = 2,
    crosshair = 3,
    pointing_hand = 4,
    resize_ew = 5,
    resize_ns = 6,
    resize_nwse = 7,
    resize_nesw = 8,
    resize_all = 9,
    not_allowed = 10,
};

var RGFW_keycodes: [337]Key = [337]Key{
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .back_space, .tab,       .null,       .null,    .null,      .@"return",     .null,      .null,
    .shift_l,    .control_l, .alt_l,      .null,    .caps_lock, .null,          .null,      .null,
    .null,       .null,      .null,       .escape,  .null,      .null,          .null,      .null,
    .space,      .null,      .null,       .end,     .home,      .left,          .up,        .right,
    .down,       .null,      .null,       .null,    .null,      .insert,        .delete,    .null,
    .@"0",       .@"1",      .@"2",       .@"3",    .@"4",      .@"5",          .@"6",      .@"7",
    .@"8",       .@"9",      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .a,         .b,          .c,       .d,         .e,             .f,         .g,
    .h,          .i,         .j,          .k,       .l,         .m,             .n,         .o,
    .p,          .q,         .r,          .s,       .t,         .u,             .v,         .w,
    .x,          .y,         .z,          .super_l, .null,      .null,          .null,      .null,
    .kp_0,       .kp_1,      .kp_2,       .kp_3,    .kp_4,      .kp_5,          .kp_6,      .kp_7,
    .kp_8,       .kp_9,      .multiply,   .null,    .null,      .kp_minus,      .kp_period, .kp_slash,
    .f1,         .f2,        .f3,         .f4,      .f5,        .f6,            .f7,        .f8,
    .f9,         .f10,       .f11,        .f12,     .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .numlock,    .null,      .kp_return,  .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .semicolon,  .equals,  .comma,     .minus,         .period,    .slash,
    .backtick,   .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .bracket, .null,      .close_bracket, .quote,     .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .null,       .null,      .back_slash, .null,    .null,      .page_down,     .null,      .null,
    .null,       .null,      .null,       .null,    .null,      .null,          .null,      .null,
    .page_up,
};

const RGFW_keyState = packed struct { current: bool = false, prev: bool = false };

var RGFW_keyboard: [100]RGFW_keyState = .{.{}} ** 100;

fn RGFW_apiKeyCodeToRGFW(keycode: u32) u32 {
    _ = std.meta.intToEnum(Key, keycode) catch return 0;
    return @intFromEnum(RGFW_keycodes[keycode]);
}

fn RGFW_resetKey() void {
    for (0..RGFW_keyboard.len) |i| {
        RGFW_keyboard[i].prev = false;
    }
}

var RGFW_jsPressed: [4][16]u8 = std.mem.zeroes([4][16]u8);
var RGFW_joysticks: [4]i32 = std.mem.zeroes([4]i32);
var RGFW_joystickCount: u16 = 0;

fn RGFW_windowmovefuncEMPTY(_: *Window, _: Rect) void {}
fn RGFW_windowresizefuncEMPTY(_: *Window, _: Rect) void {}
fn RGFW_windowquitfuncEMPTY(_: *Window) void {}
fn RGFW_focusfuncEMPTY(_: *Window, _: bool) void {}
fn RGFW_mouseNotifyfuncEMPTY(_: *Window, _: Point, _: bool) void {}
fn RGFW_mouseposfuncEMPTY(_: *Window, _: Point) void {}
fn RGFW_dndInitfuncEMPTY(_: *Window, _: Point) void {}
fn RGFW_windowrefreshfuncEMPTY(_: *Window) void {}
fn RGFW_keyfuncEMPTY(_: *Window, _: u32, _: []u8, _: u8, _: bool) void {}
fn RGFW_mousebuttonfuncEMPTY(_: *Window, _: u8, _: f64, _: bool) void {}
fn RGFW_jsButtonfuncEMPTY(_: *Window, _: u16, _: u8, _: bool) void {}
fn RGFW_jsAxisfuncEMPTY(_: *Window, _: u16, _: []Point, _: u8) void {}
fn RGFW_dndfuncEMPTY(_: *Window, _: [][]u8, _: u32) void {}

var RGFW_windowMoveCallback: RGFW_windowmovefunc = RGFW_windowmovefuncEMPTY;
var RGFW_windowResizeCallback: RGFW_windowresizefunc = RGFW_windowresizefuncEMPTY;
var RGFW_windowQuitCallback: RGFW_windowquitfunc = RGFW_windowquitfuncEMPTY;
var RGFW_mousePosCallback: RGFW_mouseposfunc = RGFW_mouseposfuncEMPTY;
var RGFW_windowRefreshCallback: RGFW_windowrefreshfunc = RGFW_windowrefreshfuncEMPTY;
var RGFW_focusCallback: RGFW_focusfunc = RGFW_focusfuncEMPTY;
var RGFW_mouseNotifyCallBack: RGFW_mouseNotifyfunc = RGFW_mouseNotifyfuncEMPTY;
var RGFW_dndCallback: RGFW_dndfunc = RGFW_dndfuncEMPTY;
var RGFW_dndInitCallback: RGFW_dndInitfunc = RGFW_dndInitfuncEMPTY;
var RGFW_keyCallback: RGFW_keyfunc = RGFW_keyfuncEMPTY;
var RGFW_mouseButtonCallback: RGFW_mousebuttonfunc = RGFW_mousebuttonfuncEMPTY;
var RGFW_jsButtonCallback: RGFW_jsButtonfunc = RGFW_jsButtonfuncEMPTY;
var RGFW_jsAxisCallback: RGFW_jsAxisfunc = RGFW_jsAxisfuncEMPTY;

var RGFW_bufferSize = Area{};

const max_drops = 260;
const max_path = 260;

pub fn RGFW_window_basic_init(allocator: std.mem.Allocator, rect: Rect, args: WindowOptions) !*Window {
    const win = try allocator.create(Window);

    win.event.droppedFiles = try allocator.alloc([]u8, max_drops);
    for (0..max_drops) |i| win.event.droppedFiles[i] = try allocator.alloc(u8, max_path);

    const screenR = getScreenSize();

    win.r = if (args.fullscreen)
        Rect{
            .x = 0,
            .y = 0,
            .w = @intCast(screenR.w),
            .h = @intCast(screenR.h),
        }
    else
        rect;

    win.event.inFocus = true;
    win.event.droppedFilesCount = 0;
    RGFW_joystickCount = 0;
    win._winArgs = .{};
    win.event.lockState = 0;

    return win;
}

var RGFW_root: ?*Window = null;
var RGFW_className: ?[:0]const u8 = null;

var RGFW_mouseButtons: [5]RGFW_keyState = .{.{}} ** 5;

fn captureCursor(win: *Window, _: Rect) void {
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

fn releaseCursor(_: *Window) void {
    _ = os.ClipCursor(null);
    const id = os.RAWINPUTDEVICE{
        .usUsagePage = 0x01,
        .usUsage = 0x02,
        .dwFlags = 0x01,
        .hwndTarget = null,
    };
    _ = os.RegisterRawInputDevices(@ptrCast(&id), 1, @sizeOf(os.RAWINPUTDEVICE));
}

const RGFW_CAPSLOCK = 1;
const RGFW_NUMLOCK = 2;

fn RGFW_updateLockState(win: *Window, capital: bool, numlock: bool) void {
    if (capital and win.event.lockState & RGFW_CAPSLOCK == 0)
        win.event.lockState |= RGFW_CAPSLOCK
    else if (!capital and win.event.lockState & RGFW_CAPSLOCK != 0)
        win.event.lockState ^= RGFW_CAPSLOCK;

    if (numlock and win.event.lockState & RGFW_NUMLOCK == 0)
        win.event.lockState |= RGFW_NUMLOCK
    else if (!numlock and win.event.lockState & RGFW_NUMLOCK != 0)
        win.event.lockState ^= RGFW_NUMLOCK;
}

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

const RGFW_mouseIconSrc = [11]u32{
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

var RGFWjoystickApi: ?*anyopaque = @as(?*anyopaque, @ptrFromInt(@as(c_int, 0)));

fn WndProc(hWnd: os.HWND, message: os.UINT, wParam: os.WPARAM, lParam: os.LPARAM) callconv(os.WINAPI) os.LRESULT {
    switch (message) {
        os.WM_MOVE => {
            RGFW_eventWindow.r.x = os.LOWORD(lParam);
            RGFW_eventWindow.r.y = os.HIWORD(lParam);
            RGFW_eventWindow.src.window = hWnd;
        },
        os.WM_SIZE => {
            RGFW_eventWindow.r.w = os.LOWORD(lParam);
            RGFW_eventWindow.r.h = os.HIWORD(lParam);
            RGFW_eventWindow.src.window = hWnd;
        },
        else => {},
    }

    return os.DefWindowProcA(hWnd, message, wParam, lParam);
}

var XInputGetStateSRC: ?*const fn (os.DWORD, *os.STATE) callconv(os.WINAPI) os.DWORD = null;
var XInputGetKeystrokeSRC: ?*const fn (os.DWORD, os.DWORD, *os.XINPUT_KEYSTROKE) callconv(os.WINAPI) os.DWORD = null;

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

pub fn RGFW_init_buffer(win: *Window) void {
    _ = win;
}

var RGFW_xinput2RGFW = [22]u8{
    RGFW_JS_A,
    RGFW_JS_B,
    RGFW_JS_X,
    RGFW_JS_Y,
    RGFW_JS_R1,
    RGFW_JS_L1,
    RGFW_JS_L2,
    RGFW_JS_R2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    RGFW_JS_UP,
    RGFW_JS_DOWN,
    RGFW_JS_LEFT,
    RGFW_JS_RIGHT,
    RGFW_JS_START,
    RGFW_JS_SELECT,
};

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
            e.button = RGFW_xinput2RGFW[keystroke.VirtualKey - 0x5800];
            RGFW_jsPressed[i][e.button] = @intFromBool(keystroke.Flags & os.XINPUT_KEYSTROKE_KEYDOWN == 0);

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

pub const RGFW_mInfo = struct {
    iIndex: u32,
    hMonitor: ?os.HMONITOR,
};

pub fn GetMonitorByHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
    const info: *RGFW_mInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));
    if (info.hMonitor == hMonitor) return 0;

    info.iIndex += 1;
    return 1;
}

fn win32CreateMonitor(src: ?os.HMONITOR) Monitor {
    var monitor: Monitor = undefined;
    var monitorInfo = os.MONITORINFO{};

    _ = os.GetMonitorInfoA(src, &monitorInfo);

    var info = RGFW_mInfo{ .iIndex = 0, .hMonitor = src };

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

var RGFW_monitors: [6]Monitor = @import("std").mem.zeroes([6]Monitor);

fn GetMonitorHandle(hMonitor: os.HMONITOR, _: os.HDC, _: *os.RECT, dwData: os.LPARAM) callconv(os.WINAPI) os.BOOL {
    const info: *RGFW_mInfo = @ptrFromInt(@as(usize, @bitCast(dwData)));

    if (info.iIndex >= 6) return 0;

    RGFW_monitors[info.iIndex] = win32CreateMonitor(hMonitor);
    info.iIndex += 1;

    return 1;
}

fn RGFW_loadHandleImage(_: *Window, src: []const u8, a: Area, icon: bool) os.HICON {
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

fn RGFW_win32_initTimer() os.LARGE_INTEGER {
    const frequency = struct {
        var static = os.LARGE_INTEGER{ .QuadPart = 0 };
    };

    if (frequency.static.QuadPart == 0) {
        _ = os.timeBeginPeriod(1);
        _ = os.QueryPerformanceFrequency(&frequency.static);
    }

    return frequency.static;
}

// pub const RGFW_ALPHA = @as(c_int, 128);

pub const WindowOptions = packed struct {
    /// the window doesn't have border
    no_border: bool = false,
    ///  the window cannot be resized  by the user
    no_resize: bool = false,
    /// the window supports drag and dro
    allow_dnd: bool = false,
    /// the window should hide the mouse or not (can be toggled later on) using `RGFW_window_mouseSho
    hide_mouse: bool = false,
    /// the window is fullscreen by default or not
    fullscreen: bool = false,
    /// center the window on the screen
    center: bool = false,
    /// use OpenGL software rendering
    opengl_software: bool = false,
    /// (cocoa only), move to resource folder
    cocoa_move_to_resource_dir: bool = false,
    /// scale the window to the screen
    scale_to_monitor: bool = false,
    /// DO not init an API (mostly for bindings, you should use ` no_api: bool = false, ` in C
    no_init_api: bool = false,
    /// don't render (using the GPU based API
    no_gpu_render: bool = false,
    /// don't render (using the CPU based buffer rendering
    no_cpu_render: bool = false,
    /// the window is hidden
    window_hide: bool = false,
    hold_mouse: bool = false,
    mouse_left: bool = false,
};

pub const RGFW_mouseLeft = 1;
pub const RGFW_mouseMiddle = 2;
pub const RGFW_mouseRight = 3;
pub const RGFW_mouseScrollUp = 4;
pub const RGFW_mouseScrollDown = 5;

pub const RGFW_HOLD_MOUSE = 1 << 2;
pub const RGFW_MOUSE_LEFT = 1 << 3;

test {
    @setEvalBranchQuota(0x100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
