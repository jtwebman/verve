const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const testing = std.testing;

// ── Helpers ───────────────────────────────────────────────

fn checkSource(source: []const u8) !Checker {
    const alloc = std.heap.page_allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var checker = Checker.init(alloc, source);
    try checker.check(file);
    return checker;
}

fn expectNoErrors(source: []const u8) !void {
    var checker = try checkSource(source);
    if (checker.hasErrors()) {
        std.debug.print("\nUnexpected errors:\n", .{});
        checker.printErrors();
    }
    try testing.expect(!checker.hasErrors());
}

fn expectError(source: []const u8, expected_substring: []const u8) !void {
    var checker = try checkSource(source);
    try testing.expect(checker.hasErrors());
    var found = false;
    for (checker.errors.items) |err| {
        if (std.mem.indexOf(u8, err.message, expected_substring) != null) {
            found = true;
            break;
        }
    }
    if (!found) {
        std.debug.print("\nExpected error containing: '{s}'\nGot errors:\n", .{expected_substring});
        checker.printErrors();
    }
    try testing.expect(found);
}

fn expectErrorCount(source: []const u8, expected: usize) !void {
    var checker = try checkSource(source);
    if (checker.errors.items.len != expected) {
        std.debug.print("\nExpected {d} errors, got {d}:\n", .{ expected, checker.errors.items.len });
        checker.printErrors();
    }
    try testing.expectEqual(expected, checker.errors.items.len);
}

// ── Entry point ───────────────────────────────────────────

test "valid: module with main function" {
    try expectNoErrors(
        \\module App {
        \\    fn main(args: list<string>) -> int {
        \\        return 0;
        \\    }
        \\}
    );
}

test "valid: process with main function" {
    try expectNoErrors(
        \\struct AppState { running: bool = false; }
        \\process App<AppState> {
        \\    receive main(state: AppState, args: list<string>) -> int {
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: no entry point" {
    try expectError(
        \\module Helper {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
    , "no entry point found");
}

test "valid: library with exports and no main" {
    try expectNoErrors(
        \\/// Math utilities.
        \\export module Math {
        \\    /// Add two numbers.
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\}
    );
}

test "error: multiple entry points" {
    try expectError(
        \\module App1 {
        \\    fn main() -> int { return 0; }
        \\}
        \\module App2 {
        \\    fn main() -> int { return 0; }
        \\}
    , "multiple entry points");
}

// ── Undefined variables ───────────────────────────────────

test "valid: variable defined before use" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        return x;
        \\    }
        \\}
    );
}

test "error: variable without type declaration" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x = 10;
        \\        return x;
        \\    }
        \\}
    , "must be declared with a type");
}

test "valid: variable reassignment after declaration" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        x = 20;
        \\        return x;
        \\    }
        \\}
    );
}

test "error: undefined variable" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        return x;
        \\    }
        \\}
    , "undefined variable 'x'");
}

test "valid: function parameter in scope" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(n: int) -> int {
        \\        return n;
        \\    }
        \\}
    );
}

// ── Unknown types ─────────────────────────────────────────

test "valid: built-in types" {
    try expectNoErrors(
        \\struct Record {
        \\    a: int = 0;
        \\    b: string = "";
        \\    c: bool = false;
        \\    d: float = 0.0;
        \\    e: uuid = "";
        \\    f: void = void;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "valid: user-defined type" {
    try expectNoErrors(
        \\type Money = decimal;
        \\struct Account {
        \\    balance: Money = 0;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: unknown type in struct field" {
    try expectError(
        \\struct Account {
        \\    balance: Dollars = 0;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "unknown type 'Dollars'");
}

test "error: unknown type in function param" {
    try expectError(
        \\module Main {
        \\    fn main(x: Foo) -> int { return 0; }
        \\}
    , "unknown type 'Foo'");
}

test "error: unknown type in return type" {
    try expectError(
        \\module Main {
        \\    fn main() -> Foo { return 0; }
        \\}
    , "unknown type 'Foo'");
}

test "valid: generic types" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(args: list<string>) -> int { return 0; }
        \\}
    );
}

test "error: unknown generic type" {
    try expectError(
        \\module Main {
        \\    fn main(x: Foo<int>) -> int { return 0; }
        \\}
    , "unknown generic type 'Foo'");
}

// ── Guard checks ──────────────────────────────────────────

test "valid: boolean guard expression" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        guard x > 0;
        \\        return x;
        \\    }
        \\}
    );
}

test "error: string literal as guard" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        guard "hello";
        \\        return 0;
        \\    }
        \\}
    , "guard/while condition must be boolean, got string");
}

test "error: int literal as guard" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        guard 42;
        \\        return 0;
        \\    }
        \\}
    , "guard/while condition must be boolean, got int");
}

// ── Transition checks ─────────────────────────────────────

test "valid: field assign in receive handler" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

// ── receive; checks ───────────────────────────────────────

test "error: receive in module function" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        receive;
        \\        return 0;
        \\    }
        \\}
    , "receive; can only be used inside a process");
}

