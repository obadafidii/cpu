const Cpu = @import("src/cpu.zig").Cpu;

pub fn main() !void {
    var cpu = try Cpu.init();
    try cpu.simulate();
}
