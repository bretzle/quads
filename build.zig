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

    const exe = b.addExecutable(.{
        .name = "basic mq",
        .root_source_file = b.path("examples/basic_mq.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("quads", quads);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const t = b.addTest(.{ .root_source_file = b.path("src/quads.zig") });
    t.root_module.addImport("gl", gl);
    const test_step = b.step("test", "run tests");
    test_step.dependOn(&t.step);
}
