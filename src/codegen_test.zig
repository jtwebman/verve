const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const Backend = @import("codegen.zig").LinuxX86Backend;
const testing = std.testing;
const alloc = std.heap.page_allocator;

/// Compile a Verve source string to a native binary and run it.
/// Returns the exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();

    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);

    var backend = Backend.init(alloc);
    backend.compileProgram(program);

    const path = "/tmp/verve_codegen_test";
    try backend.build(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var child = std.process.Child.init(&.{path}, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

/// Compile and run, capture stdout.
fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();

    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);

    var backend = Backend.init(alloc);
    backend.compileProgram(program);

    const path = "/tmp/verve_codegen_capture_test";
    try backend.build(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var buf: [4096]u8 = undefined;
    const n = try child.stdout.?.readAll(&buf);
    const term = try child.wait();
    const exit_code: u8 = switch (term) {
        .Exited => |code| code,
        else => 255,
    };
    return .{ .exit = exit_code, .stdout = try alloc.dupe(u8, buf[0..n]) };
}

// ════════════════════════════════════════════════════════════
// Return values
// ════════════════════════════════════════════════════════════

test "compile: return 0" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: return 42" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 42;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

// ════════════════════════════════════════════════════════════
// Arithmetic
// ════════════════════════════════════════════════════════════

test "compile: addition 3 + 4" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 3 + 4;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 7), exit);
}

test "compile: subtraction 10 - 3" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 10 - 3;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 7), exit);
}

test "compile: multiplication 6 * 7" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 6 * 7;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: division 42 / 6" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 42 / 6;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 7), exit);
}

test "compile: modulo 10 % 3" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 10 % 3;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: complex expression (2 + 3) * 4" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return (2 + 3) * 4;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 20), exit);
}

test "compile: negation -(-42)" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return -(-42);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

// ════════════════════════════════════════════════════════════
// Variables
// ════════════════════════════════════════════════════════════

test "compile: variable assignment" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 42;
        \\        return x;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: variable reassignment" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 10;
        \\        x = x + 5;
        \\        return x;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 15), exit);
}

test "compile: multiple variables" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: int = 10;
        \\        b: int = 20;
        \\        c: int = a + b;
        \\        return c;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 30), exit);
}

// ════════════════════════════════════════════════════════════
// Comparisons
// ════════════════════════════════════════════════════════════

test "compile: less than true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if 3 < 5 { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: less than false" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if 5 < 3 { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: equality" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if 42 == 42 { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

// ════════════════════════════════════════════════════════════
// If/else
// ════════════════════════════════════════════════════════════

test "compile: if true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if true { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: if false goes to else" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if false {
        \\            return 1;
        \\        } else {
        \\            return 2;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 2), exit);
}

test "compile: else if chain" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 2;
        \\        if x == 1 {
        \\            return 10;
        \\        } else if x == 2 {
        \\            return 20;
        \\        } else {
        \\            return 30;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 20), exit);
}

// ════════════════════════════════════════════════════════════
// While loops
// ════════════════════════════════════════════════════════════

test "compile: while loop sum 1..10" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        sum: int = 0;
        \\        i: int = 1;
        \\        while i <= 10 {
        \\            sum = sum + i;
        \\            i = i + 1;
        \\        }
        \\        return sum;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 55), exit);
}

test "compile: while loop factorial 5" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        result: int = 1;
        \\        i: int = 1;
        \\        while i <= 5 {
        \\            result = result * i;
        \\            i = i + 1;
        \\        }
        \\        return result;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 120), exit); // 5! = 120
}

test "compile: fibonacci 10" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: int = 0;
        \\        b: int = 1;
        \\        i: int = 0;
        \\        while i < 10 {
        \\            temp: int = b;
        \\            b = a + b;
        \\            a = temp;
        \\            i = i + 1;
        \\        }
        \\        return a;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 55), exit); // fib(10) = 55
}

// ════════════════════════════════════════════════════════════
// Logical operators
// ════════════════════════════════════════════════════════════

test "compile: and true true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if true && true { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: and true false" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if true && false { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: or false true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if false || true { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: not true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if !true { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

// ════════════════════════════════════════════════════════════
// Function calls
// ════════════════════════════════════════════════════════════

test "compile: call function returning constant" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn get_value() -> int {
        \\        return 42;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return get_value();
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: call function with one arg" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return double(21);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: call function with two args" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return add(35, 7);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: call function with three args" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn sum3(a: int, b: int, c: int) -> int {
        \\        return a + b + c;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return sum3(10, 20, 12);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: nested function calls" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\    fn add_one(x: int) -> int {
        \\        return x + 1;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return add_one(double(20));
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 41), exit);
}

test "compile: function with local vars" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn compute(x: int, y: int) -> int {
        \\        sum: int = x + y;
        \\        product: int = x * y;
        \\        return sum + product;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return compute(3, 4);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 19), exit); // (3+4) + (3*4) = 7+12 = 19
}

