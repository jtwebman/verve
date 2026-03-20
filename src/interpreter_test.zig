const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Value = @import("value.zig").Value;
const testing = std.testing;

// ── Helper ────────────────────────────────────────────────

fn run(source: []const u8, module_name: []const u8, fn_name: []const u8, args: []const Value) !Value {
    const alloc = std.heap.page_allocator;
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

// ── Structs ───────────────────────────────────────────────

test "create struct literal" {
    const val = try run(
        \\module Test {
        \\    fn make() -> string {
        \\        p = Point { x: 10, y: 20 };
        \\        return p.x;
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 10), val.int);
}

test "access struct field" {
    const val = try run(
        \\module Test {
        \\    fn make() -> int {
        \\        p = Point { x: 3, y: 4 };
        \\        return p.x + p.y;
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 7), val.int);
}

test "struct in list" {
    const val = try run(
        \\module Test {
        \\    fn make() -> int {
        \\        items = list();
        \\        append items { Point { x: 1, y: 2 }; }
        \\        append items { Point { x: 3, y: 4 }; }
        \\        return items[0].x + items[1].y;
        \\    }
        \\}
    , "Test", "make", &.{});
    try testing.expectEqual(@as(i64, 5), val.int);
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

// ── Break ─────────────────────────────────────────────────

test "break exits while loop" {
    const val = try run(
        \\module Test {
        \\    fn find() -> int {
        \\        i: int = 0;
        \\        while i < 100 {
        \\            match i == 5 {
        \\                true => break;
        \\                false => i = i + 1;
        \\            }
        \\        }
        \\        return i;
        \\    }
        \\}
    , "Test", "find", &.{});
    try testing.expectEqual(@as(i64, 5), val.int);
}

test "break in nested match inside while" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> int {
        \\        total: int = 0;
        \\        i: int = 0;
        \\        while true {
        \\            match i >= 3 {
        \\                true => break;
        \\                false => {
        \\                    total = total + i;
        \\                    i = i + 1;
        \\                }
        \\            }
        \\        }
        \\        return total;
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqual(@as(i64, 3), val.int); // 0+1+2 = 3
}

// ── Continue ──────────────────────────────────────────────

test "continue skips iteration" {
    const val = try run(
        \\module Test {
        \\    fn sum_odd() -> int {
        \\        total: int = 0;
        \\        i: int = 0;
        \\        while i < 6 {
        \\            i = i + 1;
        \\            match i % 2 == 0 {
        \\                true => continue;
        \\                false => total = total + i;
        \\            }
        \\        }
        \\        return total;
        \\    }
        \\}
    , "Test", "sum_odd", &.{});
    try testing.expectEqual(@as(i64, 9), val.int); // 1+3+5 = 9
}

// ── String operations ─────────────────────────────────────

test "String.starts_with" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return String.starts_with("hello world", "hello");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "String.ends_with" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return String.ends_with("hello world", "world");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "String.trim" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        return String.trim("  hello  ");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("hello", val.string);
}

test "String.replace" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        return String.replace("hello world", "world", "zig");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("hello zig", val.string);
}

test "String.split" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        parts: list<string> = String.split("a,b,c", ",");
        \\        return parts.len;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 3), val.int);
}

test "String.slice" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        return String.slice("hello world", 0, 5);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("hello", val.string);
}

// ── Map operations ────────────────────────────────────────

test "create map and put/get" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        m: map<string, int> = map();
        \\        Map.put(m, "x", 42);
        \\        return Map.get(m, "x");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "map has and keys" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        m: map<string, int> = map();
        \\        Map.put(m, "a", 1);
        \\        Map.put(m, "b", 2);
        \\        return Map.has(m, "a");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "map keys returns list" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        m: map<string, int> = map();
        \\        Map.put(m, "a", 1);
        \\        Map.put(m, "b", 2);
        \\        ks: list<string> = Map.keys(m);
        \\        return ks.len;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 2), val.int);
}

test "map index access" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        m: map<string, int> = map();
        \\        Map.put(m, "x", 99);
        \\        return m["x"];
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 99), val.int);
}

// ── Set operations ────────────────────────────────────────

test "create set and add/has" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        s: set<int> = set();
        \\        Set.add(s, 42);
        \\        Set.add(s, 42);
        \\        return Set.has(s, 42);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "set deduplicates" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: set<int> = set();
        \\        Set.add(s, 1);
        \\        Set.add(s, 2);
        \\        Set.add(s, 1);
        \\        return s.len;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 2), val.int);
}

test "set remove" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: set<int> = set();
        \\        Set.add(s, 1);
        \\        Set.add(s, 2);
        \\        Set.remove(s, 1);
        \\        return s.len;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 1), val.int);
}

