const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Loader = @import("loader.zig").Loader;
const Value = @import("value.zig").Value;

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.skip(); // skip program name

    const command = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, command, "check")) {
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };
        var loader = Loader.init(alloc);
        const merged = loader.loadFile(file_path) catch |err| {
            switch (err) {
                error.FileNotFound => std.debug.print("Error: file not found: {s}\n", .{file_path}),
                error.ParseFailed => std.debug.print("Parse error in {s}\n", .{file_path}),
                error.CircularImport => std.debug.print("Error: circular import detected\n", .{}),
                else => std.debug.print("Error: {}\n", .{err}),
            }
            return;
        };
        std.debug.print("Loaded {d} declarations from {s}\n", .{ merged.decls.len, file_path });
        for (merged.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    const exp = if (m.exported) " (exported)" else "";
                    std.debug.print("  module {s}{s} ({d} functions)\n", .{ m.name, exp, m.functions.len });
                },
                .process_decl => |p| {
                    const exp = if (p.exported) " (exported)" else "";
                    std.debug.print("  process {s}{s} ({d} handlers)\n", .{ p.name, exp, p.receive_handlers.len });
                },
                .struct_decl => |s| {
                    const exp = if (s.exported) " (exported)" else "";
                    std.debug.print("  struct {s}{s} ({d} fields)\n", .{ s.name, exp, s.fields.len });
                },
                .type_decl => |t| {
                    const exp = if (t.exported) " (exported)" else "";
                    std.debug.print("  type {s}{s}\n", .{ t.name, exp });
                },
            }
        }
    } else if (std.mem.eql(u8, command, "run")) {
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };

        var loader = Loader.init(alloc);
        const merged = loader.loadFile(file_path) catch |err| {
            switch (err) {
                error.FileNotFound => std.debug.print("Error: file not found: {s}\n", .{file_path}),
                error.ParseFailed => std.debug.print("Parse error in {s}\n", .{file_path}),
                error.CircularImport => std.debug.print("Error: circular import detected\n", .{}),
                else => std.debug.print("Error: {}\n", .{err}),
            }
            return;
        };

        var interp = Interpreter.init(alloc);
        interp.load(merged) catch |err| {
            std.debug.print("Load error: {}\n", .{err});
            return;
        };

        const entry = interp.findMain() orelse {
            std.debug.print("Error: no entry point found. Add fn main(args: list<string>) -> int to a process or module.\n", .{});
            return;
        };

        const result = blk: {
            if (entry.is_process) {
                break :blk interp.runProcessMain(entry.module, &.{}) catch |err| {
                    std.debug.print("Runtime error: {}\n", .{err});
                    return;
                };
            } else {
                break :blk interp.callFunction(entry.module, entry.name, &.{}) catch |err| {
                    std.debug.print("Runtime error: {}\n", .{err});
                    return;
                };
            }
        };

        switch (result) {
            .int => |code| {
                if (code != 0) {
                    std.process.exit(@intCast(@as(u64, @bitCast(code))));
                }
            },
            .void => {},
            else => {},
        }
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\verve - AI-first programming language
        \\
        \\Usage:
        \\  verve run <file.vv>     Run a Verve program
        \\  verve check <file.vv>   Check a Verve program
        \\
    , .{});
}
