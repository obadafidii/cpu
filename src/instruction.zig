const std = @import("std");
const Opcode = @import("opcode.zig").Opcode;

// Instruction this is the structural layout of
// what the decoded binary will look like when read
// from memory.
//
// In computer architecture there are 3 major types of
// instructions.
//
// 1. Operation instruction eg ADD, SUB and NOT
// 2. Data movement instruction eg MOV, STORE and LOAD
// 3. Control flow instruction eg CALL, RET
//
// The immediate is added for immediate instruction type I-Type
// eg ADDI, SUBI, where we are reading the value from register
// instead of memory.
pub const Instruction = struct {
    // operation to be performed.
    opcode: Opcode,

    // destination register
    // ADD r1, r2 -> add value in
    // r2 to r1 and store in r2
    register1: u32,

    // source register
    // ADD r1, r2 -> r2 is source
    register2: u32,

    // used for jumps and memory operations
    addresses: u16,

    // for immediate values
    immediate: u32,

    // size of the instruction, it is used to move
    // to the beginning of the next instruction using
    // the current's instruction length.
    length: u8,

    const Self = @This();

    pub fn init(opcode: Opcode) Instruction {
        return .{
            .register1 = 0,
            .register2 = 0,
            .addresses = 0,
            .immediate = 0,
            .length = 0,
            .opcode = opcode,
        };
    }
};
