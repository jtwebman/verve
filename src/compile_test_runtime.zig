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

fn compileAndCaptureIO(source: []const u8) !struct { exit: u8, stdout: []const u8, stderr: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_runtime";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};

    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    const stdout_n = try child.stdout.?.readAll(&stdout_buf);
    const stderr_n = try child.stderr.?.readAll(&stderr_buf);
    const term = try child.wait();

    return .{
        .exit = switch (term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = try alloc.dupe(u8, stdout_buf[0..stdout_n]),
        .stderr = try alloc.dupe(u8, stderr_buf[0..stderr_n]),
    };
}

test "compile: list<int> overflow fails fast" {
    const r = try compileAndCaptureIO(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        xs: list<int> = list();
        \\        i: int = 0;
        \\        while i < 257 {
        \\            append xs { i; }
        \\            i = i + 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), r.exit);
    try testing.expectEqualStrings("", r.stdout);
    try testing.expect(std.mem.indexOf(u8, r.stderr, "Verve runtime error: list capacity exceeded") != null);
}

test "compile: list<string> overflow fails fast" {
    const r = try compileAndCaptureIO(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        xs: list<string> = list();
        \\        i: int = 0;
        \\        while i < 257 {
        \\            append xs { "x"; }
        \\            i = i + 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), r.exit);
    try testing.expectEqualStrings("", r.stdout);
    try testing.expect(std.mem.indexOf(u8, r.stderr, "Verve runtime error: list capacity exceeded") != null);
}

test "compile: stack push overflow fails fast" {
    const r = try compileAndCaptureIO(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        xs: stack<int> = stack();
        \\        i: int = 0;
        \\        while i < 257 {
        \\            Stack.push(xs, i);
        \\            i = i + 1;
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 1), r.exit);
    try testing.expectEqualStrings("", r.stdout);
    try testing.expect(std.mem.indexOf(u8, r.stderr, "Verve runtime error: list capacity exceeded") != null);
}
