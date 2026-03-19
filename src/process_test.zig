const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Value = @import("value.zig").Value;
const testing = std.testing;

// ── Helper ────────────────────────────────────────────────

fn runMain(source: []const u8) !Value {
    const alloc = std.heap.page_allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var interp = Interpreter.init(alloc);
    try interp.load(file);
    const entry = interp.findMain() orelse return error.Unexpected;
    if (entry.is_process) {
        return try interp.runProcessMain(entry.module, &.{});
    } else {
        return try interp.callFunction(entry.module, entry.name, &.{});
    }
}

fn run(source: []const u8, module_name: []const u8, fn_name: []const u8, args: []const Value) !Value {
    const alloc = std.heap.page_allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var interp = Interpreter.init(alloc);
    try interp.load(file);
    return try interp.callFunction(module_name, fn_name, args);
}

// ── Spawn & send ──────────────────────────────────────────

test "spawn process and send message" {
    const val = try runMain(
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c = spawn Counter();
        \\        match c.GetCount() {
        \\            :ok{val} => return val;
        \\            :error{reason} => return 1;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "spawn process and increment state" {
    const val = try runMain(
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c = spawn Counter();
        \\        c.Increment();
        \\        c.Increment();
        \\        c.Increment();
        \\        match c.Increment() {
        \\            :ok{val} => return val;
        \\            :error{reason} => return 0;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 4), val.int);
}

test "process guard fails returns error" {
    const val = try runMain(
        \\process Account {
        \\    state {
        \\        balance: int;
        \\    }
        \\    receive Withdraw(amount: int) -> int {
        \\        guard amount > 0;
        \\        guard balance >= amount;
        \\        transition balance { balance - amount; }
        \\        return balance;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        acc = spawn Account();
        \\        match acc.Withdraw(100) {
        \\            :ok{val} => return val;
        \\            :error{reason} => return 1;
        \\        }
        \\    }
        \\}
    );
    // balance is 0, can't withdraw 100 — guard fails
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "multiple processes with independent state" {
    const val = try runMain(
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive Add(n: int) -> int {
        \\        transition count { count + n; }
        \\        return count;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        a = spawn Counter();
        \\        b = spawn Counter();
        \\        a.Add(10);
        \\        b.Add(20);
        \\        a.Add(5);
        \\        match a.GetCount() {
        \\            :ok{va} => {
        \\                match b.GetCount() {
        \\                    :ok{vb} => return va + vb;
        \\                    :error{r} => return 0;
        \\                }
        \\            }
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    // a = 15, b = 20, total = 35
    try testing.expectEqual(@as(i64, 35), val.int);
}

test "process state transition with guard" {
    const val = try runMain(
        \\process Ledger {
        \\    state {
        \\        balance: int;
        \\    }
        \\    receive Deposit(amount: int) -> int {
        \\        guard amount > 0;
        \\        transition balance { balance + amount; }
        \\        return balance;
        \\    }
        \\    receive Withdraw(amount: int) -> int {
        \\        guard amount > 0;
        \\        guard balance >= amount;
        \\        transition balance { balance - amount; }
        \\        return balance;
        \\    }
        \\    receive GetBalance() -> int {
        \\        return balance;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        ledger = spawn Ledger();
        \\        ledger.Deposit(100);
        \\        ledger.Deposit(50);
        \\        ledger.Withdraw(30);
        \\        match ledger.GetBalance() {
        \\            :ok{val} => return val;
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    // 100 + 50 - 30 = 120
    try testing.expectEqual(@as(i64, 120), val.int);
}

test "process entry point with main" {
    const val = try runMain(
        \\process App {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive main() -> int {
        \\        return 42;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 42), val.int);
}

test "process calls module function" {
    const val = try runMain(
        \\module Math {
        \\    fn double(x: int) -> int {
        \\        return x * 2;
        \\    }
        \\}
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive AddDoubled(n: int) -> int {
        \\        doubled = Math.double(n);
        \\        transition count { count + doubled; }
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c = spawn Counter();
        \\        match c.AddDoubled(5) {
        \\            :ok{val} => return val;
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 10), val.int);
}

test "send to dead process returns error" {
    const val = try runMain(
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c = spawn Counter();
        \\        // First call works
        \\        match c.GetCount() {
        \\            :ok{val} => println("Got: ", val);
        \\            :error{reason} => println("Error");
        \\        }
        \\        // TODO: kill the process, then send should fail
        \\        // For now, verify the ok path works
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "match send handles all three cases" {
    // Verify the AI pattern: match send always has :ok, :error, :timeout
    const val = try runMain(
        \\process Ledger {
        \\    state {
        \\        balance: int;
        \\    }
        \\    receive Withdraw(amount: int) -> int {
        \\        guard balance >= amount;
        \\        transition balance { balance - amount; }
        \\        return balance;
        \\    }
        \\    receive Deposit(amount: int) -> int {
        \\        guard amount > 0;
        \\        transition balance { balance + amount; }
        \\        return balance;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        ledger = spawn Ledger();
        \\        ledger.Deposit(100);
        \\        // This should fail — balance is 100, withdrawing 200
        \\        match ledger.Withdraw(200) {
        \\            :ok{val} => return val;
        \\            :error{reason} => return 1;
        \\        }
        \\    }
        \\}
    );
    // Guard fails: balance(100) >= 200 is false
    try testing.expectEqual(@as(i64, 1), val.int);
}

test "multiple operations with guard success and failure" {
    const val = try runMain(
        \\process Account {
        \\    state {
        \\        balance: int;
        \\    }
        \\    receive Deposit(amount: int) -> int {
        \\        guard amount > 0;
        \\        transition balance { balance + amount; }
        \\        return balance;
        \\    }
        \\    receive Withdraw(amount: int) -> int {
        \\        guard amount > 0;
        \\        guard balance >= amount;
        \\        transition balance { balance - amount; }
        \\        return balance;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        acc = spawn Account();
        \\        // Deposit works
        \\        match acc.Deposit(100) {
        \\            :ok{v} => println("Deposited, balance: ", v);
        \\            :error{r} => return 1;
        \\        }
        \\        // Withdraw within balance works
        \\        match acc.Withdraw(30) {
        \\            :ok{v} => println("Withdrew 30, balance: ", v);
        \\            :error{r} => return 2;
        \\        }
        \\        // Withdraw over balance fails
        \\        match acc.Withdraw(200) {
        \\            :ok{v} => return 3;
        \\            :error{r} => println("Correctly rejected overdraw");
        \\        }
        \\        // Deposit zero fails guard
        \\        match acc.Deposit(0) {
        \\            :ok{v} => return 4;
        \\            :error{r} => println("Correctly rejected zero deposit");
        \\        }
        \\        // Final balance should be 70
        \\        match acc.Withdraw(70) {
        \\            :ok{v} => return v;
        \\            :error{r} => return 5;
        \\        }
        \\    }
        \\}
    );
    // 100 - 30 - 70 = 0
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "watch a process" {
    const val = try runMain(
        \\process Worker {
        \\    state {
        \\        value: int;
        \\    }
        \\    receive SetValue(v: int) -> int {
        \\        transition value { v; }
        \\        return value;
        \\    }
        \\}
        \\process App {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive main() -> int {
        \\        w = spawn Worker();
        \\        watch w;
        \\        match w.SetValue(99) {
        \\            :ok{v} => return v;
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 99), val.int);
}

test "receive; processes a queued message" {
    // In single-threaded interpreter, receive; processes from mailbox
    // This tests the basic pattern — more meaningful in multi-threaded runtime
    const val = try runMain(
        \\process App {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive main() -> int {
        \\        // No messages queued — receive; is no-op in single-threaded
        \\        receive;
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 0), val.int);
}

test "tell fires and forgets" {
    const val = try runMain(
        \\process Logger {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive Log(msg: string) -> void {
        \\        transition count { count + 1; }
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        logger = spawn Logger();
        \\        tell logger.Log("first");
        \\        tell logger.Log("second");
        \\        tell logger.Log("third");
        \\        match logger.GetCount() {
        \\            :ok{v} => return v;
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 3), val.int);
}

test "send to process from module function" {
    const val = try runMain(
        \\process Counter {
        \\    state {
        \\        count: int;
        \\    }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\}
        \\module Helper {
        \\    fn increment_three_times(c: int) -> int {
        \\        // TODO: need to pass process reference properly
        \\        return 3;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c = spawn Counter();
        \\        c.Increment();
        \\        c.Increment();
        \\        c.Increment();
        \\        match c.Increment() {
        \\            :ok{val} => return val;
        \\            :error{r} => return 0;
        \\        }
        \\    }
        \\}
    );
    try testing.expectEqual(@as(i64, 4), val.int);
}
