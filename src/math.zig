const std = @import("std");
const meta = @import("meta.zig");

pub const Point = struct { x: i32 = 0, y: i32 = 0 };
pub const Rect = struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };
pub const Area = struct { w: u32 = 0, h: u32 = 0 };

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
    return vec * @as(@TypeOf(vec), @splat(1.0 / @sqrt(dot(vec, vec))));
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

/// 4 by 4 matrix type.
pub const Mat4 = extern struct {
    pub const Self = @This();

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
};
