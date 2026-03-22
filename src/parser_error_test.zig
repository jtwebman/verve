const std = @import("std");
const Parser = @import("parser.zig").Parser;
const testing = std.testing;

// ── Helper ────────────────────────────────────────────────

fn expectParseError(source: []const u8, expected_substring: []const u8) !void {
    var p = Parser.init(source, std.heap.page_allocator);
    const result = p.parseFile();
    try testing.expect(result == error.ParseFailed);
    const msg = p.formatError();
    const found = std.mem.indexOf(u8, msg, expected_substring) != null;
    if (!found) {
        std.debug.print("\nExpected error containing: '{s}'\nGot: '{s}'\n", .{ expected_substring, msg });
    }
    try testing.expect(found);
}

fn expectExprError(source: []const u8, expected_substring: []const u8) !void {
    var p = Parser.init(source, std.heap.page_allocator);
    const result = p.parseExpr();
    try testing.expect(result == error.ParseFailed);
    const msg = p.formatError();
    const found = std.mem.indexOf(u8, msg, expected_substring) != null;
    if (!found) {
        std.debug.print("\nExpected error containing: '{s}'\nGot: '{s}'\n", .{ expected_substring, msg });
    }
    try testing.expect(found);
}

fn expectStmtError(source: []const u8, expected_substring: []const u8) !void {
    var p = Parser.init(source, std.heap.page_allocator);
    const result = p.parseStmt();
    try testing.expect(result == error.ParseFailed);
    const msg = p.formatError();
    const found = std.mem.indexOf(u8, msg, expected_substring) != null;
    if (!found) {
        std.debug.print("\nExpected error containing: '{s}'\nGot: '{s}'\n", .{ expected_substring, msg });
    }
    try testing.expect(found);
}

// ── Top-level errors ──────────────────────────────────────

test "error: unknown top-level keyword" {
    try expectParseError("class Foo {}", "expected 'module', 'process', 'struct', 'type', 'import', or 'export'");
}

test "error: garbage at top level" {
    try expectParseError("12345", "expected 'module', 'process', 'struct', 'type', 'import', or 'export'");
}

test "error: empty module missing brace" {
    try expectParseError("module Foo", "expected '{'");
}

// ── Struct errors ─────────────────────────────────────────

test "error: struct missing opening brace" {
    try expectParseError("struct Account (", "expected '{'");
}

test "error: struct field missing colon" {
    try expectParseError("struct Account { name string; }", "expected ':'");
}

test "error: struct field missing semicolon" {
    try expectParseError("struct Account { name: string }", "expected ';'");
}

test "error: struct field missing type" {
    try expectParseError("struct Account { name: ; }", "expected identifier");
}

// ── Type errors ───────────────────────────────────────────

test "error: type missing equals" {
    try expectParseError("type Name string;", "expected '='");
}

test "error: type missing semicolon" {
    try expectParseError("type Name = string", "expected ';'");
}

test "error: enum missing closing brace" {
    try expectParseError("type X = enum { A, B", "expected '}'");
}

// ── Function errors ───────────────────────────────────────

test "error: function missing parens" {
    try expectParseError(
        \\module Test {
        \\    fn add -> int { return 1; }
        \\}
    , "expected '('");
}

test "error: function missing return type arrow" {
    try expectParseError(
        \\module Test {
        \\    fn add() int { return 1; }
        \\}
    , "expected '->'");
}

test "error: function missing body brace" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int return 1;
        \\}
    , "expected '{'");
}

test "error: function param missing colon" {
    try expectParseError(
        \\module Test {
        \\    fn add(a int) -> int { return a; }
        \\}
    , "expected ':'");
}

// ── Module errors ─────────────────────────────────────────

test "error: unknown declaration in module" {
    try expectParseError(
        \\module Test {
        \\    var x = 5;
        \\}
    , "expected 'use', 'fn', or constant declaration inside module");
}

test "error: module missing closing brace" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { return 1; }
    , "expected 'use', 'fn', or constant declaration inside module 'Test' but found '<end of file>'");
}

// ── Process errors ────────────────────────────────────────

test "error: unknown declaration in process" {
    try expectParseError(
        \\process Ledger {
        \\    fn bad() -> int { return 1; }
        \\}
    , "expected 'state', 'invariant', or 'receive' inside process");
}

test "error: process memory missing keyword" {
    try expectParseError(
        \\process Ledger [size: 64] {
        \\    state {
        \\        balance: int = 0;
        \\    }
        \\}
    , "expected 'memory'");
}

