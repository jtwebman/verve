const std = @import("std");
const ast = @import("ast.zig");

pub const TypeError = struct {
    message: []const u8,
    line: usize,
    col: usize,
};

pub const Checker = struct {
    alloc: std.mem.Allocator,
    errors: std.ArrayListUnmanaged(TypeError),
    modules: std.StringHashMapUnmanaged(ast.ModuleDecl),
    process_decls: std.StringHashMapUnmanaged(ast.ProcessDecl),
    struct_decls: std.StringHashMapUnmanaged(ast.StructDecl),
    type_decls: std.StringHashMapUnmanaged(ast.TypeDecl),
    in_receive_handler: bool,
    current_scope: std.StringHashMapUnmanaged([]const u8), // name -> type

    pub fn init(alloc: std.mem.Allocator) Checker {
        return .{
            .alloc = alloc,
            .errors = .{},
            .modules = .{},
            .process_decls = .{},
            .struct_decls = .{},
            .type_decls = .{},
            .in_receive_handler = false,
            .current_scope = .{},
        };
    }

    pub fn check(self: *Checker, file: ast.File) !void {
        // First pass: collect all declarations
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| try self.modules.put(self.alloc, m.name, m),
                .process_decl => |p| try self.process_decls.put(self.alloc, p.name, p),
                .struct_decl => |s| try self.struct_decls.put(self.alloc, s.name, s),
                .type_decl => |t| try self.type_decls.put(self.alloc, t.name, t),
            }
        }

        // Second pass: check each declaration
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| try self.checkModule(m),
                .process_decl => |p| try self.checkProcess(p),
                .struct_decl => |s| try self.checkStruct(s),
                .type_decl => {},
            }
        }

        // Check for entry point
        try self.checkEntryPoint();

        // Check for recursion (call graph cycles)
        try self.checkNoRecursion();
    }

    // ── Entry point ───────────────────────────────────────────

    fn checkEntryPoint(self: *Checker) !void {
        var found: usize = 0;

        var proc_iter = self.process_decls.iterator();
        while (proc_iter.next()) |entry| {
            for (entry.value_ptr.receive_handlers) |handler| {
                if (std.mem.eql(u8, handler.name, "main")) found += 1;
            }
        }

        var mod_iter = self.modules.iterator();
        while (mod_iter.next()) |entry| {
            for (entry.value_ptr.functions) |func| {
                if (std.mem.eql(u8, func.name, "main")) found += 1;
            }
        }

        if (found == 0) {
            try self.addError("no entry point found — add fn main(args: list<string>) -> int", 0, 0);
        } else if (found > 1) {
            try self.addError("multiple entry points found — only one main() is allowed", 0, 0);
        }
    }

    // ── Module checking ───────────────────────────────────────

    fn checkModule(self: *Checker, m: ast.ModuleDecl) !void {
        for (m.functions) |func| {
            try self.checkFnDecl(func, m.name, false);
        }
    }

    // ── Process checking ──────────────────────────────────────

    fn checkProcess(self: *Checker, p: ast.ProcessDecl) !void {
        // Check state fields have valid types
        for (p.state_fields) |field| {
            try self.checkTypeExists(field.type_expr);
        }

        // Check receive handlers
        for (p.receive_handlers) |handler| {
            try self.checkReceiveDecl(handler, p);
        }
    }

    fn checkReceiveDecl(self: *Checker, handler: ast.ReceiveDecl, p: ast.ProcessDecl) !void {
        self.in_receive_handler = true;
        defer self.in_receive_handler = false;

        self.current_scope = .{};

        // Add params to scope
        for (handler.params) |param| {
            try self.checkTypeExists(param.type_expr);
            try self.current_scope.put(self.alloc, param.name, self.typeExprName(param.type_expr));
        }

        // Add process state to scope
        for (p.state_fields) |field| {
            try self.current_scope.put(self.alloc, field.name, self.typeExprName(field.type_expr));
        }

        // Check guards
        for (handler.guards) |guard| {
            try self.checkExprIsBoolean(guard);
        }
        try self.checkGuardConsistency(handler.guards);

        // Check body
        for (handler.body) |stmt| {
            try self.checkStmt(stmt);
        }
    }

    // ── Function checking ─────────────────────────────────────

    fn checkFnDecl(self: *Checker, func: ast.FnDecl, module_name: []const u8, is_process: bool) !void {
        _ = is_process;

        self.current_scope = .{};

        // Add sibling functions to scope (same module)
        if (self.modules.get(module_name)) |mod| {
            for (mod.functions) |sibling| {
                try self.current_scope.put(self.alloc, sibling.name, "fn");
            }
        }

        // Add params to scope
        for (func.params) |param| {
            try self.checkTypeExists(param.type_expr);
            try self.current_scope.put(self.alloc, param.name, self.typeExprName(param.type_expr));
        }

        // Check return type exists
        try self.checkTypeExists(func.return_type);

        // Check guards
        for (func.guards) |guard| {
            try self.checkExprIsBoolean(guard);
        }
        try self.checkGuardConsistency(func.guards);

        // Check body
        for (func.body) |stmt| {
            try self.checkStmt(stmt);
        }

        // Warn about obvious poison values and divergence
        try self.warnUnguardedDivision(func.body, func.guards);
        try self.checkForDivergence(func.body);
    }

    // ── Struct checking ───────────────────────────────────────

    fn checkStruct(self: *Checker, s: ast.StructDecl) !void {
        // Check field types exist
        var seen_fields: std.StringHashMapUnmanaged(void) = .{};
        for (s.fields) |field| {
            try self.checkTypeExists(field.type_expr);
            if (seen_fields.get(field.name) != null) {
                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "duplicate field '{s}' in struct '{s}'", .{ field.name, s.name }),
                    0,
                    0,
                );
            }
            try seen_fields.put(self.alloc, field.name, {});
        }
    }

    // ── Statement checking ────────────────────────────────────

    fn checkStmt(self: *Checker, stmt: ast.Stmt) !void {
        switch (stmt) {
            .assign => |a| {
                try self.checkExpr(a.value);
                if (a.type_expr) |te| {
                    // Declaration: x: int = 42;
                    try self.checkTypeExists(te);
                    try self.current_scope.put(self.alloc, a.name, self.typeExprName(te));
                } else {
                    // Reassignment: x = 43;
                    if (self.current_scope.get(a.name) == null) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "variable '{s}' must be declared with a type: {s}: <type> = ...", .{ a.name, a.name }),
                            0,
                            0,
                        );
                    }
                }
            },
            .return_stmt => |r| {
                if (r.value) |val| {
                    try self.checkExpr(val);
                }
            },
            .while_stmt => |w| {
                try self.checkExprIsBoolean(w.condition);
                for (w.body) |s| try self.checkStmt(s);
            },
            .match_stmt => |m| {
                try self.checkExpr(m.subject);
                if (m.arms.len == 0) {
                    try self.addError("match must have at least one arm", 0, 0);
                }

                // Check boolean exhaustiveness
                if (m.subject == .binary_op) {
                    try self.checkBooleanExhaustiveness(m.arms);
                }
                if (m.subject == .identifier) {
                    if (self.current_scope.get(m.subject.identifier)) |type_name| {
                        if (std.mem.eql(u8, type_name, "bool")) {
                            try self.checkBooleanExhaustiveness(m.arms);
                        }
                        // Check enum exhaustiveness
                        if (self.type_decls.get(type_name)) |td| {
                            if (td.value == .enum_type) {
                                try self.checkEnumExhaustiveness(td.value.enum_type, m.arms, type_name);
                            }
                        }
                    }
                }

                for (m.arms) |arm| {
                    switch (arm.pattern) {
                        .tag => |t| {
                            for (t.bindings) |binding| {
                                try self.current_scope.put(self.alloc, binding, "unknown");
                            }
                        },
                        else => {},
                    }
                    for (arm.body) |s| try self.checkStmt(s);
                }
            },
            .transition => |t| {
                if (!self.in_receive_handler) {
                    try self.addError("transition can only be used inside a receive handler", 0, 0);
                }
                try self.checkExpr(t.target);
                for (t.fields) |f| {
                    try self.checkExpr(f.value);
                }
            },
            .append => |a| {
                try self.checkExpr(a.target);
                try self.checkExpr(a.value);
            },
            .tell_stmt => |t| {
                try self.checkExpr(t.target);
                // Verify target is a process, not a module
                if (t.target == .identifier) {
                    const name = t.target.identifier;
                    if (self.modules.get(name) != null) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "cannot use 'tell' with module '{s}' — tell is for processes only", .{name}),
                            0,
                            0,
                        );
                    }
                }
                for (t.args) |arg| try self.checkExpr(arg);
            },
            .expr_stmt => |e| {
                try self.checkExpr(e);
            },
            .receive_stmt => {
                if (!self.in_receive_handler) {
                    try self.addError("receive; can only be used inside a process", 0, 0);
                }
            },
            .watch_stmt => |w| {
                try self.checkExpr(w.target);
            },
            .send_stmt => {},
        }
    }

    // ── Expression checking ───────────────────────────────────

    fn checkExpr(self: *Checker, expr: ast.Expr) !void {
        switch (expr) {
            .int_literal, .float_literal, .string_literal, .bool_literal => {},
            .tag, .none_literal, .void_literal => {},
            .identifier => |name| {
                // Check built-in functions
                if (std.mem.eql(u8, name, "print") or
                    std.mem.eql(u8, name, "println") or
                    std.mem.eql(u8, name, "list") or
                    std.mem.eql(u8, name, "spawn"))
                {
                    return;
                }
                if (self.current_scope.get(name) == null) {
                    try self.addError(
                        try std.fmt.allocPrint(self.alloc, "undefined variable '{s}'", .{name}),
                        0,
                        0,
                    );
                }
            },
            .binary_op => |op| {
                try self.checkExpr(op.left.*);
                try self.checkExpr(op.right.*);
            },
            .unary_op => |op| {
                try self.checkExpr(op.operand.*);
            },
            .field_access => |fa| {
                // Module.func or value.field — don't error on module names
                if (fa.target.* == .identifier) {
                    const name = fa.target.identifier;
                    if (self.modules.get(name) != null) return;
                    if (self.process_decls.get(name) != null) return;
                }
                try self.checkExpr(fa.target.*);
            },
            .index_access => |ia| {
                try self.checkExpr(ia.target.*);
                try self.checkExpr(ia.index.*);
            },
            .call => |c| {
                try self.checkExpr(c.target.*);
                for (c.args) |arg| try self.checkExpr(arg);
            },
            .struct_literal => |sl| {
                // Check struct exists
                if (self.struct_decls.get(sl.name) == null) {
                    // Could be an undeclared struct — warn but don't block
                    // (structs might be in imported files we haven't checked)
                }
                for (sl.fields) |f| try self.checkExpr(f.value);
            },
            .match_expr => {},
        }
    }

    fn checkExprIsBoolean(self: *Checker, expr: ast.Expr) !void {
        try self.checkExpr(expr);
        switch (expr) {
            .string_literal => try self.addError("guard/while condition must be boolean, got string", 0, 0),
            .int_literal => try self.addError("guard/while condition must be boolean, got int", 0, 0),
            .float_literal => try self.addError("guard/while condition must be boolean, got float", 0, 0),
            else => {},
        }
    }

    // ── Poison value warnings ─────────────────────────────────

    // ── Guard consistency ──────────────────────────────────────

    fn checkGuardConsistency(self: *Checker, guards: []const ast.Expr) !void {
        for (guards) |guard| {
            // Check for always-false guards
            if (guard == .bool_literal and !guard.bool_literal) {
                try self.addError("guard is always false — function can never execute", 0, 0);
            }
            // Check for contradictions: guard x > 0; guard x < 0;
            // (simplified: check literal contradictions)
            if (guard == .binary_op) {
                const op = guard.binary_op;
                // Check: x > x, x < x, x != x — always false
                if (op.left.* == .identifier and op.right.* == .identifier) {
                    if (std.mem.eql(u8, op.left.identifier, op.right.identifier)) {
                        switch (op.op) {
                            .lt, .gt, .neq => {
                                try self.addError(
                                    try std.fmt.allocPrint(self.alloc, "guard '{s}' compared to itself with '{s}' is always false", .{
                                        op.left.identifier,
                                        switch (op.op) {
                                            .lt => "<",
                                            .gt => ">",
                                            .neq => "!=",
                                            else => "?",
                                        },
                                    }),
                                    0,
                                    0,
                                );
                            },
                            else => {},
                        }
                    }
                }
            }
        }
    }

    // ── Divergence detection ───────────────────────────────────

    fn checkForDivergence(self: *Checker, stmts: []const ast.Stmt) !void {
        for (stmts) |stmt| {
            switch (stmt) {
                .while_stmt => |w| {
                    // while true { ... } with no return/break is infinite
                    if (w.condition == .bool_literal and w.condition.bool_literal) {
                        if (!self.bodyHasReturn(w.body)) {
                            try self.addError("potential infinite loop — 'while true' with no return statement", 0, 0);
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn bodyHasReturn(self: *Checker, stmts: []const ast.Stmt) bool {
        for (stmts) |stmt| {
            switch (stmt) {
                .return_stmt => return true,
                .match_stmt => |m| {
                    for (m.arms) |arm| {
                        if (self.bodyHasReturn(arm.body)) return true;
                    }
                },
                .while_stmt => |w| {
                    if (self.bodyHasReturn(w.body)) return true;
                },
                else => {},
            }
        }
        return false;
    }

    // ── Poison value warnings ─────────────────────────────────

    fn warnUnguardedDivision(self: *Checker, stmts: []const ast.Stmt, guards: []const ast.Expr) !void {
        // Check if any expression uses division without a guard checking divisor != 0
        _ = guards;
        for (stmts) |stmt| {
            switch (stmt) {
                .assign => |a| try self.checkForUnguardedDivision(a.value),
                .return_stmt => |r| {
                    if (r.value) |v| try self.checkForUnguardedDivision(v);
                },
                else => {},
            }
        }
    }

    fn checkForUnguardedDivision(self: *Checker, expr: ast.Expr) !void {
        switch (expr) {
            .binary_op => |op| {
                if (op.op == .div or op.op == .mod) {
                    // Check if divisor is a literal 0
                    if (op.right.* == .int_literal and op.right.int_literal == 0) {
                        try self.addError("division by zero — divisor is always 0", 0, 0);
                    }
                }
                try self.checkForUnguardedDivision(op.left.*);
                try self.checkForUnguardedDivision(op.right.*);
            },
            .call => |c| {
                for (c.args) |arg| try self.checkForUnguardedDivision(arg);
            },
            else => {},
        }
    }

    // ── Type checking helpers ─────────────────────────────────

    fn checkTypeExists(self: *Checker, t: ast.TypeExpr) !void {
        switch (t) {
            .simple => |name| {
                // Built-in types
                const builtins = [_][]const u8{
                    "int",     "int8",    "int16",   "int32",        "int64",
                    "uint8",   "uint16",  "uint32",  "uint64",       "float",
                    "float32", "float64", "decimal",  "string",       "bool",
                    "byte",    "bytes",   "void",    "uuid",         "email",
                    "uri",     "phone",   "utc_datetime", "duration", "Result",
                };
                for (builtins) |b| {
                    if (std.mem.eql(u8, name, b)) return;
                }
                // User-defined types
                if (self.type_decls.get(name) != null) return;
                if (self.struct_decls.get(name) != null) return;
                // Type params (single uppercase letter or generic param)
                if (name.len == 1 and std.ascii.isUpper(name[0])) return;

                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "unknown type '{s}'", .{name}),
                    0,
                    0,
                );
            },
            .generic => |g| {
                // Check base type and args
                const known_generics = [_][]const u8{ "list", "map", "process", "Result" };
                var found = false;
                for (known_generics) |kg| {
                    if (std.mem.eql(u8, g.name, kg)) { found = true; break; }
                }
                if (!found and self.struct_decls.get(g.name) == null) {
                    try self.addError(
                        try std.fmt.allocPrint(self.alloc, "unknown generic type '{s}'", .{g.name}),
                        0,
                        0,
                    );
                }
                for (g.args) |arg| try self.checkTypeExists(arg);
            },
            .optional => |inner| try self.checkTypeExists(inner.*),
            .enum_type => {},
            .union_type => |variants| {
                for (variants) |v| {
                    for (v.fields) |f| try self.checkTypeExists(f.type_expr);
                }
            },
            .fn_type => |f| {
                for (f.params) |p| try self.checkTypeExists(p);
                try self.checkTypeExists(f.return_type.*);
            },
            .constrained => |c| try self.checkTypeExists(c.base.*),
        }
    }

    fn typeExprName(self: *Checker, t: ast.TypeExpr) []const u8 {
        _ = self;
        return switch (t) {
            .simple => |name| name,
            .generic => |g| g.name,
            else => "unknown",
        };
    }

    // ── Match exhaustiveness ────────────────────────────────────

    fn checkBooleanExhaustiveness(self: *Checker, arms: []const ast.MatchArm) !void {
        var has_true = false;
        var has_false = false;
        var has_wildcard = false;

        for (arms) |arm| {
            switch (arm.pattern) {
                .literal => |e| {
                    if (e == .bool_literal) {
                        if (e.bool_literal) has_true = true else has_false = true;
                    }
                },
                .wildcard => has_wildcard = true,
                else => {},
            }
        }

        if (!has_wildcard) {
            if (!has_true and !has_false) {
                // Neither — could be matching on something else
                return;
            }
            if (!has_true) {
                try self.addError("match on boolean is missing 'true' case", 0, 0);
            }
            if (!has_false) {
                try self.addError("match on boolean is missing 'false' case", 0, 0);
            }
        }
    }

    fn checkEnumExhaustiveness(self: *Checker, variants: []const []const u8, arms: []const ast.MatchArm, type_name: []const u8) !void {
        var has_wildcard = false;
        var covered: std.StringHashMapUnmanaged(void) = .{};

        for (arms) |arm| {
            switch (arm.pattern) {
                .tag => |t| try covered.put(self.alloc, t.tag, {}),
                .wildcard => has_wildcard = true,
                .literal => |e| {
                    if (e == .tag) try covered.put(self.alloc, e.tag, {});
                },
            }
        }

        if (!has_wildcard) {
            for (variants) |variant| {
                if (covered.get(variant) == null) {
                    try self.addError(
                        try std.fmt.allocPrint(self.alloc, "match on '{s}' is missing case ':{s}'", .{ type_name, variant }),
                        0,
                        0,
                    );
                }
            }
        }
    }

    // ── Call graph cycle detection (no recursion) ──────────────

    fn checkNoRecursion(self: *Checker) !void {
        // Build call graph: function_key -> list of function_keys it calls
        // Key format: "ModuleName.functionName"
        var call_graph: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)) = .{};

        // Collect calls from module functions
        var mod_iter = self.modules.iterator();
        while (mod_iter.next()) |entry| {
            const mod_name = entry.key_ptr.*;
            for (entry.value_ptr.functions) |func| {
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ mod_name, func.name });
                var callees: std.ArrayListUnmanaged([]const u8) = .{};
                try self.collectCalls(func.body, func.guards, mod_name, &callees);
                try call_graph.put(self.alloc, key, callees);
            }
        }

        // Collect calls from process receive handlers
        var proc_iter = self.process_decls.iterator();
        while (proc_iter.next()) |entry| {
            const proc_name = entry.key_ptr.*;
            for (entry.value_ptr.receive_handlers) |handler| {
                const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ proc_name, handler.name });
                var callees: std.ArrayListUnmanaged([]const u8) = .{};
                try self.collectCalls(handler.body, handler.guards, proc_name, &callees);
                try call_graph.put(self.alloc, key, callees);
            }
        }

        // Detect cycles using DFS
        var visited: std.StringHashMapUnmanaged(u8) = .{}; // 0=unvisited, 1=in_progress, 2=done

        var graph_iter = call_graph.iterator();
        while (graph_iter.next()) |entry| {
            const key = entry.key_ptr.*;
            if ((visited.get(key) orelse 0) == 0) {
                try self.detectCycleDFS(key, &call_graph, &visited);
            }
        }
    }

    fn detectCycleDFS(
        self: *Checker,
        node: []const u8,
        graph: *std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)),
        visited: *std.StringHashMapUnmanaged(u8),
    ) !void {
        try visited.put(self.alloc, node, 1); // mark in progress

        if (graph.get(node)) |callees| {
            for (callees.items) |callee| {
                const state = visited.get(callee) orelse 0;
                if (state == 1) {
                    // Cycle found!
                    try self.addError(
                        try std.fmt.allocPrint(self.alloc, "recursion detected: '{s}' calls '{s}' which creates a cycle — use a while loop instead", .{ node, callee }),
                        0,
                        0,
                    );
                } else if (state == 0) {
                    try self.detectCycleDFS(callee, graph, visited);
                }
            }
        }

        try visited.put(self.alloc, node, 2); // mark done
    }

    fn collectCalls(self: *Checker, body: []const ast.Stmt, guards: []const ast.Expr, current_module: []const u8, callees: *std.ArrayListUnmanaged([]const u8)) !void {
        for (guards) |guard| {
            try self.collectCallsFromExpr(guard, current_module, callees);
        }
        for (body) |stmt| {
            try self.collectCallsFromStmt(stmt, current_module, callees);
        }
    }

    fn collectCallsFromStmt(self: *Checker, stmt: ast.Stmt, current_module: []const u8, callees: *std.ArrayListUnmanaged([]const u8)) !void {
        switch (stmt) {
            .assign => |a| try self.collectCallsFromExpr(a.value, current_module, callees),
            .return_stmt => |r| {
                if (r.value) |val| try self.collectCallsFromExpr(val, current_module, callees);
            },
            .while_stmt => |w| {
                try self.collectCallsFromExpr(w.condition, current_module, callees);
                for (w.body) |s| try self.collectCallsFromStmt(s, current_module, callees);
            },
            .match_stmt => |m| {
                try self.collectCallsFromExpr(m.subject, current_module, callees);
                for (m.arms) |arm| {
                    for (arm.body) |s| try self.collectCallsFromStmt(s, current_module, callees);
                }
            },
            .transition => |t| {
                try self.collectCallsFromExpr(t.target, current_module, callees);
                for (t.fields) |f| try self.collectCallsFromExpr(f.value, current_module, callees);
            },
            .append => |a| {
                try self.collectCallsFromExpr(a.target, current_module, callees);
                try self.collectCallsFromExpr(a.value, current_module, callees);
            },
            .tell_stmt => |t| {
                for (t.args) |arg| try self.collectCallsFromExpr(arg, current_module, callees);
            },
            .expr_stmt => |e| try self.collectCallsFromExpr(e, current_module, callees),
            .watch_stmt => |w| try self.collectCallsFromExpr(w.target, current_module, callees),
            .receive_stmt, .send_stmt => {},
        }
    }

    fn collectCallsFromExpr(self: *Checker, expr: ast.Expr, current_module: []const u8, callees: *std.ArrayListUnmanaged([]const u8)) !void {
        switch (expr) {
            .call => |c| {
                // Module.function(args)
                if (c.target.* == .field_access) {
                    const fa = c.target.field_access;
                    if (fa.target.* == .identifier) {
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ fa.target.identifier, fa.field });
                        try callees.append(self.alloc, key);
                    }
                }
                // bare function call: func(args) — in same module
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    // Skip builtins
                    if (!std.mem.eql(u8, name, "print") and
                        !std.mem.eql(u8, name, "println") and
                        !std.mem.eql(u8, name, "list") and
                        !std.mem.eql(u8, name, "spawn"))
                    {
                        const key = try std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ current_module, name });
                        try callees.append(self.alloc, key);
                    }
                }
                // Check args too
                try self.collectCallsFromExpr(c.target.*, current_module, callees);
                for (c.args) |arg| try self.collectCallsFromExpr(arg, current_module, callees);
            },
            .binary_op => |op| {
                try self.collectCallsFromExpr(op.left.*, current_module, callees);
                try self.collectCallsFromExpr(op.right.*, current_module, callees);
            },
            .unary_op => |op| try self.collectCallsFromExpr(op.operand.*, current_module, callees),
            .field_access => |fa| try self.collectCallsFromExpr(fa.target.*, current_module, callees),
            .index_access => |ia| {
                try self.collectCallsFromExpr(ia.target.*, current_module, callees);
                try self.collectCallsFromExpr(ia.index.*, current_module, callees);
            },
            else => {},
        }
    }

    // ── Error management ──────────────────────────────────────

    fn addError(self: *Checker, message: []const u8, line: usize, col: usize) !void {
        try self.errors.append(self.alloc, .{
            .message = message,
            .line = line,
            .col = col,
        });
    }

    pub fn hasErrors(self: *Checker) bool {
        return self.errors.items.len > 0;
    }

    pub fn printErrors(self: *Checker) void {
        for (self.errors.items) |err| {
            if (err.line > 0) {
                std.debug.print("  line {d}, col {d}: {s}\n", .{ err.line, err.col, err.message });
            } else {
                std.debug.print("  {s}\n", .{err.message});
            }
        }
    }
};
