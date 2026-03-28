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
    const path = "/tmp/verve_ct_basic";
    try backend.build(path, zig_path);
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
    const path = "/tmp/verve_ct_basic_cap";
    try backend.build(path, zig_path);
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
// Enums
// ════════════════════════════════════════════════════════════

test "compile: enum match" {
    try testing.expectEqual(@as(u8, 20), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Green;
        \\    match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\} }
    ));
}

test "compile: enum comparison" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Dir = enum { Up, Down };
        \\module App { fn main(args: list<string>) -> int {
        \\    a: Dir = :Up;
        \\    b: Dir = :Up;
        \\    if a == b { return 1; }
        \\    return 0;
        \\} }
    ));
}

test "compile: enum in struct" {
    try testing.expectEqual(@as(u8, 2), try compileAndRun(
        \\type Currency = enum { USD, EUR, GBP };
        \\struct Account { currency: Currency = :USD; }
        \\module App { fn main(args: list<string>) -> int {
        \\    a: Account = Account { currency: :GBP };
        \\    match a.currency { :USD => return 0; :EUR => return 1; :GBP => return 2; }
        \\} }
    ));
}

test "compile: enum inequality" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    a: Color = :Red;
        \\    b: Color = :Blue;
        \\    if a != b { return 1; }
        \\    return 0;
        \\} }
    ));
}

test "compile: enum match wildcard" {
    try testing.expectEqual(@as(u8, 99), try compileAndRun(
        \\type Suit = enum { Hearts, Diamonds, Clubs, Spades };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Suit = :Clubs;
        \\    match s { :Hearts => return 1; _ => return 99; }
        \\} }
    ));
}

test "compile: enum first variant" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Red;
        \\    match c { :Red => return 0; :Green => return 1; :Blue => return 2; }
        \\} }
    ));
}

test "compile: enum last variant" {
    try testing.expectEqual(@as(u8, 2), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Blue;
        \\    match c { :Red => return 0; :Green => return 1; :Blue => return 2; }
        \\} }
    ));
}

test "compile: enum struct default field" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\type Currency = enum { USD, EUR, GBP };
        \\struct Account { currency: Currency = :USD; balance: int = 0; }
        \\module App { fn main(args: list<string>) -> int {
        \\    a: Account = Account {};
        \\    match a.currency { :USD => return 0; :EUR => return 1; :GBP => return 2; }
        \\} }
    ));
}

test "compile: enum passed to function" {
    try testing.expectEqual(@as(u8, 10), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App {
        \\    fn color_value(c: Color) -> int { match c { :Red => return 10; :Green => return 20; :Blue => return 30; } }
        \\    fn main(args: list<string>) -> int { c: Color = :Red; return color_value(c); }
        \\}
    ));
}

test "compile: enum returned from function" {
    try testing.expectEqual(@as(u8, 20), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App {
        \\    fn pick() -> int { c: Color = :Green; return c; }
        \\    fn main(args: list<string>) -> int {
        \\        c: Color = :Green;
        \\        match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\    }
        \\}
    ));
}

test "compile: two enum types" {
    try testing.expectEqual(@as(u8, 11), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\type Size = enum { Small, Medium, Large };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Red;
        \\    s: Size = :Medium;
        \\    x: int = 0;
        \\    match c { :Red => { x = 10; } :Green => { x = 20; } :Blue => { x = 30; } }
        \\    match s { :Small => { x = x + 0; } :Medium => { x = x + 1; } :Large => { x = x + 2; } }
        \\    return x;
        \\} }
    ));
}

test "compile: enum in if condition" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\type Toggle = enum { On, Off };
        \\module App { fn main(args: list<string>) -> int {
        \\    t: Toggle = :On;
        \\    if t == :On { return 42; }
        \\    return 0;
        \\} }
    ));
}

test "compile: enum reassignment" {
    try testing.expectEqual(@as(u8, 30), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Red;
        \\    c = :Blue;
        \\    match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\} }
    ));
}

test "compile: enum many variants" {
    try testing.expectEqual(@as(u8, 6), try compileAndRun(
        \\type Day = enum { Mon, Tue, Wed, Thu, Fri, Sat, Sun };
        \\module App { fn main(args: list<string>) -> int {
        \\    d: Day = :Sun;
        \\    match d { :Mon => return 0; :Tue => return 1; :Wed => return 2; :Thu => return 3; :Fri => return 4; :Sat => return 5; :Sun => return 6; }
        \\} }
    ));
}

// ════════════════════════════════════════════════════════════
// Tagged Unions
// ════════════════════════════════════════════════════════════

test "compile: tagged union construct and match" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Shape = :circle{42};
        \\    match s { :circle{r} => return r; :rect{s} => return s; }
        \\} }
    ));
}

test "compile: tagged union second variant" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Shape = :rect{7};
        \\    match s { :circle{r} => return r; :rect{side} => return side; }
        \\} }
    ));
}

test "compile: tagged union bare tag" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Light = union { :red {}; :yellow {}; :green {}; };
        \\module App { fn main(args: list<string>) -> int {
        \\    l: Light = :yellow{};
        \\    match l { :red{} => return 0; :yellow{} => return 1; :green{} => return 2; }
        \\} }
    ));
}

test "compile: tagged union wildcard" {
    try testing.expectEqual(@as(u8, 99), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Shape = :rect{5};
        \\    match s { :circle{r} => return r; _ => return 99; }
        \\} }
    ));
}

test "compile: tagged union with string value" {
    const r = try compileAndCapture(
        \\type Msg = union { :text { content: string }; :num { value: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    m: Msg = :text{"hello"};
        \\    match m { :text{s} => { Stdio.println(s); return 0; } :num{n} => return n; }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n", r.stdout);
}

test "compile: two tagged union types" {
    try testing.expectEqual(@as(u8, 15), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\type Result = union { :ok { value: int }; :err { code: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Shape = :circle{10};
        \\    r: Result = :ok{5};
        \\    x: int = 0;
        \\    match s { :circle{radius} => { x = radius; } :rect{side} => { x = side; } }
        \\    match r { :ok{v} => { x = x + v; } :err{c} => { x = x + c; } }
        \\    return x;
        \\} }
    ));
}

test "compile: tagged union passed to function" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\module App {
        \\    fn area(s: Shape) -> int { match s { :circle{r} => return r; :rect{side} => return side; } }
        \\    fn main(args: list<string>) -> int { s: Shape = :circle{42}; return area(s); }
        \\}
    ));
}

test "compile: tagged union reassignment" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    s: Shape = :circle{42};
        \\    s = :rect{7};
        \\    match s { :circle{r} => return r; :rect{side} => return side; }
        \\} }
    ));
}

test "compile: tagged union three variants" {
    try testing.expectEqual(@as(u8, 3), try compileAndRun(
        \\type Op = union { :add { value: int }; :sub { value: int }; :mul { value: int }; };
        \\module App { fn main(args: list<string>) -> int {
        \\    op: Op = :mul{3};
        \\    match op { :add{v} => return v; :sub{v} => return v; :mul{v} => return v; }
        \\} }
    ));
}

test "compile: existing Result match still works" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result { :ok{f} => { Stdio.println("ok"); return 0; } :error{r} => { return 1; } }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}