// ── Match checks ──────────────────────────────────────────

test "valid: match with two arms" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(x: bool) -> int {
        \\        match x {
        \\            true => return 1;
        \\            false => return 0;
        \\        }
        \\    }
        \\}
    );
}

test "error: empty match" {
    try expectError(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x {
        \\        }
        \\    }
        \\}
    , "match must have at least one arm");
}

test "valid: boolean match with both cases" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x > 0 {
        \\            true => return 1;
        \\            false => return 0;
        \\        }
        \\    }
        \\}
    );
}

test "error: boolean match missing false" {
    try expectError(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x > 0 {
        \\            true => return 1;
        \\        }
        \\    }
        \\}
    , "missing 'false' case");
}

test "error: boolean match missing true" {
    try expectError(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x > 0 {
        \\            false => return 0;
        \\        }
        \\    }
        \\}
    , "missing 'true' case");
}

// ── Enum match exhaustiveness ─────────────────────────────

test "valid: enum match covers all variants" {
    try expectNoErrors(
        \\type Color = enum { Red, Green, Blue };
        \\module Main {
        \\    fn name(c: Color) -> string {
        \\        match c {
        \\            :Red => return "red";
        \\            :Green => return "green";
        \\            :Blue => return "blue";
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: enum match missing variant" {
    try expectError(
        \\type Color = enum { Red, Green, Blue };
        \\module Main {
        \\    fn name(c: Color) -> string {
        \\        match c {
        \\            :Red => return "red";
        \\            :Green => return "green";
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "missing case ':Blue'");
}

test "valid: enum match with wildcard" {
    try expectNoErrors(
        \\type Color = enum { Red, Green, Blue };
        \\module Main {
        \\    fn name(c: Color) -> string {
        \\        match c {
        \\            :Red => return "red";
        \\            _ => return "other";
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: enum match missing multiple variants" {
    try expectError(
        \\type Direction = enum { North, South, East, West };
        \\module Main {
        \\    fn name(d: Direction) -> string {
        \\        match d {
        \\            :North => return "north";
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "missing case");
}

test "error: match not exhaustive without wildcard" {
    try expectError(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x {
        \\            42 => return 1;
        \\        }
        \\    }
        \\}
    , "match is not exhaustive");
}

test "valid: match with wildcard is exhaustive" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x {
        \\            42 => return 1;
        \\            _ => return 0;
        \\        }
        \\    }
        \\}
    );
}

test "valid: Result match with ok and error is exhaustive" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Get(state: CounterState) -> int { return state.count; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.Get) {
        \\            :ok{val} => return val;
        \\            :error{reason} => return 1;
        \\        }
        \\    }
        \\}
    );
}

test "valid: boolean match with wildcard" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(x: int) -> int {
        \\        match x > 0 {
        \\            true => return 1;
        \\            _ => return 0;
        \\        }
        \\    }
        \\}
    );
}

// ── While checks ──────────────────────────────────────────

test "error: string condition in while" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        while "yes" {
        \\            return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "guard/while condition must be boolean, got string");
}

// ── Struct checks ─────────────────────────────────────────

test "valid: struct with unique fields" {
    try expectNoErrors(
        \\struct Point {
        \\    x: int = 0;
        \\    y: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: duplicate struct field" {
    try expectError(
        \\struct Point {
        \\    x: int = 0;
        \\    x: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "duplicate field 'x' in struct 'Point'");
}

// ── Process state in scope ────────────────────────────────

test "error: struct field without default value" {
    try expectError(
        \\struct BadState {
        \\    count: int;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "requires a default value");
}

test "valid: process state accessible in handler" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive GetCount(state: CounterState) -> int {
        \\        return state.count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

// ── Complex valid programs ────────────────────────────────

test "valid: full program with module and process" {
    try expectNoErrors(
        \\type AccountId = uuid;
        \\
        \\struct Account {
        \\    id: AccountId = "";
        \\    name: string = "";
        \\    active: bool = false;
        \\}
        \\
        \\module Pricing {
        \\    fn apply_fee(amount: int, rate: int) -> int {
        \\        return amount + rate;
        \\    }
        \\}
        \\
        \\struct LedgerState { balance: int = 0; }
        \\process Ledger<LedgerState> {
        \\    receive Deposit(state: LedgerState, amount: int) -> int {
        \\        guard amount > 0;
        \\        state.balance = state.balance + amount;
        \\        return state.balance;
        \\    }
        \\    receive GetBalance(state: LedgerState) -> int {
        \\        return state.balance;
        \\    }
        \\}
        \\
        \\module Main {
        \\    fn main() -> int {
        \\        fee: int = Pricing.apply_fee(100, 5);
        \\        return 0;
        \\    }
        \\}
    );
}

// ── Guard consistency ─────────────────────────────────────

test "error: guard always false" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        guard false;
        \\        return 0;
        \\    }
        \\}
    , "guard is always false");
}

test "error: guard x > x is always false" {
    try expectError(
        \\module Main {
        \\    fn check(x: int) -> int {
        \\        guard x > x;
        \\        return x;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "compared to itself");
}

test "error: guard x != x is always false" {
    try expectError(
        \\module Main {
        \\    fn check(x: int) -> int {
        \\        guard x != x;
        \\        return x;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "compared to itself");
}

test "valid: guard x == x is fine" {
    try expectNoErrors(
        \\module Main {
        \\    fn check(x: int) -> int {
        \\        guard x == x;
        \\        return x;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

// ── Poison value warnings ─────────────────────────────────

test "error: literal division by zero" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        return 42 / 0;
        \\    }
        \\}
    , "division by zero");
}

test "error: literal modulo by zero" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        return 42 % 0;
        \\    }
        \\}
    , "division by zero");
}

test "valid: division by non-zero" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        return 42 / 6;
        \\    }
        \\}
    );
}

