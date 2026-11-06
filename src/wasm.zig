// WebAssembly entry point.
//
// This file exposes the CPU and the assembler to JavaScript. Zig compiles
// it to `cpu.wasm` (see `zig build web`). JavaScript talks to it through
// plain numbers and pointers into the wasm linear memory:
//
//   1. JS writes the assembly source into `source_ptr()` and calls
//      `assemble(len)`. On success the program is loaded into the CPU.
//   2. JS calls `step()` / `reset()` and reads the machine state back
//      through `registers_ptr()`, `memory_ptr()`, `pc()`, `flags()` ...
//
// Nothing is allocated per step, the CPU lives in a single global.
const std = @import("std");
const cpu_mod = @import("cpu.zig");
const memory = @import("memory.zig");
const asm_mod = @import("assembler/assembler.zig");

const Cpu = cpu_mod.Cpu;
const Assembler = asm_mod.Assembler;
const SourceMapEntry = asm_mod.SourceMapEntry;
const MemoryMap = memory.MemoryMap;

const ROM_WORDS = (@as(usize, MemoryMap.ROM_END) - MemoryMap.ROM_START + 1) / 4;
const RAM_BYTES = @as(usize, MemoryMap.RAM_END) - MemoryMap.RAM_START + 1;

var machine: Cpu = undefined;
var ready = false;

// input buffer the assembly source is copied into from JS
var source: [64 * 1024]u8 = undefined;

// last successfully assembled program, kept so `reset` can reload it
var text: [ROM_WORDS]u32 = undefined;
var text_len: usize = 0;
var data: [RAM_BYTES]u8 = undefined;
var data_len: usize = 0;
var source_map: [ROM_WORDS]SourceMapEntry = undefined;
var source_map_len: usize = 0;

// symbols serialised as text, one per line: name \t kind \t address \t size
var symbols: [16 * 1024]u8 = undefined;
var symbols_len: usize = 0;

// last error (assembler or cpu)
var message: [256]u8 = undefined;
var message_len: usize = 0;
var message_line: u32 = 0;
var message_column: u32 = 0;

fn set_message(line: u32, column: u32, text_: []const u8) void {
    const n = @min(text_.len, message.len);
    @memcpy(message[0..n], text_[0..n]);
    message_len = n;
    message_line = line;
    message_column = column;
}

fn ensure_ready() void {
    if (ready) return;
    machine = Cpu.init() catch unreachable;
    machine.reset();
    ready = true;
}

export fn init() void {
    ensure_ready();
}

// ---------------------------------------------------------------------
// assembler
// ---------------------------------------------------------------------

export fn source_ptr() [*]u8 {
    return &source;
}

export fn source_capacity() u32 {
    return source.len;
}

// returns 0 on success, 1 when the source has an error
export fn assemble(len: u32) i32 {
    ensure_ready();
    const input = source[0..@min(len, source.len)];

    var assembler = Assembler.init(std.heap.wasm_allocator);
    defer assembler.deinit();

    assembler.assemble(input) catch |err| {
        switch (err) {
            error.AssemblyFailed => set_message(
                assembler.diagnostic.line,
                assembler.diagnostic.column,
                assembler.diagnostic.message(),
            ),
            error.OutOfMemory => set_message(0, 0, "assembler ran out of memory"),
        }
        return 1;
    };

    @memcpy(text[0..assembler.text.items.len], assembler.text.items);
    text_len = assembler.text.items.len;
    @memcpy(data[0..assembler.data.items.len], assembler.data.items);
    data_len = assembler.data.items.len;
    @memcpy(source_map[0..assembler.source_map.items.len], assembler.source_map.items);
    source_map_len = assembler.source_map.items.len;

    symbols_len = 0;
    for (assembler.symbols.symbols.items) |symbol| {
        const kind = if (symbol.type == .VarSymbol) "var" else "label";
        const line = std.fmt.bufPrint(symbols[symbols_len..], "{s}\t{s}\t{d}\t{d}\n", .{
            symbol.name, kind, symbol.address, symbol.size,
        }) catch break;
        symbols_len += line.len;
    }

    message_len = 0;
    reset();
    return 0;
}

export fn error_ptr() [*]const u8 {
    return &message;
}
export fn error_len() u32 {
    return @intCast(message_len);
}
export fn error_line() u32 {
    return message_line;
}
export fn error_column() u32 {
    return message_column;
}

export fn text_ptr() [*]const u32 {
    return &text;
}
export fn text_words() u32 {
    return @intCast(text_len);
}
export fn data_bytes() u32 {
    return @intCast(data_len);
}
// pairs of u32: (address, line)
export fn source_map_ptr() [*]const SourceMapEntry {
    return &source_map;
}
export fn source_map_count() u32 {
    return @intCast(source_map_len);
}
export fn symbols_ptr() [*]const u8 {
    return &symbols;
}
export fn symbols_bytes() u32 {
    return @intCast(symbols_len);
}

// ---------------------------------------------------------------------
// cpu
// ---------------------------------------------------------------------

// clears the machine and reloads the last assembled program
export fn reset() void {
    ensure_ready();
    machine.reset();
    machine.load_program(text[0..text_len], data[0..data_len]) catch {
        set_message(0, 0, "program does not fit in memory");
    };
}

// runs one fetch/decode/execute cycle.
// returns 0 = still running, 1 = halted, 2 = error (see error_ptr)
export fn step() i32 {
    ensure_ready();
    if (machine.is_halted == 1) return 1;
    machine.step() catch |err| {
        var buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s} at PC 0x{X:0>4}", .{ @errorName(err), machine.program_counter }) catch "cpu error";
        set_message(0, 0, msg);
        return 2;
    };
    return if (machine.is_halted == 1) 1 else 0;
}

// runs up to `max_steps` instructions, stops early on halt or error.
// returns the same codes as `step`.
export fn run(max_steps: u32) i32 {
    var i: u32 = 0;
    while (i < max_steps) : (i += 1) {
        const status = step();
        if (status != 0) return status;
    }
    return 0;
}

export fn registers_ptr() [*]const u32 {
    return &machine.registers;
}
export fn memory_ptr() [*]const u8 {
    return &machine.main_memory.space;
}
export fn memory_size() u32 {
    return memory.MEMORY_SIZE;
}
export fn pc() u32 {
    return machine.program_counter;
}
export fn sp() u32 {
    return machine.stack_pointer;
}
export fn flags() u32 {
    return machine.flags.bits();
}
export fn halted() u32 {
    return machine.is_halted;
}
export fn cycles() u32 {
    return @truncate(machine.cycles);
}

// details of the last executed instruction (for the pipeline view)
export fn has_last() u32 {
    return @intFromBool(machine.last_instruction != null);
}
export fn last_pc() u32 {
    return machine.last_pc;
}
export fn last_opcode() u32 {
    const i = machine.last_instruction orelse return 0;
    return @intFromEnum(i.opcode);
}
export fn last_r1() u32 {
    const i = machine.last_instruction orelse return 0;
    return i.register1;
}
export fn last_r2() u32 {
    const i = machine.last_instruction orelse return 0;
    return i.register2;
}
export fn last_immediate() u32 {
    const i = machine.last_instruction orelse return 0;
    return i.immediate;
}
export fn last_length() u32 {
    const i = machine.last_instruction orelse return 0;
    return i.length;
}
