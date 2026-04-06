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

fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_type";
    try backend.build(path, getZigPath());
    var child = std.process.Child.init(&.{path}, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_type_cap";
    try backend.build(path, getZigPath());
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
// Enums
// ════════════════════════════════════════════════════════════

test "compile: enum match" {
    try testing.expectEqual(@as(u8, 20), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\process App { receive main(args: list<string>) -> int {
        \\    c: Color = :Green;
        \\    match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\} }
    ));
}

test "compile: enum comparison" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Dir = enum { Up, Down };
        \\process App { receive main(args: list<string>) -> int {
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
        \\process App { receive main(args: list<string>) -> int {
        \\    a: Account = Account { currency: :GBP };
        \\    match a.currency { :USD => return 0; :EUR => return 1; :GBP => return 2; }
        \\} }
    ));
}

test "compile: enum inequality" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\process App { receive main(args: list<string>) -> int {
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
        \\process App { receive main(args: list<string>) -> int {
        \\    s: Suit = :Clubs;
        \\    match s { :Hearts => return 1; _ => return 99; }
        \\} }
    ));
}

test "compile: enum first variant" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\process App { receive main(args: list<string>) -> int {
        \\    c: Color = :Red;
        \\    match c { :Red => return 0; :Green => return 1; :Blue => return 2; }
        \\} }
    ));
}

test "compile: enum last variant" {
    try testing.expectEqual(@as(u8, 2), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\process App { receive main(args: list<string>) -> int {
        \\    c: Color = :Blue;
        \\    match c { :Red => return 0; :Green => return 1; :Blue => return 2; }
        \\} }
    ));
}

test "compile: enum struct default field" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\type Currency = enum { USD, EUR, GBP };
        \\struct Account { currency: Currency = :USD; balance: int = 0; }
        \\process App { receive main(args: list<string>) -> int {
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
        \\}
        \\process App { receive main(args: list<string>) -> int { c: Color = :Red; return color_value(c); } }
    ));
}

test "compile: enum returned from function" {
    try testing.expectEqual(@as(u8, 20), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\module App {
        \\    fn pick() -> int { c: Color = :Green; return c; }
        \\}
        \\process App { receive main(args: list<string>) -> int {
        \\    c: Color = :Green;
        \\    match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\} }
    ));
}

test "compile: two enum types" {
    try testing.expectEqual(@as(u8, 11), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\type Size = enum { Small, Medium, Large };
        \\process App { receive main(args: list<string>) -> int {
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
        \\process App { receive main(args: list<string>) -> int {
        \\    t: Toggle = :On;
        \\    if t == :On { return 42; }
        \\    return 0;
        \\} }
    ));
}

test "compile: enum reassignment" {
    try testing.expectEqual(@as(u8, 30), try compileAndRun(
        \\type Color = enum { Red, Green, Blue };
        \\process App { receive main(args: list<string>) -> int {
        \\    c: Color = :Red;
        \\    c = :Blue;
        \\    match c { :Red => return 10; :Green => return 20; :Blue => return 30; }
        \\} }
    ));
}

test "compile: enum many variants" {
    try testing.expectEqual(@as(u8, 6), try compileAndRun(
        \\type Day = enum { Mon, Tue, Wed, Thu, Fri, Sat, Sun };
        \\process App { receive main(args: list<string>) -> int {
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
        \\process App { receive main(args: list<string>) -> int {
        \\    s: Shape = :circle{42};
        \\    match s { :circle{r} => return r; :rect{s} => return s; }
        \\} }
    ));
}

test "compile: tagged union second variant" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\process App { receive main(args: list<string>) -> int {
        \\    s: Shape = :rect{7};
        \\    match s { :circle{r} => return r; :rect{side} => return side; }
        \\} }
    ));
}

test "compile: tagged union bare tag" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\type Light = union { :red {}; :yellow {}; :green {}; };
        \\process App { receive main(args: list<string>) -> int {
        \\    l: Light = :yellow{};
        \\    match l { :red{} => return 0; :yellow{} => return 1; :green{} => return 2; }
        \\} }
    ));
}

