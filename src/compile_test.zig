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
        \\struct P { x: int; y: int; }
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
