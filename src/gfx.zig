pub const low = struct {
    pub usingnamespace @import("gfx/common.zig");
    pub usingnamespace @import("gfx/renderer_low.zig");
};

pub const high = struct {
    pub usingnamespace @import("gfx/common.zig");
    pub usingnamespace @import("gfx/renderer_high.zig");
};
