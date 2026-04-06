const std = @import("std");
const testing = std.testing;

fn getZigPath() []const u8 {
    return std.posix.getenv("VERVE_ZIG") orelse "/home/jt/.local/zig/zig";
}

fn buildCliBinary(alloc: std.mem.Allocator) ![]const u8 {
    const bin_path = "/tmp/verve_cli_test_bin";
    var child = std.process.Child.init(&.{
        getZigPath(),
        "build-exe",
        "src/main.zig",
        "-OReleaseFast",
        "-femit-bin=/tmp/verve_cli_test_bin",
    }, alloc);
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.BuildFailed,
        else => return error.BuildFailed,
    }
    return bin_path;
}

fn runCli(alloc: std.mem.Allocator, cwd_path: []const u8, bin_path: []const u8, args: []const []const u8) !struct { exit: u8, stdout: []const u8, stderr: []const u8 } {
    const argv = try alloc.alloc([]const u8, args.len + 1);
    defer alloc.free(argv);
    argv[0] = bin_path;
    for (args, 0..) |arg, i| argv[i + 1] = arg;

    var child = std.process.Child.init(argv, alloc);
    child.cwd = cwd_path;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    const stdout_bytes = try child.stdout.?.readToEndAlloc(alloc, 64 * 1024);
    const stderr_bytes = try child.stderr.?.readToEndAlloc(alloc, 64 * 1024);
    const term = try child.wait();
    return .{
        .exit = switch (term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = stdout_bytes,
        .stderr = stderr_bytes,
    };
}

test "cli: check exit codes and json behavior" {
    const alloc = testing.allocator;
    const repo_root = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(repo_root);
    const bin_path = try buildCliBinary(alloc);
    defer std.fs.cwd().deleteFile(bin_path) catch {};

    const invalid_path = "/tmp/verve_cli_invalid.vv";
    const valid_path = "/tmp/verve_cli_valid.vv";
    defer std.fs.cwd().deleteFile(invalid_path) catch {};
    defer std.fs.cwd().deleteFile(valid_path) catch {};

    try std.fs.cwd().writeFile(.{
        .sub_path = invalid_path,
        .data =
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        x: string = 1;
        \\        return 0;
        \\    }
        \\}
        ,
    });

    try std.fs.cwd().writeFile(.{
        .sub_path = valid_path,
        .data =
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        return 0;
        \\    }
        \\}
        ,
    });

    const invalid = try runCli(alloc, repo_root, bin_path, &.{ "check", invalid_path });
    defer alloc.free(invalid.stdout);
    defer alloc.free(invalid.stderr);
    try testing.expectEqual(@as(u8, 1), invalid.exit);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.containsAtLeast(u8, invalid.stderr, 1, "Type errors in"));

    const invalid_json = try runCli(alloc, repo_root, bin_path, &.{ "check", "--json", invalid_path });
    defer alloc.free(invalid_json.stdout);
    defer alloc.free(invalid_json.stderr);
    try testing.expectEqual(@as(u8, 1), invalid_json.exit);
    try testing.expectEqualStrings("", invalid_json.stdout);
    try testing.expect(std.mem.startsWith(u8, invalid_json.stderr, "["));
    try testing.expect(std.mem.endsWith(u8, invalid_json.stderr, "]\n") or std.mem.endsWith(u8, invalid_json.stderr, "]"));
    try testing.expect(!std.mem.containsAtLeast(u8, invalid_json.stderr, 1, "Type errors in"));

    const valid_json = try runCli(alloc, repo_root, bin_path, &.{ "check", "--json", valid_path });
    defer alloc.free(valid_json.stdout);
    defer alloc.free(valid_json.stderr);
    try testing.expectEqual(@as(u8, 0), valid_json.exit);
    try testing.expectEqualStrings("", valid_json.stdout);
    try testing.expectEqualStrings("[]\n", valid_json.stderr);

    const invalid_json_post = try runCli(alloc, repo_root, bin_path, &.{ "check", invalid_path, "--json" });
    defer alloc.free(invalid_json_post.stdout);
    defer alloc.free(invalid_json_post.stderr);
    try testing.expectEqual(@as(u8, 1), invalid_json_post.exit);
    try testing.expectEqualStrings("", invalid_json_post.stdout);
    try testing.expect(std.mem.startsWith(u8, invalid_json_post.stderr, "["));
    try testing.expect(!std.mem.containsAtLeast(u8, invalid_json_post.stderr, 1, "Type errors in"));
}

test "cli: fmt supports --check before and after file" {
    const alloc = testing.allocator;
    const repo_root = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(repo_root);
    const bin_path = try buildCliBinary(alloc);
    defer std.fs.cwd().deleteFile(bin_path) catch {};

    const fmt_path = "/tmp/verve_cli_fmt.vv";
    defer std.fs.cwd().deleteFile(fmt_path) catch {};

    try std.fs.cwd().writeFile(.{
        .sub_path = fmt_path,
        .data =
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        return 0;
        \\    }
        \\}
        ,
    });

    const fmt_run = try runCli(alloc, repo_root, bin_path, &.{ "fmt", fmt_path });
    defer alloc.free(fmt_run.stdout);
    defer alloc.free(fmt_run.stderr);
    try testing.expectEqual(@as(u8, 0), fmt_run.exit);

    const fmt_check_after = try runCli(alloc, repo_root, bin_path, &.{ "fmt", fmt_path, "--check" });
    defer alloc.free(fmt_check_after.stdout);
    defer alloc.free(fmt_check_after.stderr);
    try testing.expectEqual(@as(u8, 0), fmt_check_after.exit);

    const fmt_check_before = try runCli(alloc, repo_root, bin_path, &.{ "fmt", "--check", fmt_path });
    defer alloc.free(fmt_check_before.stdout);
    defer alloc.free(fmt_check_before.stderr);
    try testing.expectEqual(@as(u8, 0), fmt_check_before.exit);
}

test "cli: test command succeeds on test file and fails on file with no tests" {
    const alloc = testing.allocator;
    const repo_root = try std.fs.cwd().realpathAlloc(alloc, ".");
    defer alloc.free(repo_root);
    const bin_path = try buildCliBinary(alloc);
    defer std.fs.cwd().deleteFile(bin_path) catch {};

    const ok = try runCli(alloc, repo_root, bin_path, &.{ "test", "examples/tested.vv" });
    defer alloc.free(ok.stdout);
    defer alloc.free(ok.stderr);
    try testing.expectEqual(@as(u8, 0), ok.exit);
    try testing.expect(std.mem.containsAtLeast(u8, ok.stdout, 1, "12 passed, 0 failed"));

    const no_tests = try runCli(alloc, repo_root, bin_path, &.{ "test", "examples/math.vv" });
    defer alloc.free(no_tests.stdout);
    defer alloc.free(no_tests.stderr);
    try testing.expectEqual(@as(u8, 1), no_tests.exit);
    try testing.expectEqualStrings("", no_tests.stdout);
    try testing.expect(std.mem.containsAtLeast(u8, no_tests.stderr, 1, "No test blocks found"));
}
