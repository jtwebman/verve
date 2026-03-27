const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const testing = std.testing;

// ── Helpers ───────────────────────────────────────────────

fn checkSource(source: []const u8) !Checker {
    const alloc = std.heap.page_allocator;
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var checker = Checker.init(alloc);
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
        \\        c: int = spawn Counter();
        \\        match c.Get() {
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

// ── send/tell checks ──────────────────────────────────────

test "error: send on module (calling module function with process syntax)" {
    // Module functions should be called directly, not via send/tell pattern
    // This is caught when tell is used with a module name
    try expectError(
        \\module Logger {
        \\    fn log(msg: string) -> void {
        \\        return;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        tell Logger.log("hello");
        \\        return 0;
        \\    }
        \\}
    , "cannot use 'tell' with module");
}

test "error: tell on module" {
    try expectError(
        \\module Logger {
        \\    fn log(msg: string) -> void {
        \\        return;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        tell Logger.log("hello");
        \\        return 0;
        \\    }
        \\}
    , "cannot use 'tell' with module 'Logger'");
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

// ── Tell arg checking ─────────────────────────────────────

test "error: wrong arg count to tell" {
    try expectError(
        \\struct WorkerState { value: int = 0; }
        \\process Worker<WorkerState> {
        \\    receive SetValue(state: WorkerState, v: int) -> int {
        \\        state.value = v;
        \\        return state.value;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int {
        \\        w: int = spawn Worker();
        \\        tell w.SetValue(1, 2);
        \\        return 0;
        \\    }
        \\}
    , "expects 1 argument(s), got 2");
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
        \\        w: int = spawn Worker();
        \\        tell w.SetValue(42);
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

test "valid: spawn assigned to int" {
    try expectNoErrors(
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
    );
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
    , "cannot assign int to string");
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
