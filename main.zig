const std = @import("std");
const cpu = @import("src/cpu.zig");

pub fn main() !void {
    try cpu.run();
}
