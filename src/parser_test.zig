const std = @import("std");
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const testing = std.testing;

// ── Helper ────────────────────────────────────────────────
// Use page_allocator so test runner doesn't report leaks.
// Parser AST lives for the duration of compilation — no deinit path.

fn parse(source: []const u8) Parser {
    return Parser.init(source, std.heap.page_allocator);
}

// ── Type Declarations ─────────────────────────────────────

test "parse simple type alias" {
    var p = parse("type Name = string;");
    _ = p.matchKeyword("type");
    const decl = try p.parseTypeDecl();
    try testing.expectEqualStrings("Name", decl.name);
    try testing.expectEqualStrings("string", decl.value.simple);
}

test "parse enum type" {
    var p = parse("type Currency = enum { USD, EUR, GBP };");
    _ = p.matchKeyword("type");
    const decl = try p.parseTypeDecl();
    try testing.expectEqualStrings("Currency", decl.name);
    try testing.expectEqual(@as(usize, 3), decl.value.enum_type.len);
    try testing.expectEqualStrings("USD", decl.value.enum_type[0]);
    try testing.expectEqualStrings("EUR", decl.value.enum_type[1]);
    try testing.expectEqualStrings("GBP", decl.value.enum_type[2]);
}

// ── Struct Declarations ───────────────────────────────────

test "parse simple struct" {
    var p = parse(
        \\struct Account {
        \\    id: uuid;
        \\    name: string;
        \\    active: bool;
        \\}
    );
    _ = p.matchKeyword("struct");
    const decl = try p.parseStructDecl();
    try testing.expectEqualStrings("Account", decl.name);
    try testing.expectEqual(@as(usize, 3), decl.fields.len);
    try testing.expectEqualStrings("id", decl.fields[0].name);
    try testing.expectEqualStrings("uuid", decl.fields[0].type_expr.simple);
    try testing.expectEqualStrings("name", decl.fields[1].name);
    try testing.expectEqualStrings("active", decl.fields[2].name);
    try testing.expectEqualStrings("bool", decl.fields[2].type_expr.simple);
}

test "parse generic struct" {
    var p = parse(
        \\struct Queue<T> {
        \\    head: int;
        \\    tail: int;
        \\}
    );
    _ = p.matchKeyword("struct");
    const decl = try p.parseStructDecl();
    try testing.expectEqualStrings("Queue", decl.name);
    try testing.expectEqual(@as(usize, 1), decl.type_params.len);
    try testing.expectEqualStrings("T", decl.type_params[0]);
}

// ── Expressions ───────────────────────────────────────────

test "parse integer literal" {
    var p = parse("42");
    const expr = try p.parseExpr();
    try testing.expectEqual(@as(i64, 42), expr.int_literal);
}

test "parse string literal" {
    var p = parse("\"hello world\"");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("hello world", expr.string_literal);
}

test "parse bool true" {
    var p = parse("true");
    const expr = try p.parseExpr();
    try testing.expectEqual(true, expr.bool_literal);
}

test "parse bool false" {
    var p = parse("false");
    const expr = try p.parseExpr();
    try testing.expectEqual(false, expr.bool_literal);
}

test "parse tag" {
    var p = parse(":ok");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("ok", expr.tag);
}

test "parse identifier" {
    var p = parse("foo");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("foo", expr.identifier);
}

test "parse addition" {
    var p = parse("1 + 2");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Op.add, expr.binary_op.op);
    try testing.expectEqual(@as(i64, 1), expr.binary_op.left.int_literal);
    try testing.expectEqual(@as(i64, 2), expr.binary_op.right.int_literal);
}

test "parse multiplication before addition" {
    var p = parse("1 + 2 * 3");
    const expr = try p.parseExpr();
    // should be 1 + (2 * 3)
    try testing.expectEqual(ast.Op.add, expr.binary_op.op);
    try testing.expectEqual(@as(i64, 1), expr.binary_op.left.int_literal);
    try testing.expectEqual(ast.Op.mul, expr.binary_op.right.binary_op.op);
}

test "parse comparison" {
    var p = parse("a >= b");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Op.gte, expr.binary_op.op);
    try testing.expectEqualStrings("a", expr.binary_op.left.identifier);
    try testing.expectEqualStrings("b", expr.binary_op.right.identifier);
}

test "parse equality" {
    var p = parse("x == 0");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Op.eq, expr.binary_op.op);
    try testing.expectEqualStrings("x", expr.binary_op.left.identifier);
    try testing.expectEqual(@as(i64, 0), expr.binary_op.right.int_literal);
}

