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

    // `zig build check` compiles the native binary without installing it (used by CI)
    const check_step = b.step("check", "check that the project compiles");
    check_step.dependOn(&run_exe.step);

    // `zig build web` compiles the emulator + assembler to WebAssembly and
    // puts it next to the frontend in zig-out/web. Serve that folder with
    // any static file server, e.g. `python3 -m http.server -d zig-out/web`.
    const wasm = b.addExecutable(.{ .name = "cpu", .root_module = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = .ReleaseSmall,
    }) });
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });
    const install_site = b.addInstallDirectory(.{
        .source_dir = b.path("web"),
        .install_dir = .{ .custom = "web" },
        .install_subdir = "",
    });
    const web_step = b.step("web", "build the wasm module and the web frontend into zig-out/web");
    web_step.dependOn(&install_wasm.step);
    web_step.dependOn(&install_site.step);

    const test_exe = b.addTest(.{ .name = "tests", .root_module = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = b.graph.host,
    }) });
    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "run all tests");
    test_step.dependOn(&test_cmd.step);
}
