const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "cpu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.graph.host,
        }),
    });
    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the executable");
    run_step.dependOn(&run.step);

    const tests = b.addTest(.{
        .name = "tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests.zig"),
            .target = b.graph.host,
        }),
    });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}
