const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize });
    const dep_zstbi = b.dependency("zstbi", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "zig-game-of-life",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("sokol", dep_sokol.module("sokol"));
    exe.root_module.addImport("zstbi", dep_zstbi.module("root"));
    exe.linkLibrary(dep_zstbi.artifact("zstbi"));
    b.installArtifact(exe);

    const install = b.getInstallStep();
    const install_data = b.addInstallDirectory(.{
        .source_dir = b.path("src/data"),
        .install_dir = .{ .prefix = {} },
        .install_subdir = "bin/data",
    });

    install.dependOn(&install_data.step);
    

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(install);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
