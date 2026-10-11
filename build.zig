const std = @import("std");

pub fn build(b: *std.Build) void {
    const run_exe = b.addExecutable(.{ .name = "cpu", .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    }) });

    b.installArtifact(run_exe);

    const run_cmd = b.addRunArtifact(run_exe);
    const run_step = b.step("run", "run cpu");
    run_step.dependOn(&run_cmd.step);

    const cpu_module = b.createModule(.{
        .root_source_file = b.path("src/cpu.zig"),
    });
    const memory_module = b.createModule(.{
        .root_source_file = b.path("src/memory.zig"),
    });

    run_exe.root_module.addImport("cpu", cpu_module);
    run_exe.root_module.addImport("memory", memory_module);

    const test_exe = b.addTest(.{ .name = "tests", .root_module = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = b.graph.host,
    }) });
    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "run all tests");
    test_step.dependOn(&test_cmd.step);
}
