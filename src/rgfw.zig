const std = @import("std");
const builtin = @import("builtin");

pub const callbacks = @import("callbacks.zig");
pub const time = @import("time.zig");
pub const math = @import("math.zig");
pub const gfx = @import("gfx.zig");

const common = @import("platform/common.zig");
const platform = switch (builtin.os.tag) {
    .windows => @import("platform/windows.zig"),
    else => unreachable,
};

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

pub const JoystickButton = enum {
    none,
    a,
    b,
    y,
    x,
    start,
    select,
    home,
    up,
    down,
    left,
    right,
    l1,
    l2,
    r1,
    r2,
};

pub const MouseButton = enum { left, middle, right, scroll_up, scroll_down };

pub const max_drops = 260;
pub const max_path = 260;

pub const WindowOptions = packed struct {
    /// the window doesn't have border
    no_border: bool = false,
    ///  the window cannot be resized  by the user
    no_resize: bool = false,
    /// the window supports drag and dro
    allow_dnd: bool = false,
    /// the window should hide the mouse or not (can be toggled later on) using `RGFW_WindowSrc.mouseSho
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

pub const LockState = packed struct {
    caps: bool = false,
    num: bool = false,
};

pub const Monitor = struct {
    name: [128]u8,
    rect: math.Rect,
    scale: math.Vec2,
    phys: math.Vec2,

    pub fn get() []const Monitor {
        return platform.monitor.get();
    }

    pub fn primary() Monitor {
        return platform.monitor.primary();
    }
};

// TODO turn into union
pub const Event = struct {
    keyName: [16]u8,
    droppedFiles: [][]u8,
    droppedFilesCount: u32,
    typ: EventType,
    point: math.Point,
    keycode: Key,
    repeat: bool,
    in_focus: bool,
    lockState: LockState,
    button: MouseButton,
    scroll: f64,
    joystick: u16,
    joy_button: JoystickButton,
    axis: [2]math.Point,
    frameTime: u64,
    frameTime2: u64,
};

pub const Wait = enum(i32) {
    no_wait = 0,
    next = -1,
    _,

    pub inline fn millis(ms: i32) Wait {
        return @enumFromInt(ms);
    }
};

pub const Window = struct {
    src: platform.WindowSrc,
    userPtr: ?*anyopaque,
    event: Event,
    r: math.Rect,
    _lastMousePoint: math.Point,
    _winArgs: WindowOptions,

    pub fn create(allocator: std.mem.Allocator, name: [:0]const u8, rect: math.Rect, args: WindowOptions) !*Window {
        const win = try allocator.create(Window);

        win.event.droppedFiles = try allocator.alloc([]u8, max_drops);
        for (0..max_drops) |i| win.event.droppedFiles[i] = try allocator.alloc(u8, max_path);

        const screenR = getScreenSize();

        win.r = if (args.fullscreen)
            .{
                .x = 0,
                .y = 0,
                .w = @intCast(screenR.w),
                .h = @intCast(screenR.h),
            }
        else
            rect;

        win.event.in_focus = true;
        win.event.droppedFilesCount = 0;
        common.joystickCount = 0;
        win._winArgs = .{};
        win.event.lockState = .{};

        platform.WindowSrc.init(win, name, args);

        return win;
    }

    pub fn close(win: *Window, allocator: std.mem.Allocator) void {
        platform.WindowSrc.close(win, allocator);
    }

    pub fn checkEvent(win: *Window) ?*Event {
        return platform.WindowSrc.checkEvent(win);
    }

    pub fn eventWait(win: *Window, wait: Wait) void {
        platform.WindowSrc.eventWait(win, wait);
    }

    pub fn checkEvents(win: *Window, wait: Wait) void {
        win.eventWait(wait);
        while ((win.checkEvent() != null) and !win.shouldClose()) {
            if (win.event.typ == .quit) return;
        }
    }

    pub fn move(win: *Window, v: math.Point) void {
        win.r.x = v.x;
        win.r.y = v.y;
        platform.WindowSrc.move(win);
    }

    pub fn moveToMonitor(win: *Window, m: Monitor) void {
        win.move(.{
            .x = m.rect.x + win.r.x,
            .y = m.rect.y + win.r.y,
        });
    }

    pub fn resize(win: *Window, a: math.Area) void {
        win.r.w = @intCast(a.w);
        win.r.h = @intCast(a.h);
        platform.WindowSrc.resize(win);
    }

    pub fn setMinSize(win: *Window, a: math.Area) void {
        win.src.minSize = a;
    }

    pub fn setMaxSize(win: *Window, a: math.Area) void {
        win.src.maxSize = a;
    }

    pub fn maximize(win: *Window) void {
        const screen = getScreenSize();
        win.move(.{});
        win.resize(screen);
    }

    pub fn minimize(win: *Window) void {
        platform.WindowSrc.minimize(win);
    }

    pub fn restore(win: *Window) void {
        platform.WindowSrc.restore(win);
    }

    pub fn setBorder(win: *Window, border: bool) void {
        platform.WindowSrc.setBorder(win, border);
    }

    pub fn setDND(win: *Window, allow: bool) void {
        platform.WindowSrc.setDND(win, allow);
    }

    pub fn setName(win: *Window, name: [:0]const u8) void {
        platform.WindowSrc.setName(win, name);
    }

    pub fn setIcon(win: *Window, src: []const u8, a: math.Area, channels: i32) void {
        platform.WindowSrc.setIcon(win, src, a, channels);
    }

    pub fn setMouse(win: *Window, image: []const u8, a: math.Area, channels: i32) void {
        platform.WindowSrc.setMouse(win, image, a, channels);
    }

    pub fn setMouseStandard(win: *Window, mouse: MouseIcons) void {
        platform.WindowSrc.setMouseStandard(win, mouse);
    }

    pub fn setMouseDefault(win: *Window) void {
        win.setMouseStandard(.arrow);
    }

    /// Locks cursor to center of window
    pub fn mouseHold(win: *Window, _: math.Area) void {
        if (win._winArgs.hold_mouse) return;

        win._winArgs.hide_mouse = true;
        platform.captureCursor(win, win.r);
        win.moveMouse(.{ .x = win.r.x + @divTrunc(win.r.w, 2), .y = win.r.y + @divTrunc(win.r.h, 2) });
    }

    pub fn mouseUnhold(win: *Window) void {
        if (win._winArgs.hold_mouse) {
            win._winArgs.hold_mouse = false;
            platform.releaseCursor(win);
        }
    }

    pub fn hide(win: *Window) void {
        platform.WindowSrc.hide(win);
    }

    pub fn show(win: *Window) void {
        platform.WindowSrc.show(win);
    }

    pub fn setShouldClose(win: *Window) void {
        win.event.typ = .quit;
        callbacks.windowQuitCallback(win);
    }

    pub fn getMousePoint(win: *Window) math.Point {
        return platform.WindowSrc.getMousePoint(win);
    }

    pub fn showMouse(win: *Window, s: bool) void {
        if (s) {
            win.setMouseDefault();
        } else {
            win.setMouse(&.{ 0, 0, 0, 0 }, .{ .w = 1, .h = 1 }, 4);
        }
    }

    pub fn moveMouse(win: *Window, p: math.Point) void {
        platform.WindowSrc.moveMouse(win, p);
    }

    pub fn shouldClose(win: *Window) bool {
        return win.event.typ == .quit;
    }

    pub fn isFullscreen(win: *Window) bool {
        return platform.WindowSrc.isFullscreen(win);
    }

    pub fn isHidden(win: *Window) bool {
        return platform.WindowSrc.isHidden(win);
    }

    pub fn isMinimized(win: *Window) bool {
        return platform.WindowSrc.isMinimized(win);
    }

    pub fn isMaximized(win: *Window) bool {
        return platform.WindowSrc.isMaximized(win);
    }

    pub fn scaleToMonitor(win: *Window) void {
        const monitor = win.getMonitor();
        win.resize(.{
            .w = @intFromFloat(monitor.scale[0] * @as(f32, @floatFromInt(win.r.w))),
            .h = @intFromFloat(monitor.scale[1] * @as(f32, @floatFromInt(win.r.h))),
        });
    }

    pub fn getMonitor(win: *Window) Monitor {
        return platform.WindowSrc.getMonitor(win);
    }

    pub fn makeCurrent(win: *Window) void {
        platform.makeCurrent_OpenGL(win);
    }

    pub fn checkFPS(win: *Window, fpsCap: u32) u32 {
        var deltaTime = time.getTimeNS() - win.event.frameTime;

        var output_fps: u32 = 0;
        const fps: u64 = @intFromFloat(@round(@as(f64, 1e9) / @as(f64, @floatFromInt(deltaTime))));
        output_fps = @truncate(fps);

        if (fpsCap != 0 and fps > fpsCap) {
            const frameTimeNS: u64 = @intFromFloat(1e+9 / @as(f64, @floatFromInt(fpsCap)));
            const sleepTimeMS: u64 = (frameTimeNS - deltaTime) / 1_000_000;

            if (sleepTimeMS > 0) {
                time.sleep(sleepTimeMS);
                win.event.frameTime = 0;
            }
        }

        win.event.frameTime = time.getTimeNS();

        if (fpsCap == 0) return output_fps;

        deltaTime = time.getTimeNS() - win.event.frameTime2;

        output_fps = @intFromFloat(@round(@as(f64, 1e+9) / @as(f64, @floatFromInt(deltaTime))));
        win.event.frameTime2 = time.getTimeNS();

        return output_fps;
    }

    pub fn swapBuffers(win: *Window) void {
        platform.WindowSrc.swapBuffers(win);
    }

    pub fn swapInterval(win: *Window, interval: i32) void {
        return platform.WindowSrc.swapInterval(win, interval);
    }
};

pub fn getScreenSize() math.Area {
    return platform.getScreenSize();
}

pub fn stopCheckEvents() void {
    platform.stopCheckEvents();
}

pub fn getGlobalMousePoint() math.Point {
    return platform.getGlobalMousePoint();
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

pub fn keyCodeToCharAuto(keycode: u32, lockState: LockState) u8 {
    return keyCodeToChar(keycode, common.shouldShift(keycode, lockState));
}

pub fn isPressed(win: *Window, key: Key) bool {
    return common.keyboard[@intFromEnum(key)].current and win.event.in_focus;
}

pub fn wasPressed(win: *Window, key: Key) bool {
    return common.keyboard[@intFromEnum(key)].prev and win.event.in_focus;
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

pub fn isMousePressed(win: *Window, button: MouseButton) bool {
    return common.mouseButtons.get(button).current and win.event.in_focus;
}

pub fn wasMousePressed(win: *Window, button: MouseButton) bool {
    return common.mouseButtons.get(button).prev and win.event.in_focus;
}

pub fn isMouseHeld(win: *Window, button: MouseButton) bool {
    return (isMousePressed(win, button) and wasMousePressed(win, button));
}

pub fn isMouseReleased(win: *Window, button: MouseButton) bool {
    return (!isMousePressed(win, button) and wasMousePressed(win, button));
}

pub fn registerJoystick(win: *Window, _: i32) u16 {
    return registerJoystickF(win, "");
}

pub fn registerJoystickF(_: *Window, _: [:0]const u8) u16 {
    return common.joystickCount - 1;
}

pub fn isPressedJS(_: *Window, controller: u16, button: JoystickButton) bool {
    return common.jsPressed[controller].get(button);
}

pub const getProcAddress = platform.getProcAddress;

test {
    @setEvalBranchQuota(0x100000);
    _ = std.testing.refAllDeclsRecursive(@This());
}
