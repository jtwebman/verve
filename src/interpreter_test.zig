const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Value = @import("value.zig").Value;
const testing = std.testing;

// ── Helper ────────────────────────────────────────────────

fn run(source: []const u8, module_name: []const u8, fn_name: []const u8, args: []const Value) !Value {
    const alloc = testing.allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var interp = Interpreter.init(alloc);
    try interp.load(file);
    return try interp.callFunction(module_name, fn_name, args);
}

// ── Basic expressions ─────────────────────────────────────

test "return integer literal" {
    const val = try run(
        \\module Test {
        \\    fn get() -> int {
        \\        return 42;
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "return string literal" {
    const val = try run(
        \\module Test {
        \\    fn get() -> string {
        \\        return "hello";
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqualStrings("hello", val.string);
}

test "return bool literal" {
    const val = try run(
        \\module Test {
        \\    fn get() -> bool {
        \\        return true;
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqual(true, val.bool);
}

test "return tag" {
    const val = try run(
        \\module Test {
        \\    fn get() -> Result {
        \\        return :ok;
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqualStrings("ok", val.tag);
}

// ── Arithmetic ────────────────────────────────────────────

test "add two integers" {
    const val = try run(
        \\module Test {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
    , "Test", "add", &.{ .{ .int = 3 }, .{ .int = 4 } });
    try testing.expectEqual(@as(i64, 7), val.int);
}

test "subtract integers" {
    const val = try run(
        \\module Test {
        \\    fn sub(a: int, b: int) -> int {
        \\        return a - b;
        \\    }
        \\}
    , "Test", "sub", &.{ .{ .int = 10 }, .{ .int = 3 } });
    try testing.expectEqual(@as(i64, 7), val.int);
}

test "multiply integers" {
    const val = try run(
        \\module Test {
        \\    fn mul(a: int, b: int) -> int {
        \\        return a * b;
        \\    }
        \\}
    , "Test", "mul", &.{ .{ .int = 6 }, .{ .int = 7 } });
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "divide integers" {
    const val = try run(
        \\module Test {
        \\    fn div(a: int, b: int) -> int {
        \\        return a / b;
        \\    }
        \\}
    , "Test", "div", &.{ .{ .int = 42 }, .{ .int = 6 } });
    try testing.expectEqual(@as(i64, 7), val.int);
}

test "modulo" {
    const val = try run(
        \\module Test {
        \\    fn rem(a: int, b: int) -> int {
        \\        return a % b;
        \\    }
        \\}
    , "Test", "rem", &.{ .{ .int = 10 }, .{ .int = 3 } });
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "operator precedence" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> int {
        \\        return 2 + 3 * 4;
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqual(@as(i64, 14), val.int);
}

// ── Poison values ─────────────────────────────────────────

test "integer overflow produces poison" {
    const val = try run(
        \\module Test {
        \\    fn overflow() -> int {
        \\        return 9223372036854775807 + 1;
        \\    }
        \\}
    , "Test", "overflow", &.{});
    try testing.expect(val.isPoison());
    try testing.expectEqual(Value{ .overflow = {} }, val);
}

test "division by zero produces poison" {
    const val = try run(
        \\module Test {
        \\    fn divzero() -> int {
        \\        return 42 / 0;
        \\    }
        \\}
    , "Test", "divzero", &.{});
    try testing.expect(val.isPoison());
    try testing.expectEqual(Value{ .div_zero = {} }, val);
}

test "poison propagates through operations" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> int {
        \\        return (42 / 0) + 1;
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expect(val.isPoison());
}

// ── Comparisons ───────────────────────────────────────────

test "equality check" {
    const val = try run(
        \\module Test {
        \\    fn check(a: int, b: int) -> bool {
        \\        return a == b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .int = 5 }, .{ .int = 5 } });
    try testing.expectEqual(true, val.bool);
}

test "inequality check" {
    const val = try run(
        \\module Test {
        \\    fn check(a: int, b: int) -> bool {
        \\        return a != b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .int = 5 }, .{ .int = 3 } });
    try testing.expectEqual(true, val.bool);
}

test "less than" {
    const val = try run(
        \\module Test {
        \\    fn check(a: int, b: int) -> bool {
        \\        return a < b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .int = 3 }, .{ .int = 5 } });
    try testing.expectEqual(true, val.bool);
}

test "greater than or equal" {
    const val = try run(
        \\module Test {
        \\    fn check(a: int, b: int) -> bool {
        \\        return a >= b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .int = 5 }, .{ .int = 5 } });
    try testing.expectEqual(true, val.bool);
}

// ── Variables & assignment ────────────────────────────────

test "variable assignment" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> int {
        \\        x = 10;
        \\        return x;
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqual(@as(i64, 10), val.int);
}

test "variable reassignment" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> int {
        \\        x = 10;
        \\        x = x + 5;
        \\        return x;
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqual(@as(i64, 15), val.int);
}

// ── While loops ───────────────────────────────────────────

test "while loop counting" {
    const val = try run(
        \\module Test {
        \\    fn count() -> int {
        \\        i = 0;
        \\        total = 0;
        \\        while i < 5 {
        \\            total = total + i;
        \\            i = i + 1;
        \\        }
        \\        return total;
        \\    }
        \\}
    , "Test", "count", &.{});
    try testing.expectEqual(@as(i64, 10), val.int); // 0+1+2+3+4 = 10
}

test "while loop with early return" {
    const val = try run(
        \\module Test {
        \\    fn find() -> int {
        \\        i = 0;
        \\        while i < 100 {
        \\            match i == 7 {
        \\                true => return i;
        \\                false => i = i + 1;
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "Test", "find", &.{});
    try testing.expectEqual(@as(i64, 7), val.int);
}

// ── Match ─────────────────────────────────────────────────

test "match on boolean" {
    const val = try run(
        \\module Test {
        \\    fn check(x: bool) -> int {
        \\        match x {
        \\            true => return 1;
        \\            false => return 0;
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{.{ .bool = true }});
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "match on boolean false" {
    const val = try run(
        \\module Test {
        \\    fn check(x: bool) -> int {
        \\        match x {
        \\            true => return 1;
        \\            false => return 0;
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{.{ .bool = false }});
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "match on tag" {
    const val = try run(
        \\module Test {
        \\    fn check(x: Result) -> int {
        \\        match x {
        \\            :ok => return 1;
        \\            :error => return 0;
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{.{ .tag = "ok" }});
    try testing.expectEqual(@as(i64, 1), val.int);
}

// ── Guards ────────────────────────────────────────────────

test "guard passes" {
    const val = try run(
        \\module Test {
        \\    fn positive(x: int) -> int {
        \\        guard x > 0;
        \\        return x;
        \\    }
        \\}
    , "Test", "positive", &.{.{ .int = 5 }});
    try testing.expectEqual(@as(i64, 5), val.int);
}

test "guard fails returns error" {
    const val = try run(
        \\module Test {
        \\    fn positive(x: int) -> int {
        \\        guard x > 0;
        \\        return x;
        \\    }
        \\}
    , "Test", "positive", &.{.{ .int = 0 }});
    // Should return :error{:guard_failed}
    try testing.expectEqualStrings("error", val.tag_with_value.tag);
}

// ── Function calls ────────────────────────────────────────

test "call function within same module" {
    const val = try run(
        \\module Test {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\    fn quadruple(x: int) -> int {
        \\        return double(double(x));
        \\    }
        \\}
    , "Test", "quadruple", &.{.{ .int = 3 }});
    try testing.expectEqual(@as(i64, 12), val.int);
}

test "call function across modules" {
    const val = try run(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\module Test {
        \\    fn calc() -> int {
        \\        return Math.add(3, 4);
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqual(@as(i64, 7), val.int);
}

// ── Complex programs ──────────────────────────────────────

test "fibonacci" {
    const val = try run(
        \\module Test {
        \\    fn fib(n: int) -> int {
        \\        a = 0;
        \\        b = 1;
        \\        i = 0;
        \\        while i < n {
        \\            temp = b;
        \\            b = a + b;
        \\            a = temp;
        \\            i = i + 1;
        \\        }
        \\        return a;
        \\    }
        \\}
    , "Test", "fib", &.{.{ .int = 10 }});
    try testing.expectEqual(@as(i64, 55), val.int);
}

test "factorial with while" {
    const val = try run(
        \\module Test {
        \\    fn factorial(n: int) -> int {
        \\        result = 1;
        \\        i = 1;
        \\        while i <= n {
        \\            result = result * i;
        \\            i = i + 1;
        \\        }
        \\        return result;
        \\    }
        \\}
    , "Test", "factorial", &.{.{ .int = 10 }});
    try testing.expectEqual(@as(i64, 3628800), val.int);
}

test "guard with comparison function" {
    const val = try run(
        \\module Test {
        \\    fn is_positive(x: int) -> bool {
        \\        return x > 0;
        \\    }
        \\    fn safe_divide(a: int, b: int) -> int {
        \\        guard is_positive(b);
        \\        return a / b;
        \\    }
        \\}
    , "Test", "safe_divide", &.{ .{ .int = 10 }, .{ .int = 2 } });
    try testing.expectEqual(@as(i64, 5), val.int);
}

// ── Lists ─────────────────────────────────────────────────

test "create empty list" {
    const val = try run(
        \\module Test {
        \\    fn make() -> int {
        \\        items = list();
        \\        return items.len;
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "append to list and read" {
    const val = try run(
        \\module Test {
        \\    fn make() -> int {
        \\        items = list();
        \\        append items { 42; }
        \\        return items[0];
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "list length after appends" {
    const val = try run(
        \\module Test {
        \\    fn make() -> int {
        \\        items = list();
        \\        append items { 1; }
        \\        append items { 2; }
        \\        append items { 3; }
        \\        return items.len;
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 3), val.int);
}

test "iterate list with while" {
    const val = try run(
        \\module Test {
        \\    fn sum() -> int {
        \\        items = list();
        \\        append items { 10; }
        \\        append items { 20; }
        \\        append items { 30; }
        \\        total = 0;
        \\        i = 0;
        \\        while i < items.len {
        \\            total = total + items[i];
        \\            i = i + 1;
        \\        }
        \\        return total;
        \\    }
        \\}
    , "Test", "sum", &.{});
    try testing.expectEqual(@as(i64, 60), val.int);
}

test "list out of bounds returns poison" {
    const val = try run(
        \\module Test {
        \\    fn bad() -> int {
        \\        items = list();
        \\        append items { 1; }
        \\        return items[5];
        \\    }
        \\}
    , "Test", "bad", &.{});
    try testing.expect(val.isPoison());
}

// ── Guards with functions ─────────────────────────────────

test "guard with comparison function fails" {
    const val = try run(
        \\module Test {
        \\    fn is_positive(x: int) -> bool {
        \\        return x > 0;
        \\    }
        \\    fn safe_divide(a: int, b: int) -> int {
        \\        guard is_positive(b);
        \\        return a / b;
        \\    }
        \\}
    , "Test", "safe_divide", &.{ .{ .int = 10 }, .{ .int = 0 } });
    try testing.expectEqualStrings("error", val.tag_with_value.tag);
}
