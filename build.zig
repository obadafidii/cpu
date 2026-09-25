const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_exe = b.addExecutable(.{
        .name = "cpu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.graph.host,
        }),
    });
    const run_step = b.step("run", "run cpu");
    run_step.dependOn(&run_exe.step);

    const test_exe = b.addTest(.{ .name = "tests", .root_module = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = b.graph.host,
    }) });
    const test_step = b.step("test", "run all tests");
    test_step.dependOn(&test_exe.step);
}
