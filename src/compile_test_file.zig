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

/// Compile, run, capture stdout.
fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_file_cap";
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
// File IO
// ════════════════════════════════════════════════════════════

test "compile: File.open read success" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result { :ok{f} => { Stdio.println("ok"); return 0; } :error{r} => { return 1; } }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

test "compile: File.open read + Stream.read_all" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result {
        \\        :ok{f} => {
        \\            content: string = Stream.read_all(f);
        \\            if String.len(content) > 0 { Stdio.println("has_content"); }
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("has_content\n", r.stdout);
}

test "compile: File.open read + Stream.read_line" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result {
        \\        :ok{f} => {
        \\            line: string = Stream.read_line(f);
        \\            if String.len(line) > 0 { Stdio.println("got_line"); }
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("got_line\n", r.stdout);
}

test "compile: File.open read + Stream.read_bytes" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result {
        \\        :ok{f} => {
        \\            bytes: string = Stream.read_bytes(f, 10);
        \\            if String.len(bytes) > 0 { Stdio.println("got_bytes"); }
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("got_bytes\n", r.stdout);
}

test "compile: File.open write + read back" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    wr: Result<stream> = File.open("/tmp/verve_test_write.txt", "w");
        \\    match wr {
        \\        :ok{f} => {
        \\            Stream.write(f, "hello verve");
        \\            Stream.close(f);
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\    rr: Result<stream> = File.open("/tmp/verve_test_write.txt", "r");
        \\    match rr {
        \\        :ok{f} => {
        \\            content: string = Stream.read_all(f);
        \\            Stdio.println(content);
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello verve\n", r.stdout);
}

test "compile: File.size" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    wr: Result<stream> = File.open("/tmp/verve_test_size.txt", "w");
        \\    match wr {
        \\        :ok{f} => {
        \\            Stream.write(f, "12345");
        \\            File.fsync(f);
        \\            sz: int = File.size(f);
        \\            Stdio.println(sz);
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("5\n", r.stdout);
}

test "compile: File.seek" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    wr: Result<stream> = File.open("/tmp/verve_test_seek.txt", "w");
        \\    match wr {
        \\        :ok{f} => { Stream.write(f, "abcdef"); Stream.close(f); }
        \\        :error{r} => { return 1; }
        \\    }
        \\    rr: Result<stream> = File.open("/tmp/verve_test_seek.txt", "r");
        \\    match rr {
        \\        :ok{f} => {
        \\            File.seek(f, 3);
        \\            rest: string = Stream.read_all(f);
        \\            Stdio.println(rest);
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("def\n", r.stdout);
}

test "compile: File.truncate" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    wr: Result<stream> = File.open("/tmp/verve_test_trunc.txt", "w");
        \\    match wr {
        \\        :ok{f} => {
        \\            Stream.write(f, "abcdef");
        \\            File.truncate(f, 3);
        \\            Stream.close(f);
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\    rr: Result<stream> = File.open("/tmp/verve_test_trunc.txt", "r");
        \\    match rr {
        \\        :ok{f} => {
        \\            content: string = Stream.read_all(f);
        \\            Stdio.println(content);
        \\            Stream.close(f);
        \\            return 0;
        \\        }
        \\        :error{r} => { return 1; }
        \\    }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("abc\n", r.stdout);
}

test "compile: File.open nonexistent returns error" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("/tmp/verve_nonexistent_file_xyz.txt", "r");
        \\    match result { :ok{f} => { return 1; } :error{r} => { Stdio.println("error"); return 0; } }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("error\n", r.stdout);
}

test "compile: existing Result match still works" {
    const r = try compileAndCapture(
        \\process App { receive main(args: list<string>) -> int {
        \\    result: Result<stream> = File.open("examples/math.vv", "r");
        \\    match result { :ok{f} => { Stdio.println("ok"); return 0; } :error{r} => { return 1; } }
        \\} }
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}
