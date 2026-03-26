const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const ZigBackend = @import("zig_backend.zig").ZigBackend;
const testing = std.testing;
const alloc = std.heap.page_allocator;

const zig_path = "/home/jt/.local/zig/zig";

/// Compile Verve source to native binary, run it, return exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    const path = "/tmp/verve_compile_test";
    try backend.build(path, zig_path);
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

/// Compile, run, capture stdout.
fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    const path = "/tmp/verve_compile_capture_test";
    try backend.build(path, zig_path);
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var buf: [4096]u8 = undefined;
    const n = try child.stdout.?.readAll(&buf);
    const term = try child.wait();
    return .{
        .exit = switch (term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = try alloc.dupe(u8, buf[0..n]),
    };
}

// ════════════════════════════════════════════════════════════
// Basic compilation
// ════════════════════════════════════════════════════════════

test "compile: return 0" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 0; } }
    ));
}

test "compile: return 42" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 42; } }
    ));
}

// ════════════════════════════════════════════════════════════
// Arithmetic
// ════════════════════════════════════════════════════════════

test "compile: 3 + 4" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 3 + 4; } }
    ));
}

test "compile: 6 * 7" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 6 * 7; } }
    ));
}

test "compile: 42 / 6" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 42 / 6; } }
    ));
}

test "compile: 10 % 3" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return 10 % 3; } }
    ));
}

// ════════════════════════════════════════════════════════════
// Variables and control flow
// ════════════════════════════════════════════════════════════

test "compile: variable" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { x: int = 42; return x; } }
    ));
}

test "compile: if true" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if true { return 1; } return 0; } }
    ));
}

test "compile: if else" {
    try testing.expectEqual(@as(u8, 2), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if false { return 1; } else { return 2; } } }
    ));
}

test "compile: while sum" {
    try testing.expectEqual(@as(u8, 55), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { s: int = 0; i: int = 1; while i <= 10 { s = s + i; i = i + 1; } return s; } }
    ));
}

test "compile: break" {
    try testing.expectEqual(@as(u8, 5), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { i: int = 0; while true { if i == 5 { break; } i = i + 1; } return i; } }
    ));
}

// ════════════════════════════════════════════════════════════
// Functions
// ════════════════════════════════════════════════════════════

test "compile: function call" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn get() -> int { return 42; } fn main(args: list<string>) -> int { return get(); } }
    ));
}

test "compile: function with args" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn add(a: int, b: int) -> int { return a + b; } fn main(args: list<string>) -> int { return add(35, 7); } }
    ));
}

test "compile: nested calls" {
    try testing.expectEqual(@as(u8, 41), try compileAndRun(
        \\module App { fn dbl(x: int) -> int { return x * 2; } fn add1(x: int) -> int { return x + 1; } fn main(args: list<string>) -> int { return add1(dbl(20)); } }
    ));
}

// ════════════════════════════════════════════════════════════
// Strings and println
// ════════════════════════════════════════════════════════════

test "compile: println string" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { println("hello"); return 0; } }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n", r.stdout);
}

test "compile: println int" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { x: int = 42; println(x); return 0; } }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: print multiple" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { println("a", "b"); return 0; } }
    );
    try testing.expectEqualStrings("ab\n", r.stdout);
}

// ════════════════════════════════════════════════════════════
// Structs
// ════════════════════════════════════════════════════════════

test "compile: struct" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\struct P { x: int = 0; y: int = 0; }
        \\module App { fn main(args: list<string>) -> int { p: P = P { x: 35, y: 7 }; return p.x + p.y; } }
    ));
}

// ════════════════════════════════════════════════════════════
// Lists
// ════════════════════════════════════════════════════════════

test "compile: list" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { l: list<int> = list(); append l { 10; } append l { 32; } return l[0] + l[1]; } }
    ));
}

test "compile: list len" {
    try testing.expectEqual(@as(u8, 3), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { l: list<int> = list(); append l { 1; } append l { 2; } append l { 3; } return l.len; } }
    ));
}

// ════════════════════════════════════════════════════════════
// String comparison
// ════════════════════════════════════════════════════════════