// ── Divergence detection ──────────────────────────────────

test "error: while true with no return" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        while true {
        \\            Stdio.println("forever");
        \\        }
        \\    }
        \\}
    , "potential infinite loop");
}

test "valid: while true with return inside" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        while true {
        \\            return 0;
        \\        }
        \\    }
        \\}
    );
}

test "valid: while with condition variable" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        running: bool = true;
        \\        while running {
        \\            return 0;
        \\        }
        \\        return 1;
        \\    }
        \\}
    );
}

// ── Recursion detection ───────────────────────────────────

test "valid: no recursion" {
    try expectNoErrors(
        \\module Main {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        return add(1, 2);
        \\    }
        \\}
    );
}

test "error: direct recursion" {
    try expectError(
        \\module Main {
        \\    fn countdown(n: int) -> int {
        \\        return countdown(n);
        \\    }
        \\    fn main() -> int {
        \\        return countdown(10);
        \\    }
        \\}
    , "recursion detected");
}

test "error: mutual recursion" {
    try expectError(
        \\module Main {
        \\    fn ping(n: int) -> int {
        \\        return pong(n);
        \\    }
        \\    fn pong(n: int) -> int {
        \\        return ping(n);
        \\    }
        \\    fn main() -> int {
        \\        return ping(10);
        \\    }
        \\}
    , "recursion detected");
}

test "error: cross-module recursion" {
    try expectError(
        \\module A {
        \\    fn call_b() -> int {
        \\        return B.call_a();
        \\    }
        \\}
        \\module B {
        \\    fn call_a() -> int {
        \\        return A.call_b();
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "recursion detected");
}

test "valid: A calls B calls C (no cycle)" {
    try expectNoErrors(
        \\module C {
        \\    fn value() -> int { return 42; }
        \\}
        \\module B {
        \\    fn get() -> int { return C.value(); }
        \\}
        \\module Main {
        \\    fn main() -> int { return B.get(); }
        \\}
    );
}

// ── Multiple errors ───────────────────────────────────────

test "reports multiple errors" {
    const checker = try checkSource(
        \\module Main {
        \\    fn main() -> Foo {
        \\        guard 42;
        \\        return x;
        \\    }
        \\}
    );
    // Should have at least 3 errors: unknown type Foo, int guard, undefined x
    try testing.expect(checker.errors.items.len >= 3);
}

// ── Call checking ──────────────────────────────────────────

test "error: too many arguments" {
    try expectError(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        return add(1, 2, 3);
        \\    }
        \\}
    , "expects 2 argument(s), got 3");
}

test "error: too few arguments" {
    try expectError(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        return add(1);
        \\    }
        \\}
    , "expects 2 argument(s), got 1");
}

test "error: wrong argument type" {
    try expectError(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        return add(1, "hello");
        \\    }
        \\}
    , "argument 'b' in call to 'Math.add'");
}

test "valid: correct call" {
    try expectNoErrors(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        return add(1, 2);
        \\    }
        \\}
    );
}

test "valid: cross-module call" {
    try expectNoErrors(
        \\module Util {
        \\    fn double(x: int) -> int {
        \\        return x + x;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        return Util.double(5);
        \\    }
        \\}
    );
}

// ── Return type checking ──────────────────────────────────

test "error: return string from int function" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        return "hello";
        \\    }
        \\}
    , "Main.main: return type mismatch");
}

test "error: return int from string function" {
    try expectError(
        \\module Main {
        \\    fn greet() -> string {
        \\        return 42;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "Main.greet: return type mismatch");
}

test "valid: matching return type" {
    try expectNoErrors(
        \\module Main {
        \\    fn greet() -> string {
        \\        return "hello";
        \\    }
        \\    fn main() -> int {
        \\        return 0;
        \\    }
        \\}
    );
}

// ── Assignment type checking ──────────────────────────────

test "error: assign string to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = "hello";
        \\        return 0;
        \\    }
        \\}
    , "Main.main: type mismatch in 'x'");
}

test "error: reassign wrong type" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        x = "hello";
        \\        return x;
        \\    }
        \\}
    , "cannot assign string to int");
}

test "valid: matching assignment" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = 42;
        \\        x = 100;
        \\        return x;
        \\    }
        \\}
    );
}

