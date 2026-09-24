const Self = @This();

pub const Opcode = union(enum) {
    Add: struct {
        R1: u8,
        R2: u8,
    },
    Sub: struct { R1: u8, R2: u8 },
};

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
pub const OpcodeBinary = enum(u8) {
    Add = 0x30,
    Sub = 0x31,
    Load = 0x10,
    Mov = 0x11,
    HLT = 0x01,
};
