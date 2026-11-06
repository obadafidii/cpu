const std = @import("std");

const memory = @import("memory.zig");
const opcode_mod = @import("opcode.zig");
const Instruction = @import("instruction.zig").Instruction;

// opcodes
const Opcode = opcode_mod.Opcode;

const hexToOpcode = opcode_mod.hexToOpcode;

// memroy: 64 kibi byte memory = 64 * 1024 * 1024
const _64KiB_Memory = memory.Memory(memory.MEMORY_SIZE);

// layout of the computer memory.
const MemoryMap = memory.MemoryMap;

pub const CpuError = error{ InvalidInstruction, InvalidRegister, InvalidMemoryRead };

pub const Cpu = struct {
    const Self = @This();

    // tracks the currently executing instruction
    program_counter: u32,

    stack_pointer: u32,
    flags: FLAGS,

    // tracks if the cpu is still running.
    is_halted: u8,

    // Registers are the storage locations inside
    // the processor (cpu) they're very small
    // but extremely fast for processing. If the
    // needed value or instruction is in the register
    // we don't need to go to memory because that is costly
    // but if we need too, we use the Load/Store concept
    //
    // Conceptual Overview:
    // From: Memory -> Registers => Load
    // From: Registers -> Memory => Store
    registers: [16]u32,

    // Represents the main memory of the machine
    // it exposes APIs to load/store bits
    main_memory: _64KiB_Memory,

    const FLAGS = struct {
        const InnerSelf = @This();

        // zero flag
        Z: i8,
        // carry flag
        C: i8,
        // negative flag
        N: i8,

        pub fn set_z(self: InnerSelf, value: i8) void {
            self.Z = value;
        }

        pub fn set_x(self: InnerSelf, value: i8) void {
            self.X = value;
        }

        pub fn set_N(self: InnerSelf, value: i8) void {
            self.N = value;
        }

        pub fn zero_flag_is_set(self: InnerSelf) bool {
            return self.Z == 0;
        }

        pub fn carry_flag_is_set(self: InnerSelf) bool {
            return self.Z == 0;
        }

        pub fn default() FLAGS {
            return .{
                .Z = 1 << 0,
                .C = 1 << 1,
                .N = 1 << 2,
            };
        }
    };

    // total number of registers supported by this CPU
    const MAX_REGISTERS_COUNT: i8 = 16;

    pub fn simulate(self: *Self) !void {
        const rom = [_]u32{
            // load 3 into R0
            0x10, // load
            0x00, // R0
            3, // immediate value(3)

            // load 5 into R1
            0x10, // load opcode
            0x01, // R1
            0x05, // immediate value(5)

            // add R0, R1 and store in R0
            0x30, // add opcode
            0x00, // R0
            0x01, // R1

            // stop the cpu
            0x01, // halt opcode
        };

        std.debug.print("registers before program: {any}\n", .{self.registers});

        var word_location: u16 = MemoryMap.ROM_START;
        for (rom) |value| {
            self.main_memory.write_32_bits(word_location, value);
            word_location += 4;
        }
        try self.start();
        std.debug.print("\nregisters after program: {any}\n", .{self.registers});
        // std.debug.print("\nmain memory = {any}\n", .{self.main_memory.space});
    }

    pub fn init() !Cpu {
        return .{
            .program_counter = 0,
            .main_memory = try _64KiB_Memory.init(),
            .stack_pointer = 0,
            .is_halted = 0,
            .registers = [_]u32{0} ** MAX_REGISTERS_COUNT,
            .flags = FLAGS.default(),
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
            const jumped = try self.execute(decoded_instruction);

            // we only move to the next instruction when the instruction
            // does not perform an a jump.
            if (!jumped) {
                self._move_to_next_instruction(decoded_instruction);
            }

            //TODO: work on jump instructions later. JZ, JNZ, JP
        }
    }

    // Fetch: read instructions in bytes from main memory
    // it reads 4 memory cells at once which means it returns 32 bits.
    fn fetch(self: *Self) u32 {
        return self.main_memory.read_32_bits(self.program_counter);
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
                // PC           4bytes    4bytes
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
            // [jump-instruction] <address>
            .JMP, .JZ, .JNZ => |op| {
                var jump_instrcution = Instruction.init(op);
                jump_instrcution.length = 8;
                return jump_instrcution;
            },
            _ => CpuError.InvalidInstruction,
        };
    }

    fn execute(self: *Self, instruction: Instruction) !bool {
        var jump_occurred: bool = false;

        try switch (instruction.opcode) {
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
            .JMP => {
                // a jump instruction just moves (jumps) the program
                // counter to the specified address
                self.program_counter = instruction.addresses;
                jump_occurred = true;
            },
            .JZ => {
                // the JZ instruction only jump is the zero flag is set.
                if (self.flags.zero_flag_is_set()) {
                    self.program_counter = instruction.addresses;
                    jump_occurred = true;
                }
            },
            .JNZ => {
                // JNZ instruction jumps when zero flag is not set
                if (self.flags.zero_flag_is_set()) {
                    self.program_counter = instruction.addresses;
                    jump_occurred = true;
                }
            },
            .Hlt => {
                self.is_halted = 1;
            },
            _ => CpuError.InvalidInstruction,
        };

        return jump_occurred;
    }

    // helper method to make sure we don't read outside of memory boundary.
    fn _safely_read_register_at_offset(self: *const Self, offset: u16) CpuError!u32 {
        const reg = self.main_memory.read_32_bits(self.program_counter + offset);

        // 15 is the number of registers my cpu has.
        if (reg > MAX_REGISTERS_COUNT) {
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

    const jmp = try cpu.decode(0x40);
    try std.testing.expectEqual(jmp.opcode, Opcode.JMP);
    try std.testing.expectEqual(jmp.length, 8);

    const jz = try cpu.decode(0x41);
    try std.testing.expectEqual(jz.opcode, Opcode.JZ);
    try std.testing.expectEqual(jz.length, 8);

    const jnz = try cpu.decode(0x42);
    try std.testing.expectEqual(jnz.opcode, Opcode.JNZ);
    try std.testing.expectEqual(jnz.length, 8);
}