// ── Generics in scope ─────────────────────────────────────

test "valid: list<int> preserved in scope" {
    try expectNoErrors(
        \\module Main {
        \\    fn main(args: list<string>) -> int {
        \\        nums: list<int> = list(1, 2, 3);
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: fn returning int assigned to string var" {
    try expectError(
        \\module Math {
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\    fn main() -> int {
        \\        x: string = add(1, 2);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "valid: correct tell" {
    try expectNoErrors(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive SetValue(state: WorkerState, v: int) -> int {
        \\        state.value = v;
        \\        return state.value;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        Process.tell(w.SetValue, 42);
        \\        return 0;
        \\    }
        \\}
    );
}

// ── Built-in function return types ────────────────────────

test "error: Stdio.println assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = Stdio.println("hello");
        \\        return x;
        \\    }
        \\}
    , "cannot assign void to int");
}

test "error: return Stdio.println from int function" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        return Stdio.println("hi");
        \\    }
        \\}
    , "Main.main: return type mismatch");
}

test "valid: spawn assigned to pid" {
    try expectNoErrors(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive Get(state: WorkerState) -> int { return state.value; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        return 0;
        \\    }
        \\}
    );
}

// ── Typed PID tests ─────────────────────────────────────

test "error: pid with unknown process type" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        w: pid<NonExistent> = spawn Worker();
        \\        return 0;
        \\    }
        \\}
    , "unknown process type 'NonExistent'");
}

test "error: spawn pid assigned to int" {
    try expectError(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive Get(state: WorkerState) -> int { return state.value; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: int = spawn Worker();
        \\        return 0;
        \\    }
        \\}
    , "cannot assign pid<Worker> to int");
}

test "error: spawn pid assigned to string" {
    try expectError(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive Get(state: WorkerState) -> int { return state.value; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: string = spawn Worker();
        \\        return 0;
        \\    }
        \\}
    , "cannot assign pid<Worker> to string");
}

test "valid: pid as function parameter" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\}
        \\module Main {
        \\    fn send_increment(c: pid<Counter>) -> int {
        \\        match Process.send(c.Increment) {
        \\            :ok{val} => return val;
        \\            :error{e} => return 0;
        \\        }
        \\    }
        \\    fn main() -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        return send_increment(c);
        \\    }
        \\}
    );
}

test "valid: pid type inferred from spawn" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Inc(state: CounterState) -> int {
        \\        state.count = state.count + 1;
        \\        return state.count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.Inc) {
        \\            :ok{val} => return val;
        \\            :error{e} => return 0;
        \\        }
        \\    }
        \\}
    );
}

test "valid: pid with tell" {
    try expectNoErrors(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive SetValue(state: WorkerState, v: int) -> void {
        \\        state.value = v;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: pid<Worker> = spawn Worker();
        \\        match Process.tell(w.SetValue, 42) {
        \\            :ok{val} => return 0;
        \\            :error{e} => return 1;
        \\        }
        \\    }
        \\}
    );
}

test "error: wrong pid type" {
    try expectError(
        \\struct AState { x: int = 0; }
        \\struct BState { y: int = 0; }
        \\process ProcA<AState> {
        \\    receive GetX(state: AState) -> int { return state.x; }
        \\}
        \\process ProcB<BState> {
        \\    receive GetY(state: BState) -> int { return state.y; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        a: pid<ProcA> = spawn ProcB();
        \\        return 0;
        \\    }
        \\}
    , "cannot assign pid<ProcB> to pid<ProcA>");
}

test "error: wrong pid type passed to function" {
    try expectError(
        \\struct AState { x: int = 0; }
        \\struct BState { y: int = 0; }
        \\process ProcA<AState> {
        \\    receive GetX(state: AState) -> int { return state.x; }
        \\}
        \\process ProcB<BState> {
        \\    receive GetY(state: BState) -> int { return state.y; }
        \\}
        \\module Main {
        \\    fn use_a(a: pid<ProcA>) -> int { return 0; }
        \\    fn main() -> int {
        \\        b: pid<ProcB> = spawn ProcB();
        \\        return use_a(b);
        \\    }
        \\}
    , "expected pid<ProcA>, got pid<ProcB>");
}

test "valid: Process.self returns typed pid in handler" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive GetSelf(state: CounterState) -> int {
        \\        me: pid<Counter> = Process.self();
        \\        return 0;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: Process.self wrong pid type in handler" {
    try expectError(
        \\struct AState { x: int = 0; }
        \\struct BState { y: int = 0; }
        \\process ProcA<AState> {
        \\    receive GetSelf(state: AState) -> int {
        \\        me: pid<ProcB> = Process.self();
        \\        return 0;
        \\    }
        \\}
        \\process ProcB<BState> {
        \\    receive Noop(state: BState) -> int { return 0; }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "cannot assign pid<ProcA> to pid<ProcB>");
}

// ── Built-in module function return types ─────────────────

test "error: String.len assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = String.len("hello");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "valid: String.len assigned to int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = String.len("hello");
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: String.contains assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = String.contains("hello", "he");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign bool to int");
}

