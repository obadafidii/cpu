const std = @import("std");

pub const MemoryError = error{MisconfigurationError};

// MemoryMap constructs the partitions of my 64kib memory
// I have 65535 bytes = 64KiB. To graphically understand GPT
// generated this ascii image.
//
// Address
// 0xFFFF  ┌───────────────────────────┐
//         │                           │
//         │         STACK             │  4 KiB
//         │                           │
// 0xF000  ├───────────────────────────┤
//         │                           │
//         │                           │
//         │                           │
//         │          RAM              │  56 KiB
//         │                           │
//         │                           │
//         │                           │
// 0x1000  ├───────────────────────────┤
//         │                           │
//         │          ROM              │  4 KiB
//         │                           │
// 0x0000  └───────────────────────────┘
//
// Everything sums up to 64KiB
pub const MemoryMap = struct {
    // ROM size = 4kb
    pub const ROM_START: u16 = 0x0000;
    pub const ROM_END: u16 = 0x0FFF;

    // Ram size = 56kb
    pub const RAM_START: u16 = 0x1000;
    pub const RAM_END = 0xEFFF;

    // Stack size = 4kb
    pub const STACK_START: u16 = 0xF000;
    pub const STACK_END: u16 = 0xFFFF;
};

pub const MEMORY_SIZE: usize = 65536;

// Memory is a configurable function that return a type will
// memory cells configured to the specified size.
//
// NOTE: Memory is made up of addresses and each address is 1byte.
// A single byte contains 8bits
//
// Imagine our memory as a linear array
// M = [x, x, x, x, x]
//
// To get the instruction in memory at the 2nd index will be M[pc + 1]
// This means increment the program counter by 1 byte (8 bits) to get
// the address. An instruction might span across several address
pub fn Memory(comptime N: i32) type {
    return struct {
        const Self = @This();

        // The memory space is byte addressable
        space: [N]u8,

        pub fn init() MemoryError!Self {
            if (N <= 0) {
                return MemoryError.MisconfigurationError;
            }
            return .{
                .space = [_]u8{0} ** N,
            };
        }

        pub fn size(self: Self) usize {
            return self.space.len;
        }

        // 8bits -> 1 byte
        pub fn read_8_bits(self: *const Self, address: usize) u8 {
            return self.space[address];
        }

        // 16bits -> 2 bytes, the architecture is little endian so the lower
        // byte is read first, then the higher byte is shifted left by 8 bits
        // the result is the combined 16-bit value
        //
        // Example:
        //  if the space contains [0x12, 0x34], read_16_bits(0) returns 0x3412
        // first -> self.space[address] = 0x12
        // second -> self.space[address + 1]  = 0x34
        // second -> second << 8 = 0x3400
        // first | second = 0x3412
        pub fn read_16_bits(self: *const Self, address: usize) u16 {
            return @as(u16, self.space[address]) | (@as(u16, self.space[address + 1]) << 8);
        }

        // 32bits -> 4 bytes
        //
        // Example:
        //  if the space contains [0x12, 0x34, 0x56, 0x78], read_32_bits(0) returns 0x78563412
        //  first -> self.space[address] = 0x12
        //  second -> self.space[address + 1] = 0x34
        //  third -> self.space[address + 2] = 0x56
        //  fourth -> self.space[address + 3] = 0x78
        //  fourth << 24 = 0x78000000
        //  third | fourth = 0x78560000
        //  second | third = 0x78563400
        //  first | second = 0x78563412
        pub fn read_32_bits(self: *const Self, address: usize) u32 {
            return @as(u32, self.space[address]) |
                @as(u32, self.space[address + 1]) << 8 |
                @as(u32, self.space[address + 2]) << 16 |
                @as(u32, self.space[address + 3]) << 24;
        }

        // read 8 bytes
        pub fn read_64_bits(self: *const Self, address: usize) u64 {
            return @as(u64, self.space[address]) |
                @as(u64, self.space[address + 1]) << 8 |
                @as(u64, self.space[address + 2]) << 16 |
                @as(u64, self.space[address + 3]) << 24 |
                @as(u64, self.space[address + 4]) << 32 |
                @as(u64, self.space[address + 5]) << 40 |
                @as(u64, self.space[address + 6]) << 48 |
                @as(u64, self.space[address + 7]) << 56;
        }

        // 8bits -> 1byte, this is writing one byte into a memory cell
        pub fn write_8_bits(self: *Self, address: usize, data: u8) void {
            self.space[address] = data;
        }

        // 16bits -> 2bytes, this is writing 2 bytes into 2 memory cells
        //
        // Example:
        // writing 0x1234 to memory will involve
        //  1. Shift each byte right by 1 byte 8btis
        //      = 0x1234 >> 8
        //      = 0x0012
        //
        //  2. Then truncate the value (zig's way)
        //     = @truncate(0x0012)
        //     = 0x12
        // The truncate method in zig say's "discard the top most bits and give me the rest"
        //
        // I am using little endian for my architecture and endianness is not determined by
        // bitwise operations but by the order we arrange the bytes in memory
        //
        // in 16-bit form:
        // 0x1234
        //
        // bytes:
        // [0x12][0x34]
        //  high   low
        //
        // little-endian memory:
        // lower address
        //     ↓
        // +---------+---------+
        // |  0x34   |  0x12   |
        // +---------+---------+
        //  address   address+1
        //
        // big-endian memory:
        // higer address
        //     ↓
        // +---------+---------+
        // |  0x12   |  0x34   |
        // +---------+---------+
        //  address   address+1
        pub fn write_16_bits(self: *Self, address: usize, data: u16) void {
            self.space[address] = @truncate(data); // 0x34
            self.space[address + 1] = @truncate(data >> 8); // 0x12
        }

        // 32bits -> 4bytes, this writes in 4 memory cells/locs
        pub fn write_32_bits(self: *Self, address: usize, data: u32) void {
            self.space[address] = @truncate(data); // 0x78
            self.space[address + 1] = @truncate(data >> 8); // 0x56
            self.space[address + 2] = @truncate(data >> 16); // 0x34
            self.space[address + 3] = @truncate(data >> 24); // 0x12
        }

        // 64bits -> 8bytes, this writes in 8 memory cells/locs
        pub fn write_64_bits(self: *Self, address: usize, data: u64) void {
            self.space[address] = @truncate(data);
            self.space[address + 1] = @truncate(data >> 8);
            self.space[address + 2] = @truncate(data >> 16);
            self.space[address + 3] = @truncate(data >> 24);
            self.space[address + 4] = @truncate(data >> 32);
            self.space[address + 5] = @truncate(data >> 40);
            self.space[address + 6] = @truncate(data >> 48);
            self.space[address + 7] = @truncate(data >> 56);
        }
    };
}

