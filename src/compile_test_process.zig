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
    const path = "/tmp/verve_ct_proc";
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
    const path = "/tmp/verve_ct_proc_cap";
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
