const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const ZigBackend = @import("zig_backend.zig").ZigBackend;
const testing = std.testing;
const alloc = std.heap.page_allocator;

fn getZigPath() []const u8 {
    return std.posix.getenv("VERVE_ZIG") orelse "/home/jt/.local/zig/zig";
}

fn getOptimizeMode() []const u8 {
    return std.posix.getenv("VERVE_OPTIMIZE") orelse "-OReleaseFast";
}

/// Compile Verve source to native binary, run it, return exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_proc";
    try backend.build(path, getZigPath());
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
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_proc_cap";
    try backend.build(path, getZigPath());
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
        \\        counter: pid<Counter> = spawn Counter();
        \\        match Process.send(counter.Increment) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(counter.Increment) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(counter.GetCount) {
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
        \\        counter: pid<Counter> = spawn Counter();
        \\        Process.tell(counter.Increment);
        \\        Process.tell(counter.Increment);
        \\        Process.tell(counter.Increment);
        \\        match Process.send(counter.GetCount) {
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
        \\        counter: pid<Counter> = spawn Counter();
        \\        match Process.send(counter.Add, 5) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("guard failed");
        \\        }
        \\        match Process.send(counter.Add, 0) {
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
        \\        p: pid<Pair> = spawn Pair();
        \\        match Process.send(p.SetX, 10) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.SetY, 32) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.Sum) {
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
        \\        a1: pid<Adder> = spawn Adder();
        \\        a2: pid<Adder> = spawn Adder();
        \\        match Process.send(a1.Add, 10) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a2.Add, 20) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a1.Add, 5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a1.GetTotal) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a2.GetTotal) {
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
        \\        c: pid<Counter> = spawn Counter();
        \\        i: int = 0;
        \\        while i < 50 {
        \\            Process.tell(c.Increment);
        \\            i = i + 1;
        \\        }
        \\        match Process.send(c.GetCount) {
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
        \\        k: pid<NameKeeper> = spawn NameKeeper();
        \\        match Process.send(k.SetName, "alice") {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(k.SetName, "bob") {
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
    // Process.exit kills the worker mid-handler. Main uses tell (fire-and-forget)
    // so it doesn't block. Worker may or may not print before main exits.
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\struct WState { x: int = 0; }
        \\process Worker<WState> {
        \\    receive DoWork(state: WState, val: int) -> void {
        \\        Process.exit();
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        Process.tell(w.DoWork, 42);
        \\        return 0;
        \\    }
        \\}
    ));
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
        \\        p: pid<Point> = spawn Point();
        \\        match Process.send(p.MoveX, 10) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.MoveY, 20) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.MoveX, 5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.GetX) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(p.GetY) {
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
        \\        g: pid<Greeter> = spawn Greeter();
        \\        Process.tell(g.SetName, "world");
        \\        match Process.send(g.Greet) {
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
        \\        a: pid<Accumulator> = spawn Accumulator();
        \\        match Process.send(a.Add, 1.5) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a.Add, 2.5) {
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
        \\        f: pid<Flag> = spawn Flag();
        \\        match Process.send(f.IsActive) {
        \\            :ok{v} => Stdio.println(v);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        Process.tell(f.Set, true);
        \\        match Process.send(f.IsActive) {
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

test "compile: void handler with tell" {
    const r = try compileAndCapture(
        \\struct LogState { count: int = 0; }
        \\process Logger<LogState> {
        \\    receive Log(state: LogState) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: LogState) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        logger: pid<Logger> = spawn Logger();
        \\        Process.tell(logger.Log);
        \\        Process.tell(logger.Log);
        \\        Process.tell(logger.Log);
        \\        match Process.send(logger.GetCount) {
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

test "compile: void handler with params" {
    const r = try compileAndCapture(
        \\struct AccState { total: int = 0; }
        \\process Acc<AccState> {
        \\    receive Add(state: AccState, n: int) -> void {
        \\        state.total = state.total + n;
        \\    }
        \\    receive GetTotal(state: AccState) -> int {
        \\        return state.total;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        acc: pid<Acc> = spawn Acc();
        \\        Process.tell(acc.Add, 10);
        \\        Process.tell(acc.Add, 20);
        \\        Process.tell(acc.Add, 12);
        \\        match Process.send(acc.GetTotal) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: mailbox overflow returns error on send" {
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> [mailbox: 2] {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.Inc) {
        \\            :ok{v} => Stdio.println("ok1");
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        match Process.send(c.Inc) {
        \\            :ok{v} => Stdio.println("ok2");
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        match Process.send(c.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok1\nok2\n2\n", r.stdout);
}

test "compile: match tell returns Result" {
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.tell(c.Inc) {
        \\            :ok{v} => Stdio.println("sent");
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        match Process.send(c.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("sent\n1\n", r.stdout);
}

// ── Scheduler tests ─────────────────────────────────────

test "compile: scheduler runs with single thread" {
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        match Process.send(c.GetCount) {
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

test "compile: multiple processes communicate" {
    const r = try compileAndCapture(
        \\struct AS { total: int = 0; }
        \\process Adder<AS> {
        \\    receive Add(state: AS, n: int) -> void {
        \\        state.total = state.total + n;
        \\    }
        \\    receive GetTotal(state: AS) -> int {
        \\        return state.total;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        a1: pid<Adder> = spawn Adder();
        \\        a2: pid<Adder> = spawn Adder();
        \\        Process.tell(a1.Add, 10);
        \\        Process.tell(a2.Add, 20);
        \\        Process.tell(a1.Add, 5);
        \\        match Process.send(a1.GetTotal) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        match Process.send(a2.GetTotal) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("15\n20\n", r.stdout);
}

test "compile: process with tight loop yields (reduction counting)" {
    const r = try compileAndCapture(
        \\struct WS { result: int = 0; }
        \\process Worker<WS> {
        \\    receive Compute(state: WS, n: int) -> int {
        \\        i: int = 0;
        \\        while i < n {
        \\            i = i + 1;
        \\        }
        \\        state.result = i;
        \\        return i;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        match Process.send(w.Compute, 10000) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10000\n", r.stdout);
}

test "compile: thread_id returns a value" {
    const r = try compileAndCapture(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        tid: int = Process.thread_id();
        \\        Stdio.println(tid);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

// ── Yield + send/tell interaction tests ──────────────────

test "compile: tell with yield handler then send" {
    // Tests: tell Inc (3x), tell Save (handler yields), tell Inc, send GetTotal
    // Save handler calls Process.yield() — tests that yield during tell dispatch works.
    // GetTotal is a send — tests that send after yields returns correct result.
    // Expected: 3 incs + save(yields) + 1 inc = 4 total
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; saved: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive Save(state: CS) -> void {
        \\        state.saved = state.count;
        \\        Process.yield();
        \\    }
        \\    receive GetTotal(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Save);
        \\        Process.tell(c.Inc);
        \\        match Process.send(c.GetTotal) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("4\n", r.stdout);
}

test "compile: yield splits handler — saved reflects pre-yield state" {
    // Save sets saved AFTER yield, so saved = count at time of yield (3).
    // Inc after Save bumps count to 4 but saved stays 3.
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; saved: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive Save(state: CS) -> void {
        \\        Process.yield();
        \\        state.saved = state.count;
        \\    }
        \\    receive GetSaved(state: CS) -> int {
        \\        return state.saved;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Inc);
        \\        Process.tell(c.Save);
        \\        Process.tell(c.Inc);
        \\        match Process.send(c.GetSaved) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3\n", r.stdout);
}

test "compile: send to dead process returns error" {
    const r = try compileAndCapture(
        \\struct WS { x: int = 0; }
        \\process Worker<WS> {
        \\    receive DoWork(state: WS) -> void {
        \\        Process.exit();
        \\    }
        \\    receive GetResult(state: WS) -> int {
        \\        return 42;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        Process.tell(w.DoWork);
        \\        match Process.send(w.GetResult) {
        \\            :ok{val} => Stdio.println("ok");
        \\            :error{e} => Stdio.println("error");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("error\n", r.stdout);
}

test "compile: tell and send to different processes interleave correctly" {
    // Validates that a tell to process A doesn't corrupt a send to process B.
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\struct CS2 { count: int = 0; }
        \\process Counter2<CS2> {
        \\    receive Inc(state: CS2) -> void {
        \\        state.count = state.count + 10;
        \\    }
        \\    receive GetCount(state: CS2) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c1: pid<Counter> = spawn Counter();
        \\        c2: pid<Counter2> = spawn Counter2();
        \\        Process.tell(c1.Inc);
        \\        Process.tell(c1.Inc);
        \\        Process.tell(c1.Inc);
        \\        Process.tell(c2.Inc);
        \\        match Process.send(c2.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        match Process.send(c1.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("10\n3\n", r.stdout);
}

test "compile: send returns 0 correctly (not confused with error)" {
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> {
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: parent death kills child processes" {
    // Main spawns counter, counter is a child of main.
    // When main exits, counter should be killed automatically.
    // This is tested implicitly: if the scheduler didn't clean up,
    // the program would hang. A clean exit proves children were killed.
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        Process.tell(c.Inc);
        \\        Stdio.println("done");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("done\n", r.stdout);
}

test "compile: mailbox full returns error string" {
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> [mailbox: 1] {
        \\    receive Inc(state: CS) -> void {
        \\        state.count = state.count + 1;
        \\    }
        \\    receive GetCount(state: CS) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.GetCount) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: send retries on full mailbox instead of failing" {
    // With [mailbox: 2], flood tells then send — send should still succeed
    // because verve_send now yields and retries when mailbox is full.
    const r = try compileAndCapture(
        \\struct CS { count: int = 0; }
        \\process Counter<CS> [mailbox: 2] {
        \\    receive Inc(state: CS) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        i: int = 0;
        \\        while i < 20 {
        \\            match Process.tell(c.Inc) {
        \\                :ok{v} => { i = i + 1; }
        \\                :error{e} => { Process.yield(); }
        \\            }
        \\        }
        \\        match Process.send(c.Inc) {
        \\            :ok{val} => Stdio.println(val);
        \\            :error{e} => Stdio.println(e);
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("21\n", r.stdout);
}

test "compile: send_timeout returns timeout on unresponsive process" {
    // Block handler loops long enough that 1ms timeout expires before
    // the Fast handler gets a chance to run. 10M iterations with yield_check
    // every 4000 = 2500 yields + loop time, well over 1ms even in ReleaseFast.
    const r = try compileAndCapture(
        \\struct CS { val: int = 0; }
        \\process Slow<CS> {
        \\    receive Block(state: CS) -> int {
        \\        i: int = 0;
        \\        while i < 10000000 {
        \\            i = i + 1;
        \\        }
        \\        return state.val;
        \\    }
        \\    receive Fast(state: CS) -> int {
        \\        return 42;
        \\    }
        \\}
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        s: pid<Slow> = spawn Slow();
        \\        Process.tell(s.Block);
        \\        match Process.send_timeout(s.Fast, 1) {
        \\            :ok{val} => Stdio.println("ok");
        \\            :error{e} => Stdio.println("timeout");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("timeout\n", r.stdout);
}
