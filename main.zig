const std = @import("std");
const cpu_mod = @import("src/cpu.zig");

const Cpu = cpu_mod.Cpu;
const CpuError = cpu_mod.CpuError;

pub fn main(_: std.process.Init) !void {
    var cpu = try Cpu.init();
    std.debug.print("is_halted: {}", .{cpu.is_halted});
    try cpu.start();
}