test "compile: function with if/else" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn abs(x: int) -> int {
        \\        if x >= 0 {
        \\            return x;
        \\        } else {
        \\            return 0 - x;
        \\        }
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        return abs(-42);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: function used in loop" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn square(x: int) -> int {
        \\        return x * x;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        sum: int = 0;
        \\        i: int = 1;
        \\        while i <= 4 {
        \\            sum = sum + square(i);
        \\            i = i + 1;
        \\        }
        \\        return sum;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 30), exit); // 1+4+9+16 = 30
}

// ════════════════════════════════════════════════════════════
// String output (println)
// ════════════════════════════════════════════════════════════

test "compile: println string literal" {
    const result = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println("Hello from Verve!");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), result.exit);
    try testing.expectEqualStrings("Hello from Verve!\n", result.stdout);
}

test "compile: multiple println calls" {
    const result = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println("line 1");
        \\        println("line 2");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), result.exit);
    try testing.expectEqualStrings("line 1\nline 2\n", result.stdout);
}

test "compile: print without newline" {
    const result = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        print("hello ");
        \\        print("world");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), result.exit);
    try testing.expectEqualStrings("hello world", result.stdout);
}

// ════════════════════════════════════════════════════════════
// Structs
// ════════════════════════════════════════════════════════════

test "compile: struct create and field access" {
    const exit = try compileAndRun(
        \\struct Point {
        \\    x: int;
        \\    y: int;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        p: Point = Point { x: 10, y: 32 };
        \\        return p.x + p.y;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: struct three fields" {
    const exit = try compileAndRun(
        \\struct Token {
        \\    kind: int;
        \\    value: int;
        \\    pos: int;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        tok: Token = Token { kind: 10, value: 20, pos: 12 };
        \\        return tok.kind + tok.value + tok.pos;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: struct field used in condition" {
    const exit = try compileAndRun(
        \\struct Item {
        \\    value: int;
        \\    active: int;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        item: Item = Item { value: 42, active: 1 };
        \\        if item.active == 1 {
        \\            return item.value;
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: struct passed to function" {
    const exit = try compileAndRun(
        \\struct Point {
        \\    x: int;
        \\    y: int;
        \\}
        \\module App {
        \\    fn sum_point(p: Point) -> int {
        \\        return p.x + p.y;
        \\    }
        \\    fn main(args: list<string>) -> int {
        \\        p: Point = Point { x: 35, y: 7 };
        \\        return sum_point(p);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: multiple structs" {
    const exit = try compileAndRun(
        \\struct A {
        \\    x: int;
        \\}
        \\struct B {
        \\    y: int;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: A = A { x: 20 };
        \\        b: B = B { y: 22 };
        \\        return a.x + b.y;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

// ════════════════════════════════════════════════════════════
// Lists
// ════════════════════════════════════════════════════════════

test "compile: list create and length" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        items: list<int> = list();
        \\        return items.len;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: list append and length" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        items: list<int> = list();
        \\        append items { 10; }
        \\        append items { 20; }
        \\        append items { 30; }
        \\        return items.len;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 3), exit);
}

test "compile: list index access" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        items: list<int> = list();
        \\        append items { 10; }
        \\        append items { 32; }
        \\        return items[0] + items[1];
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

test "compile: list iterate with while" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        items: list<int> = list();
        \\        append items { 10; }
        \\        append items { 20; }
        \\        append items { 12; }
        \\        sum: int = 0;
        \\        i: int = 0;
        \\        while i < items.len {
        \\            sum = sum + items[i];
        \\            i = i + 1;
        \\        }
        \\        return sum;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), exit);
}

// ════════════════════════════════════════════════════════════
// String operations
// ════════════════════════════════════════════════════════════

test "compile: String.byte_at" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return String.byte_at("ABC", 0);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 65), exit); // 'A' = 65
}

test "compile: String.byte_at index 1" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return String.byte_at("ABC", 1);
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 66), exit); // 'B' = 66
}

test "compile: String.is_digit true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.is_digit("5") { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: String.is_digit false" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.is_digit("x") { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: String.is_alpha true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.is_alpha("a") { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: String.is_whitespace true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.is_whitespace(" ") { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: string equality true" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if "hello" == "hello" { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: string equality false" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if "hello" == "world" { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), exit);
}

test "compile: string inequality" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if "abc" != "def" { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}

test "compile: combined comparison and logic" {
    const exit = try compileAndRun(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 5;
        \\        if x > 0 && x < 10 { return 1; }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), exit);
}
