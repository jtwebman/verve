const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower/lower.zig").Lower;
const ZigBackend = @import("zig_backend.zig").ZigBackend;
const testing = std.testing;
const alloc = std.heap.page_allocator;
var temp_counter: std.atomic.Value(u64) = .init(0);

fn getZigPath() []const u8 {
    return std.posix.getenv("VERVE_ZIG") orelse "/home/jt/.local/zig/zig";
}

fn getOptimizeMode() []const u8 {
    return std.posix.getenv("VERVE_OPTIMIZE") orelse "-OReleaseFast";
}

fn uniquePath(prefix: []const u8) ![]const u8 {
    const id = temp_counter.fetchAdd(1, .monotonic);
    return std.fmt.allocPrint(alloc, "/tmp/{s}_{d}_{d}", .{ prefix, std.time.nanoTimestamp(), id });
}

fn compileTestRunnerCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);

    var backend = ZigBackend.init(alloc);
    backend.emitTestRunner(program);
    backend.optimize_mode = getOptimizeMode();

    const path = try uniquePath("verve_ct_runner");
    defer alloc.free(path);
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

test "compile test runner: examples and tests pass with process main present" {
    const r = try compileTestRunnerCapture(
        \\module Math {
        \\    /// @example add(2, 3) == 5
        \\    /// @example add(0, 0) == 0
        \\    fn add(a: int, b: int) -> int {
        \\        return a + b;
        \\    }
        \\
        \\    test "add works" {
        \\        assert add(10, 20) == 30;
        \\    }
        \\}
        \\
        \\process Main {
        \\    receive main() -> int {
        \\        return 0;
        \\    }
        \\}
    );
    defer alloc.free(r.stdout);
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "PASS: @example Math.add #0"));
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "PASS: @example Math.add #1"));
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "PASS: add works"));
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "3 passed, 0 failed"));
}

test "compile test runner: failing assertion exits nonzero" {
    const r = try compileTestRunnerCapture(
        \\module Math {
        \\    test "broken" {
        \\        assert 1 == 2;
        \\    }
        \\}
        \\
        \\process Main {
        \\    receive main() -> int {
        \\        return 0;
        \\    }
        \\}
    );
    defer alloc.free(r.stdout);
    try testing.expectEqual(@as(u8, 1), r.exit);
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "FAIL: broken"));
    try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "0 passed, 1 failed"));
}