test "valid: String.contains assigned to bool" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: bool = String.contains("hello", "he");
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: String.trim assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = String.trim("  hello  ");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign string to int");
}

test "error: Stdio.out assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = Stdio.out();
        \\        return 0;
        \\    }
        \\}
    , "cannot assign stream to int");
}

test "valid: Stdio.out assigned to stream" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        s: stream = Stdio.out();
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: Set.has assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: set<int> = set();
        \\        x: string = Set.has(s, 1);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign bool to string");
}

test "error: return String.len from string function" {
    try expectError(
        \\module Main {
        \\    fn greet() -> string {
        \\        return String.len("hi");
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "Main.greet: return type mismatch");
}

// ── Field access inference ────────────────────────────────

test "valid: string.len returns int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        s: string = "hello";
        \\        x: int = s.len;
        \\        return x;
        \\    }
        \\}
    );
}

test "error: list.len assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        nums: list<int> = list(1, 2, 3);
        \\        x: string = nums.len;
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "valid: struct field access type" {
    try expectNoErrors(
        \\struct Point {
        \\    x: int = 0;
        \\    y: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        p: Point = Point { x: 1, y: 2 };
        \\        v: int = p.x;
        \\        return v;
        \\    }
        \\}
    );
}

test "error: struct field access wrong type" {
    try expectError(
        \\struct Point {
        \\    x: int = 0;
        \\    y: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        p: Point = Point { x: 1, y: 2 };
        \\        v: string = p.x;
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

// ── Index access inference ────────────────────────────────

test "valid: list<int> index returns int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        nums: list<int> = list(1, 2, 3);
        \\        x: int = nums[0];
        \\        return x;
        \\    }
        \\}
    );
}

test "error: list<int> index assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        nums: list<int> = list(1, 2, 3);
        \\        x: string = nums[0];
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "valid: string index returns string" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        s: string = "hello";
        \\        c: string = s[0];
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: string index assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: string = "hello";
        \\        c: int = s[0];
        \\        return 0;
        \\    }
        \\}
    , "cannot assign string to int");
}

test "error: map<string, int> index assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: string = m["key"];
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "valid: map<string, int> index returns int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: int = m["key"];
        \\        return x;
        \\    }
        \\}
    );
}

// ── Additional built-in function coverage ─────────────────

test "error: spawn assigned to string" {
    try expectError(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive Get(state: WorkerState) -> int { return state.value; }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: string = spawn Worker();
        \\        return 0;
        \\    }
        \\}
    , "cannot assign pid<Worker> to string");
}

test "error: print assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = Stdio.print("hi");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to string");
}

// ── Additional String module coverage ─────────────────────

test "valid: String.trim assigned to string" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = String.trim("  hello  ");
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: String.starts_with assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: int = String.starts_with("hello", "he");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign bool to int");
}

test "valid: String.starts_with assigned to bool" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: bool = String.starts_with("hello", "he");
        \\        return 0;
        \\    }
        \\}
    );
}

test "valid: String.replace assigned to string" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = String.replace("hello", "l", "r");
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: String.byte_at assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = String.byte_at("hello", 0);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

// ── Additional Map/Set/Stack/Queue coverage ───────────────

test "valid: Map.has assigned to bool" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: bool = Map.has(m, "key");
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: Map.put assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: int = Map.put(m, "key", 42);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to int");
}

test "valid: Set.has assigned to bool" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        s: set<int> = set();
        \\        x: bool = Set.has(s, 1);
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: Set.add assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: set<int> = set();
        \\        x: int = Set.add(s, 1);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to int");
}

test "error: Stack.push assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: stack<int> = stack();
        \\        x: int = Stack.push(s, 1);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to int");
}

test "error: Queue.push assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        q: queue<int> = queue();
        \\        x: int = Queue.push(q, 1);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to int");
}

// ── Additional Stream coverage ────────────────────────────

test "error: Stream.write assigned to string" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: stream = Stdio.out();
        \\        x: string = Stream.write(s, "hi");
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to string");
}

test "error: Stream.close assigned to int" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        s: stream = Stdio.out();
        \\        x: int = Stream.close(s);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign void to int");
}

// ── Additional field access coverage ──────────────────────

test "valid: list.len assigned to int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        nums: list<int> = list(1, 2, 3);
        \\        x: int = nums.len;
        \\        return x;
        \\    }
        \\}
    );
}

test "valid: map.len assigned to int" {
    try expectNoErrors(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: int = m.len;
        \\        return x;
        \\    }
        \\}
    );
}

test "error: map.len assigned to bool" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        m: map<string, int> = map();
        \\        x: bool = m.len;
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to bool");
}

