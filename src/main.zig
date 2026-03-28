const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const Loader = @import("loader.zig").Loader;

fn getZigPath(alloc: std.mem.Allocator) []const u8 {
    // VERVE_ZIG env var takes priority, then search PATH for "zig"
    if (std.posix.getenv("VERVE_ZIG")) |p| return p;
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{ "which", "zig" },
    }) catch return "zig";
    const path = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    if (path.len > 0) return path;
    return "zig";
}

fn getTmpPath(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    const tmp_dir = std.posix.getenv("TMPDIR") orelse
        std.posix.getenv("TMP") orelse
        std.posix.getenv("TEMP") orelse "/tmp";
    const pid = std.os.linux.getpid();
    return std.fmt.allocPrint(alloc, "{s}/{s}_{d}", .{ tmp_dir, name, pid }) catch "/tmp/verve_fallback";
}

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
        // Type check
        const Chk = @import("checker.zig").Checker;
        var checker = Chk.init(alloc);
        checker.check(merged) catch {};
        if (checker.hasErrors()) {
            std.debug.print("Type errors in {s}:\n", .{file_path});
            checker.printErrors();
        } else {
            std.debug.print("OK — no errors\n", .{});
        }

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
        // verve run = compile to temp binary + execute (like go run)
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };

        const source = std.fs.cwd().readFileAlloc(alloc, file_path, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error reading {s}: {}\n", .{ file_path, err });
            return;
        };

        var parser = Parser.init(source, alloc);
        const file = parser.parseFile() catch {
            std.debug.print("Parse error in {s}\n", .{file_path});
            return;
        };

        var lower = Lower.init(alloc);
        const program = lower.lowerFile(file) catch |err| {
            std.debug.print("Lowering error: {}\n", .{err});
            return;
        };

        // Validate IR before code generation
        var validator = @import("ir_validate.zig").Validator.init(alloc);
        validator.validate(program);
        if (validator.hasErrors()) {
            std.debug.print("IR validation errors:\n", .{});
            validator.printErrors();
            return;
        }

        const ZigBackend = @import("zig_backend.zig").ZigBackend;
        var backend = ZigBackend.init(alloc);
        backend.emit(program);

        // Build to temp path
        const zig_path = getZigPath(alloc);
        const tmp_path = getTmpPath(alloc, "verve_run");
        backend.build(tmp_path, zig_path) catch |err| {
            std.debug.print("Build error: {}\n", .{err});
            return;
        };

        // Execute the compiled binary
        // Collect remaining args for the program
        var child_args = std.ArrayListUnmanaged([]const u8){};
        try child_args.append(alloc, tmp_path);
        while (args.next()) |arg| {
            try child_args.append(alloc, arg);
        }
        var child = std.process.Child.init(child_args.items, alloc);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        try child.spawn();
        const term = try child.wait();

        // Clean up
        std.fs.cwd().deleteFile(tmp_path) catch {};

        switch (term) {
            .Exited => |code| {
                if (code != 0) std.process.exit(code);
            },
            else => std.process.exit(1),
        }
    } else if (std.mem.eql(u8, command, "test")) {
        // verve test = compile test blocks + run
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };

        const source = std.fs.cwd().readFileAlloc(alloc, file_path, 10 * 1024 * 1024) catch |err| {
            std.debug.print("Error reading {s}: {}\n", .{ file_path, err });
            return;
        };

        var parser = Parser.init(source, alloc);
        const file = parser.parseFile() catch {
            std.debug.print("Parse error in {s}\n", .{file_path});
            return;
        };

        var lower = Lower.init(alloc);
        const program = lower.lowerFile(file) catch |err| {
            std.debug.print("Lowering error: {}\n", .{err});
            return;
        };

        var validator = @import("ir_validate.zig").Validator.init(alloc);
        validator.validate(program);
        if (validator.hasErrors()) {
            std.debug.print("IR validation errors:\n", .{});
            validator.printErrors();
            return;
        }

        if (program.test_names.items.len == 0) {
            std.debug.print("No test blocks found in {s}\n", .{file_path});
            return;
        }

        const ZigBackend = @import("zig_backend.zig").ZigBackend;
        var backend = ZigBackend.init(alloc);
        backend.emitTestRunner(program);

        const zig_path = getZigPath(alloc);
        const tmp_path = getTmpPath(alloc, "verve_test");
        backend.build(tmp_path, zig_path) catch |err| {
            std.debug.print("Build error: {}\n", .{err});
            return;
        };

        // Run the test binary
        var child = std.process.Child.init(&.{tmp_path}, alloc);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        try child.spawn();
        const term = try child.wait();

        std.fs.cwd().deleteFile(tmp_path) catch {};

        switch (term) {
            .Exited => |code| {
                if (code != 0) std.process.exit(code);
            },
            else => std.process.exit(1),
        }
    } else if (std.mem.eql(u8, command, "fmt")) {
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };
        const check_only = blk: {
            if (args.next()) |arg| {
                break :blk std.mem.eql(u8, arg, "--check");
            }
            break :blk false;
        };
        const source = std.fs.cwd().readFileAlloc(alloc, file_path, 1024 * 1024) catch |err| {
            std.debug.print("Error reading {s}: {}\n", .{ file_path, err });
            return;
        };
        var parser = Parser.init(source, alloc);
        const file = parser.parseFile() catch {
            std.debug.print("Parse error in {s}: {s}\n", .{ file_path, parser.formatError() });
            return;
        };

        const Fmt = @import("formatter.zig").Formatter;
        var fmt = Fmt.init(alloc);
        const formatted = fmt.format(file) catch {
            std.debug.print("Format error\n", .{});
            return;
        };

        if (check_only) {
            if (!std.mem.eql(u8, source, formatted)) {
                std.debug.print("FAIL — {s} is not formatted. Run: verve fmt {s}\n", .{ file_path, file_path });
                std.process.exit(1);
            }
            std.debug.print("OK — {s} is formatted\n", .{file_path});
        } else {
            std.fs.cwd().writeFile(.{ .sub_path = file_path, .data = formatted }) catch |err| {
                std.debug.print("Error writing {s}: {}\n", .{ file_path, err });
                return;
            };
            std.debug.print("Formatted {s}\n", .{file_path});
        }
    } else if (std.mem.eql(u8, command, "build")) {
        const file_path = args.next() orelse {
            std.debug.print("Error: no file specified\n", .{});
            return;
        };
        var loader = Loader.init(alloc);
        const merged = loader.loadFile(file_path) catch |err| {
            switch (err) {
                error.FileNotFound => std.debug.print("Error: file not found: {s}\n", .{file_path}),
                error.ParseFailed => std.debug.print("Parse error in {s}\n", .{file_path}),
                else => std.debug.print("Error: {}\n", .{err}),
            }
            return;
        };

        // Lower AST to IR
        const Lwr = @import("lower.zig").Lower;
        var lower = Lwr.init(alloc);
        const program = lower.lowerFile(merged) catch |err| {
            std.debug.print("Lowering error: {}\n", .{err});
            return;
        };

        // Validate IR
        var validator = @import("ir_validate.zig").Validator.init(alloc);
        validator.validate(program);
        if (validator.hasErrors()) {
            std.debug.print("IR validation errors:\n", .{});
            validator.printErrors();
            return;
        }

        // Compile IR via Zig backend
        const ZigBackend = @import("zig_backend.zig").ZigBackend;
        var backend = ZigBackend.init(alloc);
        backend.emit(program);

        // Determine output path
        const out_path = if (std.mem.endsWith(u8, file_path, ".vv"))
            std.fmt.allocPrint(alloc, "{s}", .{file_path[0 .. file_path.len - 3]}) catch "a.out"
        else
            std.fmt.allocPrint(alloc, "{s}.out", .{file_path}) catch "a.out";

        const zig_path = getZigPath(alloc);
        backend.build(out_path, zig_path) catch |err| {
            std.debug.print("Build error: {}\n", .{err});
            return;
        };

        std.debug.print("Built {s}\n", .{out_path});
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\verve - AI-first programming language
        \\
        \\Usage:
        \\  verve build <file.vv>   Compile to native binary
        \\  verve run <file.vv>     Compile and run (like go run)
        \\  verve check <file.vv>   Type check
        \\  verve test <file.vv>    Run @example and @property tests
        \\  verve fmt <file.vv>     Format in place
        \\
    , .{});
}
