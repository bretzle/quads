const math = @import("../math.zig");
const gfx = @import("../gfx.zig");

const Vec3f = gfx.Vec3f;

pub inline fn rgb(r: anytype, g: anytype, b: anytype) gfx.Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

// these should probable be on the matrix type

pub inline fn getWorldX(x: f32) f32 {
    return 2.0 * x / @as(f32, @floatFromInt(gfx.args.current_rect.w)) - 1;
}

pub inline fn getWorldY(y: f32) f32 {
    return 1.0 + -2.0 * y / @as(f32, @floatFromInt(gfx.args.current_rect.h));
}

pub inline fn getWorldZ(z: f32) f32 {
    return z;
}

pub inline fn getWorldPoint(x: f32, y: f32, z: f32) Vec3f {
    return .{
        getWorldX(x),
        getWorldY(y),
        getWorldZ(z),
    };
}

pub inline fn getMatrixX(matrix: *const math.Mat4, x: f32, y: f32, z: f32) f32 {
    return (matrix.get(0) * x + matrix.get(4) * y + matrix.get(8) * z + matrix.get(12));
}

pub inline fn getMatrixY(matrix: *const math.Mat4, x: f32, y: f32, z: f32) f32 {
    return (matrix.get(1) * x + matrix.get(5) * y + matrix.get(9) * z + matrix.get(13));
}

pub inline fn getMatrixZ(matrix: *const math.Mat4, x: f32, y: f32, z: f32) f32 {
    return (matrix.get(2) * x + matrix.get(6) * y + matrix.get(10) * z + matrix.get(14));
}

pub inline fn getMatrixPoint(matrix: *const math.Mat4, x: f32, y: f32, z: f32) Vec3f {
    return .{
        getMatrixX(matrix, x, y, z),
        getMatrixY(matrix, x, y, z),
        getMatrixZ(matrix, x, y, z),
    };
}

pub inline fn getFinalPoint(matrix: *const math.Mat4, x: f32, y: f32, z: f32) Vec3f {
    return getMatrixPoint(matrix, getWorldX(x), getWorldY(y), getWorldZ(z));
}

pub inline fn cast2(x: [2]i32) [2]f32 {
    return .{ @floatFromInt(x[0]), @floatFromInt(x[1]) };
}

pub inline fn cast4(x: [4]i32) [4]f32 {
    return .{ @floatFromInt(x[0]), @floatFromInt(x[1]), @floatFromInt(x[2]), @floatFromInt(x[3]) };
}

// TODO handle args.rotate
pub fn getDrawMatrix(center: Vec3f) math.Mat4 {
    _ = center; // autofix
    return math.Mat4.identity;
}
