const quads = @import("quads.zig");
const math = @import("math.zig");

const Window = quads.Window;
const MouseButton = quads.MouseButton;
const JoystickButton = quads.JoystickButton;

pub const WindowMoveFn = *const fn (win: *Window, r: math.Rect) void;
pub const WindowResizeFn = *const fn (win: *Window, r: math.Rect) void;
pub const WindowQuitFn = *const fn (win: *Window) void;
pub const FocusFn = *const fn (win: *Window, focus: bool) void;
pub const MouseNotifyFn = *const fn (win: *Window, pos: math.Point, status: bool) void;
pub const MousePosFn = *const fn (win: *Window, pos: math.Point) void;
pub const DndInitFn = *const fn (win: *Window, pos: math.Point) void;
pub const WindowRefreshFn = *const fn (win: *Window) void;
pub const KeyFn = *const fn (win: *Window, keycode: quads.Key, name: []const u8, lock: quads.LockState, pressed: bool) void;
pub const MouseButtonFn = *const fn (win: *Window, button: MouseButton, scroll: f64, pressed: bool) void;
pub const JoyButtonFn = *const fn (win: *Window, joystick: u16, button: JoystickButton, pressed: bool) void;
pub const JoyAxisFn = *const fn (win: *Window, joystick: u16, axis: [2]math.Point) void;
pub const DndFn = *const fn (win: *Window, dropped_files: [][]u8, count: u32) void;

pub var windowMoveCallback: WindowMoveFn = stubs.windowMove;
pub var windowResizeCallback: WindowResizeFn = stubs.windowResize;
pub var windowQuitCallback: WindowQuitFn = stubs.windowQuit;
pub var focusCallback: FocusFn = stubs.focus;
pub var mouseNotifyCallBack: MouseNotifyFn = stubs.mouseNotify;
pub var mousePosCallback: MousePosFn = stubs.mousePos;
pub var dndInitCallback: DndInitFn = stubs.dndInit;
pub var windowRefreshCallback: WindowRefreshFn = stubs.windowRefresh;
pub var keyCallback: KeyFn = stubs.key;
pub var mouseButtonCallback: MouseButtonFn = stubs.mouseButton;
pub var joyButtonCallback: JoyButtonFn = stubs.joyButton;
pub var joyAxisCallback: JoyAxisFn = stubs.joyAxis;
pub var dndCallback: DndFn = stubs.dnd;

const stubs = struct {
    fn windowMove(_: *Window, _: math.Rect) void {}
    fn windowResize(_: *Window, _: math.Rect) void {}
    fn windowQuit(_: *Window) void {}
    fn focus(_: *Window, _: bool) void {}
    fn mouseNotify(_: *Window, _: math.Point, _: bool) void {}
    fn mousePos(_: *Window, _: math.Point) void {}
    fn dndInit(_: *Window, _: math.Point) void {}
    fn windowRefresh(_: *Window) void {}
    fn key(_: *Window, _: quads.Key, _: []const u8, _: quads.LockState, _: bool) void {}
    fn mouseButton(_: *Window, _: MouseButton, _: f64, _: bool) void {}
    fn joyButton(_: *Window, _: u16, _: JoystickButton, _: bool) void {}
    fn joyAxis(_: *Window, _: u16, _: [2]math.Point) void {}
    fn dnd(_: *Window, _: [][]u8, _: u32) void {}
};

pub fn setWindowMoveCallback(func: WindowMoveFn) ?WindowMoveFn {
    const prev = if (windowMoveCallback == stubs.windowMove) null else windowMoveCallback;
    windowMoveCallback = func;
    return prev;
}

pub fn setWindowResizeCallback(func: WindowResizeFn) ?WindowResizeFn {
    const prev = if (windowResizeCallback == stubs.windowResize) null else windowResizeCallback;
    windowResizeCallback = func;
    return prev;
}

pub fn setWindowQuitCallback(func: WindowQuitFn) ?WindowQuitFn {
    const prev = if (windowQuitCallback == stubs.windowQuit) null else windowQuitCallback;
    windowQuitCallback = func;
    return prev;
}

pub fn setMousePosCallback(func: MousePosFn) ?MousePosFn {
    const prev = if (mousePosCallback == stubs.mousePos) null else mousePosCallback;
    mousePosCallback = func;
    return prev;
}

pub fn setWindowRefreshCallback(func: WindowRefreshFn) ?WindowRefreshFn {
    const prev = if (windowRefreshCallback == stubs.windowRefresh) null else windowRefreshCallback;
    windowRefreshCallback = func;
    return prev;
}

pub fn setFocusCallback(func: FocusFn) ?FocusFn {
    const prev = if (focusCallback == stubs.focus) null else focusCallback;
    focusCallback = func;
    return prev;
}

pub fn setMouseNotifyCallBack(func: MouseNotifyFn) ?MouseNotifyFn {
    const prev = if (mouseNotifyCallBack == stubs.mouseNotify) null else mouseNotifyCallBack;
    mouseNotifyCallBack = func;
    return prev;
}

pub fn setDndCallback(func: DndFn) ?DndFn {
    const prev = if (dndCallback == stubs.dnd) null else dndCallback;
    dndCallback = func;
    return prev;
}

pub fn setDndInitCallback(func: DndInitFn) ?DndInitFn {
    const prev = if (dndInitCallback == stubs.dndInit) null else dndInitCallback;
    dndInitCallback = func;
    return prev;
}

pub fn setKeyCallback(func: KeyFn) ?KeyFn {
    const prev = if (keyCallback == stubs.key) null else keyCallback;
    keyCallback = func;
    return prev;
}

pub fn setMouseButtonCallback(func: MouseButtonFn) ?MouseButtonFn {
    const prev = if (mouseButtonCallback == stubs.mouseButton) null else mouseButtonCallback;
    mouseButtonCallback = func;
    return prev;
}

pub fn setJoyButtonCallback(func: JoyButtonFn) ?JoyButtonFn {
    const prev = if (joyButtonCallback == stubs.joyButton) null else joyButtonCallback;
    joyButtonCallback = func;
    return prev;
}

pub fn setJoyAxisCallback(func: JoyAxisFn) ?JoyAxisFn {
    const prev = if (joyAxisCallback == stubs.joyAxis) null else joyAxisCallback;
    joyAxisCallback = func;
    return prev;
}
