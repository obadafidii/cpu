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

pub fn Memory(comptime N: i32) type {
    return struct {
        const Self = @This();
        space: [N]i8,

        pub fn init() MemoryError!Self {
            if (N <= 0) {
                return MemoryError.MisconfigurationError;
            }
            return .{
                .space = [_]i8{0} ** N,
            };
        }

        pub fn size(self: Self) i8 {
            return self.space.len;
        }

        pub fn read_8_bytes(self: *Self, address: u16) u8 {
            _ = self;
            _ = address;
            return "";
        }
        pub fn read_16_bytes(self: *Self, address: u16) u16 {
            _ = self;
            _ = address;
            return "";
        }
        pub fn read_32_bytes(self: *Self, address: u32) u32 {
            _ = self;
            _ = address;
            return 1;
        }

        pub fn write_8_bytes(self: *Self, address: u16, data: u8) void {
            _ = self;
            _ = address;
            _ = data;
        }

        pub fn write_16_bytes(self: *Self, address: u16, data: u16) void {
            _ = self;
            _ = address;
            _ = data;
        }

        pub fn write_32_bytes(self: *Self, address: u16, data: u32) void {
            _ = self;
            _ = address;
            _ = data;
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
