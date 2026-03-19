const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Value = @import("value.zig").Value;

pub const VerifyResult = struct {
    examples_passed: usize,
    examples_failed: usize,
    failures: std.ArrayListUnmanaged(Failure),

    pub const Failure = struct {
        function: []const u8,
        example: []const u8,
        expected: []const u8,
        got: []const u8,
    };
};

pub const Verifier = struct {
    alloc: std.mem.Allocator,
    interp: *Interpreter,

    pub fn init(alloc: std.mem.Allocator, interp: *Interpreter) Verifier {
        return .{
            .alloc = alloc,
            .interp = interp,
        };
    }

    pub fn verify(self: *Verifier, file: ast.File) !VerifyResult {
        var result = VerifyResult{
            .examples_passed = 0,
            .examples_failed = 0,
            .failures = .{},
        };

        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    for (m.functions) |func| {
                        try self.verifyFunction(func, m.name, &result);
                    }
                },
                .process_decl => |p| {
                    for (p.receive_handlers) |handler| {
                        try self.verifyReceiveHandler(handler, p.name, &result);
                    }
                },
                else => {},
            }
        }

        return result;
    }

    fn verifyFunction(self: *Verifier, func: ast.FnDecl, module_name: []const u8, result: *VerifyResult) !void {
        const doc = func.doc_comment orelse return;
        const examples = try self.extractExamples(doc);

        for (examples) |example| {
            try self.runExample(example, module_name, func.name, result);
        }
    }

    fn verifyReceiveHandler(self: *Verifier, handler: ast.ReceiveDecl, proc_name: []const u8, result: *VerifyResult) !void {
        _ = proc_name;
        const doc = handler.doc_comment orelse return;
        _ = try self.extractExamples(doc);
        // TODO: run examples for receive handlers (need to spawn process first)
        _ = result;
    }

    fn extractExamples(self: *Verifier, doc: []const u8) ![]const []const u8 {
        var examples: std.ArrayListUnmanaged([]const u8) = .{};

        var lines = std.mem.splitScalar(u8, doc, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t', '/' });
            if (std.mem.startsWith(u8, trimmed, "@example ")) {
                const example_text = trimmed["@example ".len..];
                try examples.append(self.alloc, std.mem.trim(u8, example_text, &[_]u8{ ' ', '\t' }));
            }
        }

        return try examples.toOwnedSlice(self.alloc);
    }

    fn runExample(self: *Verifier, example: []const u8, module_name: []const u8, fn_name: []const u8, result: *VerifyResult) !void {
        // Parse: "add(2, 3) == 5"
        // Split on " == "
        const eq_pos = std.mem.indexOf(u8, example, " == ") orelse {
            try result.failures.append(self.alloc, .{
                .function = fn_name,
                .example = example,
                .expected = "?",
                .got = "invalid example format — expected 'call(args) == expected'",
            });
            result.examples_failed += 1;
            return;
        };

        const call_text = example[0..eq_pos];
        const expected_text = example[eq_pos + 4 ..];

        // Parse and evaluate the call
        var call_parser = Parser.init(call_text, self.alloc);
        const call_expr = call_parser.parseExpr() catch {
            try result.failures.append(self.alloc, .{
                .function = fn_name,
                .example = example,
                .expected = expected_text,
                .got = "failed to parse call expression",
            });
            result.examples_failed += 1;
            return;
        };

        // Parse the expected value
        var expected_parser = Parser.init(expected_text, self.alloc);
        const expected_expr = expected_parser.parseExpr() catch {
            try result.failures.append(self.alloc, .{
                .function = fn_name,
                .example = example,
                .expected = expected_text,
                .got = "failed to parse expected value",
            });
            result.examples_failed += 1;
            return;
        };

        // Create a scope with module context
        var scope = @import("interpreter.zig").Scope.init(self.alloc);

        // Evaluate expected
        const expected_val = self.interp.evalExpr(expected_expr, &scope) catch {
            result.examples_failed += 1;
            return;
        };

        // Evaluate the call — need to handle both bare calls and module-qualified calls
        // If it's a bare call like "add(2, 3)", qualify it with the module name
        var actual_expr = call_expr;
        if (call_expr == .call and call_expr.call.target.* == .identifier) {
            // Bare call — wrap as Module.function
            const fa_target = try self.alloc.create(ast.Expr);
            fa_target.* = .{ .identifier = module_name };
            const qualified = try self.alloc.create(ast.Expr);
            qualified.* = .{ .field_access = .{ .target = fa_target, .field = call_expr.call.target.identifier } };
            actual_expr = .{ .call = .{ .target = qualified, .args = call_expr.call.args } };
        }

        const actual_val = self.interp.evalExpr(actual_expr, &scope) catch {
            try result.failures.append(self.alloc, .{
                .function = fn_name,
                .example = example,
                .expected = expected_text,
                .got = "runtime error during evaluation",
            });
            result.examples_failed += 1;
            return;
        };

        // Compare
        if (Value.eql(actual_val, expected_val)) {
            result.examples_passed += 1;
        } else {
            var got_buf: [256]u8 = undefined;
            var got_stream = std.io.fixedBufferStream(&got_buf);
            actual_val.format(got_stream.writer()) catch {};
            const got_str = try self.alloc.dupe(u8, got_stream.getWritten());

            try result.failures.append(self.alloc, .{
                .function = fn_name,
                .example = example,
                .expected = expected_text,
                .got = got_str,
            });
            result.examples_failed += 1;
        }
    }
};