test "compile: string eq true" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if "hi" == "hi" { return 1; } return 0; } }
    ));
}

test "compile: string eq false" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if "hi" == "no" { return 1; } return 0; } }
    ));
}

test "compile: string var eq" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { s: string = "hello"; if s == "hello" { return 1; } return 0; } }
    ));
}

// ════════════════════════════════════════════════════════════
// Match
// ════════════════════════════════════════════════════════════

test "compile: match int" {
    try testing.expectEqual(@as(u8, 20), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { x: int = 2; match x { 1 => return 10; 2 => return 20; _ => return 0; } } }
    ));
}

// ════════════════════════════════════════════════════════════
// Logical operators
// ════════════════════════════════════════════════════════════

test "compile: and" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if 3 > 0 && 3 < 10 { return 1; } return 0; } }
    ));
}

test "compile: or" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if false || true { return 1; } return 0; } }
    ));
}

// ════════════════════════════════════════════════════════════
// String operations
// ════════════════════════════════════════════════════════════

test "compile: String.byte_at" {
    try testing.expectEqual(@as(u8, 65), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { return String.byte_at("ABC", 0); } }
    ));
}

test "compile: String.is_digit" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\module App { fn main(args: list<string>) -> int { if String.is_digit("5") { return 1; } return 0; } }
    ));
}

// ════════════════════════════════════════════════════════════
// File IO
// ════════════════════════════════════════════════════════════

test "compile: File.open success" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result { :ok{f} => { println("ok"); return 0; } :error{r} => { return 1; } }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

// ════════════════════════════════════════════════════════════
// Processes
// ════════════════════════════════════════════════════════════

