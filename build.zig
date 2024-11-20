const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gl = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"3.3",
        .profile = .core,
    });

    const quads = b.addModule("quads", .{
        .root_source_file = b.path("src/quads.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "gl", .module = gl },
        },
    });

    inline for (.{ "basic_mq", "text" }) |name| {
        buildExample(b, name, target, optimize, quads);
    }

    const t = b.addTest(.{ .root_source_file = b.path("src/quads.zig") });
    t.root_module.addImport("gl", gl);
    const test_step = b.step("test", "run tests");
    test_step.dependOn(&t.step);
}

fn buildExample(b: *std.Build, comptime name: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, quads: *std.Build.Module) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("examples/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.isWasm()) {
        exe.entry = .disabled;
        exe.rdynamic = true;
    }

    exe.root_module.addImport("quads", quads);

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = if (target.result.isWasm()) .{ .override = .{ .custom = "../www" } } else .default,
    });

    const step = b.step(name, "build " ++ name ++ " example");
    if (target.result.isWasm()) {
        step.dependOn(&install.step);
    }

    if (!target.result.isWasm()) {
        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        b.installArtifact(exe);
    }
}
