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
    const path = "/tmp/verve_ct_json";
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
    const path = "/tmp/verve_ct_json_cap";
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

// ── Env tests ──────────────────────────────────────

test "compile: env get existing var" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        home: string = Env.get("HOME");
        \\        if String.len(home) > 0 {
        \\            Stdio.println("has home");
        \\        } else {
        \\            Stdio.println("no home");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("has home\n", r.stdout);
}

test "compile: env get nonexistent var" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        val: string = Env.get("VERVE_DEFINITELY_NOT_SET_XYZ");
        \\        if String.len(val) == 0 {
        \\            Stdio.println("empty");
        \\        } else {
        \\            Stdio.println("unexpected");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("empty\n", r.stdout);
}

// ── JSON tests ─────────────────────────────────────

test "compile: json get_string from object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"verve\", \"version\": 1}";
        \\        name: string = Json.get_string(data, "name");
        \\        Stdio.println(name);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("verve\n", r.stdout);
}

test "compile: json get_int from object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"count\": 42, \"name\": \"test\"}";
        \\        count: int = Json.get_int(data, "count");
        \\        Stdio.println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: json get_bool from object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"active\": true, \"deleted\": false}";
        \\        if Json.get_bool(data, "active") {
        \\            Stdio.println("active");
        \\        } else {
        \\            Stdio.println("not active");
        \\        }
        \\        if Json.get_bool(data, "deleted") {
        \\            Stdio.println("deleted");
        \\        } else {
        \\            Stdio.println("not deleted");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("active\nnot deleted\n", r.stdout);
}

test "compile: json nested object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"user\": {\"name\": \"alice\", \"age\": 30}}";
        \\        user: string = Json.get_object(data, "user");
        \\        name: string = Json.get_string(user, "name");
        \\        age: int = Json.get_int(user, "age");
        \\        Stdio.println(name);
        \\        Stdio.println(age);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("alice\n30\n", r.stdout);
}

test "compile: json missing key returns zero" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"test\"}";
        \\        missing: int = Json.get_int(data, "nope");
        \\        Stdio.println(missing);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: json multiple fields" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"a\": 1, \"b\": 2, \"c\": 3, \"d\": 4}";
        \\        Stdio.println(Json.get_int(data, "a"));
        \\        Stdio.println(Json.get_int(data, "b"));
        \\        Stdio.println(Json.get_int(data, "c"));
        \\        Stdio.println(Json.get_int(data, "d"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1\n2\n3\n4\n", r.stdout);
}

test "compile: json negative number" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"temp\": -5}";
        \\        Stdio.println(Json.get_int(data, "temp"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("-5\n", r.stdout);
}

test "compile: json string with spaces and special chars" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"msg\": \"hello world!\"}";
        \\        msg: string = Json.get_string(data, "msg");
        \\        Stdio.println(msg);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello world!\n", r.stdout);
}

test "compile: json deeply nested" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"a\": {\"b\": {\"c\": 99}}}";
        \\        a: string = Json.get_object(data, "a");
        \\        b: string = Json.get_object(a, "b");
        \\        c: int = Json.get_int(b, "c");
        \\        Stdio.println(c);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("99\n", r.stdout);
}

test "compile: json to_int and to_bool leaf extraction" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        Stdio.println(Json.to_int("42"));
        \\        Stdio.println(Json.to_int("-7"));
        \\        Stdio.println(Json.to_bool("true"));
        \\        Stdio.println(Json.to_bool("false"));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n-7\n1\n0\n", r.stdout);
}

test "compile: json typed parse struct" {
    const r = try compileAndCapture(
        \\struct User {
        \\    name: string = "";
        \\    age: int = 0;
        \\    active: bool = false;
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"name\": \"alice\", \"age\": 30, \"active\": true}";
        \\        match Json.parse(data, User) {
        \\            :ok{user} => {
        \\                Stdio.println(user.name);
        \\                Stdio.println(user.age);
        \\                if user.active {
        \\                    Stdio.println("active");
        \\                } else {
        \\                    Stdio.println("not active");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("alice\n30\nactive\n", r.stdout);
}

test "compile: json typed parse missing fields use zero defaults" {
    const r = try compileAndCapture(
        \\struct Config {
        \\    host: string = "";
        \\    port: int = 0;
        \\    debug: bool = false;
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"port\": 3000}";
        \\        match Json.parse(data, Config) {
        \\            :ok{cfg} => {
        \\                Stdio.println(cfg.port);
        \\                if cfg.debug {
        \\                    Stdio.println("debug on");
        \\                } else {
        \\                    Stdio.println("debug off");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3000\ndebug off\n", r.stdout);
}

test "compile: json typed parse extra fields ignored" {
    const r = try compileAndCapture(
        \\struct Item {
        \\    id: int = 0;
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"id\": 42, \"name\": \"widget\", \"price\": 9.99}";
        \\        match Json.parse(data, Item) {
        \\            :ok{item} => Stdio.println(item.id);
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("42\n", r.stdout);
}

test "compile: json typed parse invalid json returns error" {
    const r = try compileAndCapture(
        \\struct Thing {
        \\    x: int = 0;
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "not json at all";
        \\        match Json.parse(data, Thing) {
        \\            :ok{t} => Stdio.println("unexpected success");
        \\            :error{e} => Stdio.println("correctly failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("correctly failed\n", r.stdout);
}

test "compile: json typed parse with http request body" {
    const r = try compileAndCapture(
        \\struct CreateUser {
        \\    name: string = "";
        \\    email: string = "";
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        http_data: string = "POST /users HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\": \"bob\", \"email\": \"bob@test.com\"}";
        \\        req: int = Http.parse_request(http_data);
        \\        body: string = Http.req_body(req);
        \\        match Json.parse(body, CreateUser) {
        \\            :ok{user} => {
        \\                Stdio.println(user.name);
        \\                Stdio.println(user.email);
        \\            }
        \\            :error{e} => Stdio.println("parse failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("bob\nbob@test.com\n", r.stdout);
}

test "compile: json build simple object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "name", "verve");
        \\        Json.build_add_int(b, "version", 1);
        \\        result: string = Json.build_end(b);
        \\        Stdio.println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"name\":\"verve\",\"version\":1}\n", r.stdout);
}

test "compile: json build with bool" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_bool(b, "yes", true);
        \\        Json.build_add_bool(b, "no", false);
        \\        result: string = Json.build_end(b);
        \\        Stdio.println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"yes\":true,\"no\":false}\n", r.stdout);
}

test "compile: json build empty object" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        result: string = Json.build_end(b);
        \\        Stdio.println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{}\n", r.stdout);
}

test "compile: json build then parse roundtrip" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello");
        \\        Json.build_add_int(b, "num", 42);
        \\        json: string = Json.build_end(b);
        \\        msg: string = Json.get_string(json, "msg");
        \\        num: int = Json.get_int(json, "num");
        \\        Stdio.println(msg);
        \\        Stdio.println(num);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello\n42\n", r.stdout);
}

test "compile: json build with special chars in string" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello world!");
        \\        result: string = Json.build_end(b);
        \\        Stdio.println(result);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"msg\":\"hello world!\"}\n", r.stdout);
}

test "compile: json array length" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"items\": [1, 2, 3, 4, 5]}";
        \\        count: int = Json.get_array_len(data, "items");
        \\        Stdio.println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n", r.stdout);
}

test "compile: json empty array length" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "{\"items\": []}";
        \\        count: int = Json.get_array_len(data, "items");
        \\        Stdio.println(count);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}