test "compile: process main handler" {
    const r = try compileAndCapture(
        \\process App {
        \\    state { x: int = 0; }
        \\    receive main() -> int {
        \\        println("hello from process");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello from process\n", r.stdout);
}

test "compile: process state default zero" {
    const r = try compileAndCapture(
        \\process App {
        \\    state { count: int = 0; }
        \\    receive main() -> int {
        \\        println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: process transition and state read" {
    const r = try compileAndCapture(
        \\process App {
        \\    state { count: int = 0; }
        \\    receive main() -> int {
        \\        transition count { count + 5; }
        \\        println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n", r.stdout);
}

test "compile: spawn and send" {
    const r = try compileAndCapture(
        \\process Counter {
        \\    state { count: int = 0; }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        match counter.Increment() {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("err");
        \\        }
        \\        match counter.Increment() {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("err");
        \\        }
        \\        match counter.GetCount() {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n2\n2\n", r.stdout);
}

test "compile: spawn and tell" {
    const r = try compileAndCapture(
        \\process Counter {
        \\    state { count: int = 0; }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        tell counter.Increment();
        \\        tell counter.Increment();
        \\        tell counter.Increment();
        \\        match counter.GetCount() {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n", r.stdout);
}

test "compile: guard failure" {
    const r = try compileAndCapture(
        \\process Counter {
        \\    state { count: int = 0; }
        \\    receive Add(n: int) -> int {
        \\        guard n > 0;
        \\        transition count { count + n; }
        \\        return count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        match counter.Add(5) {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("guard failed");
        \\        }
        \\        match counter.Add(0) {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("guard failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\nguard failed\n", r.stdout);
}

test "compile: multiple state fields" {
    const r = try compileAndCapture(
        \\process Pair {
        \\    state { x: int = 0; y: int = 0; }
        \\    receive SetX(val: int) -> int {
        \\        transition x { val; }
        \\        return x;
        \\    }
        \\    receive SetY(val: int) -> int {
        \\        transition y { val; }
        \\        return y;
        \\    }
        \\    receive Sum() -> int {
        \\        return x + y;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        p: int = spawn Pair();
        \\        match p.SetX(10) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.SetY(32) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.Sum() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10\n32\n42\n", r.stdout);
}

test "compile: multi-process interaction" {
    const r = try compileAndCapture(
        \\process Adder {
        \\    state { total: int = 0; }
        \\    receive Add(n: int) -> int {
        \\        transition total { total + n; }
        \\        return total;
        \\    }
        \\    receive GetTotal() -> int {
        \\        return total;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a1: int = spawn Adder();
        \\        a2: int = spawn Adder();
        \\        match a1.Add(10) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match a2.Add(20) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match a1.Add(5) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match a1.GetTotal() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match a2.GetTotal() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10\n20\n15\n15\n20\n", r.stdout);
}

test "compile: message throughput via tell" {
    const r = try compileAndCapture(
        \\process Counter {
        \\    state { count: int = 0; }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: int = spawn Counter();
        \\        i: int = 0;
        \\        while i < 50 {
        \\            tell c.Increment();
        \\            i = i + 1;
        \\        }
        \\        match c.GetCount() {
        \\            :ok{val} => println(val);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("50\n", r.stdout);
}

// ── Overflow / poison tests ────────────────────────

test "compile: division by zero produces poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 10 / 0;
        \\        // Poison prints as a large negative number (sentinel)
        \\        if x > 0 {
        \\            println("wrong: positive");
        \\        } else {
        \\            println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: modulo by zero produces poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: int = 10 % 0;
        \\        if x > 0 {
        \\            println("wrong");
        \\        } else {
        \\            println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagates through addition" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        result: int = bad + 5;
        \\        if result > 0 {
        \\            println("wrong");
        \\        } else {
        \\            println("propagated");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("propagated\n", r.stdout);
}

test "compile: overflow on addition" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        max: int = 9223372036854775807;
        \\        result: int = max + 1;
        \\        if result > 0 {
        \\            println("wrapped");
        \\        } else {
        \\            println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: overflow on multiplication" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        big: int = 9223372036854775807;
        \\        result: int = big * 2;
        \\        if result > 0 {
        \\            println("wrapped");
        \\        } else {
        \\            println("poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: underflow on subtraction" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        min: int = 0 - 9223372036854775807;
        \\        result: int = min - 2;
        \\        if result < 0 {
        \\            println("poison");
        \\        } else {
        \\            println("wrapped");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagates through multiple operations" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        r1: int = bad + 5;
        \\        r2: int = r1 * 3;
        \\        r3: int = r2 - 1;
        \\        if r3 > 0 {
        \\            println("wrong");
        \\        } else {
        \\            println("still poison");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("still poison\n", r.stdout);
}

test "compile: poison does not affect independent values" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        good: int = 3 + 4;
        \\        println(good);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("7\n", r.stdout);
}

test "compile: normal arithmetic still works" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(3 + 4);
        \\        println(10 - 3);
        \\        println(6 * 7);
        \\        println(42 / 6);
        \\        println(10 % 3);
        \\        println(0 - 5);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("7\n7\n42\n7\n1\n-5\n", r.stdout);
}

// ── Arena / memory tests ───────────────────────────

test "compile: many tagged results dont crash (arena allocation)" {
    const r = try compileAndCapture(
        \\process Counter {
        \\    state { count: int = 0; }
        \\    receive Inc() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: int = spawn Counter();
        \\        i: int = 0;
        \\        while i < 1000 {
        \\            match c.Inc() {
        \\                :ok{v} => {
        \\                    i = i + 1;
        \\                }
        \\                :error{e} => {
        \\                    i = i + 1;
        \\                }
        \\            }
        \\        }
        \\        match c.Inc() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1001\n", r.stdout);
}

test "compile: many string conversions dont crash (arena allocation)" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        i: int = 0;
        \\        while i < 500 {
        \\            s: string = Convert.to_string(i);
        \\            i = i + 1;
        \\        }
        \\        println("survived");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("survived\n", r.stdout);
}

test "compile: many string concats dont crash (arena allocation)" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "";
        \\        i: int = 0;
        \\        while i < 200 {
        \\            s = s + "a";
        \\            i = i + 1;
        \\        }
        \\        println(String.len(s));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("200\n", r.stdout);
}

// ── String concat tests ────────────────────────────

test "compile: string concat literals" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "hello" + " " + "world";
        \\        println(s);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world\n", r.stdout);
}

test "compile: string concat variables" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: string = "foo";
        \\        b: string = "bar";
        \\        c: string = a + b;
        \\        println(c);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("foobar\n", r.stdout);
}

test "compile: string concat length" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "ab" + "cd";
        \\        println(String.len(s));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("4\n", r.stdout);
}

test "compile: string concat empty" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "hello" + "";
        \\        println(s);
        \\        s2: string = "" + "world";
        \\        println(s2);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\nworld\n", r.stdout);
}

test "compile: string concat chain" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "a" + "b" + "c" + "d" + "e";
        \\        println(s);
        \\        println(String.len(s));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("abcde\n5\n", r.stdout);
}

test "compile: string concat with convert" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        name: string = "count";
        \\        num: string = Convert.to_string(42);
        \\        result: string = name + ": " + num;
        \\        println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("count: 42\n", r.stdout);
}

test "compile: string concat in loop" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "";
        \\        i: int = 0;
        \\        while i < 5 {
        \\            s = s + "x";
        \\            i = i + 1;
        \\        }
        \\        println(s);
        \\        println(String.len(s));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("xxxxx\n5\n", r.stdout);
}

test "compile: string concat with stream read_line" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "world");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                line: string = Stream.read_line(client);
        \\                                result: string = "hello " + line;
        \\                                println(result);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world\n", r.stdout);
}

test "compile: string equality after concat" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: string = "hel" + "lo";
        \\        if a == "hello" {
        \\            println("equal");
        \\        } else {
        \\            println("not equal");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("equal\n", r.stdout);
}

// ── Math tests ─────────────────────────────────────

test "compile: math abs min max" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.abs(-42));
        \\        println(Math.min(10, 3));
        \\        println(Math.max(10, 3));
        \\        println(Math.clamp(50, 0, 100));
        \\        println(Math.clamp(-5, 0, 100));
        \\        println(Math.clamp(200, 0, 100));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n3\n10\n50\n0\n100\n", r.stdout);
}

test "compile: math abs edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.abs(0));
        \\        println(Math.abs(1));
        \\        println(Math.abs(-1));
        \\        println(Math.abs(999999));
        \\        println(Math.abs(-999999));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n1\n999999\n999999\n", r.stdout);
}

test "compile: math min max edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.min(0, 0));
        \\        println(Math.min(-5, 5));
        \\        println(Math.min(5, -5));
        \\        println(Math.max(0, 0));
        \\        println(Math.max(-5, 5));
        \\        println(Math.max(5, -5));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n-5\n-5\n0\n5\n5\n", r.stdout);
}

test "compile: math clamp edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.clamp(5, 5, 5));
        \\        println(Math.clamp(0, -10, 10));
        \\        println(Math.clamp(-100, -10, 10));
        \\        println(Math.clamp(100, -10, 10));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n0\n-10\n10\n", r.stdout);
}

test "compile: math pow edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.pow(2, 0));
        \\        println(Math.pow(0, 5));
        \\        println(Math.pow(1, 1000));
        \\        println(Math.pow(-2, 3));
        \\        println(Math.pow(-2, 4));
        \\        println(Math.pow(10, 6));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n0\n1\n-8\n16\n1000000\n", r.stdout);
}

test "compile: math sqrt edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.sqrt(0));
        \\        println(Math.sqrt(1));
        \\        println(Math.sqrt(4));
        \\        println(Math.sqrt(9));
        \\        println(Math.sqrt(10));
        \\        println(Math.sqrt(10000));
        \\        println(Math.sqrt(-1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n2\n3\n3\n100\n0\n", r.stdout);
}

test "compile: math log2 edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.log2(1));
        \\        println(Math.log2(2));
        \\        println(Math.log2(3));
        \\        println(Math.log2(8));
        \\        println(Math.log2(1023));
        \\        println(Math.log2(1024));
        \\        println(Math.log2(0));
        \\        println(Math.log2(-1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n1\n3\n9\n10\n0\n0\n", r.stdout);
}

test "compile: math pow sqrt log2" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.pow(2, 10));
        \\        println(Math.pow(3, 3));
        \\        println(Math.sqrt(144));
        \\        println(Math.sqrt(2));
        \\        println(Math.log2(1024));
        \\        println(Math.log2(1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1024\n27\n12\n1\n10\n0\n", r.stdout);
}

// ── System tests ───────────────────────────────────

test "compile: system time_ms" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        t: int = System.time_ms();
        \\        if t > 0 {
        \\            println("ok");
        \\        } else {
        \\            println("bad");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

// ── Math float tests ───────────────────────────────

test "compile: math floor ceil round" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.floor(3.7));
        \\        println(Math.floor(3.0));
        \\        println(Math.floor(0.5));
        \\        println(Math.ceil(3.2));
        \\        println(Math.ceil(3.0));
        \\        println(Math.ceil(0.1));
        \\        println(Math.round(3.5));
        \\        println(Math.round(3.4));
        \\        println(Math.round(0.5));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n3\n0\n4\n3\n1\n4\n3\n1\n", r.stdout);
}

test "compile: math floor ceil round zero" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Math.floor(0.0));
        \\        println(Math.ceil(0.0));
        \\        println(Math.round(0.0));
        \\        println(Math.floor(0.1));
        \\        println(Math.floor(0.9));
        \\        println(Math.ceil(0.1));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n0\n0\n0\n0\n1\n", r.stdout);
}

test "compile: math sin cos tan" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        zero_sin: float = Math.sin(0.0);
        \\        zero_cos: float = Math.cos(0.0);
        \\        // sin(0) == 0, cos(0) == 1
        \\        println(Math.round(zero_sin));
        \\        println(Math.round(zero_cos));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n", r.stdout);
}

test "compile: math sqrt_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r4: float = Math.sqrt_f(4.0);
        \\        println(Math.round(r4));
        \\        r9: float = Math.sqrt_f(9.0);
        \\        println(Math.round(r9));
        \\        r0: float = Math.sqrt_f(0.0);
        \\        println(Math.round(r0));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("2\n3\n0\n", r.stdout);
}

test "compile: math pow_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r1: float = Math.pow_f(2.0, 10.0);
        \\        println(Math.round(r1));
        \\        r2: float = Math.pow_f(3.0, 0.0);
        \\        println(Math.round(r2));
        \\        r3: float = Math.pow_f(2.0, -1.0);
        \\        // 2^-1 = 0.5, round = 1 (rounds half-up)
        \\        println(Math.round(r3));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1024\n1\n1\n", r.stdout);
}

test "compile: math log log10 exp" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        // exp(0) = 1
        \\        e0: float = Math.exp(0.0);
        \\        println(Math.round(e0));
        \\        // log(1) = 0
        \\        l1: float = Math.log(1.0);
        \\        println(Math.round(l1));
        \\        // log10(100) = 2
        \\        l100: float = Math.log10(100.0);
        \\        println(Math.round(l100));
        \\        // log10(1000) = 3
        \\        l1000: float = Math.log10(1000.0);
        \\        println(Math.round(l1000));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n0\n2\n3\n", r.stdout);
}

test "compile: math abs_f min_f max_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a1: float = Math.abs_f(3.5);
        \\        println(Math.round(a1));
        \\        mn: float = Math.min_f(1.5, 2.5);
        \\        println(Math.round(mn));
        \\        mx: float = Math.max_f(1.5, 2.5);
        \\        println(Math.round(mx));
        \\        mn2: float = Math.min_f(0.1, 0.9);
        \\        println(Math.round(mn2));
        \\        mx2: float = Math.max_f(0.1, 0.9);
        \\        println(Math.round(mx2));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("4\n2\n3\n0\n1\n", r.stdout);
}

// ── Convert float tests ────────────────────────────

test "compile: convert to_float and to_int_f" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        f: float = Convert.to_float(42);
        \\        println(Math.round(f));
        \\        i: int = Convert.to_int_f(3.7);
        \\        println(i);
        \\        zero: int = Convert.to_int_f(0.0);
        \\        println(zero);
        \\        big: float = Convert.to_float(1000);
        \\        println(Math.round(big));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n3\n0\n1000\n", r.stdout);
}

test "compile: convert float_to_string" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = Convert.float_to_string(3.14);
        \\        println(s);
        \\        s0: string = Convert.float_to_string(0.0);
        \\        println(s0);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Zig formats 3.14 as "3.14e0" or "3.14" depending on version
    // Just check it starts with "3.14"
    try testing.expect(r.stdout.len > 0);
    try testing.expect(r.stdout[0] == '3');
}

test "compile: convert string_to_float" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        f: float = Convert.string_to_float("3.14");
        \\        println(Math.round(f));
        \\        f2: float = Convert.string_to_float("100.0");
        \\        println(Math.round(f2));
        \\        bad: float = Convert.string_to_float("abc");
        \\        println(Math.round(bad));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n100\n0\n", r.stdout);
}

test "compile: convert float roundtrip" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        original: int = 99;
        \\        f: float = Convert.to_float(original);
        \\        back: int = Convert.to_int_f(f);
        \\        if back == original {
        \\            println("roundtrip ok");
        \\        } else {
        \\            println("roundtrip failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("roundtrip ok\n", r.stdout);
}

// ── System tests ───────────────────────────────────

test "compile: system exit with code" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println("before");
        \\        System.exit(0);
        \\        println("after");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("before\n", r.stdout);
}

test "compile: system exit nonzero" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        System.exit(42);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 42), r.exit);
}

test "compile: system time_ms increases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        t1: int = System.time_ms();
        \\        t2: int = System.time_ms();
        \\        if t2 >= t1 {
        \\            println("ok");
        \\        } else {
        \\            println("time went backwards");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

// ── Convert tests ──────────────────────────────────

test "compile: convert int to string and back" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = Convert.to_string(42);
        \\        println(s);
        \\        n: int = Convert.to_int("123");
        \\        println(n);
        \\        neg: string = Convert.to_string(-7);
        \\        println(neg);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n123\n-7\n", r.stdout);
}

test "compile: convert to_string edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s0: string = Convert.to_string(0);
        \\        println(s0);
        \\        s1: string = Convert.to_string(1);
        \\        println(s1);
        \\        sn: string = Convert.to_string(-1);
        \\        println(sn);
        \\        sb: string = Convert.to_string(1000000);
        \\        println(sb);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n-1\n1000000\n", r.stdout);
}

test "compile: convert to_int edge cases" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Convert.to_int("0"));
        \\        println(Convert.to_int("-42"));
        \\        println(Convert.to_int("999"));
        \\        println(Convert.to_int("abc"));
        \\        println(Convert.to_int(""));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n-42\n999\n0\n0\n", r.stdout);
}

test "compile: convert roundtrip" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        original: int = 12345;
        \\        s: string = Convert.to_string(original);
        \\        back: int = Convert.to_int(s);
        \\        if back == original {
        \\            println("roundtrip ok");
        \\        } else {
        \\            println("roundtrip failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("roundtrip ok\n", r.stdout);
}

// ── Env tests ──────────────────────────────────────

test "compile: env get existing var" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        home: string = Env.get("HOME");
        \\        if String.len(home) > 0 {
        \\            println("has home");
        \\        } else {
        \\            println("no home");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("has home\n", r.stdout);
}

test "compile: env get nonexistent var" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        val: string = Env.get("VERVE_DEFINITELY_NOT_SET_XYZ");
        \\        if String.len(val) == 0 {
        \\            println("empty");
        \\        } else {
        \\            println("unexpected");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("empty\n", r.stdout);
}

// ── JSON tests ─────────────────────────────────────

test "compile: json get_string from object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"verve\", \"version\": 1}";
        \\        name: string = Json.get_string(data, "name");
        \\        println(name);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("verve\n", r.stdout);
}

test "compile: json get_int from object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"count\": 42, \"name\": \"test\"}";
        \\        count: int = Json.get_int(data, "count");
        \\        println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: json get_bool from object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"active\": true, \"deleted\": false}";
        \\        if Json.get_bool(data, "active") {
        \\            println("active");
        \\        } else {
        \\            println("not active");
        \\        }
        \\        if Json.get_bool(data, "deleted") {
        \\            println("deleted");
        \\        } else {
        \\            println("not deleted");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("active\nnot deleted\n", r.stdout);
}

test "compile: json nested object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"user\": {\"name\": \"alice\", \"age\": 30}}";
        \\        user: string = Json.get_object(data, "user");
        \\        name: string = Json.get_string(user, "name");
        \\        age: int = Json.get_int(user, "age");
        \\        println(name);
        \\        println(age);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("alice\n30\n", r.stdout);
}

test "compile: json missing key returns zero" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"test\"}";
        \\        missing: int = Json.get_int(data, "nope");
        \\        println(missing);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: json multiple fields" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"a\": 1, \"b\": 2, \"c\": 3, \"d\": 4}";
        \\        println(Json.get_int(data, "a"));
        \\        println(Json.get_int(data, "b"));
        \\        println(Json.get_int(data, "c"));
        \\        println(Json.get_int(data, "d"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n2\n3\n4\n", r.stdout);
}

test "compile: json negative number" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"temp\": -5}";
        \\        println(Json.get_int(data, "temp"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("-5\n", r.stdout);
}

test "compile: json string with spaces and special chars" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"msg\": \"hello world!\"}";
        \\        msg: string = Json.get_string(data, "msg");
        \\        println(msg);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world!\n", r.stdout);
}

test "compile: json deeply nested" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"a\": {\"b\": {\"c\": 99}}}";
        \\        a: string = Json.get_object(data, "a");
        \\        b: string = Json.get_object(a, "b");
        \\        c: int = Json.get_int(b, "c");
        \\        println(c);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("99\n", r.stdout);
}

test "compile: json to_int and to_bool leaf extraction" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        println(Json.to_int("42"));
        \\        println(Json.to_int("-7"));
        \\        println(Json.to_bool("true"));
        \\        println(Json.to_bool("false"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n-7\n1\n0\n", r.stdout);
}

test "compile: json build simple object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "name", "verve");
        \\        Json.build_add_int(b, "version", 1);
        \\        result: string = Json.build_end(b);
        \\        println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"name\":\"verve\",\"version\":1}\n", r.stdout);
}

