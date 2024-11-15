const builtin = @import("builtin");
const platform = switch (builtin.os.tag) {
    .windows => @import("platform/windows.zig"),
    else => unreachable,
};

/// get time in seconds
pub fn getTime() u64 {
    return platform.time.getTime();
}

/// get time in nanoseconds
pub fn getTimeNS() u64 {
    return platform.time.getTimeNS();
}

pub fn sleep(ms: u64) void {
    platform.time.sleep(ms);
}
