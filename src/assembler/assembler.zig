/// Assembler module handles scanning/parsing
/// and execution of assembly code that will
/// be feed into the cpu later.
///
/// Assembler is divided into two sections
///     1. Data section (.data): where variables,
///        user inputs or generally data is stored
///     2. Text Section (.text): this is where
///        instructions are stored.
///
/// Example
///     .data
///         age: 10
///         name: .asciiz "king"
///
///     .text
///     start:
///         LOAD R1, age        ; R1 <- address of `age` (0x1000)
///         LOAD R2, 0x20
///         ADD  R1, R2
///         HLT
///
/// The assembler works in three steps:
///     1. scan:     source text -> tokens
///     2. parse:    tokens -> parsed instructions + data, every
///                  label/variable gets an address (pass 1)
///     3. resolve:  symbols used as operands are replaced by their
///                  addresses and machine code is emitted (pass 2)
///
/// Encoding (matches what Cpu.decode expects): every field of an
/// instruction occupies a full 32-bit little-endian word.
///     LOAD rd, imm   -> [0x10][rd][imm]     12 bytes
///     MOV  rd, rs    -> [0x11][rd][rs]      12 bytes
///     ADD  rd, rs    -> [0x30][rd][rs]      12 bytes
///     SUB  rd, rs    -> [0x31][rd][rs]      12 bytes
///     HLT            -> [0x01]               4 bytes
///
/// Jump instructions (JMP, JZ, JNZ) are recognised but not
/// assembled yet.
const std = @import("std");
const opcode_mod = @import("../opcode.zig");
const memory = @import("../memory.zig");
const symbol_table = @import("symbol_table.zig");

// standard library
const Allocator = std.mem.Allocator;

// user imports
const Opcode = opcode_mod.Opcode;
const MemoryMap = memory.MemoryMap;
const SymbolTable = symbol_table.SymbolTable;
pub const Symbol = symbol_table.Symbol;

pub const AssembleError = error{AssemblyFailed} || Allocator.Error;

pub const TokType = enum {
    Tok_Instruction,
    Register,
    Number,
    Address, // reserved for jump targets, not used yet
    Label, // identifier directly followed by ':'
    Identifier,
    Directive, // .data, .text, .word ...
    String, // "hello"
    Colon,
    Comma,
    EOL, // end-of-line
    EOF, // end-of-file
};

pub const Token = struct {
    type: TokType,
    text: []const u8,
    // numeric payload: register index, opcode or literal value.
    // i128 so both negative literals and full 64-bit values fit.
    value: i128,
    line: u32,
    column: u32,

    pub fn init(
        _text: []const u8,
        _type: TokType,
        value: i128,
        line: u32,
        column: u32,
    ) Token {
        return .{ .text = _text, .type = _type, .value = value, .line = line, .column = column };
    }
};

// An operand is either known right away (register, number) or
// refers to a symbol that is resolved in pass 2.
pub const Operand = union(enum) {
    none,
    register: u4,
    immediate: u32,
    symbol: Token,
};

pub const ParsedInstruction = struct {
    opcode: Opcode,
    operands: [2]Operand,
    // address of the instruction in ROM
    address: u32,
    // size in bytes
    size: u32,
    line: u32,
};

pub const Directive = enum {
    Byte,
    Half,
    Word,
    DWord,
    ASCII,
    ASCIIZ,
    Space,

    pub fn from_text(text: []const u8) ?Directive {
        const table = .{
            .{ ".byte", Directive.Byte },
            .{ ".half", Directive.Half },
            .{ ".word", Directive.Word },
            .{ ".dword", Directive.DWord },
            .{ ".ascii", Directive.ASCII },
            .{ ".asciiz", Directive.ASCIIZ },
            .{ ".space", Directive.Space },
        };
        inline for (table) |entry| {
            if (std.ascii.eqlIgnoreCase(text, entry[0])) return entry[1];
        }
        return null;
    }

    // natural alignment of the directive, values are placed on
    // addresses that are a multiple of their size.
    pub fn alignment(self: Directive) u32 {
        return switch (self) {
            .Half => 2,
            .Word => 4,
            .DWord => 8,
            else => 1,
        };
    }

    pub fn element_size(self: Directive) u32 {
        return switch (self) {
            .Byte => 1,
            .Half => 2,
            .Word => 4,
            .DWord => 8,
            else => 1,
        };
    }
};