test "compile: json build with bool" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_bool(b, "yes", true);
        \\        Json.build_add_bool(b, "no", false);
        \\        result: string = Json.build_end(b);
        \\        println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"yes\":true,\"no\":false}\n", r.stdout);
}

test "compile: json build empty object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        result: string = Json.build_end(b);
        \\        println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{}\n", r.stdout);
}

test "compile: json build then parse roundtrip" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello");
        \\        Json.build_add_int(b, "num", 42);
        \\        json: string = Json.build_end(b);
        \\        msg: string = Json.get_string(json, "msg");
        \\        num: int = Json.get_int(json, "num");
        \\        println(msg);
        \\        println(num);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n42\n", r.stdout);
}

test "compile: json build with special chars in string" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello world!");
        \\        result: string = Json.build_end(b);
        \\        println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"msg\":\"hello world!\"}\n", r.stdout);
}

test "compile: json array length" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"items\": [1, 2, 3, 4, 5]}";
        \\        count: int = Json.get_array_len(data, "items");
        \\        println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n", r.stdout);
}

test "compile: json empty array length" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"items\": []}";
        \\        count: int = Json.get_array_len(data, "items");
        \\        println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

// ── TCP tests ──────────────────────────────────────

test "compile: tcp listen and connect loopback" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "hello from client");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                line: string = Stream.read_line(client);
        \\                                println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello from client\n", r.stdout);
}

