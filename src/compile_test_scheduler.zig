const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower/lower.zig").Lower;
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
    const path = "/tmp/verve_ct_sched";
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
    const path = "/tmp/verve_ct_sched_cap";
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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
        \\process App {
        \\    receive main(args: list<string>) -> int {
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

// ── Timer tests ──────────────────────────────────────

test "compile: Timer.sleep basic" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        Stdio.println("before");
        \\        Timer.sleep(10);
        \\        Stdio.println("after");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("before\nafter\n", r.stdout);
}

test "compile: Timer.sleep yields to other processes" {
    const r = try compileAndCapture(
        \\process Worker {
        \\    receive Ping() -> int {
        \\        Stdio.println("pong");
        \\        return 1;
        \\    }
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        Stdio.println("sleeping");
        \\        Timer.sleep(50);
        \\        match Process.send(w.Ping) {
        \\            :ok{v} => Stdio.println("done");
        \\            :error{e} => Stdio.println("err");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("sleeping\npong\ndone\n", r.stdout);
}

test "compile: Timer.sleep zero ms is no-op" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        Timer.sleep(0);
        \\        Stdio.println("ok");
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}