pub const Data = struct { name: ?[]const u8, directive: Directive, address: u32, size: u32, line: u32 };

// maps a ROM address to the source line it was assembled from, the
// frontend uses this to highlight the line the CPU is executing.
pub const SourceMapEntry = extern struct { address: u32, line: u32 };

pub const Diagnostic = struct {
    line: u32 = 0,
    column: u32 = 0,
    buffer: [256]u8 = undefined,
    len: usize = 0,

    pub fn message(self: *const Diagnostic) []const u8 {
        return self.buffer[0..self.len];
    }
};

const Section = enum { text, data };

const Mnemonic = struct { name: []const u8, opcode: Opcode };
const mnemonics = [_]Mnemonic{
    .{ .name = "LOAD", .opcode = .Load },
    .{ .name = "LD", .opcode = .Load },
    .{ .name = "LDI", .opcode = .Load },
    .{ .name = "MOV", .opcode = .Mov },
    .{ .name = "ADD", .opcode = .Add },
    .{ .name = "SUB", .opcode = .Sub },
    .{ .name = "HLT", .opcode = .Hlt },
    .{ .name = "HALT", .opcode = .Hlt },
    .{ .name = "JMP", .opcode = .JMP },
    .{ .name = "JZ", .opcode = .JZ },
    .{ .name = "JNZ", .opcode = .JNZ },
};

fn lookup_mnemonic(text: []const u8) ?Opcode {
    for (mnemonics) |m| {
        if (std.ascii.eqlIgnoreCase(m.name, text)) return m.opcode;
    }
    return null;
}

// R0..R15 (case insensitive), returns the register index
fn lookup_register(text: []const u8) ?u4 {
    if (text.len < 2 or text.len > 3) return null;
    if (text[0] != 'R' and text[0] != 'r') return null;
    const index = std.fmt.parseInt(u8, text[1..], 10) catch return null;
    // reject things like "R01"
    if (text.len == 3 and text[1] == '0') return null;
    if (index > 15) return null;
    return @intCast(index);
}

