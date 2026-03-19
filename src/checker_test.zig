const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const testing = std.testing;

// ── Helpers ───────────────────────────────────────────────

fn checkSource(source: []const u8) !Checker {
    const alloc = testing.allocator;
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
        \\process App {
        \\    state {
        \\        running: bool [capacity: 1];
        \\    }
        \\    receive main(args: list<string>) -> int {
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
        \\        x = 10;
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
        \\    a: int;
        \\    b: string;
        \\    c: bool;
        \\    d: float;
        \\    e: uuid;
        \\    f: void;
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
        \\    balance: Money;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: unknown type in struct field" {
    try expectError(
        \\struct Account {
        \\    balance: Dollars;
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

test "valid: transition in receive handler" {
    try expectNoErrors(
        \\process Counter {
        \\    state {
        \\        count: int [capacity: 1];
        \\    }
        \\    receive Increment() -> int {
        \\        transition count { count + 1; }
        \\        return count;
        \\    }
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: transition in module function" {
    try expectError(
        \\module Main {
        \\    fn main() -> int {
        \\        transition balance { 100; }
        \\        return 0;
        \\    }
        \\}
    , "transition can only be used inside a receive handler");
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
        \\    x: int;
        \\    y: int;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    );
}

test "error: duplicate struct field" {
    try expectError(
        \\struct Point {
        \\    x: int;
        \\    x: int;
        \\}
        \\module Main {
        \\    fn main() -> int { return 0; }
        \\}
    , "duplicate field 'x' in struct 'Point'");
}

// ── Process state in scope ────────────────────────────────

test "valid: process state accessible in handler" {
    try expectNoErrors(
        \\process Counter {
        \\    state {
        \\        count: int [capacity: 1];
        \\    }
        \\    receive GetCount() -> int {
        \\        return count;
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
        \\    id: AccountId;
        \\    name: string;
        \\    active: bool;
        \\}
        \\
        \\module Pricing {
        \\    fn apply_fee(amount: int, rate: int) -> int {
        \\        return amount + rate;
        \\    }
        \\}
        \\
        \\process Ledger {
        \\    state {
        \\        balance: int [capacity: 1];
        \\    }
        \\    receive Deposit(amount: int) -> int {
        \\        guard amount > 0;
        \\        transition balance { balance + amount; }
        \\        return balance;
        \\    }
        \\    receive GetBalance() -> int {
        \\        return balance;
        \\    }
        \\}
        \\
        \\module Main {
        \\    fn main() -> int {
        \\        fee = Pricing.apply_fee(100, 5);
        \\        return 0;
        \\    }
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
