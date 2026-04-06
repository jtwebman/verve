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
    child.cwd = "/home/jt/projects/verve";
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.BuildFailed,
        else => return error.BuildFailed,
    }
    return bin_path;
}

fn runCli(alloc: std.mem.Allocator, bin_path: []const u8, args: []const []const u8) !struct { exit: u8, stdout: []const u8, stderr: []const u8 } {
    const argv = try alloc.alloc([]const u8, args.len + 1);
    defer alloc.free(argv);
    argv[0] = bin_path;
    for (args, 0..) |arg, i| argv[i + 1] = arg;

    var child = std.process.Child.init(argv, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = "/home/jt/projects/verve";
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

    const invalid = try runCli(alloc, bin_path, &.{ "check", invalid_path });
    defer alloc.free(invalid.stdout);
    defer alloc.free(invalid.stderr);
    try testing.expectEqual(@as(u8, 1), invalid.exit);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.containsAtLeast(u8, invalid.stderr, 1, "Type errors in"));

    const invalid_json = try runCli(alloc, bin_path, &.{ "check", "--json", invalid_path });
    defer alloc.free(invalid_json.stdout);
    defer alloc.free(invalid_json.stderr);
    try testing.expectEqual(@as(u8, 1), invalid_json.exit);
    try testing.expectEqualStrings("", invalid_json.stdout);
    try testing.expect(std.mem.startsWith(u8, invalid_json.stderr, "["));
    try testing.expect(std.mem.endsWith(u8, invalid_json.stderr, "]\n") or std.mem.endsWith(u8, invalid_json.stderr, "]"));
    try testing.expect(!std.mem.containsAtLeast(u8, invalid_json.stderr, 1, "Type errors in"));

    const valid_json = try runCli(alloc, bin_path, &.{ "check", "--json", valid_path });
    defer alloc.free(valid_json.stdout);
    defer alloc.free(valid_json.stderr);
    try testing.expectEqual(@as(u8, 0), valid_json.exit);
    try testing.expectEqualStrings("", valid_json.stdout);
    try testing.expectEqualStrings("[]\n", valid_json.stderr);

    const invalid_json_post = try runCli(alloc, bin_path, &.{ "check", invalid_path, "--json" });
    defer alloc.free(invalid_json_post.stdout);
    defer alloc.free(invalid_json_post.stderr);
    try testing.expectEqual(@as(u8, 1), invalid_json_post.exit);
    try testing.expectEqualStrings("", invalid_json_post.stdout);
    try testing.expect(std.mem.startsWith(u8, invalid_json_post.stderr, "["));
    try testing.expect(!std.mem.containsAtLeast(u8, invalid_json_post.stderr, 1, "Type errors in"));
}
