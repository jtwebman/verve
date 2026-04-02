const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const ir = @import("ir.zig");
const testing = std.testing;
const alloc = std.heap.page_allocator;

/// Parse and lower Verve source to IR, return the program.
fn lowerSource(source: []const u8) !ir.Program {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    return try lower.lowerFile(file);
}

/// Find a function by name in the program.
fn findFunction(program: ir.Program, name: []const u8) ?ir.Function {
    for (program.functions.items) |func| {
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    return null;
}

/// Check if any instruction in any block matches a predicate.
fn hasInst(func: ir.Function, comptime pred: fn (ir.Inst) bool) bool {
    for (func.blocks.items) |block| {
        for (block.insts.items) |inst| {
            if (pred(inst)) return true;
        }
    }
    return false;
}

fn isAddI64(inst: ir.Inst) bool {
    return inst == .add_i64;
}

fn isAddF64(inst: ir.Inst) bool {
    return inst == .add_f64;
}

fn isRet(inst: ir.Inst) bool {
    return inst == .ret;
}

fn isBranch(inst: ir.Inst) bool {
    return inst == .branch;
}

fn isCall(inst: ir.Inst) bool {
    return inst == .call;
}

fn isStructAlloc(inst: ir.Inst) bool {
    return inst == .struct_alloc;
}

fn isStructStore(inst: ir.Inst) bool {
    return inst == .struct_store;
}

fn isCallBuiltin(inst: ir.Inst) bool {
    return inst == .call_builtin;
}

fn isProcessSpawn(inst: ir.Inst) bool {
    return inst == .process_spawn;
}

fn isConstInt(inst: ir.Inst) bool {
    return inst == .const_int;
}

fn isConstString(inst: ir.Inst) bool {
    return inst == .const_string;
}

fn isStoreLocal(inst: ir.Inst) bool {
    return inst == .store_local;
}

fn isLoadLocal(inst: ir.Inst) bool {
    return inst == .load_local;
}

// ── Tests ────────────────────────────────────────────────

test "IR: integer addition lowers to add_i64" {
    const program = try lowerSource(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\process Math {
        \\    receive main() -> int { return 0; }
        \\}
    );
    const func = findFunction(program, "add") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isAddI64));
    try testing.expect(hasInst(func, isRet));
}

test "IR: float addition lowers to add_f64" {
    const program = try lowerSource(
        \\module Math {
        \\    fn add(a: float, b: float) -> float {
        \\        return a + b;
        \\    }
        \\}
        \\process Math {
        \\    receive main() -> int { return 0; }
        \\}
    );
    const func = findFunction(program, "add") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isAddF64));
}

test "IR: if/else lowers to branch" {
    const program = try lowerSource(
        \\module App {
        \\    fn abs(x: int) -> int {
        \\        if x > 0 {
        \\            return x;
        \\        } else {
        \\            return 0 - x;
        \\        }
        \\    }
        \\}
        \\process App {
        \\    receive main() -> int { return 0; }
        \\}
    );
    const func = findFunction(program, "abs") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isBranch));
    // Should have multiple blocks (entry, then, else)
    try testing.expect(func.blocks.items.len >= 3);
}

test "IR: function call lowers to call instruction" {
    const program = try lowerSource(
        \\module App {
        \\    fn helper() -> int { return 42; }
        \\}
        \\process App {
        \\    receive main() -> int {
        \\        return App.helper();
        \\    }
        \\}
    );
    const func = findFunction(program, "main") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isCall));
}

test "IR: struct literal lowers to struct_alloc and struct_store" {
    const program = try lowerSource(
        \\struct Point {
        \\    x: int = 0;
        \\    y: int = 0;
        \\}
        \\process App {
        \\    receive main() -> int {
        \\        p: Point = Point { x: 10, y: 20 };
        \\        return 0;
        \\    }
        \\}
    );
    const func = findFunction(program, "main") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isStructAlloc));
    try testing.expect(hasInst(func, isStructStore));
}

test "IR: return statement lowers to ret" {
    const program = try lowerSource(
        \\process App {
        \\    receive main() -> int {
        \\        return 42;
        \\    }
        \\}
    );
    const func = findFunction(program, "main") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isRet));
    try testing.expect(hasInst(func, isConstInt));
}

test "IR: variable assignment lowers to store_local/load_local" {
    const program = try lowerSource(
        \\process App {
        \\    receive main() -> int {
        \\        x: int = 10;
        \\        return x;
        \\    }
        \\}
    );
    const func = findFunction(program, "main") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isStoreLocal));
    try testing.expect(hasInst(func, isLoadLocal));
}

test "IR: string constant lowers to const_string" {
    const program = try lowerSource(
        \\process App {
        \\    receive main() -> int {
        \\        s: string = "hello";
        \\        return 0;
        \\    }
        \\}
    );
    const func = findFunction(program, "main") orelse return error.TestUnexpectedResult;
    try testing.expect(hasInst(func, isConstString));
}

test "IR: program has correct entry module" {
    const program = try lowerSource(
        \\process App {
        \\    receive main() -> int { return 0; }
        \\}
    );
    try testing.expectEqualStrings("App", program.entry_module);
    try testing.expectEqualStrings("main", program.entry_function);
}

test "IR: function count matches source" {
    const program = try lowerSource(
        \\module App {
        \\    fn helper() -> int { return 1; }
        \\    fn other() -> int { return 2; }
        \\}
        \\process App {
        \\    receive main() -> int { return 0; }
        \\}
    );
    // Should have 3 functions
    try testing.expectEqual(@as(usize, 3), program.functions.items.len);
}
