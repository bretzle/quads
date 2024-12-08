const std = @import("std");
const builtin = @import("builtin");
const glgen = @import("zigglgen");

const Example = struct {
    name: []const u8,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    b.addNamedLazyPath("test_runner", b.path("test_running.zig"));

    const gl = glgen.generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"3.3",
        .profile = .core,
    });

    const quads = b.addModule("quads", .{
        .root_source_file = b.path("src/quads/quads.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gfx = b.addModule("gfx", .{
        .root_source_file = b.path("src/gfx/gfx.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "gl", .module = gl },
            .{ .name = "quads", .module = quads },
        },
    });

    const winit = b.addModule("winit", .{
        .root_source_file = b.path("src/winit/winit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "quads", .module = quads },
        },
    });

    try buildTests(b, &.{ quads, gfx, winit });
    try buildDocs(b, &.{ quads, gfx, winit });

    const examples = &[_]Example{
        .{ .name = "basic", .imports = &.{
            .{ .name = "winit", .module = winit },
            .{ .name = "gfx", .module = gfx },
        } },
        .{ .name = "text", .imports = &.{
            .{ .name = "winit", .module = winit },
            .{ .name = "gfx", .module = gfx },
            .{ .name = "quads", .module = quads },
        } },
        .{ .name = "benchmarking", .imports = &.{
            .{ .name = "quads", .module = quads },
        } },
    };
    buildExamples(b, target, optimize, examples);

    const clean = b.step("clean", "Clean up");
    clean.dependOn(&b.addRemoveDirTree(b.path("zig-out")).step);
    if (builtin.os.tag != .windows) clean.dependOn(&b.addRemoveDirTree(b.path(".zig-cache")).step);
}

fn buildTests(b: *std.Build, modules: []const *std.Build.Module) !void {
    const step = b.step("test", "run tests");

    for (modules) |module| {
        const t = b.addTest(.{
            .root_source_file = module.root_source_file.?,
            .test_runner = b.path("src/test_runner.zig"),
            .target = module.resolved_target,
            .optimize = module.optimize.?,
        });

        var it = module.import_table.iterator();
        while (it.next()) |entry| {
            t.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
        }

        const run = b.addRunArtifact(t);
        step.dependOn(&run.step);
    }
}

fn buildDocs(b: *std.Build, modules: []const *std.Build.Module) !void {
    const step = b.step("docs", "generate docs");

    for (modules) |module| {
        const obj = b.addObject(.{
            .name = std.fs.path.stem(module.root_source_file.?.getDisplayName()),
            .root_source_file = module.root_source_file,
            .target = module.resolved_target.?,
            .optimize = module.optimize.?,
        });

        const install = b.addInstallDirectory(.{
            .source_dir = obj.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = b.fmt("docs/{s}", .{obj.name}),
        });

        step.dependOn(&install.step);
    }
}

// TODO: handle wasm again
fn buildExamples(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, examples: []const Example) void {
    const all = b.step("all", "build all examples");

    for (examples) |example| {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example.name})),
            .target = target,
            .optimize = optimize,
        });

        for (example.imports) |import| {
            exe.root_module.addImport(import.name, import.module);
        }

        const step = b.step(example.name, b.fmt("run example - {s}", .{example.name}));
        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);

        const install = b.addInstallArtifact(exe, .{});
        all.dependOn(&install.step);
    }
}

comptime {
    const required_zig = "0.14.0-dev.2245+4fc295dc0";
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(required_zig) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        const error_message =
            \\Sorry, it looks like your version of zig is too old. :-(
            \\
            \\quads requires development build {}
            \\
            \\Please download a development ("master") build from https://ziglang.org/download/
            \\
            \\
        ;
        @compileError(std.fmt.comptimePrint(error_message, .{min_zig}));
    }
}