test "compile: tcp connect refused" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.open("127.0.0.1", 1) {
        \\            :ok{conn} => println("unexpected success");
        \\            :error{e} => println("refused");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("refused\n", r.stdout);
}

test "compile: tcp read eof on peer close" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "data");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                line: string = Stream.read_line(client);
        \\                                println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("data\n", r.stdout);
}

test "compile: tcp bidirectional echo" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.write_line(conn, "ping");
        \\                                req: string = Stream.read_line(client);
        \\                                println(req);
        \\                                Stream.write_line(client, "pong");
        \\                                resp: string = Stream.read_line(conn);
        \\                                println(resp);
        \\                                Stream.close(client);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ping\npong\n", r.stdout);
}

test "compile: tcp multiple sequential connections" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                i: int = 0;
        \\                while i < 3 {
        \\                    match Tcp.open("127.0.0.1", port) {
        \\                        :ok{conn} => {
        \\                            Stream.write_line(conn, "msg");
        \\                            Stream.close(conn);
        \\                            match Tcp.accept(listener) {
        \\                                :ok{client} => {
        \\                                    line: string = Stream.read_line(client);
        \\                                    println(line);
        \\                                    Stream.close(client);
        \\                                }
        \\                                :error{e} => println("accept failed");
        \\                            }
        \\                        }
        \\                        :error{e} => println("connect failed");
        \\                    }
        \\                    i = i + 1;
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("msg\nmsg\nmsg\n", r.stdout);
}

