const std = @import("std");
const ast = @import("ast.zig");
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

fn readSource(path: []const u8) ![]const u8 {
    return std.fs.cwd().readFileAlloc(alloc, path, 1024 * 1024);
}

fn hasProcessMain(file: ast.File) bool {
    for (file.decls) |decl| {
        switch (decl) {
            .process_decl => |p| {
                for (p.receive_handlers) |handler| {
                    if (std.mem.eql(u8, handler.name, "main")) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

fn compileExample(path: []const u8) !void {
    const source = try readSource(path);
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    if (!hasProcessMain(file)) return error.NoProcessMainEntryPoint;

    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();

    const stem = std.fs.path.stem(path);
    const out_path = try std.fmt.allocPrint(alloc, "/tmp/verve_test_example_{s}", .{stem});
    defer std.fs.cwd().deleteFile(out_path) catch {};

    try backend.build(out_path, getZigPath());
}

test "smoke examples: hello and parser compile" {
    const buildable = [_][]const u8{
        "examples/hello.vv",
        "examples/parser.vv",
    };

    for (buildable) |path| {
        compileExample(path) catch |err| {
            std.debug.print("failed smoke example build: {s}: {s}\n", .{ path, @errorName(err) });
            return err;
        };
    }
}

test "smoke examples: math stays library-only" {
    try testing.expectError(error.NoProcessMainEntryPoint, compileExample("examples/math.vv"));
}
