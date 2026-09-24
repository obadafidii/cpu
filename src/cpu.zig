const std = @import("std");

const memory = @import("memory.zig");
const instruction = @import("instruction.zig");
const opcode = @import("opcode.zig");

const Opcode = opcode.Opcode;
const OpcodeBinary = opcode.OpcodeBinary;
const Instruction = instruction.Instruction;
const _64KiB_Memory = memory.Memory(65535); // 64 kibi byte memory = 64 * 1024 * 1024

pub const CpuErrors = error{InvalidInstruction};

const CPU = struct {
    const Self = @This();

    program_counter: i32,
    stack_pointer: i32,
    flags: i8,
    is_halted: i8,

    registers: [16]i32,
    memory: _64KiB_Memory,

    const FLAG_Z: i8 = 1 << 0;
    const FLAG_C: i8 = 1 << 1;
    const FLAG_N: i8 = 1 << 2;

    fn init() CPU {
        return .{ .program_counter = 0, .memory = _64KiB_Memory.init(), .stack_pointer = 0, .is_halted = 0, .registers = [16]i32{} };
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
            self.execute(decoded_instruction);
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
    fn decode(_: *Self, code: u32) CpuErrors!Instruction {
        switch (code) {
            OpcodeBinary.Add => {},
            OpcodeBinary.Sub => {},
        }

        return CpuErrors.InvalidInstruction;
    }

    fn execute(self: *Self, instr: Instruction) !void {
        _ = self;
        _ = instr;
        return;
    }

    // helper method to make sure we don't read outside of memory boundary.
    fn _safe_register(self: *Self, offset: u16) u32 {
        return self.memory.read_32_bytes(self.program_counter + offset) & 0x0F;
    }

    fn _is_halted(self: *Self) bool {
        return self.is_halted;
    }
};