test "valid: struct field with string type" {
    try expectNoErrors(
        \\struct Person {
        \\    name: string = "";
        \\    age: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        p: Person = Person { name: "Alice", age: 30 };
        \\        n: string = p.name;
        \\        a: int = p.age;
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: struct string field assigned to int" {
    try expectError(
        \\struct Person {
        \\    name: string = "";
        \\    age: int = 0;
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        p: Person = Person { name: "Alice", age: 30 };
        \\        x: int = p.name;
        \\        return 0;
        \\    }
        \\}
    , "cannot assign string to int");
}

// ── Cross-module call type mismatches ─────────────────────

test "error: cross-module wrong arg type" {
    try expectError(
        \\module Util {
        \\    fn double(x: int) -> int {
        \\        return x + x;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        return Util.double("hello");
        \\    }
        \\}
    , "argument 'x' in call to 'Util.double'");
}

test "error: cross-module return type mismatch" {
    try expectError(
        \\module Util {
        \\    fn double(x: int) -> int {
        \\        return x + x;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        x: string = Util.double(5);
        \\        return 0;
        \\    }
        \\}
    , "cannot assign int to string");
}

test "error: cross-module too many args" {
    try expectError(
        \\module Util {
        \\    fn double(x: int) -> int {
        \\        return x + x;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        return Util.double(5, 10);
        \\    }
        \\}
    , "expects 1 argument(s), got 2");
}

// ── Type alias resolution in assignments ──────────────────

test "valid: type alias compatible with base type" {
    try expectNoErrors(
        \\type Money = int;
        \\module Main {
        \\    fn main() -> int {
        \\        x: Money = 42;
        \\        return 0;
        \\    }
        \\}
    );
}

test "error: type alias incompatible assignment" {
    try expectError(
        \\type Money = int;
        \\module Main {
        \\    fn main() -> int {
        \\        x: Money = "hello";
        \\        return 0;
        \\    }
        \\}
    , "cannot assign string to Money");
}

// ── Result<T> inner type checking ─────────────────────

test "checker: Result type accepted on match" {
    try expectNoErrors(
        \\struct CounterState { count: int = 0; }
        \\process Counter<CounterState> {
        \\    receive Increment(state: CounterState) -> int {
        \\        return state.count + 1;
        \\    }
        \\}
        \\module App {
        \\    fn main() -> int {
        \\        c: pid<Counter> = spawn Counter();
        \\        match Process.send(c.Increment) {
        \\            :ok{val} => return val;
        \\            :error{e} => return 0;
        \\        }
        \\    }
        \\}
    );
}

test "checker: File.open returns Result" {
    try expectNoErrors(
        \\module App {
        \\    fn main() -> int {
        \\        result: Result<stream> = File.open("test.txt", "r");
        \\        match result {
        \\            :ok{f} => return 0;
        \\            :error{e} => return 1;
        \\        }
        \\    }
        \\}
    );
}

// ── Error location tests ─────────────────────────────────

fn expectErrorWithLocation(source: []const u8, expected_substring: []const u8) !void {
    var checker = try checkSource(source);
    try testing.expect(checker.hasErrors());
    var found = false;
    for (checker.errors.items) |err| {
        if (std.mem.indexOf(u8, err.message, expected_substring) != null) {
            // Verify line > 0 (has real location)
            if (err.line > 0) {
                found = true;
                break;
            }
        }
    }
    if (!found) {
        std.debug.print("\nExpected error with location containing: '{s}'\nGot errors:\n", .{expected_substring});
        for (checker.errors.items) |err| {
            std.debug.print("  line {d}, col {d}: {s}\n", .{ err.line, err.col, err.message });
        }
    }
    try testing.expect(found);
}

test "error location: type mismatch in assignment" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        x: int = "hello";
        \\        return 0;
        \\    }
        \\}
    , "type mismatch");
}

test "error location: return type mismatch" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        return "hello";
        \\    }
        \\}
    , "return type mismatch");
}

test "error location: struct field missing default" {
    try expectErrorWithLocation(
        \\struct Point {
        \\    x: int;
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "requires a default value");
}

test "error location: exported module missing doc comment" {
    try expectErrorWithLocation(
        \\export module Lib {
        \\    /// documented
        \\    fn helper() -> int { return 0; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "missing a /// doc comment");
}

test "error location: exported function missing doc comment" {
    try expectErrorWithLocation(
        \\export module Lib {
        \\    fn helper() -> int { return 0; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "missing a /// doc comment");
}

// ── Scope isolation tests ────────────────────────────────

test "scope: variable declared in if-body not visible after" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        if true {
        \\            x: int = 42;
        \\        }
        \\        y: int = x;
        \\        return 0;
        \\    }
        \\}
    , "undefined variable 'x'");
}

test "scope: variable declared in while-body not visible after" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        while false {
        \\            x: int = 42;
        \\        }
        \\        y: int = x;
        \\        return 0;
        \\    }
        \\}
    , "undefined variable 'x'");
}

test "scope: variable declared before if is accessible inside" {
    try expectNoErrors(
        \\module App {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        if true {
        \\            y: int = x;
        \\        }
        \\        return x;
        \\    }
        \\}
    );
}

test "scope: variable declared before if is accessible after" {
    try expectNoErrors(
        \\module App {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        if true {
        \\            x = 20;
        \\        }
        \\        return x;
        \\    }
        \\}
    );
}