// ── String interpolation ──────────────────────────────────

test "string interpolation with variable" {
    const val = try run(
        \\module Test {
        \\    fn greet() -> string {
        \\        name: string = "world";
        \\        return "hello ${name}!";
        \\    }
        \\}
    , "Test", "greet", &.{});
    try testing.expectEqualStrings("hello world!", val.string);
}

test "string interpolation with expression" {
    const val = try run(
        \\module Test {
        \\    fn calc() -> string {
        \\        x: int = 21;
        \\        return "answer: ${x + x}";
        \\    }
        \\}
    , "Test", "calc", &.{});
    try testing.expectEqualStrings("answer: 42", val.string);
}

test "string interpolation with int" {
    const val = try run(
        \\module Test {
        \\    fn show() -> string {
        \\        n: int = 42;
        \\        return "n = ${n}";
        \\    }
        \\}
    , "Test", "show", &.{});
    try testing.expectEqualStrings("n = 42", val.string);
}

test "braces in strings are just characters" {
    const val = try run(
        \\module Test {
        \\    fn get() -> string {
        \\        return "hello {world}";
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqualStrings("hello {world}", val.string);
}

test "dollar without brace is just a character" {
    const val = try run(
        \\module Test {
        \\    fn get() -> string {
        \\        return "costs $5";
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqualStrings("costs $5", val.string);
}

test "plain string without interpolation unchanged" {
    const val = try run(
        \\module Test {
        \\    fn get() -> string {
        \\        return "hello world";
        \\    }
        \\}
    , "Test", "get", &.{});
    try testing.expectEqualStrings("hello world", val.string);
}

// ── Stdio streams ─────────────────────────────────────────

test "Stdio.out returns stream" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        out: stream = Stdio.out();
        \\        Stream.write(out, "test from stream\n");
        \\        return true;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "Stdio.err returns stream" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        err: stream = Stdio.err();
        \\        Stream.write(err, "");
        \\        return true;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

// ── File streams ──────────────────────────────────────────

test "File.open read returns result" {
    // Try to open a file that doesn't exist
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        result: Result<stream> = File.open("__nonexistent_test_file__", "r");
        \\        match result {
        \\            :error{reason} => return "got_error";
        \\            _ => return "unexpected";
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("got_error", val.string);
}

// ── String character access ───────────────────────────────

test "String.byte_at returns byte value" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        return String.byte_at("ABC", 0);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 65), val.int); // 'A' = 65
}

test "String.char_at returns character" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        return String.char_at("hello", 1);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("e", val.string);
}

test "String.char_len counts code points" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        return String.char_len("hello");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 5), val.int);
}

test "String.chars returns list of characters" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        cs: list<string> = String.chars("abc");
        \\        return cs.len;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 3), val.int);
}

test "String.is_alpha" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return String.is_alpha("a");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "String.is_digit" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return String.is_digit("5");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "String.is_whitespace" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return String.is_whitespace(" ");
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "String.is_alnum" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        a: bool = String.is_alnum("x");
        \\        b: bool = String.is_alnum("3");
        \\        c: bool = String.is_alnum(" ");
        \\        return a == true == b == true == !c;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "string index access returns single byte" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        s: string = "hello";
        \\        return s[1];
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqualStrings("e", val.string);
}

test "string index out of bounds returns poison" {
    const val = try run(
        \\module Test {
        \\    fn check() -> string {
        \\        s: string = "hi";
        \\        return s[5];
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expect(val.isPoison());
}

// ── Stack operations ──────────────────────────────────────

test "stack push and pop" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: stack<int> = stack();
        \\        Stack.push(s, 10);
        \\        Stack.push(s, 20);
        \\        Stack.push(s, 30);
        \\        top: int = Stack.pop(s);
        \\        return top;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 30), val.int);
}

test "stack peek doesn't remove" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: stack<int> = stack();
        \\        Stack.push(s, 42);
        \\        top: int = Stack.peek(s);
        \\        return s.len + top;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 43), val.int); // len=1 + peek=42
}

test "stack pop empty returns none" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        s: stack<int> = stack();
        \\        result: int = Stack.pop(s);
        \\        return result == none;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "stack with initial values" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: stack<int> = stack(1, 2, 3);
        \\        return Stack.pop(s);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 3), val.int);
}

test "stack LIFO order" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        s: stack<string> = stack();
        \\        Stack.push(s, "a");
        \\        Stack.push(s, "b");
        \\        Stack.push(s, "c");
        \\        first: string = Stack.pop(s);
        \\        second: string = Stack.pop(s);
        \\        third: string = Stack.pop(s);
        \\        if first == "c" && second == "b" && third == "a" {
        \\            return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 1), val.int);
}

