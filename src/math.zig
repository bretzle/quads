const std = @import("std");
const meta = @import("meta.zig");
const testing = @import("testing.zig");

pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

pub const radians = std.math.degreesToRadians;
pub const degrees = std.math.radiansToDegrees;

pub fn len(vec: anytype) f32 {
    meta.isVector(@TypeOf(vec));
    return @sqrt(dot(vec, vec));
}

pub fn distance(a: anytype, b: anytype) f32 {
    meta.isVector(@TypeOf(a, b));
    return len(b - a);
}

pub fn angleBetween(a: anytype, b: anytype) f32 {
    meta.isVector(@TypeOf(a, b));
    const len_a = len(a);
    const len_b = len(b);
    const dot_product = dot(a, b);
    return std.math.acos(dot_product / (len_a * len_b));
}

pub fn normalize(vec: anytype) @TypeOf(vec) {
    meta.isVector(@TypeOf(vec));
    return scale(vec, 1.0 / len(vec));
}

pub fn dot(a: anytype, b: anytype) f32 {
    meta.isVector(@TypeOf(a, b));
    return @reduce(.Add, a * b);
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub fn scale(vec: anytype, val: f32) @TypeOf(vec) {
    meta.isVector(@TypeOf(vec));
    return vec * @as(@TypeOf(vec), @splat(val));
}

pub fn lerp(a: anytype, b: anytype, t: f32) @TypeOf(a, b) {
    meta.isVector(@TypeOf(a, b));
    return scale(a, 1.0 - t) + scale(b, t);
}

const swizzle_lookup = std.StaticStringMap(u8).initComptime(.{
    .{ "x", 0 },
    .{ "y", 1 },
    .{ "z", 2 },
    .{ "w", 3 },

    .{ "r", 0 },
    .{ "g", 1 },
    .{ "b", 2 },
    .{ "a", 3 },
});

pub fn swizzle(vec: anytype, comptime str: []const u8) @TypeOf(vec) {
    meta.isVector(@TypeOf(vec));
    meta.compileAssert(@typeInfo(@TypeOf(vec)).vector.len == str.len, "output must be same size as vector", .{});

    var output: @TypeOf(vec) = undefined;

    inline for (str, 0..) |char, idx| {
        meta.compileAssert(swizzle_lookup.has(&.{char}), "{c} is not a valid swizzle component", .{char});
        const found = comptime swizzle_lookup.get(&.{char}) orelse unreachable;
        meta.compileAssert(found < @typeInfo(@TypeOf(vec)).vector.len, "todo", .{});

        output[idx] = vec[found];
    }

    return output;
}

fn SwizzleOutput(comptime str: []const u8) type {
    return @Vector(str.len, f32);
}

pub fn swizzle2(vec: anytype, comptime str: []const u8) SwizzleOutput(str) {
    var output: SwizzleOutput(str) = undefined;

    inline for (str, 0..) |char, idx| {
        meta.compileAssert(swizzle_lookup.has(&.{char}), "{c} is not a valid swizzle component", .{char});
        const found = comptime swizzle_lookup.get(&.{char}) orelse unreachable;
        meta.compileAssert(found < @typeInfo(SwizzleOutput(str)).vector.len, "todo", .{});

        output[idx] = vec[found];
    }

    return output;
}

/// 4 by 4 matrix type.
pub const Mat4 = extern struct {
    const Self = @This();

    // [row][col]
    data: [4][4]f32 = .{.{ 0, 0, 0, 0 }} ** 4,

    pub const identity = Self{
        .data = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };

    /// performs matrix multiplication of a*b
    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var ret: Mat4 = undefined;
        inline for (0..4) |row| {
            const vx: Vec4 = @splat(a.data[row][0]);
            const vy: Vec4 = @splat(a.data[row][1]);
            const vz: Vec4 = @splat(a.data[row][2]);
            const vw: Vec4 = @splat(a.data[row][3]);
            ret.data[row] = @mulAdd(Vec4, vx, b.data[0], vz * b.data[2]) + @mulAdd(Vec4, vy, b.data[1], vw * b.data[3]);
        }
        return ret;
    }

    /// Creates a look-at matrix.
    /// The matrix will create a transformation that can be used
    /// as a camera transform.
    /// the camera is located at `eye` and will look into `direction`.
    /// `up` is the direction from the screen center to the upper screen border.
    pub fn look(eye: Vec3, direction: Vec3, up: Vec3) Self {
        const f = normalize(direction);
        const s = normalize(cross(f, up));
        const u = cross(s, f);

        var ret = Self.identity;
        ret.data[0][0] = s[0];
        ret.data[1][0] = s[1];
        ret.data[2][0] = s[2];
        ret.data[0][1] = u[0];
        ret.data[1][1] = u[1];
        ret.data[2][1] = u[2];
        ret.data[0][2] = -f[0];
        ret.data[1][2] = -f[1];
        ret.data[2][2] = -f[2];
        ret.data[3][0] = -dot(s, eye);
        ret.data[3][1] = -dot(u, eye);
        ret.data[3][2] = dot(f, eye);
        return ret;
    }

    /// Creates a look-at matrix.
    /// The matrix will create a transformation that can be used
    /// as a camera transform.
    /// the camera is located at `eye` and will look at `center`.
    /// `up` is the direction from the screen center to the upper screen border.
    pub fn lookAt(eye: Vec3, center: Vec3, up: Vec3) Self {
        return look(eye, center - eye, up);
    }

    /// creates a perspective transformation matrix.
    /// `fov` is the field of view in radians,
    /// `aspect` is the screen aspect ratio (width / height)
    /// `near` is the distance of the near clip plane, whereas `far` is the distance to the far clip plane.
    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Self {
        std.debug.assert(@abs(aspect - 0.001) > 0);
        const tanHalfFovy = @tan(fov / 2);

        var ret = Self{};
        ret.data[0][0] = 1.0 / (aspect * tanHalfFovy);
        ret.data[1][1] = 1.0 / (tanHalfFovy);
        ret.data[2][2] = -(far + near) / (far - near);
        ret.data[2][3] = -1;
        ret.data[3][2] = -(2 * far * near) / (far - near);
        return ret;
    }

    /// creates an orthogonal projection matrix.
    /// `left`, `right`, `bottom` and `top` are the borders of the screen whereas `near` and `far` define the
    /// distance of the near and far clipping planes.
    pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Self {
        var result = Self.identity;
        result.data[0][0] = 2 / (right - left);
        result.data[1][1] = 2 / (top - bottom);
        result.data[2][2] = -2 / (far - near);
        result.data[3][0] = -(right + left) / (right - left);
        result.data[3][1] = -(top + bottom) / (top - bottom);
        result.data[3][2] = -(far + near) / (far - near);
        return result;
    }

    /// creates a rotation matrix around a certain axis.
    pub fn rotation(axis: Vec3, angle: f32) Self {
        const x, const y, const z = normalize(axis);
        const cos = @cos(angle);
        const sin = @sin(angle);
        const c = 1 - cos;

        return .{
            .data = .{
                .{ cos + x * x * c, x * y * c + z * sin, x * z * c - y * sin, 0 },
                .{ y * x * c - z * sin, cos + y * y * c, y * z * c + x * sin, 0 },
                .{ z * x * c + y * sin, z * y * c - x * sin, cos + z * z * c, 0 },
                .{ 0, 0, 0, 1 },
            },
        };
    }

    pub fn transpose(mat: Self) Self {
        var result = mat;

        result.data[0][0] = mat.data[0][0];
        result.data[0][1] = mat.data[1][0];
        result.data[0][2] = mat.data[2][0];
        result.data[0][3] = mat.data[3][0];
        result.data[1][0] = mat.data[0][1];
        result.data[1][1] = mat.data[1][1];
        result.data[1][2] = mat.data[2][1];
        result.data[1][3] = mat.data[3][1];
        result.data[2][0] = mat.data[0][2];
        result.data[2][1] = mat.data[1][2];
        result.data[2][2] = mat.data[2][2];
        result.data[2][3] = mat.data[3][2];
        result.data[3][0] = mat.data[0][3];
        result.data[3][1] = mat.data[1][3];
        result.data[3][2] = mat.data[2][3];
        result.data[3][3] = mat.data[3][3];

        return result;
    }

    pub fn determinant(mat: Self) f32 {
        const c01: Vec3 = cross(swizzle2(mat.data[0], "xyz"), swizzle2(mat.data[1], "xyz"));
        const c23: Vec3 = cross(swizzle2(mat.data[2], "xyz"), swizzle2(mat.data[3], "xyz"));
        const b10: Vec3 = scale(swizzle2(mat.data[0], "xyz"), mat.data[1][3]) - scale(swizzle2(mat.data[1], "xyz"), mat.data[0][3]);
        const b32: Vec3 = scale(swizzle2(mat.data[2], "xyz"), mat.data[3][3]) - scale(swizzle2(mat.data[3], "xyz"), mat.data[2][3]);

        return dot(c01, b32) + dot(c23, b10);
    }
};

test swizzle {
    const a = Vec4{ 1, 2, 3, 4 };

    try testing.expectEqual(Vec4{ 4, 3, 2, 1 }, swizzle(a, "wzyx"));
    try testing.expectEqual(Vec4{ 1, 2, 1, 2 }, swizzle(a, "xyxy"));

    const b = Vec3{ 1, 2, 3 };

    try testing.expectEqual(Vec3{ 3, 2, 1 }, swizzle(b, "zyx"));
    try testing.expectEqual(Vec3{ 1, 2, 1 }, swizzle(b, "xyx"));
}

test "determinant" {
    const mat = Mat4{
        .data = .{
            .{ 1, 0, 4, -6 },
            .{ 2, 5, 0, 3 },
            .{ -1, 2, 3, 5 },
            .{ 2, 1, -2, 3 },
        },
    };

    try testing.expectEqual(318, mat.determinant());
}