// ── Return path analysis tests ───────────────────────────

test "return: function with no return errors" {
    try expectError(
        \\module App {
        \\    fn add(a: int, b: int) -> int {
        \\        x: int = a + b;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "does not return a value on all code paths");
}

test "return: function with return in both if/else ok" {
    try expectNoErrors(
        \\module App {
        \\    fn abs(x: int) -> int {
        \\        if x > 0 {
        \\            return x;
        \\        } else {
        \\            return 0 - x;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: function with return only in if errors" {
    try expectError(
        \\module App {
        \\    fn maybe(x: int) -> int {
        \\        if x > 0 {
        \\            return x;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "does not return a value on all code paths");
}

test "return: void function with no return ok" {
    try expectNoErrors(
        \\module App {
        \\    fn doNothing() -> void {
        \\        x: int = 42;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: while true with return ok" {
    try expectNoErrors(
        \\module App {
        \\    fn loop() -> int {
        \\        while true {
        \\            return 0;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: match with both bool arms return ok" {
    try expectNoErrors(
        \\module App {
        \\    fn check(x: int) -> int {
        \\        match x > 0 {
        \\            true => return 1;
        \\            false => return 0;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

// ── Additional error location tests ──────────────────────

test "error location: reassignment type mismatch" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        x: int = 10;
        \\        x = "oops";
        \\        return 0;
        \\    }
        \\}
    , "type mismatch");
}

test "error location: variable without type declaration" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        x = 42;
        \\        return 0;
        \\    }
        \\}
    , "must be declared with a type");
}

test "error location: exported process missing doc comment" {
    try expectErrorWithLocation(
        \\struct CS { count: int = 0; }
        \\export process Counter<CS> {
        \\    /// documented
        \\    receive Inc(state: CS) -> int { return state.count; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "missing a /// doc comment");
}

test "error location: duplicate struct field" {
    try expectErrorWithLocation(
        \\struct Bad {
        \\    x: int = 0;
        \\    x: int = 1;
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "duplicate field");
}

test "error location: handler state type mismatch" {
    try expectErrorWithLocation(
        \\struct A { x: int = 0; }
        \\struct B { y: int = 0; }
        \\export process P<A> {
        \\    /// handler
        \\    receive Do(state: B) -> int { return 0; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "state parameter must be typed");
}

test "error location: process unknown state type" {
    try expectErrorWithLocation(
        \\export process P<NoSuchStruct> {
        \\    /// handler
        \\    receive Do() -> int { return 0; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "not a known struct");
}

test "error location: non-exhaustive match" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        x: int = 5;
        \\        match x > 0 {
        \\            true => return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "not exhaustive");
}

test "error location: while true no return (divergence)" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn main() -> int {
        \\        while true {
        \\            x: int = 1;
        \\        }
        \\    }
        \\}
    , "potential infinite loop");
}

test "error location: return path analysis" {
    try expectErrorWithLocation(
        \\module App {
        \\    fn bad() -> int {
        \\        x: int = 42;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "does not return a value");
}

// ── Additional scope isolation tests ─────────────────────

test "scope: variable declared in else-body not visible after" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        if false {
        \\            y: int = 1;
        \\        } else {
        \\            x: int = 42;
        \\        }
        \\        z: int = x;
        \\        return 0;
        \\    }
        \\}
    , "undefined variable 'x'");
}

test "scope: match arm binding not visible after match" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        match true {
        \\            true => {
        \\                inner: int = 99;
        \\            }
        \\            false => {
        \\                other: int = 0;
        \\            }
        \\        }
        \\        z: int = inner;
        \\        return 0;
        \\    }
        \\}
    , "undefined variable 'inner'");
}

test "scope: nested if scopes are isolated" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        if true {
        \\            if true {
        \\                deep: int = 1;
        \\            }
        \\            z: int = deep;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "undefined variable 'deep'");
}

// ── Additional return path tests ─────────────────────────

test "return: nested if/else all return ok" {
    try expectNoErrors(
        \\module App {
        \\    fn classify(x: int) -> int {
        \\        if x > 0 {
        \\            if x > 100 {
        \\                return 2;
        \\            } else {
        \\                return 1;
        \\            }
        \\        } else {
        \\            return 0;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: nested if without else in one branch errors" {
    try expectError(
        \\module App {
        \\    fn classify(x: int) -> int {
        \\        if x > 0 {
        \\            if x > 100 {
        \\                return 2;
        \\            }
        \\        } else {
        \\            return 0;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "does not return a value on all code paths");
}

test "return: match with wildcard all arms return ok" {
    try expectNoErrors(
        \\module App {
        \\    fn check(x: int) -> int {
        \\        match x {
        \\            _ => return 0;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: match without wildcard and not exhaustive errors" {
    try expectError(
        \\module App {
        \\    fn check(x: int) -> int {
        \\        match x > 0 {
        \\            true => return 1;
        \\        }
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "does not return a value on all code paths");
}

test "return: return after if without else ok" {
    try expectNoErrors(
        \\module App {
        \\    fn check(x: int) -> int {
        \\        if x > 0 {
        \\            x = x + 1;
        \\        }
        \\        return x;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "return: handler missing return errors" {
    try expectError(
        \\struct CS { v: int = 0; }
        \\process P<CS> {
        \\    receive Get(state: CS) -> int {
        \\        x: int = state.v;
        \\    }
        \\    receive main(state: CS) -> int { return 0; }
        \\}
    , "does not return a value on all code paths");
}

test "return: handler missing return has location" {
    try expectErrorWithLocation(
        \\struct CS { v: int = 0; }
        \\process P<CS> {
        \\    receive Get(state: CS) -> int {
        \\        x: int = state.v;
        \\    }
        \\    receive main(state: CS) -> int { return 0; }
        \\}
    , "does not return a value");
}

// ── Coverage for all remaining checker error paths ───────

test "error: exported handler missing doc comment" {
    try expectError(
        \\struct CS { count: int = 0; }
        \\export process Counter<CS> {
        \\    receive Inc(state: CS) -> int { return state.count; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "missing a /// doc comment");
}

test "error location: exported handler missing doc comment" {
    try expectErrorWithLocation(
        \\struct CS { count: int = 0; }
        \\export process Counter<CS> {
        \\    receive Inc(state: CS) -> int { return state.count; }
        \\}
        \\module App {
        \\    fn main() -> int { return 0; }
        \\}
    , "missing a /// doc comment");
}

test "error: handler must have state as first parameter" {
    try expectError(
        \\struct CS { x: int = 0; }
        \\process P<CS> {
        \\    receive Do(val: int) -> int { return val; }
        \\    receive main(state: CS) -> int { return 0; }
        \\}
    , "must have 'state: CS' as first parameter");
}

test "error location: handler must have state as first parameter" {
    try expectErrorWithLocation(
        \\struct CS { x: int = 0; }
        \\process P<CS> {
        \\    receive Do(val: int) -> int { return val; }
        \\    receive main(state: CS) -> int { return 0; }
        \\}
    , "must have 'state:");
}

test "error: float literal as guard condition" {
    try expectError(
        \\module App {
        \\    fn bad() -> int {
        \\        guard 3.14;
        \\        return 0;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "must be boolean, got float");
}

test "error: generic type requires type parameters" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        x: list = list();
        \\        return 0;
        \\    }
        \\}
    , "requires type parameters");
}

test "error: while condition must be boolean string" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        while "yes" {
        \\            return 0;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "must be boolean, got string");
}

test "error: while condition must be boolean int" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        while 42 {
        \\            return 0;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "must be boolean, got int");
}

test "error: guard x compared to itself" {
    try expectError(
        \\module App {
        \\    fn bad(x: int) -> int {
        \\        guard x > x;
        \\        return 0;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "compared to itself");
}

test "error: division by zero literal" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        return 42 / 0;
        \\    }
        \\}
    , "division by zero");
}

test "error: unknown type in declaration" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        x: Foo = 42;
        \\        return 0;
        \\    }
        \\}
    , "unknown type 'Foo'");
}

test "error: unknown generic type in variable" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        x: Foo<int> = 42;
        \\        return 0;
        \\    }
        \\}
    , "unknown generic type 'Foo'");
}

test "error: match on boolean missing true" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        x: bool = false;
        \\        match x {
        \\            false => return 0;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "missing 'true' case");
}

test "error: match on boolean missing false" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        x: bool = true;
        \\        match x {
        \\            true => return 0;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "missing 'false' case");
}

test "error: match on enum missing variant" {
    try expectError(
        \\type Color = enum { Red, Green, Blue };
        \\module App {
        \\    fn main() -> int {
        \\        c: Color = :Red;
        \\        match c {
        \\            :Red => return 0;
        \\            :Green => return 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    , "missing case ':Blue'");
}

test "error: recursion detected" {
    try expectError(
        \\module App {
        \\    fn loop() -> int { return App.loop(); }
        \\    fn main() -> int { return 0; }
        \\}
    , "recursion detected");
}

test "error: receive outside process" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        receive;
        \\        return 0;
        \\    }
        \\}
    , "can only be used inside a process");
}

test "error: missing entry point" {
    try expectError(
        \\module Lib {
        \\    fn helper() -> int { return 0; }
        \\}
    , "no entry point found");
}

test "error: two main functions" {
    try expectError(
        \\module A {
        \\    fn main() -> int { return 0; }
        \\}
        \\module B {
        \\    fn main() -> int { return 0; }
        \\}
    , "multiple entry points");
}

test "error: match must have at least one arm" {
    try expectError(
        \\module App {
        \\    fn main() -> int {
        \\        match true {}
        \\        return 0;
        \\    }
        \\}
    , "at least one arm");
}

test "error: guard always false literal" {
    try expectError(
        \\module App {
        \\    fn bad() -> int {
        \\        guard false;
        \\        return 0;
        \\    }
        \\    fn main() -> int { return 0; }
        \\}
    , "guard is always false");
}
