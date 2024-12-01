const std = @import("std");
const glgen = @import("zigglgen");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gl = glgen.generateBindingsModule(b, .{
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

    b.addNamedLazyPath("test_runner", b.path("test_running.zig"));

    inline for (.{ "basic_mq", "text", "benchmarking" }) |name| {
        buildExample(b, name, target, optimize, quads);
    }

    const t = b.addTest(.{
        .root_source_file = b.path("src/quads.zig"),
        .test_runner = b.path("test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    t.root_module.addImport("gl", gl);
    const test_step = b.step("test", "run tests");
    test_step.dependOn(&b.addRunArtifact(t).step);

    const docs = b.step("docs", "Build the quads docs");
    const docs_obj = b.addObject(.{
        .name = "quads",
        .root_source_file = quads.root_source_file,
        .target = target,
        .optimize = optimize,
    });
    docs.dependOn(&b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);
}

fn buildExample(b: *std.Build, comptime name: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, quads: *std.Build.Module) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("examples/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("quads", quads);

    const step = b.step(name, "build " ++ name ++ " example");

    if (target.result.isWasm()) {
        exe.entry = .disabled;
        exe.rdynamic = true;

        const install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../www" } } });
        step.dependOn(&install.step);
    } else {
        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        b.installArtifact(exe);
    }
}