test "compile: tagged union wildcard" {
    try testing.expectEqual(@as(u8, 99), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\process App { receive main(args: list<string>) -> int {
        \\    s: Shape = :rect{5};
        \\    match s { :circle{r} => return r; _ => return 99; }
        \\} }
    ));
}

test "compile: tagged union with string value" {
    const r = try compileAndCapture(
        \\type Msg = union { :text { content: string }; :num { value: int }; };
        \\process App { receive main(args: list<string>) -> int {
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
        \\process App { receive main(args: list<string>) -> int {
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
        \\}
        \\process App { receive main(args: list<string>) -> int { s: Shape = :circle{42}; return area(s); } }
    ));
}

test "compile: tagged union reassignment" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\type Shape = union { :circle { radius: int }; :rect { side: int }; };
        \\process App { receive main(args: list<string>) -> int {
        \\    s: Shape = :circle{42};
        \\    s = :rect{7};
        \\    match s { :circle{r} => return r; :rect{side} => return side; }
        \\} }
    ));
}

test "compile: tagged union three variants" {
    try testing.expectEqual(@as(u8, 3), try compileAndRun(
        \\type Op = union { :add { value: int }; :sub { value: int }; :mul { value: int }; };
        \\process App { receive main(args: list<string>) -> int {
        \\    op: Op = :mul{3};
        \\    match op { :add{v} => return v; :sub{v} => return v; :mul{v} => return v; }
        \\} }
    ));
}

// ════════════════════════════════════════════════════════════
// Generic Structs (Monomorphization)
// ════════════════════════════════════════════════════════════

test "compile: generic struct int" {
    try testing.expectEqual(@as(u8, 3), try compileAndRun(
        \\struct Pair<T> { first: T = 0; second: T = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    p: Pair<int> = Pair { first: 1, second: 2 };
        \\    return p.first + p.second;
        \\} }
    ));
}

test "compile: generic struct string" {
    const r = try compileAndCapture(
        \\struct Wrapper<T> { value: T = ""; }
        \\process App { receive main(args: list<string>) -> int {
        \\    w: Wrapper<string> = Wrapper { value: "hello" };
        \\    Stdio.println(w.value);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n", r.stdout);
}

test "compile: two instantiations of same generic" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\struct Box<T> { value: T = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    a: Box<int> = Box { value: 3 };
        \\    b: Box<int> = Box { value: 4 };
        \\    return a.value + b.value;
        \\} }
    ));
}

test "compile: generic struct passed to function" {
    try testing.expectEqual(@as(u8, 5), try compileAndRun(
        \\struct Pair<T> { first: T = 0; second: T = 0; }
        \\module App {
        \\    fn sum(p: Pair<int>) -> int { return p.first + p.second; }
        \\}
        \\process App { receive main(args: list<string>) -> int {
        \\    p: Pair<int> = Pair { first: 2, second: 3 };
        \\    return sum(p);
        \\} }
    ));
}

test "compile: generic struct multiple type params" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\struct Entry<K, V> { key: K = 0; value: V = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    e: Entry<int, int> = Entry { key: 10, value: 32 };
        \\    return e.key + e.value;
        \\} }
    ));
}

test "compile: generic struct with float" {
    try testing.expectEqual(@as(u8, 7), try compileAndRun(
        \\struct Box<T> { value: T = 0.0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    b: Box<float> = Box { value: 7.5 };
        \\    x: int = Convert.to_int_f(b.value);
        \\    return x;
        \\} }
    ));
}

test "compile: generic struct with bool" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\struct Flag<T> { value: T = false; }
        \\process App { receive main(args: list<string>) -> int {
        \\    f: Flag<bool> = Flag { value: true };
        \\    if f.value { return 1; }
        \\    return 0;
        \\} }
    ));
}

test "compile: generic struct default values" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\struct Pair<T> { first: T = 0; second: T = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    p: Pair<int> = Pair {};
        \\    return p.first + p.second;
        \\} }
    ));
}

test "compile: generic struct field reassignment" {
    try testing.expectEqual(@as(u8, 10), try compileAndRun(
        \\struct Box<T> { value: T = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    b: Box<int> = Box { value: 5 };
        \\    return b.value + b.value;
        \\} }
    ));
}

