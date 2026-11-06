const std = @import("std");

test {
    std.testing.refAllDecls(@This());

    _ = @import("src/opcode.zig");
    _ = @import("src/cpu.zig");
    _ = @import("src/instruction.zig");
    _ = @import("src/memory.zig");
    _ = @import("src/assembler/assembler.zig");
    _ = @import("src/assembler/symbol_table.zig");
}