// ── Expression errors ─────────────────────────────────────

test "error: unexpected character in expression" {
    try expectExprError("@foo", "unexpected character '@'");
}

test "error: unterminated string" {
    try expectExprError("\"hello", "unterminated string");
}

test "error: empty expression" {
    try expectExprError("", "expected expression but reached end of file");
}

// ── Statement errors ──────────────────────────────────────

test "error: missing semicolon after expression" {
    try expectStmtError("x + 1", "expected ';'");
}

test "error: missing semicolon after assignment" {
    try expectStmtError("x = 1", "expected ';'");
}

test "error: while missing opening brace" {
    try expectStmtError("while true return 1;", "expected '{'");
}

test "error: match missing opening brace" {
    try expectStmtError("match x return 1;", "expected '{'");
}

// ── Reserved words ────────────────────────────────────────

test "error: reserved word as function name" {
    try expectParseError(
        \\module Test {
        \\    fn return() -> int { return 1; }
        \\}
    , "'return' is a reserved keyword");
}

test "error: reserved word as struct field" {
    try expectParseError("struct Foo { match: int; }", "'match' is a reserved keyword");
}

test "error: reserved word as type name" {
    try expectParseError("type while = int;", "'while' is a reserved keyword");
}

test "error: reserved word as module name" {
    try expectParseError("module fn {}", "'fn' is a reserved keyword");
}

test "error: reserved word as process name" {
    try expectParseError("process guard {}", "'guard' is a reserved keyword");
}

test "error: reserved word as parameter name" {
    try expectParseError(
        \\module Test {
        \\    fn add(return: int) -> int { return 1; }
        \\}
    , "'return' is a reserved keyword");
}

// ── Double semicolons ─────────────────────────────────────

test "error: double semicolon in function body" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { return 1;; }
        \\}
    , "unexpected extra ';'");
}

test "error: triple semicolon in function body" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { x = 1;;; return x; }
        \\}
    , "unexpected extra ';'");
}

// ── Edge cases ────────────────────────────────────────────

test "error: extra closing brace at top level" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { return 1; }
        \\}
        \\}
    , "expected 'module', 'process', 'struct', 'type', 'import', or 'export' at top level");
}

test "error: double open brace in function body" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int {{ return 1; }
        \\}
    , "unexpected character '{'");
}

test "error: random symbols in expression" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { return @bad; }
        \\}
    , "unexpected character '@'");
}

test "error: missing return type arrow" {
    try expectParseError(
        \\module Test {
        \\    fn add() int { return 1; }
        \\}
    , "expected '->'");
}

test "error: semicolon after function brace" {
    try expectParseError(
        \\module Test {
        \\    fn add() -> int { return 1; };
        \\}
    , "expected 'use', 'fn', or constant declaration inside module");
}

// ── Logical operator errors ──────────────────────────────

test "error: missing right side of &&" {
    try expectParseError(
        \\module Test {
        \\    fn check() -> bool {
        \\        return true &&;
        \\    }
        \\}
    , "unexpected character ';'");
}

test "error: missing right side of ||" {
    try expectParseError(
        \\module Test {
        \\    fn check() -> bool {
        \\        return true ||;
        \\    }
        \\}
    , "unexpected character ';'");
}

// ── Line number accuracy ──────────────────────────────────

test "error on line 3 reports line 3" {
    var p = Parser.init(
        \\module Test {
        \\    fn add() -> int {
        \\        return @bad;
        \\    }
        \\}
    , std.heap.page_allocator);
    _ = p.parseFile() catch {
        const msg = p.formatError();
        const found = std.mem.indexOf(u8, msg, "line 3") != null;
        if (!found) {
            std.debug.print("\nExpected 'line 3' in: '{s}'\n", .{msg});
        }
        try testing.expect(found);
        return;
    };
    try testing.expect(false); // should have errored
}

test "error on line 5 reports line 5" {
    var p = Parser.init(
        \\type X = int;
        \\type Y = string;
        \\struct Foo {
        \\    a: int;
        \\    b: ;
        \\}
    , std.heap.page_allocator);
    _ = p.parseFile() catch {
        const msg = p.formatError();
        const found = std.mem.indexOf(u8, msg, "line 5") != null;
        if (!found) {
            std.debug.print("\nExpected 'line 5' in: '{s}'\n", .{msg});
        }
        try testing.expect(found);
        return;
    };
    try testing.expect(false);
}
