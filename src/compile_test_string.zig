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
    const path = "/tmp/verve_ct_str";
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
    const path = "/tmp/verve_ct_str_cap";
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
        \\        c: pid<Counter> = spawn Counter();
        \\        i: int = 0;
        \\        while i < 1000 {
        \\            match Process.send(c.Inc) {
        \\                :ok{v} => {
        \\                    i = i + 1;
        \\                }
        \\                :error{e} => {
        \\                    i = i + 1;
        \\                }
        \\            }
        \\        }
        \\        match Process.send(c.Inc) {
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

// ════════════════════════════════════════════════════════════
// String Interpolation
// ════════════════════════════════════════════════════════════

test "compile: string interpolation with variable" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    name: string = "world";
        \\    Stdio.println("hello ${name}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world\n", r.stdout);
}

test "compile: string interpolation with int expression" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    x: int = 42;
        \\    Stdio.println("value is ${x}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("value is 42\n", r.stdout);
}

test "compile: string interpolation with arithmetic" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    Stdio.println("1 + 1 = ${1 + 1}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1 + 1 = 2\n", r.stdout);
}

test "compile: string interpolation multiple parts" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    a: string = "hello";
        \\    b: string = "world";
        \\    Stdio.println("${a} ${b}!");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world!\n", r.stdout);
}

test "compile: string interpolation assigned to variable" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    name: string = "verve";
        \\    msg: string = "lang: ${name}";
        \\    Stdio.println(msg);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("lang: verve\n", r.stdout);
}

test "compile: string interpolation empty string parts" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    x: int = 7;
        \\    Stdio.println("${x}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("7\n", r.stdout);
}

test "compile: string interpolation with bool" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    x: bool = true;
        \\    Stdio.println("flag: ${x}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("flag: true\n", r.stdout);
}

// ════════════════════════════════════════════════════════════
// Unified to_string
// ════════════════════════════════════════════════════════════

test "compile: enum to_string via interpolation" {
    const r = try compileAndCapture(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Green;
        \\    Stdio.println("color: ${c}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("color: Green\n", r.stdout);
}

test "compile: enum to_string via println" {
    const r = try compileAndCapture(
        \\type Color = enum { Red, Green, Blue };
        \\module App { fn main(args: list<string>) -> int {
        \\    c: Color = :Blue;
        \\    Stdio.println(c);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // println without type hint falls back to int — prints the variant index
    try testing.expectEqualStrings("2\n", r.stdout);
}

test "compile: struct to_string via interpolation" {
    const r = try compileAndCapture(
        \\struct Point { x: int = 0; y: int = 0; }
        \\module App { fn main(args: list<string>) -> int {
        \\    p: Point = Point { x: 3, y: 7 };
        \\    Stdio.println("point: ${p}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("point: Point { x: 3, y: 7 }\n", r.stdout);
}

test "compile: struct to_string with string field" {
    const r = try compileAndCapture(
        \\struct User { name: string = ""; age: int = 0; }
        \\module App { fn main(args: list<string>) -> int {
        \\    u: User = User { name: "alice", age: 30 };
        \\    Stdio.println("user: ${u}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("user: User { name: alice, age: 30 }\n", r.stdout);
}

test "compile: bool to_string via println" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    x: bool = false;
        \\    Stdio.println(x);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("false\n", r.stdout);
}

test "compile: int and float to_string via println" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    Stdio.println(42);
        \\    Stdio.println(3.14);
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n3.14\n", r.stdout);
}

test "compile: list to_string via interpolation" {
    const r = try compileAndCapture(
        \\module App { fn main(args: list<string>) -> int {
        \\    items: list<int> = list();
        \\    append items { 1; }
        \\    append items { 2; }
        \\    append items { 3; }
        \\    Stdio.println("items: ${items}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("items: list<int>(3)\n", r.stdout);
}

test "compile: enum field in struct to_string" {
    const r = try compileAndCapture(
        \\type Color = enum { Red, Green, Blue };
        \\struct Pixel { color: Color = :Red; x: int = 0; }
        \\module App { fn main(args: list<string>) -> int {
        \\    p: Pixel = Pixel { color: :Green, x: 5 };
        \\    Stdio.println("pixel: ${p}");
        \\    return 0;
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("pixel: Pixel { color: Green, x: 5 }\n", r.stdout);
}