test "Memory: memory size is configurable" {
    const memory = try Memory(20).init();
    try std.testing.expectEqual(20, memory.size());
}

test "Memory: memory size cannot be zero" {
    try std.testing.expectError(MemoryError.MisconfigurationError, Memory(0).init());
}

test "memory can write and read 16-bit values" {
    var memory = try Memory(65536).init();

    memory.write_16_bits(0x1000, 0x1023);

    try std.testing.expectEqual(
        0x1023,
        memory.read_16_bits(0x1000),
    );
}

test "memory can write and read 8-bit values" {
    var memory = try Memory(65536).init();

    memory.write_8_bits(0x1000, 0x1);

    try std.testing.expectEqual(
        0x1,
        memory.read_8_bits(0x1000),
    );
}

test "memory can write and read 32-bit values" {
    var memory = try Memory(65536).init();

    memory.write_32_bits(0x1000, 0x12345678);

    try std.testing.expectEqual(
        0x12345678,
        memory.read_32_bits(0x1000),
    );
}

test "memory can write and read 64-bit values" {
    var memory = try Memory(65536).init();

    memory.write_64_bits(0x1000, 0x123456789ABCDEF0);

    try std.testing.expectEqual(
        0x123456789ABCDEF0,
        memory.read_64_bits(0x1000),
    );
}

test "Memory uses little-endian order" {
    var memory = try Memory(MEMORY_SIZE).init();
    memory.write_64_bits(MemoryMap.ROM_START, 0x123456789);

    // read 1 byte per time
    try std.testing.expectEqual(0x89, memory.read_8_bits(0));
    try std.testing.expectEqual(0x67, memory.read_8_bits(1));
    try std.testing.expectEqual(0x45, memory.read_8_bits(2));
    try std.testing.expectEqual(0x23, memory.read_8_bits(3));
    try std.testing.expectEqual(0x1, memory.read_8_bits(4));

    // reading outside of memory
    try std.testing.expectEqual(0, memory.read_8_bits(5));
    try std.testing.expectEqual(0, memory.read_8_bits(6));

    // 2. read 2 bytes per time.
    try std.testing.expectEqual(0x6789, memory.read_16_bits(0));
    try std.testing.expectEqual(0x2345, memory.read_16_bits(2));
    try std.testing.expectEqual(0x1, memory.read_16_bits(4));

    // 3. read 4 bytes per time.
    try std.testing.expectEqual(0x23456789, memory.read_32_bits(0));
    try std.testing.expectEqual(0x1, memory.read_32_bits(4));

    // 4. read 8 bytes per time.
    try std.testing.expectEqual(0x123456789, memory.read_64_bits(0));
}
