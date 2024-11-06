const std = @import("std");
const parent = @import("../rgfw.zig");

const Window = parent.Window;
const Key = parent.Key;
const JoystickButton = parent.JoystickButton;
const MouseButton = parent.MouseButton;
const Monitor = parent.Monitor;

const KeyState = packed struct { current: bool = false, prev: bool = false };

const RGFW_CAPSLOCK = 1;
const RGFW_NUMLOCK = 2;

pub var root: ?*Window = null;
pub var eventWindow: Window = undefined;

pub var jsPressed: [4]std.EnumArray(JoystickButton, bool) = .{std.EnumArray(JoystickButton, bool).initFill(false)} ** 4;
pub var joysticks: [4]i32 = std.mem.zeroes([4]i32);
pub var joystickCount: u16 = 0;

pub var mouseButtons: std.EnumArray(MouseButton, KeyState) = std.EnumArray(MouseButton, KeyState).initFill(.{});
pub var keyboard: [100]KeyState = .{.{}} ** 100;
pub var monitors: [6]Monitor = @import("std").mem.zeroes([6]Monitor);

pub const xinput2RGFW = [22]JoystickButton{
    .a,
    .b,
    .x,
    .y,
    .r1,
    .l1,
    .l2,
    .r2,
    .none,
    .none,
    .none,
    .none,
    .none,
    .none,
    .none,
    .none,
    .up,
    .down,
    .left,
    .right,
    .start,
    .select,
};

const keycodes = [337]Key{
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

pub fn updateLockState(win: *Window, capital: bool, numlock: bool) void {
    if (capital and win.event.lockState & RGFW_CAPSLOCK == 0)
        win.event.lockState |= RGFW_CAPSLOCK
    else if (!capital and win.event.lockState & RGFW_CAPSLOCK != 0)
        win.event.lockState ^= RGFW_CAPSLOCK;

    if (numlock and win.event.lockState & RGFW_NUMLOCK == 0)
        win.event.lockState |= RGFW_NUMLOCK
    else if (!numlock and win.event.lockState & RGFW_NUMLOCK != 0)
        win.event.lockState ^= RGFW_NUMLOCK;
}

/// returns true if the key should be shifted
pub fn shouldShift(keycode: u32, lockState: u8) bool {
    const help = struct {
        inline fn xor(x: bool, y: bool) bool {
            return (x and !y) or (y and !x);
        }
    };

    const caps4caps = (lockState & RGFW_CAPSLOCK != 0) and ((keycode >= @intFromEnum(Key.a)) and (keycode <= @intFromEnum(Key.z)));
    const should_shift = help.xor((keyboard[@intFromEnum(Key.shift_l)].current or keyboard[@intFromEnum(Key.shift_r)].current), caps4caps);

    return should_shift;
}

pub fn apiKeyCodeToRGFW(keycode: u32) u32 {
    _ = std.meta.intToEnum(Key, keycode) catch return 0;
    return @intFromEnum(keycodes[keycode]);
}
