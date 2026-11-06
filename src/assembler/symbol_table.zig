const std = @import("std");

// A symbol is either:
//   - a variable declared in the .data section (VarSymbol), its
//     address points into RAM (starting at 0x1000)
//   - a label declared in the .text section (LabelSymbol), its
//     address points into ROM (starting at 0x0000)
pub const Type = enum { VarSymbol, LabelSymbol };

pub const Symbol = struct {
    name: []const u8,
    type: Type,
    // where the symbol lives in memory
    address: u32,
    // number of bytes the symbol occupies (0 for labels)
    size: u32,
    // source line the symbol was declared on, used for diagnostics
    line: u32,
};

pub const SymbolError = error{DuplicateSymbol} || std.mem.Allocator.Error;

pub const SymbolTable = struct {
    const Self = @This();

    symbols: std.ArrayList(Symbol),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .symbols = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.symbols.deinit(self.allocator);
    }

    // adds a new symbol to the table, names must be unique across
    // both the .data and the .text sections.
    pub fn define(self: *Self, symbol: Symbol) SymbolError!void {
        if (self.find_symbol(symbol.name) != null) {
            return SymbolError.DuplicateSymbol;
        }
        try self.symbols.append(self.allocator, symbol);
    }

    // linear search is fine here, programs for this cpu are tiny
    // (the whole ROM is 4KiB).
    pub fn find_symbol(self: *const Self, name: []const u8) ?Symbol {
        for (self.symbols.items) |symbol| {
            if (std.mem.eql(u8, symbol.name, name)) return symbol;
        }
        return null;
    }

    // updates the size of a symbol after its data has been emitted
    pub fn set_size(self: *Self, name: []const u8, size: u32) void {
        for (self.symbols.items) |*symbol| {
            if (std.mem.eql(u8, symbol.name, name)) {
                symbol.size = size;
                return;
            }
        }
    }
};

test "symbol table: define and find" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.define(.{ .name = "age", .type = .VarSymbol, .address = 0x1000, .size = 4, .line = 2 });
    try table.define(.{ .name = "start", .type = .LabelSymbol, .address = 0, .size = 0, .line = 5 });

    try std.testing.expectEqual(@as(u32, 0x1000), table.find_symbol("age").?.address);
    try std.testing.expectEqual(Type.LabelSymbol, table.find_symbol("start").?.type);
    try std.testing.expect(table.find_symbol("missing") == null);
}

test "symbol table: duplicate names are rejected" {
    var table = SymbolTable.init(std.testing.allocator);
    defer table.deinit();

    try table.define(.{ .name = "x", .type = .VarSymbol, .address = 0x1000, .size = 4, .line = 1 });
    try std.testing.expectError(
        SymbolError.DuplicateSymbol,
        table.define(.{ .name = "x", .type = .LabelSymbol, .address = 0, .size = 0, .line = 2 }),
    );
}
