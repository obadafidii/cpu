const Self = @This();

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
//
// Something I learnt is non-exhaustive switch using _, it allows you to be able to neatly handle
// cases not captured in the enum during conversion like @enumFromInt()
pub const Opcode = enum(u8) { Add = 0x30, Sub = 0x31, Load = 0x10, Mov = 0x11, Hlt = 0x01, _ };

pub fn hexToOpcode(hex: u8) Opcode {
    return @enumFromInt(hex);
}
