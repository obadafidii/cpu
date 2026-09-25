const std = @import("std");

const memory = @import("memory.zig");
const instruction_mod = @import("instruction.zig");
const opcode_mod = @import("opcode.zig");

const Opcode = opcode_mod.Opcode;
const hexToOpcode = opcode_mod.hexToOpcode;
const Instruction = instruction_mod.Instruction;
const _64KiB_Memory = memory.Memory(65535); // 64 kibi byte memory = 64 * 1024 * 1024

pub const CpuError = error{ InvalidInstruction, InvalidRegister, InvalidMemoryRead };

const CPU = struct {
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

    fn init() !CPU {
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
        while (!self._is_halted()) {
            const binary: u32 = self.fetch();
            const decoded_instruction: Instruction = try self.decode(binary);
            try self.execute(decoded_instruction);
            self._move_to_next_instruction();
        }
    }

    fn fetch(self: *Self) u32 {
        return self.memory.read_32_bytes(self.program_counter);
    }

    // The instruction set architecture supported by this emulator
    // +----------+--------+----------+------------------------------------------------------+
    // | MNEMONIC | OPCODE | OPERANDS | DESCRIPTION                                          |
    // +----------+--------+----------+------------------------------------------------------+
    // | LOAD     | 0x10   | R, imm   | Load 32-bit immediate value into register R.         |
    // | MOV      | 0x11   | R1, R2   | Copy value from R2 into R1.                          |
    // | ADD      | 0x30   | R1, R2   | Add R2 to R1 and store the result in R1.             |
    // | SUB      | 0x31   | R1, R2   | Subtract R2 from R1 and store the result in R1.       |
    // | HLT      | 0x01   | -        | Halt the CPU.                                        |
    // +----------+--------+----------+------------------------------------------------------+
    //
    // This guide is what will help in decoding
    pub fn decode(self: *Self, hex: u8) CpuError!Instruction {
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
                instruction.register1 = try self._read_register_safely_at(4);
                instruction.register2 = try self._read_register_safely_at(8);
                instruction.length = 12;
                return instruction;
            },
            .Load => { // MOV R1, #immediate
                var load_instruction = Instruction.init(.Load);
                load_instruction.register1 = try self._read_register_safely_at(4); // 4 bytes
                load_instruction.immediate = try self._read_register_safely_at(8); // 8 bytes
                load_instruction.length = 12;
                return load_instruction;
            },
            .Mov => { // MOV R1, R2
                var move_instruction = Instruction.init(.Mov);
                move_instruction.register1 = try self._read_register_safely_at(4);
                move_instruction.immediate = try self._read_register_safely_at(8);
                move_instruction.length = 8;
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

    fn execute(self: *Self, instr: Instruction) !void {
        _ = self;
        _ = instr;
        return;
    }

    // helper method to make sure we don't read outside of memory boundary.
    fn _read_register_safely_at(self: *Self, offset: u16) CpuError!u32 {
        const reg = self.memory.read_32_bytes(self.program_counter + offset);

        // 15 is the number of registers my cpu has.
        if (reg > 15) {
            return CpuError.InvalidRegister;
        }

        return reg;
    }

    fn _is_halted(self: *Self) bool {
        return self.is_halted;
    }

    fn _move_to_next_instruction(self: *Self) void {
        self.program_counter += 1;
    }
};

test "CPU[decode]: invalid opcode returns invalid instruction" {
    var cpu = try CPU.init();
    try std.testing.expectError(CpuError.InvalidInstruction, cpu.decode(0x6));
}