fn is_ident_start(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn is_ident_char(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub const Assembler = struct {
    const Self = @This();

    // code section that contains instructions
    text: std.ArrayList(u32),

    // data section that contains variables, the memory is byte
    // addressable so data is kept as raw bytes.
    data: std.ArrayList(u8),

    tokens: std.ArrayList(Token),
    instructions: std.ArrayList(ParsedInstruction),
    data_items: std.ArrayList(Data),
    source_map: std.ArrayList(SourceMapEntry),
    symbols: SymbolTable,

    diagnostic: Diagnostic,

    allocator: std.mem.Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .data = .empty,
            .text = .empty,
            .tokens = .empty,
            .instructions = .empty,
            .data_items = .empty,
            .source_map = .empty,
            .symbols = SymbolTable.init(allocator),
            .diagnostic = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.tokens.deinit(self.allocator);
        self.instructions.deinit(self.allocator);
        self.data_items.deinit(self.allocator);
        self.source_map.deinit(self.allocator);
        self.symbols.deinit();
    }

    // assembles `source`, on success `text`, `data` and `source_map`
    // hold the program. On failure `diagnostic` explains what went wrong.
    // Slices inside the result point into `source`, keep it alive.
    pub fn assemble(self: *Self, source: []const u8) AssembleError!void {
        try self.scan(source);
        try self.parse();
        try self.resolve_symbols();
    }

    fn fail(self: *Self, line: u32, column: u32, comptime fmt: []const u8, args: anytype) AssembleError {
        self.diagnostic.line = line;
        self.diagnostic.column = column;
        const written = std.fmt.bufPrint(&self.diagnostic.buffer, fmt, args) catch blk: {
            break :blk self.diagnostic.buffer[0..];
        };
        self.diagnostic.len = written.len;
        return AssembleError.AssemblyFailed;
    }

    // ------------------------------------------------------------------
    // 1. scanning
    // ------------------------------------------------------------------

    pub fn scan(self: *Self, source: []const u8) AssembleError!void {
        var i: usize = 0;
        var line: u32 = 1;
        var line_start: usize = 0;

        while (i < source.len) {
            const c = source[i];
            const column: u32 = @intCast(i - line_start + 1);

            // whitespace
            if (c == ' ' or c == '\t' or c == '\r') {
                i += 1;
                continue;
            }

            // comments: `; ...` or `// ...`
            if (c == ';' or (c == '/' and i + 1 < source.len and source[i + 1] == '/')) {
                while (i < source.len and source[i] != '\n') i += 1;
                continue;
            }

            if (c == '\n') {
                try self.push(Token.init("\n", .EOL, 0, line, column));
                i += 1;
                line += 1;
                line_start = i;
                continue;
            }

            if (c == ',') {
                try self.push(Token.init(source[i .. i + 1], .Comma, 0, line, column));
                i += 1;
                continue;
            }

            if (c == ':') {
                try self.push(Token.init(source[i .. i + 1], .Colon, 0, line, column));
                i += 1;
                continue;
            }

            // directives: .data .text .word ...
            if (c == '.') {
                const start = i;
                i += 1;
                while (i < source.len and is_ident_char(source[i])) i += 1;
                if (i == start + 1) return self.fail(line, column, "expected a directive name after '.'", .{});
                try self.push(Token.init(source[start..i], .Directive, 0, line, column));
                continue;
            }

            // string literal
            if (c == '"') {
                const start = i + 1;
                i += 1;
                while (i < source.len and source[i] != '"' and source[i] != '\n') {
                    // skip the escaped character, but never a newline
                    if (source[i] == '\\' and i + 1 < source.len and source[i + 1] != '\n') i += 1;
                    i += 1;
                }
                if (i >= source.len or source[i] != '"') return self.fail(line, column, "unterminated string", .{});
                try self.push(Token.init(source[start..i], .String, 0, line, column));
                i += 1;
                continue;
            }

            // character literal, becomes a number: 'A' -> 65
            if (c == '\'') {
                const start = i;
                i += 1;
                var value: u8 = 0;
                if (i < source.len and source[i] == '\\') {
                    if (i + 1 >= source.len) return self.fail(line, column, "unterminated character literal", .{});
                    value = escape(source[i + 1]) orelse
                        return self.fail(line, column, "unknown escape '\\{c}'", .{source[i + 1]});
                    i += 2;
                } else if (i < source.len and source[i] != '\n') {
                    value = source[i];
                    i += 1;
                }
                if (i >= source.len or source[i] != '\'') return self.fail(line, column, "unterminated character literal", .{});
                i += 1;
                try self.push(Token.init(source[start..i], .Number, value, line, column));
                continue;
            }

            // numbers: 42, -7, 0x2A, 0b101010, 0o52, optional '#' prefix
            if (std.ascii.isDigit(c) or c == '-' or c == '#') {
                const start = i;
                if (source[i] == '#') i += 1;
                const number_start = i;
                if (i < source.len and source[i] == '-') i += 1;
                while (i < source.len and (is_ident_char(source[i]))) i += 1;
                const text = source[number_start..i];
                const value = std.fmt.parseInt(i128, text, 0) catch {
                    return self.fail(line, column, "invalid number '{s}'", .{source[start..i]});
                };
                if (value > std.math.maxInt(u64) or value < std.math.minInt(i64)) {
                    return self.fail(line, column, "number '{s}' is too large", .{source[start..i]});
                }
                try self.push(Token.init(source[start..i], .Number, value, line, column));
                continue;
            }

            // identifiers, registers, mnemonics and labels. A leading '$'
            // is allowed for registers ($R1).
            if (is_ident_start(c) or c == '$') {
                const start = i;
                if (c == '$') i += 1;
                const name_start = i;
                while (i < source.len and is_ident_char(source[i])) i += 1;
                const name = source[name_start..i];
                if (name.len == 0) return self.fail(line, column, "expected a register after '$'", .{});

                if (lookup_register(name)) |reg| {
                    try self.push(Token.init(source[start..i], .Register, reg, line, column));
                    continue;
                }
                if (c == '$') return self.fail(line, column, "'{s}' is not a register (R0-R15)", .{source[start..i]});

                // label: identifier directly followed by ':'
                var j = i;
                while (j < source.len and (source[j] == ' ' or source[j] == '\t')) j += 1;
                if (j < source.len and source[j] == ':') {
                    try self.push(Token.init(name, .Label, 0, line, column));
                    i = j + 1;
                    continue;
                }

                if (lookup_mnemonic(name)) |op| {
                    try self.push(Token.init(name, .Tok_Instruction, @intFromEnum(op), line, column));
                    continue;
                }

                try self.push(Token.init(name, .Identifier, 0, line, column));
                continue;
            }

            return self.fail(line, column, "unexpected character '{c}'", .{c});
        }

        const column: u32 = @intCast(i - line_start + 1);
        try self.push(Token.init("\n", .EOL, 0, line, column));
        try self.push(Token.init("", .EOF, 0, line, column));
    }

    fn push(self: *Self, token: Token) Allocator.Error!void {
        try self.tokens.append(self.allocator, token);
    }

    // ------------------------------------------------------------------
    // 2. parsing (pass 1): every instruction and variable gets its address
    // ------------------------------------------------------------------

    const Parser = struct {
        asm_: *Self,
        pos: usize = 0,

        fn peek(p: *Parser) Token {
            return p.asm_.tokens.items[p.pos];
        }

        fn advance(p: *Parser) Token {
            const tok = p.asm_.tokens.items[p.pos];
            if (tok.type != .EOF) p.pos += 1;
            return tok;
        }

        fn expect(p: *Parser, kind: TokType, what: []const u8) AssembleError!Token {
            const tok = p.peek();
            if (tok.type != kind) {
                return p.asm_.fail(tok.line, tok.column, "expected {s}, found {s}", .{ what, describe(tok) });
            }
            return p.advance();
        }

        fn expect_end_of_line(p: *Parser) AssembleError!void {
            const tok = p.peek();
            if (tok.type != .EOL and tok.type != .EOF) {
                return p.asm_.fail(tok.line, tok.column, "unexpected {s} at end of line", .{describe(tok)});
            }
            _ = p.advance();
        }
    };

    fn describe(tok: Token) []const u8 {
        return switch (tok.type) {
            .EOL => "end of line",
            .EOF => "end of file",
            .Comma => "','",
            .Colon => "':'",
            .String => "a string",
            else => tok.text,
        };
    }

    pub fn parse(self: *Self) AssembleError!void {
        var p = Parser{ .asm_ = self };
        var section: Section = .text;
        var text_address: u32 = MemoryMap.ROM_START;

        // labels waiting for the next item in the data section, so
        // they point at the aligned address of the value.
        var pending: std.ArrayList(Token) = .empty;
        defer pending.deinit(self.allocator);

        while (p.peek().type != .EOF) {
            // labels at the start of a line
            while (p.peek().type == .Label) {
                const label = p.advance();
                switch (section) {
                    .text => try self.define_symbol(label, .LabelSymbol, text_address, 0),
                    .data => try pending.append(self.allocator, label),
                }
            }

            const tok = p.peek();
            switch (tok.type) {
                .EOL => {
                    _ = p.advance();
                    continue;
                },
                .Directive => {
                    if (std.ascii.eqlIgnoreCase(tok.text, ".data") or std.ascii.eqlIgnoreCase(tok.text, ".text")) {
                        _ = p.advance();
                        try self.flush_pending(&pending);
                        section = if (std.ascii.eqlIgnoreCase(tok.text, ".data")) .data else .text;
                        try p.expect_end_of_line();
                        continue;
                    }
                    const directive = Directive.from_text(tok.text) orelse
                        return self.fail(tok.line, tok.column, "unknown directive '{s}'", .{tok.text});
                    if (section != .data) {
                        return self.fail(tok.line, tok.column, "'{s}' can only be used in the .data section", .{tok.text});
                    }
                    _ = p.advance();
                    try self.parse_data(&p, directive, &pending, tok);
                },
                .Number => {
                    // shorthand from the docs: `age: 10` means `age: .word 10`
                    if (section != .data) {
                        return self.fail(tok.line, tok.column, "expected an instruction, found {s}", .{tok.text});
                    }
                    try self.parse_data(&p, .Word, &pending, tok);
                },
                .Tok_Instruction => {
                    if (section != .text) {
                        return self.fail(tok.line, tok.column, "instructions belong in the .text section, add '.text' above '{s}'", .{tok.text});
                    }
                    const instruction = try self.parse_instruction(&p, text_address);
                    text_address += instruction.size;
                    const rom_size = @as(u32, MemoryMap.ROM_END) - MemoryMap.ROM_START + 1;
                    if (text_address > rom_size) {
                        return self.fail(tok.line, tok.column, "program does not fit in ROM ({d} bytes max)", .{rom_size});
                    }
                    try self.instructions.append(self.allocator, instruction);
                },
                .Identifier => {
                    return self.fail(tok.line, tok.column, "unknown instruction '{s}'", .{tok.text});
                },
                else => {
                    return self.fail(tok.line, tok.column, "unexpected {s}", .{describe(tok)});
                },
            }
        }

        try self.flush_pending(&pending);
    }

    fn define_symbol(self: *Self, tok: Token, kind: symbol_table.Type, address: u32, size: u32) AssembleError!void {
        self.symbols.define(.{
            .name = tok.text,
            .type = kind,
            .address = address,
            .size = size,
            .line = tok.line,
        }) catch |err| switch (err) {
            error.DuplicateSymbol => {
                const previous = self.symbols.find_symbol(tok.text).?;
                return self.fail(tok.line, tok.column, "'{s}' is already defined on line {d}", .{ tok.text, previous.line });
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    // labels that ended up on their own line in .data point at the
    // current end of the data section.
    fn flush_pending(self: *Self, pending: *std.ArrayList(Token)) AssembleError!void {
        for (pending.items) |label| {
            try self.define_symbol(label, .VarSymbol, self.data_address(), 0);
        }
        pending.clearRetainingCapacity();
    }

    fn data_address(self: *const Self) u32 {
        return MemoryMap.RAM_START + @as(u32, @intCast(self.data.items.len));
    }

    fn parse_data(self: *Self, p: *Parser, directive: Directive, pending: *std.ArrayList(Token), at: Token) AssembleError!void {
        // align the data section first so the labels point at the value
        const alignment = directive.alignment();
        while (self.data.items.len % alignment != 0) try self.data.append(self.allocator, 0);

        const start = self.data_address();
        for (pending.items) |label| try self.define_symbol(label, .VarSymbol, start, 0);

        switch (directive) {
            .Byte, .Half, .Word, .DWord => {
                const size = directive.element_size();
                while (true) {
                    const tok = try p.expect(.Number, "a number");
                    try self.check_range(tok, size);
                    const bits: u64 = @truncate(@as(u128, @bitCast(tok.value)));
                    var n: u32 = 0;
                    while (n < size) : (n += 1) {
                        try self.data.append(self.allocator, @truncate(bits >> @intCast(n * 8)));
                    }
                    if (p.peek().type != .Comma) break;
                    _ = p.advance();
                }
            },
            .ASCII, .ASCIIZ => {
                const tok = try p.expect(.String, "a string");
                try self.append_string(tok);
                if (directive == .ASCIIZ) try self.data.append(self.allocator, 0);
            },
            .Space => {
                const tok = try p.expect(.Number, "a size in bytes");
                if (tok.value < 0 or tok.value > 0xFFFF) {
                    return self.fail(tok.line, tok.column, ".space needs a size between 0 and 65535", .{});
                }
                try self.data.appendNTimes(self.allocator, 0, @intCast(tok.value));
            },
        }
        try p.expect_end_of_line();

        const ram_size = @as(usize, MemoryMap.RAM_END) - MemoryMap.RAM_START + 1;
        if (self.data.items.len > ram_size) {
            return self.fail(at.line, at.column, "data does not fit in RAM ({d} bytes max)", .{ram_size});
        }

        const size = self.data_address() - start;
        for (pending.items) |label| self.symbols.set_size(label.text, size);
        try self.data_items.append(self.allocator, .{
            .name = if (pending.items.len > 0) pending.items[0].text else null,
            .directive = directive,
            .address = start,
            .size = size,
            .line = at.line,
        });
        pending.clearRetainingCapacity();
    }

    fn check_range(self: *Self, tok: Token, size: u32) AssembleError!void {
        if (size >= 8) return; // scanner already limited it to 64 bits
        const bits: u7 = @intCast(size * 8);
        const max: i128 = (@as(i128, 1) << bits) - 1;
        const min: i128 = -(@as(i128, 1) << (bits - 1));
        if (tok.value > max or tok.value < min) {
            return self.fail(tok.line, tok.column, "{s} does not fit in {d} byte(s)", .{ tok.text, size });
        }
    }

    fn append_string(self: *Self, tok: Token) AssembleError!void {
        var i: usize = 0;
        while (i < tok.text.len) : (i += 1) {
            var c = tok.text[i];
            if (c == '\\') {
                i += 1;
                c = escape(tok.text[i]) orelse
                    return self.fail(tok.line, tok.column, "unknown escape '\\{c}'", .{tok.text[i]});
            }
            try self.data.append(self.allocator, c);
        }
    }

    fn parse_instruction(self: *Self, p: *Parser, address: u32) AssembleError!ParsedInstruction {
        const tok = p.advance();
        const opcode: Opcode = @enumFromInt(@as(u8, @intCast(tok.value)));
        var instruction = ParsedInstruction{
            .opcode = opcode,
            .operands = .{ .none, .none },
            .address = address,
            .size = 12,
            .line = tok.line,
        };

        switch (opcode) {
            .Load => {
                instruction.operands[0] = .{ .register = try parse_register(p) };
                _ = try p.expect(.Comma, "','");
                const value = p.peek();
                switch (value.type) {
                    .Number => {
                        _ = p.advance();
                        if (value.value > std.math.maxInt(u32) or value.value < std.math.minInt(i32)) {
                            return self.fail(value.line, value.column, "{s} does not fit in 32 bits", .{value.text});
                        }
                        instruction.operands[1] = .{ .immediate = @truncate(@as(u128, @bitCast(value.value))) };
                    },
                    .Identifier => {
                        _ = p.advance();
                        instruction.operands[1] = .{ .symbol = value };
                    },
                    else => return self.fail(value.line, value.column, "expected a number or a variable, found {s}", .{describe(value)}),
                }
            },
            .Mov, .Add, .Sub => {
                instruction.operands[0] = .{ .register = try parse_register(p) };
                _ = try p.expect(.Comma, "','");
                instruction.operands[1] = .{ .register = try parse_register(p) };
            },
            .Hlt => {
                instruction.size = 4;
            },
            .JMP, .JZ, .JNZ => {
                return self.fail(tok.line, tok.column, "jump instructions ({s}) are not supported by the assembler yet", .{tok.text});
            },
            _ => unreachable,
        }

        try p.expect_end_of_line();
        return instruction;
    }

    fn parse_register(p: *Parser) AssembleError!u4 {
        const tok = p.peek();
        if (tok.type != .Register) {
            return p.asm_.fail(tok.line, tok.column, "expected a register (R0-R15), found {s}", .{describe(tok)});
        }
        _ = p.advance();
        return @intCast(tok.value);
    }

    // ------------------------------------------------------------------
    // 3. resolving symbols (pass 2) and emitting machine code
    // ------------------------------------------------------------------

    pub fn resolve_symbols(self: *Self) AssembleError!void {
        for (self.instructions.items) |instruction| {
            try self.source_map.append(self.allocator, .{ .address = instruction.address, .line = instruction.line });
            try self.text.append(self.allocator, @intFromEnum(instruction.opcode));
            if (instruction.opcode == .Hlt) continue;

            for (instruction.operands) |operand| {
                const word: u32 = switch (operand) {
                    .none => continue,
                    .register => |r| r,
                    .immediate => |v| v,
                    .symbol => |tok| blk: {
                        const symbol = self.symbols.find_symbol(tok.text) orelse
                            return self.fail(tok.line, tok.column, "undefined symbol '{s}'", .{tok.text});
                        break :blk symbol.address;
                    },
                };
                try self.text.append(self.allocator, word);
            }
        }
    }
};

fn escape(c: u8) ?u8 {
    return switch (c) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '0' => 0,
        '\\' => '\\',
        '"' => '"',
        '\'' => '\'',
        else => null,
    };
}

// ----------------------------------------------------------------------
// tests
// ----------------------------------------------------------------------

const testing = std.testing;

fn expect_program(source: []const u8, expected_text: []const u32, expected_data: []const u8) !void {
    var assembler = Assembler.init(testing.allocator);
    defer assembler.deinit();
    assembler.assemble(source) catch |err| {
        std.debug.print("line {d}: {s}\n", .{ assembler.diagnostic.line, assembler.diagnostic.message() });
        return err;
    };
    try testing.expectEqualSlices(u32, expected_text, assembler.text.items);
    try testing.expectEqualSlices(u8, expected_data, assembler.data.items);
}

fn expect_failure(source: []const u8, line: u32, needle: []const u8) !void {
    var assembler = Assembler.init(testing.allocator);
    defer assembler.deinit();
    try testing.expectError(AssembleError.AssemblyFailed, assembler.assemble(source));
    try testing.expectEqual(line, assembler.diagnostic.line);
    if (std.mem.indexOf(u8, assembler.diagnostic.message(), needle) == null) {
        std.debug.print("message was: {s}\n", .{assembler.diagnostic.message()});
        return error.TestUnexpectedResult;
    }
}

test "assembler: matches the hand written ROM in Cpu.simulate" {
    try expect_program(
        \\LOAD R0, 3
        \\LOAD R1, 5
        \\ADD R0, R1
        \\HLT
    , &.{ 0x10, 0, 3, 0x10, 1, 5, 0x30, 0, 1, 0x01 }, &.{});
}

test "assembler: comments, case, aliases and number formats" {
    try expect_program(
        \\; full line comment
        \\  ldi $r2, #0x2A   // hex with '#' prefix
        \\  LD  R15, 0b11    ; binary
        \\  load r3, 'A'
        \\  LOAD R4, -1
        \\  mov r1, r2
        \\  sub R1, R15
        \\  halt
    , &.{ 0x10, 2, 42, 0x10, 15, 3, 0x10, 3, 65, 0x10, 4, 0xFFFFFFFF, 0x11, 1, 2, 0x31, 1, 15, 0x01 }, &.{});
}

test "assembler: data section and symbol resolution" {
    var assembler = Assembler.init(testing.allocator);
    defer assembler.deinit();
    try assembler.assemble(
        \\.text
        \\start:
        \\    LOAD R1, age
        \\    LOAD R2, name
        \\    LOAD R3, total
        \\    HLT
        \\.data
        \\age: 10
        \\flag: .byte 1, 2
        \\name: .asciiz "ok\n"
        \\total:
        \\    .word 0x11223344
        \\buf: .space 3
    );

    try testing.expectEqualSlices(u32, &.{ 0x10, 1, 0x1000, 0x10, 2, 0x1006, 0x10, 3, 0x100C, 0x01 }, assembler.text.items);
    try testing.expectEqualSlices(u8, &.{
        10, 0, 0, 0, // age
        1, 2, // flag
        'o', 'k', '\n', 0, // name
        0, 0, // padding so total is word aligned
        0x44, 0x33, 0x22, 0x11, // total
        0, 0, 0, // buf
    }, assembler.data.items);

    try testing.expectEqual(@as(u32, 0), assembler.symbols.find_symbol("start").?.address);
    try testing.expectEqual(@as(u32, 4), assembler.symbols.find_symbol("total").?.size);
    try testing.expectEqual(@as(u32, 0x1010), assembler.symbols.find_symbol("buf").?.address);

    // source map points every instruction at its line
    try testing.expectEqual(@as(usize, 4), assembler.source_map.items.len);
    try testing.expectEqual(SourceMapEntry{ .address = 12, .line = 4 }, assembler.source_map.items[1]);
    try testing.expectEqual(SourceMapEntry{ .address = 36, .line = 6 }, assembler.source_map.items[3]);
}

test "assembler: reports errors with line numbers" {
    try expect_failure("LOAD R0, 1\nFOO R1, R2\n", 2, "unknown instruction 'FOO'");
    try expect_failure("ADD R0, 5\n", 1, "expected a register");
    try expect_failure("MOV R16, R0\n", 1, "expected a register");
    try expect_failure("LOAD R0, missing\nHLT\n", 1, "undefined symbol 'missing'");
    try expect_failure("x:\nx:\n", 2, "already defined on line 1");
    try expect_failure(".data\nb: .byte 300\n", 2, "does not fit");
    try expect_failure(".data\nLOAD R0, 1\n", 2, ".text section");
    try expect_failure("LOAD R0 1\n", 1, "expected ','");
    try expect_failure("HLT R0\n", 1, "unexpected R0");
    try expect_failure(".data\ns: .ascii \"abc\n", 2, "unterminated string");
}

test "assembler: jump instructions are not supported yet" {
    try expect_failure("JMP 0\n", 1, "not supported");
    try expect_failure("JZ 4\n", 1, "not supported");
}

test "assembler: output runs on the cpu" {
    const Cpu = @import("../cpu.zig").Cpu;

    var assembler = Assembler.init(testing.allocator);
    defer assembler.deinit();
    try assembler.assemble(
        \\.data
        \\base: .word 7
        \\.text
        \\    LOAD R0, 1000
        \\    LOAD R1, 234
        \\    ADD  R0, R1     ; 1234
        \\    LOAD R2, base   ; address of base
        \\    MOV  R3, R0
        \\    SUB  R3, R1     ; 1000
        \\    HLT
    );

    var cpu = try Cpu.init();
    cpu.reset();
    try cpu.load_program(assembler.text.items, assembler.data.items);
    try cpu.start();

    try testing.expectEqual(@as(u32, 1234), cpu.registers[0]);
    try testing.expectEqual(@as(u32, 0x1000), cpu.registers[2]);
    try testing.expectEqual(@as(u32, 1000), cpu.registers[3]);
    try testing.expectEqual(@as(u8, 7), cpu.main_memory.read_8_bits(0x1000));
}
