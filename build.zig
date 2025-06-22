const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("zfc", .{
        .root_source_file = b.path("FlagCtx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_test = b.addTest(.{
        .root_source_file = b.path("FlagCtx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_test = b.addRunArtifact(lib_test);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test.step);
}