test "parse inequality" {
    var p = parse("a != b");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Op.neq, expr.binary_op.op);
}

test "parse field access" {
    var p = parse("account.balance");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("balance", expr.field_access.field);
    try testing.expectEqualStrings("account", expr.field_access.target.identifier);
}

test "parse chained field access" {
    var p = parse("a.b.c");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("c", expr.field_access.field);
    try testing.expectEqualStrings("b", expr.field_access.target.field_access.field);
    try testing.expectEqualStrings("a", expr.field_access.target.field_access.target.identifier);
}

test "parse index access" {
    var p = parse("items[0]");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("items", expr.index_access.target.identifier);
    try testing.expectEqual(@as(i64, 0), expr.index_access.index.int_literal);
}

test "parse function call" {
    var p = parse("add(1, 2)");
    const expr = try p.parseExpr();
    try testing.expectEqualStrings("add", expr.call.target.identifier);
    try testing.expectEqual(@as(usize, 2), expr.call.args.len);
    try testing.expectEqual(@as(i64, 1), expr.call.args[0].int_literal);
    try testing.expectEqual(@as(i64, 2), expr.call.args[1].int_literal);
}

test "parse method call" {
    var p = parse("Math.add(1, 2)");
    const expr = try p.parseExpr();
    try testing.expectEqual(@as(usize, 2), expr.call.args.len);
    try testing.expectEqualStrings("add", expr.call.target.field_access.field);
    try testing.expectEqualStrings("Math", expr.call.target.field_access.target.identifier);
}

test "parse not expression" {
    var p = parse("!active");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Op.not, expr.unary_op.op);
    try testing.expectEqualStrings("active", expr.unary_op.operand.identifier);
}

test "parse none literal" {
    var p = parse("none");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Expr{ .none_literal = {} }, expr);
}

test "parse void literal" {
    var p = parse("void");
    const expr = try p.parseExpr();
    try testing.expectEqual(ast.Expr{ .void_literal = {} }, expr);
}

// ── Statements ────────────────────────────────────────────

test "parse assignment" {
    var p = parse("x = 42;");
    const stmt = try p.parseStmt();
    try testing.expectEqualStrings("x", stmt.assign.name);
    try testing.expectEqual(@as(i64, 42), stmt.assign.value.int_literal);
}

test "parse return with value" {
    var p = parse("return 42;");
    const stmt = try p.parseStmt();
    try testing.expectEqual(@as(i64, 42), stmt.return_stmt.value.?.int_literal);
}

test "parse return void" {
    var p = parse("return;");
    const stmt = try p.parseStmt();
    try testing.expectEqual(@as(?ast.Expr, null), stmt.return_stmt.value);
}

test "parse while loop" {
    var p = parse(
        \\while i < 10 {
        \\    i = i + 1;
        \\}
    );
    const stmt = try p.parseStmt();
    try testing.expectEqual(ast.Op.lt, stmt.while_stmt.condition.binary_op.op);
    try testing.expectEqual(@as(usize, 1), stmt.while_stmt.body.len);
}

test "parse match statement" {
    var p = parse(
        \\match x {
        \\    true => do_something();
        \\    false => do_other();
        \\}
    );
    const stmt = try p.parseStmt();
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    try testing.expectEqual(true, stmt.match_stmt.arms[0].pattern.literal.bool_literal);
    try testing.expectEqual(false, stmt.match_stmt.arms[1].pattern.literal.bool_literal);
}

test "parse match with tag patterns" {
    var p = parse(
        \\match result {
        \\    :ok{value} => consume(value);
        \\    :error{reason} => handle(reason);
        \\}
    );
    const stmt = try p.parseStmt();
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms.len);
    try testing.expectEqualStrings("ok", stmt.match_stmt.arms[0].pattern.tag.tag);
    try testing.expectEqualStrings("value", stmt.match_stmt.arms[0].pattern.tag.bindings[0]);
    try testing.expectEqualStrings("error", stmt.match_stmt.arms[1].pattern.tag.tag);
}

test "parse match with block body" {
    var p = parse(
        \\match x {
        \\    :ok{v} => {
        \\        a = v;
        \\        b = 1;
        \\    }
        \\    :error{r} => handle(r);
        \\}
    );
    const stmt = try p.parseStmt();
    try testing.expectEqual(@as(usize, 2), stmt.match_stmt.arms[0].body.len);
    try testing.expectEqual(@as(usize, 1), stmt.match_stmt.arms[1].body.len);
}

