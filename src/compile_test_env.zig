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

/// Compile Verve source to native binary, run it, return exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_env";
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
    const path = "/tmp/verve_ct_env_cap";
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
// ════════════════════════════════════════════════════════════
// Process.env_* — typed env var access
// ════════════════════════════════════════════════════════════

const env_int_source =
    \\process App {
    \\    receive main(args: list<string>) -> int {
    \\        port: int = Process.env_int("VERVE_TEST_PORT", 8080);
    \\        Stdio.println(port);
    \\        return 0;
    \\    }
    \\}
;

const env_bool_source =
    \\process App {
    \\    receive main(args: list<string>) -> int {
    \\        debug: bool = Process.env_bool("VERVE_TEST_DEBUG", false);
    \\        Stdio.println(debug);
    \\        return 0;
    \\    }
    \\}
;

const env_float_source =
    \\process App {
    \\    receive main(args: list<string>) -> int {
    \\        rate: float = Process.env_float("VERVE_TEST_RATE", 1.5);
    \\        Stdio.println(rate);
    \\        return 0;
    \\    }
    \\}
;

/// Compile, run with custom env vars, capture stdout. Env vars override the inherited env.
fn compileAndCaptureEnv(source: []const u8, env_pairs: []const [2][]const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    // Use unique path based on source hash to avoid parallel test collisions
    var hash_buf: [16]u8 = undefined;
    const hash = std.hash.CityHash64.hash(source);
    const hash_str = std.fmt.bufPrint(&hash_buf, "{x}", .{hash}) catch "0";
    const path = std.fmt.allocPrint(alloc, "/tmp/verve_ct_env_cap_{s}", .{hash_str}) catch "/tmp/verve_ct_env_cap";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    // Build env map from inherited env + overrides
    var env = std.process.EnvMap.init(alloc);
    // Inherit current env
    const inherited = std.process.getEnvMap(alloc) catch return .{ .exit = 255, .stdout = "" };
    var it = inherited.iterator();
    while (it.next()) |entry| {
        env.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
    }
    // Apply overrides (empty value = remove)
    for (env_pairs) |pair| {
        if (pair[1].len == 0) {
            env.remove(pair[0]);
        } else {
            env.put(pair[0], pair[1]) catch {};
        }
    }
    child.env_map = &env;
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

/// Compile, run with custom env vars, return exit code only.
fn compileAndRunEnv(source: []const u8, env_pairs: []const [2][]const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    var hash_buf: [16]u8 = undefined;
    const hash = std.hash.CityHash64.hash(source);
    const hash_str = std.fmt.bufPrint(&hash_buf, "{x}", .{hash}) catch "0";
    const path = std.fmt.allocPrint(alloc, "/tmp/verve_ct_env_run_{s}", .{hash_str}) catch "/tmp/verve_ct_env_run";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    var env = std.process.EnvMap.init(alloc);
    const inherited = std.process.getEnvMap(alloc) catch return 255;
    var it = inherited.iterator();
    while (it.next()) |entry| {
        env.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
    }
    for (env_pairs) |pair| {
        if (pair[1].len == 0) {
            env.remove(pair[0]);
        } else {
            env.put(pair[0], pair[1]) catch {};
        }
    }
    child.env_map = &env;
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

// ── env_int ─────────────────────────────────────────

test "compile: Process.env_int with default" {
    const r = try compileAndCaptureEnv(env_int_source, &.{.{ "VERVE_TEST_PORT", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("8080\n", r.stdout);
}

test "compile: Process.env_int from env var" {
    const r = try compileAndCaptureEnv(env_int_source, &.{.{ "VERVE_TEST_PORT", "9090" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("9090\n", r.stdout);
}

test "compile: Process.env_int negative" {
    const r = try compileAndCaptureEnv(env_int_source, &.{.{ "VERVE_TEST_PORT", "-42" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("-42\n", r.stdout);
}

test "compile: Process.env_int invalid crashes" {
    const r = try compileAndRunEnv(env_int_source, &.{.{ "VERVE_TEST_PORT", "abc" }});
    try testing.expectEqual(@as(u8, 1), r);
}

test "compile: Process.env_int empty falls back to default" {
    const r = try compileAndCaptureEnv(env_int_source, &.{.{ "VERVE_TEST_PORT", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("8080\n", r.stdout);
}

// ── env_string ──────────────────────────────────────

test "compile: Process.env_string with default" {
    const r = try compileAndCaptureEnv(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        host: string = Process.env_string("VERVE_TEST_HOST", "localhost");
        \\        Stdio.println(host);
        \\        return 0;
        \\    }
        \\}
    , &.{.{ "VERVE_TEST_HOST", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("localhost\n", r.stdout);
}

test "compile: Process.env_string from env var" {
    const r = try compileAndCaptureEnv(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        host: string = Process.env_string("VERVE_TEST_HOST", "localhost");
        \\        Stdio.println(host);
        \\        return 0;
        \\    }
        \\}
    , &.{.{ "VERVE_TEST_HOST", "example.com" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("example.com\n", r.stdout);
}

const env_required_source =
    \\process App {
    \\    receive main(args: list<string>) -> int {
    \\        db: string = Process.env_string("VERVE_TEST_DB");
    \\        Stdio.println(db);
    \\        return 0;
    \\    }
    \\}
;

test "compile: Process.env_string required missing crashes" {
    const r = try compileAndRunEnv(env_required_source, &.{.{ "VERVE_TEST_DB", "" }});
    try testing.expectEqual(@as(u8, 1), r);
}

test "compile: Process.env_string required set works" {
    const r = try compileAndCaptureEnv(env_required_source, &.{.{ "VERVE_TEST_DB", "postgres://localhost" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("postgres://localhost\n", r.stdout);
}

// ── env_bool ────────────────────────────────────────

test "compile: Process.env_bool default false" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("false\n", r.stdout);
}

test "compile: Process.env_bool true from env" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "true" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("true\n", r.stdout);
}

test "compile: Process.env_bool TRUE case insensitive" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "TRUE" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("true\n", r.stdout);
}

test "compile: Process.env_bool 1 is true" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "1" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("true\n", r.stdout);
}

test "compile: Process.env_bool t is true" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "t" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("true\n", r.stdout);
}

test "compile: Process.env_bool false from env" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "false" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("false\n", r.stdout);
}

test "compile: Process.env_bool 0 is false" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "0" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("false\n", r.stdout);
}

test "compile: Process.env_bool f is false" {
    const r = try compileAndCaptureEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "f" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("false\n", r.stdout);
}

test "compile: Process.env_bool invalid crashes" {
    const r = try compileAndRunEnv(env_bool_source, &.{.{ "VERVE_TEST_DEBUG", "yes" }});
    try testing.expectEqual(@as(u8, 1), r);
}

test "compile: Process.env_bool default true" {
    const r = try compileAndCaptureEnv(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        verbose: bool = Process.env_bool("VERVE_TEST_VERBOSE", true);
        \\        Stdio.println(verbose);
        \\        return 0;
        \\    }
        \\}
    , &.{.{ "VERVE_TEST_VERBOSE", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("true\n", r.stdout);
}

// ── env_float ───────────────────────────────────────

test "compile: Process.env_float with default" {
    const r = try compileAndCaptureEnv(env_float_source, &.{.{ "VERVE_TEST_RATE", "" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("1.5\n", r.stdout);
}

test "compile: Process.env_float from env" {
    const r = try compileAndCaptureEnv(env_float_source, &.{.{ "VERVE_TEST_RATE", "3.14" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3.14\n", r.stdout);
}

test "compile: Process.env_float negative" {
    const r = try compileAndCaptureEnv(env_float_source, &.{.{ "VERVE_TEST_RATE", "-2.5" }});
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("-2.5\n", r.stdout);
}

test "compile: Process.env_float invalid crashes" {
    const r = try compileAndRunEnv(env_float_source, &.{.{ "VERVE_TEST_RATE", "abc" }});
    try testing.expectEqual(@as(u8, 1), r);
}

// ── batch validation ────────────────────────────────

test "compile: Process.env batch validation reports all errors" {
    const r = try compileAndRunEnv(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        port: int = Process.env_int("VERVE_TEST_PORT", 8080);
        \\        db: string = Process.env_string("VERVE_TEST_DB");
        \\        debug: bool = Process.env_bool("VERVE_TEST_DEBUG", false);
        \\        return 0;
        \\    }
        \\}
    , &.{ .{ "VERVE_TEST_PORT", "abc" }, .{ "VERVE_TEST_DB", "" }, .{ "VERVE_TEST_DEBUG", "maybe" } });
    try testing.expectEqual(@as(u8, 1), r);
}

// ── struct config pattern ───────────────────────────

test "compile: Process.env with struct pattern" {
    const r = try compileAndCaptureEnv(
        \\struct AppConfig {
        \\    port: int = 0;
        \\    host: string = "";
        \\    debug: bool = false;
        \\}
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        config: AppConfig = AppConfig {
        \\            port: Process.env_int("VERVE_TEST_PORT", 8080),
        \\            host: Process.env_string("VERVE_TEST_HOST", "localhost"),
        \\            debug: Process.env_bool("VERVE_TEST_DEBUG", false),
        \\        };
        \\        Stdio.println(config.port);
        \\        Stdio.println(config.host);
        \\        Stdio.println(config.debug);
        \\        return 0;
        \\    }
        \\}
    , &.{ .{ "VERVE_TEST_PORT", "3000" }, .{ "VERVE_TEST_HOST", "api.example.com" }, .{ "VERVE_TEST_DEBUG", "True" } });
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("3000\napi.example.com\ntrue\n", r.stdout);
}