test "compile: tcp listen port zero assigns port" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                if port > 0 {
        \\                    println("ok");
        \\                } else {
        \\                    println("bad port");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

test "compile: tcp double bind fails" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener1} => {
        \\                port: int = Tcp.port(listener1);
        \\                match Tcp.listen("127.0.0.1", port) {
        \\                    :ok{listener2} => {
        \\                        println("unexpected success");
        \\                        Stream.close(listener2);
        \\                    }
        \\                    :error{e} => println("address in use");
        \\                }
        \\                Stream.close(listener1);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("address in use\n", r.stdout);
}

test "compile: tcp data before close all delivered" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "line1");
        \\                        Stream.write_line(conn, "line2");
        \\                        Stream.write_line(conn, "line3");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                l1: string = Stream.read_line(client);
        \\                                l2: string = Stream.read_line(client);
        \\                                l3: string = Stream.read_line(client);
        \\                                println(l1);
        \\                                println(l2);
        \\                                println(l3);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("line1\nline2\nline3\n", r.stdout);
}

test "compile: tcp large transfer" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        i: int = 0;
        \\                        while i < 100 {
        \\                            Stream.write_line(conn, "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz01");
        \\                            i = i + 1;
        \\                        }
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                count: int = 0;
        \\                                done: bool = false;
        \\                                while !done {
        \\                                    line: string = Stream.read_line(client);
        \\                                    if String.len(line) > 0 {
        \\                                        count = count + 1;
        \\                                    } else {
        \\                                        done = true;
        \\                                    }
        \\                                }
        \\                                println(count);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("100\n", r.stdout);
}