// ── Functions ─────────────────────────────────────────────

test "parse simple function" {
    var p = parse(
        \\fn add(a: int, b: int) -> int {
        \\    return a + b;
        \\}
    );
    _ = p.matchKeyword("fn");
    const decl = try p.parseFnDecl(null);
    try testing.expectEqualStrings("add", decl.name);
    try testing.expectEqual(@as(usize, 2), decl.params.len);
    try testing.expectEqualStrings("a", decl.params[0].name);
    try testing.expectEqualStrings("int", decl.params[0].type_expr.simple);
    try testing.expectEqualStrings("int", decl.return_type.simple);
    try testing.expectEqual(@as(usize, 0), decl.guards.len);
    try testing.expectEqual(@as(usize, 1), decl.body.len);
}

test "parse function with guards" {
    var p = parse(
        \\fn withdraw(account: AccountId, amount: Money) -> Result {
        \\    guard amount > 0;
        \\    guard balance >= amount;
        \\    return :ok;
        \\}
    );
    _ = p.matchKeyword("fn");
    const decl = try p.parseFnDecl(null);
    try testing.expectEqualStrings("withdraw", decl.name);
    try testing.expectEqual(@as(usize, 2), decl.guards.len);
    try testing.expectEqual(@as(usize, 1), decl.body.len);
}

test "parse void function" {
    var p = parse(
        \\fn do_nothing() -> void {
        \\    return;
        \\}
    );
    _ = p.matchKeyword("fn");
    const decl = try p.parseFnDecl(null);
    try testing.expectEqualStrings("void", decl.return_type.simple);
}

// ── Modules ───────────────────────────────────────────────

test "parse simple module" {
    var p = parse(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
    );
    _ = p.matchKeyword("module");
    const decl = try p.parseModuleDecl();
    try testing.expectEqualStrings("Math", decl.name);
    try testing.expectEqual(@as(usize, 1), decl.functions.len);
    try testing.expectEqualStrings("add", decl.functions[0].name);
}

test "parse module with import" {
    var p = parse(
        \\module Transfer {
        \\    use Pricing { apply_fee, calculate_total };
        \\    fn execute(amount: Money) -> Result {
        \\        return :ok;
        \\    }
        \\}
    );
    _ = p.matchKeyword("module");
    const decl = try p.parseModuleDecl();
    try testing.expectEqualStrings("Transfer", decl.name);
    try testing.expectEqual(@as(usize, 1), decl.imports.len);
    try testing.expectEqualStrings("Pricing", decl.imports[0].module_name);
    try testing.expectEqual(@as(usize, 2), decl.imports[0].symbols.len);
}

// ── Processes ─────────────────────────────────────────────

