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

test "compile: Stdio.println string" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { Stdio.println("hello"); return 0; } }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n", r.stdout);
}

test "compile: Stdio.println int" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { x: int = 42; Stdio.println(x); return 0; } }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: Stdio.print multiple" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int { Stdio.println("a", "b"); return 0; } }
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
        \\    match result { :ok{f} => { Stdio.println("ok"); return 0; } :error{r} => { return 1; } }
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
        \\struct AppState { x: int = 0; }
        \\process App<AppState> {
        \\    receive main(state: AppState) -> int {
        \\        Stdio.println("hello from process");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello from process\n", r.stdout);
}

test "compile: process state default zero" {
    const r = try compileAndCapture(
        \\struct AppState { count: int = 0; }
        \\process App<AppState> {
        \\    receive main(state: AppState) -> int {
        \\        Stdio.println(state.count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: process state mutation and read" {
    const r = try compileAndCapture(
        \\struct AppState { count: int = 0; }
        \\process App<AppState> {
        \\    receive main(state: AppState) -> int {
        \\        state.count = state.count + 5;
        \\        Stdio.println(state.count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n", r.stdout);
}

test "compile: spawn and send" {
    const r = try compileAndCapture(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\    receive GetCount(state: CounterState) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        match counter.Increment() {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match counter.Increment() {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match counter.GetCount() {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
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
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\    receive GetCount(state: CounterState) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        tell counter.Increment();
        \\        tell counter.Increment();
        \\        tell counter.Increment();
        \\        match counter.GetCount() {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
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
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Add(state: CounterState, n: int) -> int {
        \\        guard n > 0;
        \\        state.count = state.count + n;
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        counter: int = spawn Counter();
        \\        match counter.Add(5) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("guard failed");
        \\        }
        \\        match counter.Add(0) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("guard failed");
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
        \\struct PairState { x: int = 0; y: int = 0; }
        \\process Pair<PairState> {
        \\    receive SetX(state: PairState, val: int) -> int {
        \\        state.x = val;
        \\        return state.x;
        \\    }
        \\    receive SetY(state: PairState, val: int) -> int {
        \\        state.y = val;
        \\        return state.y;
        \\    }
        \\    receive Sum(state: PairState) -> int {
        \\        return state.x + state.y;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        p: int = spawn Pair();
        \\        match p.SetX(10) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.SetY(32) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.Sum() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
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
        \\struct AdderState { total: int = 0; }
        \\process Adder<AdderState> {
        \\    receive Add(state: AdderState, n: int) -> int {
        \\        state.total = state.total + n;
        \\        return state.total;
        \\    }
        \\    receive GetTotal(state: AdderState) -> int {
        \\        return state.total;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a1: int = spawn Adder();
        \\        a2: int = spawn Adder();
        \\        match a1.Add(10) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match a2.Add(20) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match a1.Add(5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match a1.GetTotal() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match a2.GetTotal() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
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
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\    receive GetCount(state: CounterState) -> int {
        \\        return state.count;
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
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
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
        \\            Stdio.println("wrong: positive");
        \\        } else {
        \\            Stdio.println("poison");
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
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("poison");
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
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("propagated");
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
        \\            Stdio.println("wrapped");
        \\        } else {
        \\            Stdio.println("poison");
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
        \\            Stdio.println("wrapped");
        \\        } else {
        \\            Stdio.println("poison");
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
        \\        // Poison: neither > 0 nor < 0 nor == 0
        \\        if result > 0 {
        \\            Stdio.println("positive");
        \\        } else {
        \\            if result == 0 {
        \\                Stdio.println("zero");
        \\            } else {
        \\                if result < 0 {
        \\                    Stdio.println("negative");
        \\                } else {
        \\                    Stdio.println("poison");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Poison is not > 0, not == 0, not < 0 — falls through to "poison"
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
        \\            Stdio.println("wrong");
        \\        } else {
        \\            Stdio.println("still poison");
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
        \\        Stdio.println(good);
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
        \\        Stdio.println(3 + 4);
        \\        Stdio.println(10 - 3);
        \\        Stdio.println(6 * 7);
        \\        Stdio.println(42 / 6);
        \\        Stdio.println(10 % 3);
        \\        Stdio.println(0 - 5);
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
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Inc(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
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
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
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
        \\        Stdio.println("survived");
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
        \\        Stdio.println(String.len(s));
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
        \\        Stdio.println(s);
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
        \\        Stdio.println(c);
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
        \\        Stdio.println(String.len(s));
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
        \\        Stdio.println(s);
        \\        s2: string = "" + "world";
        \\        Stdio.println(s2);
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
        \\        Stdio.println(s);
        \\        Stdio.println(String.len(s));
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
        \\        Stdio.println(result);
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
        \\        Stdio.println(s);
        \\        Stdio.println(String.len(s));
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
        \\                                Stdio.println(result);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\            Stdio.println("equal");
        \\        } else {
        \\            Stdio.println("not equal");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("equal\n", r.stdout);
}

// ── String builtin tests ───────────────────────────

test "compile: String.contains" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.contains("hello world", "world") {
        \\            Stdio.println("yes");
        \\        } else {
        \\            Stdio.println("no");
        \\        }
        \\        if String.contains("hello", "xyz") {
        \\            Stdio.println("yes");
        \\        } else {
        \\            Stdio.println("no");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("yes\nno\n", r.stdout);
}

test "compile: String.starts_with and ends_with" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        if String.starts_with("hello world", "hello") {
        \\            Stdio.println("starts");
        \\        } else {
        \\            Stdio.println("no");
        \\        }
        \\        if String.ends_with("hello world", "world") {
        \\            Stdio.println("ends");
        \\        } else {
        \\            Stdio.println("no");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("starts\nends\n", r.stdout);
}

test "compile: String.trim" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = String.trim("  hello  ");
        \\        Stdio.println(s);
        \\        Stdio.println(String.len(s));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n5\n", r.stdout);
}

test "compile: String.replace" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = String.replace("hello world", "world", "verve");
        \\        Stdio.println(s);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello verve\n", r.stdout);
}

// ── Struct with string fields tests ────────────────

test "compile: struct with string and int fields" {
    const r = try compileAndCapture(
        \\struct User {
        \\    name: string = "";
        \\    age: int = 0;
        \\    active: bool = false;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"bob\", \"age\": 25, \"active\": true}";
        \\        match Json.parse(data, User) {
        \\            :ok{user} => {
        \\                Stdio.println(user.name);
        \\                Stdio.println(user.age);
        \\                if user.active {
        \\                    Stdio.println("active");
        \\                } else {
        \\                    Stdio.println("inactive");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("fail");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("bob\n25\nactive\n", r.stdout);
}

test "compile: struct string field length tracked (no strlen)" {
    const r = try compileAndCapture(
        \\struct Item {
        \\    name: string = "";
        \\    count: int = 0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"widget\", \"count\": 5}";
        \\        match Json.parse(data, Item) {
        \\            :ok{item} => {
        \\                Stdio.println(String.len(item.name));
        \\                Stdio.println(item.count);
        \\            }
        \\            :error{e} => Stdio.println("fail");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("6\n5\n", r.stdout);
}

// ── Process feature tests ──────────────────────────

test "compile: process state with string field" {
    const r = try compileAndCapture(
        \\struct NameState {
        \\    name: string = "";
        \\    count: int = 0;
        \\}
        \\process NameKeeper<NameState> {
        \\    receive SetName(state: NameState, n: string) -> int {
        \\        state.name = n;
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\    receive GetName(state: NameState) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        k: int = spawn NameKeeper();
        \\        match k.SetName("alice") {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match k.SetName("bob") {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n2\n", r.stdout);
}

test "compile: Process.exit terminates handler" {
    const r = try compileAndCapture(
        \\struct WState { x: int = 0; }
        \\process Worker<WState> {
        \\    receive DoWork(state: WState, val: int) -> int {
        \\        Stdio.println(val);
        \\        Process.exit();
        \\        return 0;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        w: int = spawn Worker();
        \\        tell w.DoWork(42);
        \\        Stdio.println("done");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\ndone\n", r.stdout);
}

// ── Poison edge case tests ─────────────────────────

test "compile: float division by zero is poison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        x: float = 1.0 / 0.0;
        \\        r: int = Math.round(x);
        \\        if r == 0 {
        \\            Stdio.println("zero");
        \\        } else {
        \\            if r > 0 {
        \\                Stdio.println("positive");
        \\            } else {
        \\                if r < 0 {
        \\                    Stdio.println("negative");
        \\                } else {
        \\                    Stdio.println("poison");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("poison\n", r.stdout);
}

test "compile: poison propagation through function return" {
    const r = try compileAndCapture(
        \\module Math2 {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        bad: int = 10 / 0;
        \\        result: int = Math2.double(bad);
        \\        if result > 0 {
        \\            Stdio.println("wrong");
        \\        } else {
        \\            if result == 0 {
        \\                Stdio.println("wrong");
        \\            } else {
        \\                if result < 0 {
        \\                    Stdio.println("wrong");
        \\                } else {
        \\                    Stdio.println("propagated");
        \\                }
        \\            }
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("propagated\n", r.stdout);
}

// ── Type system tests ──────────────────────────────

test "compile: if/else with string comparison" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: string = "hello";
        \\        if s == "hello" {
        \\            Stdio.println("match");
        \\        } else {
        \\            Stdio.println("no match");
        \\        }
        \\        if s == "world" {
        \\            Stdio.println("match");
        \\        } else {
        \\            Stdio.println("no match");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("match\nno match\n", r.stdout);
}

test "compile: nested struct field access" {
    const r = try compileAndCapture(
        \\struct Inner { value: int = 0; }
        \\struct Outer { name: string = ""; count: int = 0; }
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"test\", \"count\": 42}";
        \\        match Json.parse(data, Outer) {
        \\            :ok{obj} => {
        \\                Stdio.println(obj.name);
        \\                Stdio.println(obj.count);
        \\            }
        \\            :error{e} => Stdio.println("fail");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("test\n42\n", r.stdout);
}

// ── Math tests ─────────────────────────────────────

test "compile: math abs min max" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        Stdio.println(Math.abs(-42));
        \\        Stdio.println(Math.min(10, 3));
        \\        Stdio.println(Math.max(10, 3));
        \\        Stdio.println(Math.clamp(50, 0, 100));
        \\        Stdio.println(Math.clamp(-5, 0, 100));
        \\        Stdio.println(Math.clamp(200, 0, 100));
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
        \\        Stdio.println(Math.abs(0));
        \\        Stdio.println(Math.abs(1));
        \\        Stdio.println(Math.abs(-1));
        \\        Stdio.println(Math.abs(999999));
        \\        Stdio.println(Math.abs(-999999));
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
        \\        Stdio.println(Math.min(0, 0));
        \\        Stdio.println(Math.min(-5, 5));
        \\        Stdio.println(Math.min(5, -5));
        \\        Stdio.println(Math.max(0, 0));
        \\        Stdio.println(Math.max(-5, 5));
        \\        Stdio.println(Math.max(5, -5));
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
        \\        Stdio.println(Math.clamp(5, 5, 5));
        \\        Stdio.println(Math.clamp(0, -10, 10));
        \\        Stdio.println(Math.clamp(-100, -10, 10));
        \\        Stdio.println(Math.clamp(100, -10, 10));
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
        \\        Stdio.println(Math.pow(2, 0));
        \\        Stdio.println(Math.pow(0, 5));
        \\        Stdio.println(Math.pow(1, 1000));
        \\        Stdio.println(Math.pow(-2, 3));
        \\        Stdio.println(Math.pow(-2, 4));
        \\        Stdio.println(Math.pow(10, 6));
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
        \\        Stdio.println(Math.sqrt(0));
        \\        Stdio.println(Math.sqrt(1));
        \\        Stdio.println(Math.sqrt(4));
        \\        Stdio.println(Math.sqrt(9));
        \\        Stdio.println(Math.sqrt(10));
        \\        Stdio.println(Math.sqrt(10000));
        \\        Stdio.println(Math.sqrt(-1));
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
        \\        Stdio.println(Math.log2(1));
        \\        Stdio.println(Math.log2(2));
        \\        Stdio.println(Math.log2(3));
        \\        Stdio.println(Math.log2(8));
        \\        Stdio.println(Math.log2(1023));
        \\        Stdio.println(Math.log2(1024));
        \\        Stdio.println(Math.log2(0));
        \\        Stdio.println(Math.log2(-1));
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
        \\        Stdio.println(Math.pow(2, 10));
        \\        Stdio.println(Math.pow(3, 3));
        \\        Stdio.println(Math.sqrt(144));
        \\        Stdio.println(Math.sqrt(2));
        \\        Stdio.println(Math.log2(1024));
        \\        Stdio.println(Math.log2(1));
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
        \\            Stdio.println("ok");
        \\        } else {
        \\            Stdio.println("bad");
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
        \\        Stdio.println(Math.floor(3.7));
        \\        Stdio.println(Math.floor(3.0));
        \\        Stdio.println(Math.floor(0.5));
        \\        Stdio.println(Math.ceil(3.2));
        \\        Stdio.println(Math.ceil(3.0));
        \\        Stdio.println(Math.ceil(0.1));
        \\        Stdio.println(Math.round(3.5));
        \\        Stdio.println(Math.round(3.4));
        \\        Stdio.println(Math.round(0.5));
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
        \\        Stdio.println(Math.floor(0.0));
        \\        Stdio.println(Math.ceil(0.0));
        \\        Stdio.println(Math.round(0.0));
        \\        Stdio.println(Math.floor(0.1));
        \\        Stdio.println(Math.floor(0.9));
        \\        Stdio.println(Math.ceil(0.1));
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
        \\        Stdio.println(Math.round(zero_sin));
        \\        Stdio.println(Math.round(zero_cos));
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
        \\        Stdio.println(Math.round(r4));
        \\        r9: float = Math.sqrt_f(9.0);
        \\        Stdio.println(Math.round(r9));
        \\        r0: float = Math.sqrt_f(0.0);
        \\        Stdio.println(Math.round(r0));
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
        \\        Stdio.println(Math.round(r1));
        \\        r2: float = Math.pow_f(3.0, 0.0);
        \\        Stdio.println(Math.round(r2));
        \\        r3: float = Math.pow_f(2.0, -1.0);
        \\        // 2^-1 = 0.5, round = 1 (rounds half-up)
        \\        Stdio.println(Math.round(r3));
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
        \\        Stdio.println(Math.round(e0));
        \\        // log(1) = 0
        \\        l1: float = Math.log(1.0);
        \\        Stdio.println(Math.round(l1));
        \\        // log10(100) = 2
        \\        l100: float = Math.log10(100.0);
        \\        Stdio.println(Math.round(l100));
        \\        // log10(1000) = 3
        \\        l1000: float = Math.log10(1000.0);
        \\        Stdio.println(Math.round(l1000));
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
        \\        Stdio.println(Math.round(a1));
        \\        mn: float = Math.min_f(1.5, 2.5);
        \\        Stdio.println(Math.round(mn));
        \\        mx: float = Math.max_f(1.5, 2.5);
        \\        Stdio.println(Math.round(mx));
        \\        mn2: float = Math.min_f(0.1, 0.9);
        \\        Stdio.println(Math.round(mn2));
        \\        mx2: float = Math.max_f(0.1, 0.9);
        \\        Stdio.println(Math.round(mx2));
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
        \\        Stdio.println(Math.round(f));
        \\        i: int = Convert.to_int_f(3.7);
        \\        Stdio.println(i);
        \\        zero: int = Convert.to_int_f(0.0);
        \\        Stdio.println(zero);
        \\        big: float = Convert.to_float(1000);
        \\        Stdio.println(Math.round(big));
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
        \\        Stdio.println(s);
        \\        s0: string = Convert.float_to_string(0.0);
        \\        Stdio.println(s0);
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
        \\        Stdio.println(Math.round(f));
        \\        f2: float = Convert.string_to_float("100.0");
        \\        Stdio.println(Math.round(f2));
        \\        bad: float = Convert.string_to_float("abc");
        \\        Stdio.println(Math.round(bad));
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
        \\            Stdio.println("roundtrip ok");
        \\        } else {
        \\            Stdio.println("roundtrip failed");
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
        \\        Stdio.println("before");
        \\        System.exit(0);
        \\        Stdio.println("after");
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
        \\            Stdio.println("ok");
        \\        } else {
        \\            Stdio.println("time went backwards");
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
        \\        Stdio.println(s);
        \\        n: int = Convert.to_int("123");
        \\        Stdio.println(n);
        \\        neg: string = Convert.to_string(-7);
        \\        Stdio.println(neg);
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
        \\        Stdio.println(s0);
        \\        s1: string = Convert.to_string(1);
        \\        Stdio.println(s1);
        \\        sn: string = Convert.to_string(-1);
        \\        Stdio.println(sn);
        \\        sb: string = Convert.to_string(1000000);
        \\        Stdio.println(sb);
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
        \\        Stdio.println(Convert.to_int("0"));
        \\        Stdio.println(Convert.to_int("-42"));
        \\        Stdio.println(Convert.to_int("999"));
        \\        Stdio.println(Convert.to_int("abc"));
        \\        Stdio.println(Convert.to_int(""));
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
        \\            Stdio.println("roundtrip ok");
        \\        } else {
        \\            Stdio.println("roundtrip failed");
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
        \\            Stdio.println("has home");
        \\        } else {
        \\            Stdio.println("no home");
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
        \\            Stdio.println("empty");
        \\        } else {
        \\            Stdio.println("unexpected");
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
        \\        Stdio.println(name);
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
        \\        Stdio.println(count);
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
        \\            Stdio.println("active");
        \\        } else {
        \\            Stdio.println("not active");
        \\        }
        \\        if Json.get_bool(data, "deleted") {
        \\            Stdio.println("deleted");
        \\        } else {
        \\            Stdio.println("not deleted");
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
        \\        Stdio.println(name);
        \\        Stdio.println(age);
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
        \\        Stdio.println(missing);
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
        \\        Stdio.println(Json.get_int(data, "a"));
        \\        Stdio.println(Json.get_int(data, "b"));
        \\        Stdio.println(Json.get_int(data, "c"));
        \\        Stdio.println(Json.get_int(data, "d"));
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
        \\        Stdio.println(Json.get_int(data, "temp"));
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
        \\        Stdio.println(msg);
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
        \\        Stdio.println(c);
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
        \\        Stdio.println(Json.to_int("42"));
        \\        Stdio.println(Json.to_int("-7"));
        \\        Stdio.println(Json.to_bool("true"));
        \\        Stdio.println(Json.to_bool("false"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n-7\n1\n0\n", r.stdout);
}

test "compile: json typed parse struct" {
    const r = try compileAndCapture(
        \\struct User {
        \\    name: string = "";
        \\    age: int = 0;
        \\    active: bool = false;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"alice\", \"age\": 30, \"active\": true}";
        \\        match Json.parse(data, User) {
        \\            :ok{user} => {
        \\                Stdio.println(user.name);
        \\                Stdio.println(user.age);
        \\                if user.active {
        \\                    Stdio.println("active");
        \\                } else {
        \\                    Stdio.println("not active");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("alice\n30\nactive\n", r.stdout);
}

test "compile: json typed parse missing fields use zero defaults" {
    const r = try compileAndCapture(
        \\struct Config {
        \\    host: string = "";
        \\    port: int = 0;
        \\    debug: bool = false;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"port\": 3000}";
        \\        match Json.parse(data, Config) {
        \\            :ok{cfg} => {
        \\                Stdio.println(cfg.port);
        \\                if cfg.debug {
        \\                    Stdio.println("debug on");
        \\                } else {
        \\                    Stdio.println("debug off");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3000\ndebug off\n", r.stdout);
}

test "compile: json typed parse extra fields ignored" {
    const r = try compileAndCapture(
        \\struct Item {
        \\    id: int = 0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "{\"id\": 42, \"name\": \"widget\", \"price\": 9.99}";
        \\        match Json.parse(data, Item) {
        \\            :ok{item} => Stdio.println(item.id);
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: json typed parse invalid json returns error" {
    const r = try compileAndCapture(
        \\struct Thing {
        \\    x: int = 0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "not json at all";
        \\        match Json.parse(data, Thing) {
        \\            :ok{t} => Stdio.println("unexpected success");
        \\            :error{e} => Stdio.println("correctly failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("correctly failed\n", r.stdout);
}

test "compile: json typed parse with http request body" {
    const r = try compileAndCapture(
        \\struct CreateUser {
        \\    name: string = "";
        \\    email: string = "";
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        http_data: string = "POST /users HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\": \"bob\", \"email\": \"bob@test.com\"}";
        \\        req: int = Http.parse_request(http_data);
        \\        body: string = Http.req_body(req);
        \\        match Json.parse(body, CreateUser) {
        \\            :ok{user} => {
        \\                Stdio.println(user.name);
        \\                Stdio.println(user.email);
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("bob\nbob@test.com\n", r.stdout);
}

test "compile: json build simple object" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "name", "verve");
        \\        Json.build_add_int(b, "version", 1);
        \\        result: string = Json.build_end(b);
        \\        Stdio.println(result);
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
        \\        Stdio.println(result);
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
        \\        Stdio.println(result);
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
        \\        Stdio.println(msg);
        \\        Stdio.println(num);
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
        \\        Stdio.println(result);
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
        \\        Stdio.println(count);
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
        \\        Stdio.println(count);
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
        \\                                Stdio.println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\            :ok{conn} => Stdio.println("unexpected success");
        \\            :error{e} => Stdio.println("refused");
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
        \\                                Stdio.println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                Stdio.println(req);
        \\                                Stream.write_line(client, "pong");
        \\                                resp: string = Stream.read_line(conn);
        \\                                Stdio.println(resp);
        \\                                Stream.close(client);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                    Stdio.println(line);
        \\                                    Stream.close(client);
        \\                                }
        \\                                :error{e} => Stdio.println("accept failed");
        \\                            }
        \\                        }
        \\                        :error{e} => Stdio.println("connect failed");
        \\                    }
        \\                    i = i + 1;
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                    Stdio.println("ok");
        \\                } else {
        \\                    Stdio.println("bad port");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                        Stdio.println("unexpected success");
        \\                        Stream.close(listener2);
        \\                    }
        \\                    :error{e} => Stdio.println("address in use");
        \\                }
        \\                Stream.close(listener1);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                Stdio.println(l1);
        \\                                Stdio.println(l2);
        \\                                Stdio.println(l3);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                Stdio.println(count);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                Stdio.println("survived");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                                Stdio.println("ok");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
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
        \\                    :ok{client} => Stdio.println("unexpected");
        \\                    :error{e} => Stdio.println("rejected");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("rejected\n", r.stdout);
}

// ── HTTP tests ─────────────────────────────────────

test "compile: http parse request method and path" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(method);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\n/hello\n", r.stdout);
}

test "compile: http parse request header" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        host: string = Http.req_header(req, "Host");
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(host);
        \\        Stdio.println(ct);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("example.com\napplication/json\n", r.stdout);
}

test "compile: http build response" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        response: string = Http.respond(200, "text/plain", "hello");
        \\        Stdio.println(response);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Response includes Date header, so check key parts
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 200 OK\r\n"));
    try testing.expect(std.mem.indexOf(u8, r.stdout, "Content-Length: 5") != null);
    try testing.expect(std.mem.indexOf(u8, r.stdout, "hello") != null);
}

test "compile: http server loopback" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n");
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                path: string = Http.req_path(req);
        \\                                response: string = Http.respond(200, "text/plain", "ok");
        \\                                Stream.write(conn, response);
        \\                                Stream.close(conn);
        \\                                reply: string = Stream.read_line(client);
        \\                                Stdio.println(reply);
        \\                                Stdio.println(path);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // read_line preserves \r from HTTP \r\n line endings
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\n/test\n", r.stdout);
}

test "compile: http 404 response" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        response: string = Http.respond(404, "text/plain", "not found");
        \\        Stdio.println(response);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 404 Not Found\r\n"));
    try testing.expect(std.mem.indexOf(u8, r.stdout, "Content-Length: 9") != null);
    try testing.expect(std.mem.indexOf(u8, r.stdout, "not found") != null);
}

test "compile: http json response end to end" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello");
        \\        body: string = Json.build_end(b);
        \\        response: string = Http.respond(200, "application/json", body);
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET / HTTP/1.1\r\n\r\n");
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                Stream.write(conn, response);
        \\                                Stream.close(conn);
        \\                                reply: string = Stream.read_line(client);
        \\                                Stdio.println(reply);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\n", r.stdout);
}

test "compile: http parse POST with body" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "POST /api HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"key\":\"val\"}";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(method);
        \\        Stdio.println(body);
        \\        name: string = Json.get_string(body, "key");
        \\        Stdio.println(name);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("POST\n{\"key\":\"val\"}\nval\n", r.stdout);
}

test "compile: http parse different methods" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        get: int = Http.parse_request("GET / HTTP/1.1\r\n\r\n");
        \\        m1: string = Http.req_method(get);
        \\        Stdio.println(m1);
        \\        post: int = Http.parse_request("POST /data HTTP/1.1\r\n\r\n");
        \\        m2: string = Http.req_method(post);
        \\        Stdio.println(m2);
        \\        put: int = Http.parse_request("PUT /item HTTP/1.1\r\n\r\n");
        \\        m3: string = Http.req_method(put);
        \\        Stdio.println(m3);
        \\        del: int = Http.parse_request("DELETE /item HTTP/1.1\r\n\r\n");
        \\        m4: string = Http.req_method(del);
        \\        Stdio.println(m4);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\nPOST\nPUT\nDELETE\n", r.stdout);
}

test "compile: http response status codes" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r200: string = Http.respond(200, "text/plain", "ok");
        \\        r201: string = Http.respond(201, "text/plain", "created");
        \\        r400: string = Http.respond(400, "text/plain", "bad");
        \\        r500: string = Http.respond(500, "text/plain", "error");
        \\        // Check first line of each
        \\        Stdio.println(r200);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Just verify it doesn't crash and produces output
    try testing.expect(r.stdout.len > 0);
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 200 OK"));
}

test "compile: http server with json request and response" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "POST /api HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\":\"test\"}");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                body: string = Http.req_body(req);
        \\                                name: string = Json.get_string(body, "name");
        \\                                b: int = Json.build_object();
        \\                                Json.build_add_string(b, "hello", name);
        \\                                resp_body: string = Json.build_end(b);
        \\                                Stdio.println(resp_body);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"hello\":\"test\"}\n", r.stdout);
}

test "compile: http missing header returns empty" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(String.len(ct));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: http case insensitive headers" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nContent-Type: text/html\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        ct1: string = Http.req_header(req, "content-type");
        \\        ct2: string = Http.req_header(req, "CONTENT-TYPE");
        \\        ct3: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(ct1);
        \\        Stdio.println(ct2);
        \\        Stdio.println(ct3);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("text/html\ntext/html\ntext/html\n", r.stdout);
}

test "compile: http path with query string" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET /search?q=verve&page=1 HTTP/1.1\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/search?q=verve&page=1\n", r.stdout);
}

test "compile: http multiple requests on same listener" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                i: int = 0;
        \\                while i < 3 {
        \\                    match Tcp.open("127.0.0.1", port) {
        \\                        :ok{client} => {
        \\                            n: string = Convert.to_string(i);
        \\                            Stream.write(client, "GET /req" + n + " HTTP/1.1\r\n\r\n");
        \\                            Stream.close(client);
        \\                            match Tcp.accept(listener) {
        \\                                :ok{conn} => {
        \\                                    data: string = Stream.read_bytes(conn, 4096);
        \\                                    req: int = Http.parse_request(data);
        \\                                    path: string = Http.req_path(req);
        \\                                    Stdio.println(path);
        \\                                    Stream.close(conn);
        \\                                }
        \\                                :error{e} => Stdio.println("accept failed");
        \\                            }
        \\                        }
        \\                        :error{e} => Stdio.println("open failed");
        \\                    }
        \\                    i = i + 1;
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/req0\n/req1\n/req2\n", r.stdout);
}

test "compile: json and http integration - parse json body and respond" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "POST /echo HTTP/1.1\r\n\r\n{\"input\":\"hello\"}");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                body: string = Http.req_body(req);
        \\                                input: string = Json.get_string(body, "input");
        \\                                b: int = Json.build_object();
        \\                                Json.build_add_string(b, "output", input);
        \\                                resp: string = Json.build_end(b);
        \\                                Stdio.println(resp);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"output\":\"hello\"}\n", r.stdout);
}

test "compile: http GET without body" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(String.len(body));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: http POST with form encoded body" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "POST /login HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 21\r\n\r\nuser=alice&pass=s3cret";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        body: string = Http.req_body(req);
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(method);
        \\        Stdio.println(body);
        \\        Stdio.println(ct);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("POST\nuser=alice&pass=s3cret\napplication/x-www-form-urlencoded\n", r.stdout);
}

test "compile: http request line only no headers" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/\n", r.stdout);
}

test "compile: http lazy parsing - path only never touches headers" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                path: string = Http.req_path(req);
        \\                                if path == "/health" {
        \\                                    Stdio.println("healthy");
        \\                                } else {
        \\                                    Stdio.println("unknown");
        \\                                }
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("healthy\n", r.stdout);
}

test "compile: http GET with body (elasticsearch style)" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET /search HTTP/1.1\r\nContent-Length: 16\r\n\r\n{\"query\":\"test\"}";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        path: string = Http.req_path(req);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(method);
        \\        Stdio.println(path);
        \\        q: string = Json.get_string(body, "query");
        \\        Stdio.println(q);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\n/search\ntest\n", r.stdout);
}

test "compile: http multiple headers" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nHost: localhost\r\nAccept: text/html\r\nUser-Agent: Verve/1.0\r\nX-Custom: hello\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        host: string = Http.req_header(req, "Host");
        \\        accept: string = Http.req_header(req, "Accept");
        \\        ua: string = Http.req_header(req, "User-Agent");
        \\        custom: string = Http.req_header(req, "X-Custom");
        \\        Stdio.println(host);
        \\        Stdio.println(accept);
        \\        Stdio.println(ua);
        \\        Stdio.println(custom);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("localhost\ntext/html\nVerve/1.0\nhello\n", r.stdout);
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
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.MoveY(20) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.MoveX(5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.GetX() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match p.GetY() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10\n20\n15\n15\n20\n", r.stdout);
}

// ── Typed message protocol coverage ───────────────────

test "compile: process handler with string param" {
    const r = try compileAndCapture(
        \\struct NameState {
        \\    name: string = "";
        \\}
        \\process Greeter<NameState> {
        \\    receive SetName(state: NameState, n: string) -> int {
        \\        state.name = n;
        \\        return 0;
        \\    }
        \\    receive Greet(state: NameState) -> int {
        \\        Stdio.println("Hello " + state.name);
        \\        return 0;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        g: int = spawn Greeter();
        \\        tell g.SetName("world");
        \\        match g.Greet() {
        \\            :ok{v} => Stdio.println("ok");
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("Hello world\nok\n", r.stdout);
}

test "compile: process handler with float param" {
    const r = try compileAndCapture(
        \\struct AccState {
        \\    total: float = 0.0;
        \\}
        \\process Accumulator<AccState> {
        \\    receive Add(state: AccState, x: float) -> int {
        \\        state.total = state.total + x;
        \\        return Math.round(state.total);
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a: int = spawn Accumulator();
        \\        match a.Add(1.5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match a.Add(2.5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("2\n4\n", r.stdout);
}

test "compile: process handler with bool param" {
    const r = try compileAndCapture(
        \\struct FlagState {
        \\    active: bool = false;
        \\}
        \\process Flag<FlagState> {
        \\    receive Set(state: FlagState, val: bool) -> int {
        \\        state.active = val;
        \\        return 0;
        \\    }
        \\    receive IsActive(state: FlagState) -> int {
        \\        if state.active {
        \\            return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        f: int = spawn Flag();
        \\        match f.IsActive() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        tell f.Set(true);
        \\        match f.IsActive() {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n1\n", r.stdout);
}

test "compile: float struct field access" {
    const r = try compileAndCapture(
        \\struct Point {
        \\    x: float = 0.0;
        \\    y: float = 0.0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        p: Point = Point { x: 3.14, y: 2.72 };
        \\        Stdio.println(Math.round(p.x));
        \\        Stdio.println(Math.round(p.y));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n3\n", r.stdout);
}

test "compile: bool struct field access" {
    const r = try compileAndCapture(
        \\struct Config {
        \\    debug: bool = false;
        \\    count: int = 0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: Config = Config { debug: true, count: 42 };
        \\        if c.debug {
        \\            Stdio.println(c.count);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: mixed typed struct fields" {
    const r = try compileAndCapture(
        \\struct Record {
        \\    name: string = "";
        \\    score: float = 0.0;
        \\    active: bool = false;
        \\    age: int = 0;
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        r: Record = Record { name: "Alice", score: 9.5, active: true, age: 30 };
        \\        Stdio.println(r.name);
        \\        Stdio.println(Math.round(r.score));
        \\        if r.active {
        \\            Stdio.println(r.age);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("Alice\n10\n30\n", r.stdout);
}