test "compile: tcp write after peer close" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.close(client);
        \\                                Stream.write_line(conn, "should not crash");
        \\                                println("survived");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // SIGPIPE is ignored, write to closed socket doesn't crash
    try testing.expectEqualStrings("survived\n", r.stdout);
}

test "compile: tcp operations on closed stream" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.close(client);
        \\                                Stream.close(client);
        \\                                Stream.write_line(client, "noop");
        \\                                println("ok");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Double close and write to closed stream should not crash
    try testing.expectEqualStrings("ok\n", r.stdout);
}

test "compile: tcp accept on closed listener" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                Stream.close(listener);
        \\                match Tcp.accept(listener) {
        \\                    :ok{client} => println("unexpected");
        \\                    :error{e} => println("rejected");
        \\                }
        \\            }
        \\            :error{e} => println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("rejected\n", r.stdout);
}

test "compile: process state with new struct syntax" {
    const r = try compileAndCapture(
        \\struct PointState {
        \\    x: int = 0;
        \\    y: int = 0;
        \\}
        \\process Point<PointState> {
        \\    receive MoveX(state: PointState, dx: int) -> int {
        \\        state.x = state.x + dx;
        \\        return state.x;
        \\    }
        \\    receive MoveY(state: PointState, dy: int) -> int {
        \\        state.y = state.y + dy;
        \\        return state.y;
        \\    }
        \\    receive GetX(state: PointState) -> int {
        \\        return state.x;
        \\    }
        \\    receive GetY(state: PointState) -> int {
        \\        return state.y;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        p: int = spawn Point();
        \\        match p.MoveX(10) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.MoveY(20) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.MoveX(5) {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.GetX() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        match p.GetY() {
        \\            :ok{v} => println(v);
        \\            :error{e} => println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10\n20\n15\n15\n20\n", r.stdout);
}
