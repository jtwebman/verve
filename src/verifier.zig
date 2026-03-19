const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const Interpreter = @import("interpreter.zig").Interpreter;
const Value = @import("value.zig").Value;

pub const FUZZ_ITERATIONS: usize = 100;

pub const VerifyResult = struct {
    examples_passed: usize,
    examples_failed: usize,
    properties_passed: usize,
    properties_failed: usize,
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
            .properties_passed = 0,
            .properties_failed = 0,
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

        // Run @example tests
        const examples = try self.extractExamples(doc);
        for (examples) |example| {
            try self.runExample(example, module_name, func.name, result);
        }

        // Run @property fuzz tests
        const properties = try self.extractProperties(doc);
        for (properties) |prop| {
            try self.runProperty(prop, func, module_name, result);
        }
    }

    fn verifyReceiveHandler(self: *Verifier, handler: ast.ReceiveDecl, proc_name: []const u8, result: *VerifyResult) !void {
        _ = proc_name;
        const doc = handler.doc_comment orelse return;
        _ = try self.extractExamples(doc);
        // TODO: run examples for receive handlers (need to spawn process first)
        _ = result;
    }

    fn extractProperties(self: *Verifier, doc: []const u8) ![]const []const u8 {
        var props: std.ArrayListUnmanaged([]const u8) = .{};
        var lines = std.mem.splitScalar(u8, doc, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t', '/' });
            if (std.mem.startsWith(u8, trimmed, "@property ")) {
                const prop_text = trimmed["@property ".len..];
                try props.append(self.alloc, std.mem.trim(u8, prop_text, &[_]u8{ ' ', '\t' }));
            }
        }
        return try props.toOwnedSlice(self.alloc);
    }

    fn runProperty(self: *Verifier, prop: []const u8, func: ast.FnDecl, module_name: []const u8, result: *VerifyResult) !void {
        // Parse: "fn(a, b) { add(a, b) == add(b, a) }"
        // Extract param names between ( and )
        const paren_start = std.mem.indexOf(u8, prop, "(") orelse {
            try result.failures.append(self.alloc, .{
                .function = func.name,
                .example = prop,
                .expected = "true",
                .got = "invalid @property format — expected 'fn(params) { expression }'",
            });
            result.properties_failed += 1;
            return;
        };
        const paren_end = std.mem.indexOf(u8, prop, ")") orelse {
            result.properties_failed += 1;
            return;
        };
        const brace_start = std.mem.indexOf(u8, prop, "{") orelse {
            result.properties_failed += 1;
            return;
        };
        const brace_end = std.mem.lastIndexOf(u8, prop, "}") orelse {
            result.properties_failed += 1;
            return;
        };

        // Extract param names
        const params_text = prop[paren_start + 1 .. paren_end];
        var param_names: std.ArrayListUnmanaged([]const u8) = .{};
        var params_iter = std.mem.splitScalar(u8, params_text, ',');
        while (params_iter.next()) |param| {
            const trimmed = std.mem.trim(u8, param, &[_]u8{ ' ', '\t' });
            if (trimmed.len > 0) {
                try param_names.append(self.alloc, trimmed);
            }
        }

        // Extract body expression
        const body_text = std.mem.trim(u8, prop[brace_start + 1 .. brace_end], &[_]u8{ ' ', '\t' });

        // Parse body expression
        var body_parser = Parser.init(body_text, self.alloc);
        const body_expr = body_parser.parseExpr() catch {
            try result.failures.append(self.alloc, .{
                .function = func.name,
                .example = prop,
                .expected = "true",
                .got = "failed to parse property body",
            });
            result.properties_failed += 1;
            return;
        };

        // Fuzz: run with random inputs
        var rng = std.Random.DefaultPrng.init(42); // deterministic seed for reproducibility
        var random = rng.random();

        var i: usize = 0;
        while (i < FUZZ_ITERATIONS) : (i += 1) {
            var scope = @import("interpreter.zig").Scope.init(self.alloc);

            // Generate random int values for each param
            for (param_names.items) |pname| {
                const val = random.intRangeAtMost(i64, -1000, 1000);
                try scope.set(pname, .{ .int = val });
            }

            // Also make the function callable by bare name
            // by qualifying calls in the expression
            const prop_result = self.interp.evalExpr(body_expr, &scope) catch {
                // If evaluation fails, try qualifying function calls
                result.properties_failed += 1;
                try result.failures.append(self.alloc, .{
                    .function = func.name,
                    .example = prop,
                    .expected = "true for all inputs",
                    .got = "runtime error during property evaluation",
                });
                return;
            };

            if (prop_result != .bool or !prop_result.bool) {
                // Build input description
                var input_buf: [256]u8 = undefined;
                var input_stream = std.io.fixedBufferStream(&input_buf);
                const writer = input_stream.writer();
                for (param_names.items, 0..) |pname, pi| {
                    if (pi > 0) writer.writeAll(", ") catch {};
                    const v: Value = scope.get(pname) orelse .{ .none = {} };
                    writer.print("{s}=", .{pname}) catch {};
                    v.format(writer) catch {};
                }

                try result.failures.append(self.alloc, .{
                    .function = func.name,
                    .example = prop,
                    .expected = "true for all inputs",
                    .got = try self.alloc.dupe(u8, input_stream.getWritten()),
                });
                result.properties_failed += 1;
                return;
            }
        }

        // All iterations passed
        result.properties_passed += 1;
        _ = module_name;
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
