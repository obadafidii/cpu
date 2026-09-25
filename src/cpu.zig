const std = @import("std");

const memory = @import("memory.zig");
const instruction_mod = @import("instruction.zig");
const opcode_mod = @import("opcode.zig");

const Opcode = opcode_mod.Opcode;
const hexToOpcode = opcode_mod.hexToOpcode;
const Instruction = instruction_mod.Instruction;
const _64KiB_Memory = memory.Memory(65535); // 64 kibi byte memory = 64 * 1024 * 1024

pub const CpuError = error{ InvalidInstruction, InvalidRegister, InvalidMemoryRead };

pub const Cpu = struct {
    const Self = @This();

    program_counter: u32,
    stack_pointer: u32,
    flags: u8,
    is_halted: u8,

    registers: [16]u32,
    memory: _64KiB_Memory,

    const FLAG_Z: i8 = 1 << 0;
    const FLAG_C: i8 = 1 << 1;
    const FLAG_N: i8 = 1 << 2;

    pub fn init() !Cpu {
        return .{
            .program_counter = 0,
            .memory = try _64KiB_Memory.init(),
            .stack_pointer = 0,
            .is_halted = 0,
            .registers = [_]u32{0} ** 16,
            .flags = 0,
        };
    }

    // This starts the cpu lifecyle which is basically
    // 1. Read from memory
    // 2. Decoded and understand the instruction
    // 3. Execute the instruction, go back to step 1.
    //
    // TODO: I will come back to this and think of implementing pipelining
    // and branching prediction. Not sure yet.
    pub fn start(self: *Self) !void {
        while (self.is_halted != 1) {
            const binary: u8 = @intCast(self.fetch());
            const decoded_instruction: Instruction = try self.decode(binary);
            try self.execute(decoded_instruction);
            self._move_to_next_instruction(decoded_instruction);
        }
    }

    fn fetch(self: *Self) u32 {
        return self.memory.read_32_bytes(self.program_counter);
    }

    // decode: takes the binary read from memory and 'parse' and detects
    // which instruction is this using the opcode.
    pub fn decode(self: *const Self, hex: u8) CpuError!Instruction {
        const opcode = hexToOpcode(hex);

        return switch (opcode) {
            .Add, .Sub => |op| { // (ADD|SUB) R1, R2
                // Shape of the ADD instruction
                // +----------+--------+----------+
                // |   ADD    |   R1   |   R2     |
                // +----------+--------+----------+
                // PC         4bytes   4bytes
                //
                // So from PC the way I can access R2 is to add 8bytes and 4bytes for R1
                var instruction: Instruction = Instruction.init(op);
                instruction.register1 = try self._safely_read_register_at_offset(4);
                instruction.register2 = try self._safely_read_register_at_offset(8);
                instruction.length = 12;
                return instruction;
            },
            .Load => { // LD R1, #immediate
                var load_instruction = Instruction.init(.Load);
                load_instruction.register1 = try self._safely_read_register_at_offset(4); // 4 bytes
                load_instruction.immediate = try self._safely_read_register_at_offset(8); // 8 bytes
                load_instruction.length = 12;
                return load_instruction;
            },
            .Mov => { // MOV R1, R2
                var move_instruction = Instruction.init(.Mov);
                move_instruction.register1 = try self._safely_read_register_at_offset(4);
                move_instruction.immediate = try self._safely_read_register_at_offset(8);
                move_instruction.length = 12;
                return move_instruction;
            },
            .Hlt => { // HLT
                var halt_instr = Instruction.init(.Hlt);
                halt_instr.length = 4; // the halt opcode
                return halt_instr;
            },
            _ => CpuError.InvalidInstruction,
        };
    }

    fn execute(self: *Self, instruction: Instruction) !void {
        return switch (instruction.opcode) {
            .Load => {
                // load immediate to register1
                self.registers[instruction.register1] = instruction.immediate;
            },
            .Mov => {
                self.registers[instruction.register1] = self.registers[instruction.register2];
            },
            .Add => {
                // 1. add r2 to r1
                const operand1 = self.registers[instruction.register1];
                const operand2 = self.registers[instruction.register2];
                const sum = operand1 + operand2;

                // 2. store in r1
                self.registers[instruction.register1] = sum;
            },
            .Sub => {
                // 1. add r2 to r1
                const operand1 = self.registers[instruction.register1];
                const operand2 = self.registers[instruction.register2];
                const difference = operand1 - operand2;

                // 2. store in r1
                self.registers[instruction.register1] = difference;
            },
            .Hlt => {
                self.is_halted = 1;
            },
            _ => CpuError.InvalidInstruction,
        };
    }

    // helper method to make sure we don't read outside of memory boundary.
    fn _safely_read_register_at_offset(self: *const Self, offset: u16) CpuError!u32 {
        const reg = self.memory.read_32_bytes(self.program_counter + offset);

        // 15 is the number of registers my cpu has.
        if (reg > 15) {
            return CpuError.InvalidRegister;
        }

        return reg;
    }

    fn _move_to_next_instruction(self: *Self, instruction: Instruction) void {
        self.program_counter += instruction.length;
    }
};

// End to end test of CPU
// Fetch -> Decode -> Execute
test Cpu {}

test "decode: invalid opcode returns invalid instruction" {
    var cpu = try Cpu.init();
    try std.testing.expectError(CpuError.InvalidInstruction, cpu.decode(0x6));
}

test "decode: returns the instruction related to the read bytes" {
    const cpu = try Cpu.init();

    // 0x30 -> Add
    const add = try cpu.decode(0x30);
    try std.testing.expectEqual(add.opcode, Opcode.Add);
    try std.testing.expectEqual(add.length, 12);

    // 0x31 -> Sub
    const sub = try cpu.decode(0x31);
    try std.testing.expectEqual(sub.opcode, Opcode.Sub);
    try std.testing.expectEqual(sub.length, 12);

    // 0x10 -> load
    const load = try cpu.decode(0x10);
    try std.testing.expectEqual(load.opcode, Opcode.Load);
    try std.testing.expectEqual(load.length, 12);

    // 0x11 -> Mov
    const mov = try cpu.decode(0x11);
    try std.testing.expectEqual(mov.opcode, Opcode.Mov);
    try std.testing.expectEqual(mov.length, 12);

    // 0x01 -> Hlt
    const hlt = try cpu.decode(0x01);
    try std.testing.expectEqual(hlt.opcode, Opcode.Hlt);
    try std.testing.expectEqual(hlt.length, 4);
}