test "parse simple process" {
    var p = parse(
        \\process Counter {
        \\    state {
        \\        count: int = 0;
        \\    }
        \\    receive Increment() -> Result {
        \\        guard count >= 0;
        \\        transition count { count + 1; }
        \\        return :ok;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
    );
    _ = p.matchKeyword("process");
    const decl = try p.parseProcessDecl();
    try testing.expectEqualStrings("Counter", decl.name);
    try testing.expect(decl.memory == null);
    try testing.expectEqual(@as(usize, 1), decl.state_fields.len);
    try testing.expectEqualStrings("count", decl.state_fields[0].name);
    try testing.expectEqual(@as(usize, 2), decl.receive_handlers.len);
    try testing.expectEqualStrings("Increment", decl.receive_handlers[0].name);
    try testing.expectEqualStrings("GetCount", decl.receive_handlers[1].name);
}

test "parse process with memory budget" {
    var p = parse(
        \\process Ledger [memory: 64] {
        \\    state {
        \\        balance: int = 0;
        \\    }
        \\    receive GetBalance() -> int {
        \\        return balance;
        \\    }
        \\}
    );
    _ = p.matchKeyword("process");
    const decl = try p.parseProcessDecl();
    try testing.expectEqualStrings("Ledger", decl.name);
    try testing.expect(decl.memory != null);
    switch (decl.memory.?) {
        .sized => |expr| try testing.expectEqual(@as(i64, 64), expr.int_literal),
        .unbounded => return error.TestUnexpectedResult,
    }
}

test "parse process with unbounded memory" {
    var p = parse(
        \\process Cache [memory: unbounded] {
        \\    state {
        \\        count: int = 0;
        \\    }
        \\    receive Get() -> int {
        \\        return count;
        \\    }
        \\}
    );
    _ = p.matchKeyword("process");
    const decl = try p.parseProcessDecl();
    try testing.expectEqualStrings("Cache", decl.name);
    try testing.expect(decl.memory != null);
    try testing.expectEqual(decl.memory.?, .unbounded);
}

test "parse process with invariant" {
    var p = parse(
        \\process Ledger {
        \\    state {
        \\        balance: int = 0;
        \\    }
        \\    invariant {
        \\        balance >= 0;
        \\    }
        \\    receive Deposit(amount: int) -> Result {
        \\        guard amount > 0;
        \\        transition balance { balance + amount; }
        \\        return :ok;
        \\    }
        \\}
    );
    _ = p.matchKeyword("process");
    const decl = try p.parseProcessDecl();
    try testing.expectEqualStrings("Ledger", decl.name);
    try testing.expectEqual(@as(usize, 1), decl.invariants.len);
    try testing.expectEqual(@as(usize, 1), decl.receive_handlers.len);
}

// ── Full File Parsing ─────────────────────────────────────

test "parse complete file with types and struct" {
    var p = parse(
        \\type AccountId = uuid;
        \\type Currency = enum { USD, EUR, GBP };
        \\
        \\struct Account {
        \\    id: AccountId;
        \\    name: string;
        \\    currency: Currency;
        \\    active: bool;
        \\}
    );
    const file = try p.parseFile();
    try testing.expectEqual(@as(usize, 3), file.decls.len);
}

test "parse file with module and process" {
    var p = parse(
        \\module Pricing {
        \\    fn apply_fee(amount: int, rate: int) -> int {
        \\        return amount + rate;
        \\    }
        \\}
        \\
        \\process Ledger {
        \\    state {
        \\        balance: int = 0;
        \\    }
        \\    receive GetBalance() -> int {
        \\        return balance;
        \\    }
        \\}
    );
    const file = try p.parseFile();
    try testing.expectEqual(@as(usize, 2), file.decls.len);
    try testing.expectEqualStrings("Pricing", file.decls[0].module_decl.name);
    try testing.expectEqualStrings("Ledger", file.decls[1].process_decl.name);
}

// ── Type Expressions ──────────────────────────────────────

test "parse generic type" {
    var p = parse("list<int>");
    const t = try p.parseTypeExpr();
    try testing.expectEqualStrings("list", t.generic.name);
    try testing.expectEqual(@as(usize, 1), t.generic.args.len);
    try testing.expectEqualStrings("int", t.generic.args[0].simple);
}

test "parse nested generic type" {
    var p = parse("map<string, list<int>>");
    const t = try p.parseTypeExpr();
    try testing.expectEqualStrings("map", t.generic.name);
    try testing.expectEqual(@as(usize, 2), t.generic.args.len);
    try testing.expectEqualStrings("string", t.generic.args[0].simple);
    try testing.expectEqualStrings("list", t.generic.args[1].generic.name);
}

test "parse function type" {
    var p = parse("fn(int, int) -> bool");
    const t = try p.parseTypeExpr();
    try testing.expectEqual(@as(usize, 2), t.fn_type.params.len);
    try testing.expectEqualStrings("int", t.fn_type.params[0].simple);
    try testing.expectEqualStrings("int", t.fn_type.params[1].simple);
    try testing.expectEqualStrings("bool", t.fn_type.return_type.simple);
}

test "parse function type no params" {
    var p = parse("fn() -> void");
    const t = try p.parseTypeExpr();
    try testing.expectEqual(@as(usize, 0), t.fn_type.params.len);
    try testing.expectEqualStrings("void", t.fn_type.return_type.simple);
}

test "parse function as parameter type" {
    var p = parse(
        \\fn sort_by(items: list<int>, compare: fn(int, int) -> bool) -> list<int> {
        \\    return items;
        \\}
    );
    _ = p.matchKeyword("fn");
    const decl = try p.parseFnDecl(null);
    try testing.expectEqualStrings("sort_by", decl.name);
    try testing.expectEqual(@as(usize, 2), decl.params.len);
    try testing.expectEqualStrings("compare", decl.params[1].name);
    try testing.expectEqual(@as(usize, 2), decl.params[1].type_expr.fn_type.params.len);
}

test "parse optional type" {
    var p = parse("Account?");
    const t = try p.parseTypeExpr();
    try testing.expectEqualStrings("Account", t.optional.simple);
}