test "compile: different generic instantiations in same program" {
    const r = try compileAndCapture(
        \\struct Box<T> { value: T = 0; }
        \\process App { receive main(args: list<string>) -> int {
        \\    a: Box<int> = Box { value: 42 };
        \\    b: Box<string> = Box { value: "hello" };
        \\    Stdio.println(a.value);
        \\    Stdio.println(b.value);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\nhello\n", r.stdout);
}

// ════════════════════════════════════════════════════════════
// Optional Types (T?)
// ════════════════════════════════════════════════════════════

test "compile: optional int with value" {
    try testing.expectEqual(@as(u8, 42), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: int? = 42;
        \\    match x { :some{val} => return val; none => return 0; }
        \\} }
    ));
}

test "compile: optional int none" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: int? = none;
        \\    match x { :some{val} => return val; none => return 0; }
        \\} }
    ));
}

test "compile: optional string with value" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: string? = "hello";
        \\    match x { :some{val} => { Stdio.println(val); return 0; } none => return 1; }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n", r.stdout);
}

test "compile: optional string none" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: string? = none;
        \\    match x { :some{val} => return 0; none => return 1; }
        \\} }
    ));
}

test "compile: optional with wildcard" {
    try testing.expectEqual(@as(u8, 99), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: int? = 5;
        \\    match x { none => return 0; _ => return 99; }
        \\} }
    ));
}

test "compile: optional reassign to none" {
    try testing.expectEqual(@as(u8, 0), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: int? = 42;
        \\    x = none;
        \\    match x { :some{val} => return val; none => return 0; }
        \\} }
    ));
}

test "compile: optional bool" {
    try testing.expectEqual(@as(u8, 1), try compileAndRun(
        \\process App { receive main(args: list<string>) -> int {
        \\    x: bool? = true;
        \\    match x { :some{val} => { if val { return 1; } return 0; } none => return 2; }
        \\} }
    ));
}

// ── Sized integer types ─────────────────────────────────

test "compile: int32 struct store and load" {
    const r = try compileAndCapture(
        \\struct Point { x: int32 = 0; y: int32 = 0; }
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        p: Point = Point { x: 100, y: 200 };
        \\        sum: int = p.x + p.y;
        \\        Stdio.println(sum);
        \\        return sum - 300;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("300\n", r.stdout);
}

test "compile: uint8 boundary values" {
    const r = try compileAndCapture(
        \\struct Pixel { r: uint8 = 0; g: uint8 = 0; b: uint8 = 0; }
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        p: Pixel = Pixel { r: 255, g: 128, b: 0 };
        \\        total: int = p.r + p.g + p.b;
        \\        Stdio.println(p.r);
        \\        Stdio.println(total);
        \\        return total - 383;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("255\n383\n", r.stdout);
}

test "compile: int16 arithmetic widening" {
    const r = try compileAndCapture(
        \\struct Header { version: int16 = 0; flags: int16 = 0; }
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        h: Header = Header { version: 3, flags: 256 };
        \\        sum: int = h.version + h.flags;
        \\        product: int = h.version * h.flags;
        \\        Stdio.println(sum);
        \\        Stdio.println(product);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("259\n768\n", r.stdout);
}

test "compile: mixed sized int struct with function" {
    const r = try compileAndCapture(
        \\struct Record { id: int32 = 0; tag: uint8 = 0; score: int16 = 0; }
        \\module Util {
        \\    fn total(r: Record) -> int {
        \\        return r.id + r.tag + r.score;
        \\    }
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        r: Record = Record { id: 42, tag: 7, score: 1000 };
        \\        Stdio.println(Util.total(r));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1049\n", r.stdout);
}

test "compile: sized int process handler params" {
    const r = try compileAndCapture(
        \\process Adder {
        \\    receive Add(a: int32, b: int32) -> int {
        \\        return a + b;
        \\    }
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        adder: pid<Adder> = spawn Adder();
        \\        match Process.send(adder.Add, 100, 200) {
        \\            :ok{result} => {
        \\                Stdio.println(result);
        \\                return 0;
        \\            }
        \\            :error{e} => return 1;
        \\        }
        \\        return 1;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("300\n", r.stdout);
}