// ── Queue operations ──────────────────────────────────────

test "queue push and pop FIFO" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        q: queue<int> = queue();
        \\        Queue.push(q, 10);
        \\        Queue.push(q, 20);
        \\        Queue.push(q, 30);
        \\        return Queue.pop(q);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 10), val.int);
}

test "queue peek returns front" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        q: queue<int> = queue();
        \\        Queue.push(q, 1);
        \\        Queue.push(q, 2);
        \\        return Queue.peek(q);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "queue pop empty returns none" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        q: queue<int> = queue();
        \\        return Queue.pop(q) == none;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "queue with initial values" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        q: queue<int> = queue(1, 2, 3);
        \\        return Queue.pop(q);
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "queue FIFO order" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        q: queue<string> = queue();
        \\        Queue.push(q, "a");
        \\        Queue.push(q, "b");
        \\        Queue.push(q, "c");
        \\        first: string = Queue.pop(q);
        \\        second: string = Queue.pop(q);
        \\        third: string = Queue.pop(q);
        \\        if first == "a" && second == "b" && third == "c" {
        \\            return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 1), val.int);
}

// ── If/else ───────────────────────────────────────────────

test "if true executes body" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        x: int = 0;
        \\        if true {
        \\            x = 42;
        \\        }
        \\        return x;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "if false skips body" {
    const val = try run(
        \\module Test {
        \\    fn check() -> int {
        \\        x: int = 0;
        \\        if false {
        \\            x = 42;
        \\        }
        \\        return x;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "if/else" {
    const val = try run(
        \\module Test {
        \\    fn check(b: bool) -> int {
        \\        if b {
        \\            return 1;
        \\        } else {
        \\            return 0;
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{.{ .bool = true }});
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "logical and" {
    const val = try run(
        \\module Test {
        \\    fn check(a: bool, b: bool) -> bool {
        \\        return a && b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .bool = true }, .{ .bool = false } });
    try testing.expectEqual(false, val.bool);
}

test "logical or" {
    const val = try run(
        \\module Test {
        \\    fn check(a: bool, b: bool) -> bool {
        \\        return a || b;
        \\    }
        \\}
    , "Test", "check", &.{ .{ .bool = false }, .{ .bool = true } });
    try testing.expectEqual(true, val.bool);
}

test "logical and both true" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return true && true;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}

test "logical or both false" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        return false || false;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(false, val.bool);
}

test "logical operators in if condition" {
    const val = try run(
        \\module Test {
        \\    fn check(x: int) -> bool {
        \\        if x > 0 && x < 10 {
        \\            return true;
        \\        }
        \\        return false;
        \\    }
        \\}
    , "Test", "check", &.{.{ .int = 5 }});
    try testing.expectEqual(true, val.bool);
}

test "else if chain" {
    const val = try run(
        \\module Test {
        \\    fn check(x: int) -> string {
        \\        if x == 1 {
        \\            return "one";
        \\        } else if x == 2 {
        \\            return "two";
        \\        } else {
        \\            return "other";
        \\        }
        \\    }
        \\}
    , "Test", "check", &.{.{ .int = 2 }});
    try testing.expectEqualStrings("two", val.string);
}

// ── Module-level constants ────────────────────────────────

test "module-level constant accessible in function" {
    const val = try run(
        \\module Test {
        \\    max_size: int = 100;
        \\
        \\    fn get_max() -> int {
        \\        return max_size;
        \\    }
        \\}
    , "Test", "get_max", &.{});
    try testing.expectEqual(@as(i64, 100), val.int);
}

test "module-level set with initial values" {
    const val = try run(
        \\module Test {
        \\    vowels: set<string> = set("a", "e", "i", "o", "u");
        \\
        \\    fn is_vowel(ch: string) -> bool {
        \\        return Set.has(vowels, ch);
        \\    }
        \\}
    , "Test", "is_vowel", &.{.{ .string = "e" }});
    try testing.expectEqual(true, val.bool);
}

test "module-level list with initial values" {
    const val = try run(
        \\module Test {
        \\    primes: list<int> = list(2, 3, 5, 7, 11);
        \\
        \\    fn count() -> int {
        \\        return primes.len;
        \\    }
        \\}
    , "Test", "count", &.{});
    try testing.expectEqual(@as(i64, 5), val.int);
}

test "Stream.write_line to stream" {
    const val = try run(
        \\module Test {
        \\    fn check() -> bool {
        \\        out: stream = Stdio.out();
        \\        Stream.write_line(out, "stream write_line test");
        \\        return true;
        \\    }
        \\}
    , "Test", "check", &.{});
    try testing.expectEqual(true, val.bool);
}
