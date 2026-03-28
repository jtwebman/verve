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
    current_scope: std.StringHashMapUnmanaged(?ast.TypeExpr), // name -> type (null = unknown)
    current_module_name: ?[]const u8,
    current_fn_name: ?[]const u8,
    current_return_type: ?ast.TypeExpr,
    process_var_types: std.StringHashMapUnmanaged([]const u8), // var name -> process decl name

    const FnSignature = struct {
        name: []const u8,
        module_name: []const u8,
        params: []const ast.Param,
        return_type: ast.TypeExpr,
    };

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
            .current_module_name = null,
            .current_fn_name = null,
            .current_return_type = null,
            .process_var_types = .{},
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
        // Library files (those with exported declarations) don't need main()
        var has_exports = false;
        var mod_iter2 = self.modules.iterator();
        while (mod_iter2.next()) |entry| {
            if (entry.value_ptr.exported) has_exports = true;
        }
        var proc_iter2 = self.process_decls.iterator();
        while (proc_iter2.next()) |entry| {
            if (entry.value_ptr.exported) has_exports = true;
        }

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

        if (found == 0 and !has_exports) {
            try self.addError("no entry point found — add fn main(args: list<string>) -> int", 0, 0);
        } else if (found > 1) {
            try self.addError("multiple entry points found — only one main() is allowed", 0, 0);
        }
    }

    // ── Module checking ───────────────────────────────────────

    fn checkModule(self: *Checker, m: ast.ModuleDecl) !void {
        self.current_module_name = m.name;

        // Exported modules must have doc comments
        if (m.exported and m.doc_comment == null) {
            try self.addError(
                try std.fmt.allocPrint(self.alloc, "exported module '{s}' is missing a /// doc comment", .{m.name}),
                0,
                0,
            );
        }

        // Register module-level constants
        for (m.constants) |c| {
            if (c.type_expr) |te| {
                try self.checkTypeExists(te);
            }
        }

        for (m.functions) |func| {
            try self.checkFnDecl(func, m.name, m.exported);
        }
    }

    // ── Process checking ──────────────────────────────────────

    fn checkProcess(self: *Checker, p: ast.ProcessDecl) !void {
        // Exported processes must have doc comments
        if (p.exported and p.doc_comment == null) {
            try self.addError(
                try std.fmt.allocPrint(self.alloc, "exported process '{s}' is missing a /// doc comment", .{p.name}),
                0,
                0,
            );
        }

        // New syntax: validate state_type references a known struct
        if (p.state_type) |st| {
            if (self.struct_decls.get(st) == null) {
                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "process '{s}' state type '{s}' is not a known struct", .{ p.name, st }),
                    0,
                    0,
                );
            }
        }

        self.current_module_name = p.name;

        // Check receive handlers
        for (p.receive_handlers) |handler| {
            try self.checkReceiveDecl(handler, p, p.exported);
        }
    }

    fn checkReceiveDecl(self: *Checker, handler: ast.ReceiveDecl, p: ast.ProcessDecl, is_exported: bool) !void {
        // Exported receive handlers must have doc comments
        if (is_exported and handler.doc_comment == null and !std.mem.eql(u8, handler.name, "main")) {
            try self.addError(
                try std.fmt.allocPrint(self.alloc, "exported handler '{s}.{s}' is missing a /// doc comment", .{ p.name, handler.name }),
                0,
                0,
            );
        }

        self.in_receive_handler = true;
        defer self.in_receive_handler = false;

        self.current_scope = .{};
        self.current_fn_name = handler.name;
        self.current_return_type = handler.return_type;

        // Add params to scope
        for (handler.params) |param| {
            try self.checkTypeExists(param.type_expr);
            try self.current_scope.put(self.alloc, param.name, param.type_expr);
        }

        // New syntax: validate state param and add to scope
        if (p.state_type) |st| {
            if (handler.params.len == 0 or !std.mem.eql(u8, handler.params[0].name, "state")) {
                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "handler '{s}.{s}' must have 'state: {s}' as first parameter", .{ p.name, handler.name, st }),
                    0,
                    0,
                );
            } else if (!std.mem.eql(u8, self.typeExprName(handler.params[0].type_expr), st)) {
                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "handler '{s}.{s}' state parameter must be typed '{s}'", .{ p.name, handler.name, st }),
                    0,
                    0,
                );
            }
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

    fn checkFnDecl(self: *Checker, func: ast.FnDecl, module_name: []const u8, is_exported: bool) !void {
        // Exported functions must have doc comments
        if (is_exported and func.doc_comment == null and !std.mem.eql(u8, func.name, "main")) {
            try self.addError(
                try std.fmt.allocPrint(self.alloc, "exported function '{s}.{s}' is missing a /// doc comment", .{ module_name, func.name }),
                0,
                0,
            );
        }

        self.current_scope = .{};
        self.current_fn_name = func.name;
        self.current_return_type = func.return_type;

        // Add sibling functions and module constants to scope
        if (self.modules.get(module_name)) |mod| {
            for (mod.functions) |sibling| {
                try self.current_scope.put(self.alloc, sibling.name, null);
            }
            for (mod.constants) |c| {
                try self.current_scope.put(self.alloc, c.name, c.type_expr);
            }
        }

        // Add params to scope
        for (func.params) |param| {
            try self.checkTypeExists(param.type_expr);
            try self.current_scope.put(self.alloc, param.name, param.type_expr);
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
        // Check field types exist and defaults are provided
        var seen_fields: std.StringHashMapUnmanaged(void) = .{};
        for (s.fields) |field| {
            try self.checkTypeExists(field.type_expr);
            if (field.default_value == null) {
                try self.addError(
                    try std.fmt.allocPrint(self.alloc, "struct field '{s}' in '{s}' requires a default value — add = <value>", .{ field.name, s.name }),
                    0,
                    0,
                );
            }
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
                    try self.current_scope.put(self.alloc, a.name, te);

                    // Type check: inferred value type vs declared type
                    const inferred = self.inferExprType(a.value);
                    if (!self.typesCompatible(te, inferred)) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "{s}: type mismatch in '{s}' — cannot assign {s} to {s}", .{ self.locationPrefix(), a.name, self.formatTypeExpr(inferred), self.typeExprName(te) }),
                            0,
                            0,
                        );
                    }

                    // Track spawn process types
                    if (a.value == .call) {
                        if (a.value.call.target.* == .identifier and std.mem.eql(u8, a.value.call.target.identifier, "spawn")) {
                            if (a.value.call.args.len > 0 and a.value.call.args[0] == .string_literal) {
                                try self.process_var_types.put(self.alloc, a.name, a.value.call.args[0].string_literal);
                            }
                        }
                    }
                } else {
                    // Reassignment: x = 43;
                    if (self.current_scope.get(a.name)) |maybe_type| {
                        // Variable exists — check type compatibility on reassignment
                        if (maybe_type) |expected_type| {
                            const inferred = self.inferExprType(a.value);
                            if (!self.typesCompatible(expected_type, inferred)) {
                                try self.addError(
                                    try std.fmt.allocPrint(self.alloc, "{s}: type mismatch in '{s}' — cannot assign {s} to {s}", .{ self.locationPrefix(), a.name, self.formatTypeExpr(inferred), self.typeExprName(expected_type) }),
                                    0,
                                    0,
                                );
                            }
                        }
                    } else {
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
                    // Type check return value against declared return type
                    if (self.current_return_type) |expected| {
                        const inferred = self.inferExprType(val);
                        if (!self.typesCompatible(expected, inferred)) {
                            try self.addError(
                                try std.fmt.allocPrint(self.alloc, "{s}: return type mismatch — expected {s}, got {s}", .{ self.locationPrefix(), self.typeExprName(expected), self.formatTypeExpr(inferred) }),
                                0,
                                0,
                            );
                        }
                    }
                }
            },
            .if_stmt => |i| {
                try self.checkExprIsBoolean(i.condition);
                for (i.body) |s| try self.checkStmt(s);
                if (i.else_body) |eb| {
                    for (eb) |s| try self.checkStmt(s);
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
                    if (self.current_scope.get(m.subject.identifier)) |maybe_type| {
                        if (maybe_type) |type_expr| {
                            const type_name = self.typeExprName(type_expr);
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
                }

                // Require wildcard unless exhaustiveness is proven
                var has_wildcard = false;
                for (m.arms) |arm| {
                    if (arm.pattern == .wildcard) has_wildcard = true;
                    switch (arm.pattern) {
                        .tag => |t| {
                            for (t.bindings) |binding| {
                                try self.current_scope.put(self.alloc, binding, null);
                            }
                        },
                        else => {},
                    }
                    for (arm.body) |s| try self.checkStmt(s);
                }
                if (!has_wildcard and m.arms.len > 0) {
                    // Check if exhaustiveness was already proven (bool or enum)
                    var proven_exhaustive = false;
                    if (m.subject == .binary_op) {
                        // Bool exhaustiveness: check if both true and false are covered
                        var has_true = false;
                        var has_false = false;
                        for (m.arms) |arm| {
                            if (arm.pattern == .literal) {
                                if (arm.pattern.literal == .bool_literal) {
                                    if (arm.pattern.literal.bool_literal) has_true = true else has_false = true;
                                }
                            }
                        }
                        if (has_true and has_false) proven_exhaustive = true;
                    }
                    if (m.subject == .identifier) {
                        if (self.current_scope.get(m.subject.identifier)) |maybe_type| {
                            if (maybe_type) |type_expr| {
                                const type_name = self.typeExprName(type_expr);
                                if (std.mem.eql(u8, type_name, "bool")) {
                                    var has_true = false;
                                    var has_false = false;
                                    for (m.arms) |arm| {
                                        if (arm.pattern == .literal) {
                                            if (arm.pattern.literal == .bool_literal) {
                                                if (arm.pattern.literal.bool_literal) has_true = true else has_false = true;
                                            }
                                        }
                                    }
                                    if (has_true and has_false) proven_exhaustive = true;
                                }
                                if (self.type_decls.get(type_name)) |td| {
                                    if (td.value == .enum_type) {
                                        var all_covered = true;
                                        var covered: std.StringHashMapUnmanaged(void) = .{};
                                        for (m.arms) |arm| {
                                            switch (arm.pattern) {
                                                .tag => |t| covered.put(self.alloc, t.tag, {}) catch {},
                                                .literal => |e| {
                                                    if (e == .tag) covered.put(self.alloc, e.tag, {}) catch {};
                                                },
                                                else => {},
                                            }
                                        }
                                        for (td.value.enum_type) |variant| {
                                            if (covered.get(variant) == null) all_covered = false;
                                        }
                                        if (all_covered) proven_exhaustive = true;
                                    } else if (td.value == .union_type) {
                                        var all_covered = true;
                                        var covered: std.StringHashMapUnmanaged(void) = .{};
                                        for (m.arms) |arm| {
                                            switch (arm.pattern) {
                                                .tag => |t| covered.put(self.alloc, t.tag, {}) catch {},
                                                else => {},
                                            }
                                        }
                                        for (td.value.union_type) |variant| {
                                            if (covered.get(variant.tag) == null) all_covered = false;
                                        }
                                        if (all_covered) proven_exhaustive = true;
                                    }
                                }
                            }
                        }
                    }
                    // Result<T> exhaustiveness: :ok + :error covers all cases
                    if (!proven_exhaustive) {
                        var has_ok = false;
                        var has_error = false;
                        for (m.arms) |arm| {
                            if (arm.pattern == .tag) {
                                if (std.mem.eql(u8, arm.pattern.tag.tag, "ok")) has_ok = true;
                                if (std.mem.eql(u8, arm.pattern.tag.tag, "error")) has_error = true;
                            }
                        }
                        if (has_ok and has_error) proven_exhaustive = true;
                    }

                    if (!proven_exhaustive) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "{s}: match is not exhaustive — add a wildcard '_' arm", .{self.locationPrefix()}),
                            0,
                            0,
                        );
                    }
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
                    // Check handler arg count/types if process type is known
                    if (self.process_var_types.get(name)) |proc_name| {
                        if (self.process_decls.get(proc_name)) |proc| {
                            for (proc.receive_handlers) |handler| {
                                if (std.mem.eql(u8, handler.name, t.handler)) {
                                    // Skip the state param (injected by runtime) for new-style processes
                                    const user_params = if (proc.state_type != null and handler.params.len > 0 and
                                        std.mem.eql(u8, handler.params[0].name, "state"))
                                        handler.params[1..]
                                    else
                                        handler.params;

                                    if (t.args.len != user_params.len) {
                                        try self.addError(
                                            try std.fmt.allocPrint(self.alloc, "'{s}.{s}' expects {d} argument(s), got {d}", .{ proc_name, t.handler, user_params.len, t.args.len }),
                                            0,
                                            0,
                                        );
                                    } else {
                                        for (user_params, t.args) |param, arg| {
                                            const inferred = self.inferExprType(arg);
                                            if (!self.typesCompatible(param.type_expr, inferred)) {
                                                try self.addError(
                                                    try std.fmt.allocPrint(self.alloc, "argument type mismatch in '{s}.{s}': expected {s}, got {s}", .{ proc_name, t.handler, self.typeExprName(param.type_expr), self.formatTypeExpr(inferred) }),
                                                    0,
                                                    0,
                                                );
                                            }
                                        }
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
                for (t.args) |arg| try self.checkExpr(arg);
            },
            .expr_stmt => |e| {
                try self.checkExpr(e);
            },
            .assert_stmt => |a| {
                try self.checkExprIsBoolean(a.condition);
            },
            .break_stmt, .continue_stmt => {},
            .receive_stmt => {
                if (!self.in_receive_handler) {
                    try self.addError("receive; can only be used inside a process", 0, 0);
                }
            },
            .watch_stmt => |w| {
                try self.checkExpr(w.target);
            },
            .field_assign => |fa| {
                try self.checkExpr(fa.target);
                try self.checkExpr(fa.value);
            },
            .send_stmt => {},
        }
    }

    // ── Expression checking ───────────────────────────────────

    fn checkExpr(self: *Checker, expr: ast.Expr) !void {
        switch (expr) {
            .int_literal, .float_literal, .string_literal, .bool_literal => {},
            .string_interp => |si| {
                for (si.parts) |part| {
                    switch (part) {
                        .expr => |e| try self.checkExpr(e),
                        .literal => {},
                    }
                }
            },
            .tag, .none_literal, .void_literal => {},
            .tagged_value => |tv| {
                if (tv.value) |v| try self.checkExpr(v.*);
            },
            .identifier => |name| {
                // Check built-in functions
                if (std.mem.eql(u8, name, "list") or
                    std.mem.eql(u8, name, "map") or
                    std.mem.eql(u8, name, "set") or
                    std.mem.eql(u8, name, "stack") or
                    std.mem.eql(u8, name, "queue") or
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
                    // Built-in modules
                    if (std.mem.eql(u8, name, "String") or
                        std.mem.eql(u8, name, "Map") or
                        std.mem.eql(u8, name, "Set") or
                        std.mem.eql(u8, name, "Stack") or
                        std.mem.eql(u8, name, "Queue") or
                        std.mem.eql(u8, name, "Stdio") or
                        std.mem.eql(u8, name, "File") or
                        std.mem.eql(u8, name, "Stream") or
                        std.mem.eql(u8, name, "Tcp") or
                        std.mem.eql(u8, name, "Math") or
                        std.mem.eql(u8, name, "Env") or
                        std.mem.eql(u8, name, "System") or
                        std.mem.eql(u8, name, "Convert") or
                        std.mem.eql(u8, name, "Json") or
                        std.mem.eql(u8, name, "Http") or
                        std.mem.eql(u8, name, "Process")) return;
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
                // Check arg count and types against function signature
                if (self.lookupFnSignature(c.target.*)) |sig| {
                    const fn_qual = std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ sig.module_name, sig.name }) catch "?";
                    if (c.args.len != sig.params.len) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "{s}: '{s}' expects {d} argument(s), got {d}", .{ self.locationPrefix(), fn_qual, sig.params.len, c.args.len }),
                            0,
                            0,
                        );
                    } else {
                        for (sig.params, c.args) |param, arg| {
                            const inferred = self.inferExprType(arg);
                            if (!self.typesCompatible(param.type_expr, inferred)) {
                                try self.addError(
                                    try std.fmt.allocPrint(self.alloc, "{s}: argument '{s}' in call to '{s}' — expected {s}, got {s}", .{ self.locationPrefix(), param.name, fn_qual, self.typeExprName(param.type_expr), self.formatTypeExpr(inferred) }),
                                    0,
                                    0,
                                );
                            }
                        }
                    }
                }
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
                .break_stmt => return true,
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
                // Generic types require type parameters
                const needs_params = [_][]const u8{ "list", "map", "set", "stack", "queue" };
                for (needs_params) |g| {
                    if (std.mem.eql(u8, name, g)) {
                        try self.addError(
                            try std.fmt.allocPrint(self.alloc, "'{s}' requires type parameters — use {s}<T> instead", .{ name, name }),
                            0,
                            0,
                        );
                        return;
                    }
                }
                const builtins = [_][]const u8{
                    "int",     "int8",    "int16",        "int32",    "int64",
                    "uint8",   "uint16",  "uint32",       "uint64",   "float",
                    "float32", "float64", "decimal",      "string",   "bool",
                    "byte",    "bytes",   "void",         "uuid",     "email",
                    "uri",     "phone",   "utc_datetime", "duration", "Result",
                    "stream",
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
                const known_generics = [_][]const u8{ "list", "map", "set", "stack", "queue", "process", "Result" };
                var found = false;
                for (known_generics) |kg| {
                    if (std.mem.eql(u8, g.name, kg)) {
                        found = true;
                        break;
                    }
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

    fn locationPrefix(self: *Checker) []const u8 {
        if (self.current_module_name) |mod| {
            if (self.current_fn_name) |fn_name| {
                return std.fmt.allocPrint(self.alloc, "{s}.{s}", .{ mod, fn_name }) catch "?";
            }
            return mod;
        }
        return "?";
    }

    fn formatTypeExpr(self: *Checker, t: ?ast.TypeExpr) []const u8 {
        if (t) |te| return self.typeExprName(te);
        return "unknown";
    }

    // ── Type inference ───────────────────────────────────────────

    fn inferExprType(self: *Checker, expr: ast.Expr) ?ast.TypeExpr {
        switch (expr) {
            .int_literal => return .{ .simple = "int" },
            .float_literal => return .{ .simple = "float" },
            .string_literal, .string_interp => return .{ .simple = "string" },
            .bool_literal => return .{ .simple = "bool" },
            .void_literal => return .{ .simple = "void" },
            .identifier => |name| {
                if (self.current_scope.get(name)) |maybe_type| {
                    return maybe_type;
                }
                return null;
            },
            .binary_op => |op| {
                switch (op.op) {
                    .eq, .neq, .lt, .gt, .lte, .gte, .@"and", .@"or" => return .{ .simple = "bool" },
                    .add, .sub, .mul, .div, .mod => {
                        const left_t = self.inferExprType(op.left.*);
                        const right_t = self.inferExprType(op.right.*);
                        // String concatenation: string + string = string
                        if (op.op == .add) {
                            if (left_t) |lt| {
                                if (lt == .simple and std.mem.eql(u8, lt.simple, "string")) return .{ .simple = "string" };
                            }
                            if (right_t) |rt| {
                                if (rt == .simple and std.mem.eql(u8, rt.simple, "string")) return .{ .simple = "string" };
                            }
                        }
                        // Float promotion
                        if (left_t) |lt| {
                            if (lt == .simple and std.mem.eql(u8, lt.simple, "float")) return .{ .simple = "float" };
                        }
                        if (right_t) |rt| {
                            if (rt == .simple and std.mem.eql(u8, rt.simple, "float")) return .{ .simple = "float" };
                        }
                        return .{ .simple = "int" };
                    },
                    else => return null,
                }
            },
            .unary_op => |op| {
                switch (op.op) {
                    .not => return .{ .simple = "bool" },
                    .sub => return self.inferExprType(op.operand.*),
                    else => return null,
                }
            },
            .call => |c| {
                if (self.lookupFnSignature(c.target.*)) |sig| {
                    return sig.return_type;
                }
                // Built-in function calls
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    if (std.mem.eql(u8, name, "spawn")) {
                        return .{ .simple = "int" };
                    }
                }
                // Built-in module function calls (String.len, Map.has, etc.)
                if (c.target.* == .field_access) {
                    return self.inferBuiltinModuleCall(c.target.field_access);
                }
                return null;
            },
            .struct_literal => |sl| return .{ .simple = sl.name },
            .field_access => |fa| {
                const target_type = self.inferExprType(fa.target.*);
                if (target_type) |tt| {
                    const type_name = self.typeExprName(tt);
                    // .len on collections and strings
                    if (std.mem.eql(u8, fa.field, "len")) {
                        if (std.mem.eql(u8, type_name, "string") or
                            std.mem.eql(u8, type_name, "list") or
                            std.mem.eql(u8, type_name, "map") or
                            std.mem.eql(u8, type_name, "set") or
                            std.mem.eql(u8, type_name, "stack") or
                            std.mem.eql(u8, type_name, "queue"))
                        {
                            return .{ .simple = "int" };
                        }
                    }
                    // Struct field access
                    if (self.struct_decls.get(type_name)) |sd| {
                        for (sd.fields) |field| {
                            if (std.mem.eql(u8, field.name, fa.field)) {
                                return field.type_expr;
                            }
                        }
                    }
                }
                return null;
            },
            .index_access => |ia| {
                const target_type = self.inferExprType(ia.target.*);
                if (target_type) |tt| {
                    switch (tt) {
                        .simple => |name| {
                            if (std.mem.eql(u8, name, "string")) return .{ .simple = "string" };
                        },
                        .generic => |g| {
                            // list<T>[i] -> T
                            if (std.mem.eql(u8, g.name, "list") and g.args.len > 0) return g.args[0];
                            // map<K,V>[k] -> V
                            if (std.mem.eql(u8, g.name, "map") and g.args.len > 1) return g.args[1];
                        },
                        else => {},
                    }
                }
                return null;
            },
            else => return null,
        }
    }

    fn inferBuiltinModuleCall(self: *Checker, fa: ast.FieldAccess) ?ast.TypeExpr {
        if (fa.target.* != .identifier) return null;
        const mod = fa.target.identifier;
        const func = fa.field;

        // Check user modules first — already handled by lookupFnSignature
        if (self.modules.get(mod) != null) return null;

        if (std.mem.eql(u8, mod, "String")) return inferStringFn(func);
        if (std.mem.eql(u8, mod, "Map")) return inferMapFn(func);
        if (std.mem.eql(u8, mod, "Set")) return inferSetFn(func);
        if (std.mem.eql(u8, mod, "Stack") or std.mem.eql(u8, mod, "Queue")) return inferStackQueueFn(func);
        if (std.mem.eql(u8, mod, "Stdio")) {
            if (std.mem.eql(u8, func, "println") or std.mem.eql(u8, func, "print")) return .{ .simple = "void" };
            return .{ .simple = "stream" };
        }
        if (std.mem.eql(u8, mod, "Stream")) return inferStreamFn(func);
        return null;
    }

    fn inferStringFn(func: []const u8) ?ast.TypeExpr {
        // -> int
        if (std.mem.eql(u8, func, "len") or
            std.mem.eql(u8, func, "byte_at") or
            std.mem.eql(u8, func, "char_len")) return .{ .simple = "int" };
        // -> bool
        if (std.mem.eql(u8, func, "contains") or
            std.mem.eql(u8, func, "starts_with") or
            std.mem.eql(u8, func, "ends_with") or
            std.mem.eql(u8, func, "is_alpha") or
            std.mem.eql(u8, func, "is_digit") or
            std.mem.eql(u8, func, "is_whitespace") or
            std.mem.eql(u8, func, "is_alnum")) return .{ .simple = "bool" };
        // -> string
        if (std.mem.eql(u8, func, "trim") or
            std.mem.eql(u8, func, "replace") or
            std.mem.eql(u8, func, "slice") or
            std.mem.eql(u8, func, "char_at")) return .{ .simple = "string" };
        // split, chars -> list<string> (needs generic allocation, skip)
        return null;
    }

    fn inferMapFn(func: []const u8) ?ast.TypeExpr {
        if (std.mem.eql(u8, func, "put")) return .{ .simple = "void" };
        if (std.mem.eql(u8, func, "has")) return .{ .simple = "bool" };
        // get, keys, values -> type depends on map params, skip
        return null;
    }

    fn inferSetFn(func: []const u8) ?ast.TypeExpr {
        if (std.mem.eql(u8, func, "add") or std.mem.eql(u8, func, "remove")) return .{ .simple = "void" };
        if (std.mem.eql(u8, func, "has")) return .{ .simple = "bool" };
        return null;
    }

    fn inferStackQueueFn(func: []const u8) ?ast.TypeExpr {
        if (std.mem.eql(u8, func, "push")) return .{ .simple = "void" };
        // pop, peek -> element type unknown without generic context
        return null;
    }

    fn inferStreamFn(func: []const u8) ?ast.TypeExpr {
        if (std.mem.eql(u8, func, "write") or
            std.mem.eql(u8, func, "write_line") or
            std.mem.eql(u8, func, "close")) return .{ .simple = "void" };
        // read_line, read_all -> could be string or :eof, skip
        return null;
    }

    // ── Type compatibility ────────────────────────────────────────

    fn typesCompatible(self: *Checker, expected: ?ast.TypeExpr, actual: ?ast.TypeExpr) bool {
        const exp = expected orelse return true;
        const act = actual orelse return true;
        return self.typeExprsMatch(exp, act);
    }

    fn typeExprsMatch(self: *Checker, expected: ast.TypeExpr, actual: ast.TypeExpr) bool {
        switch (expected) {
            .simple => |exp_name| {
                const resolved_exp = self.resolveAlias(exp_name);
                switch (actual) {
                    .simple => |act_name| {
                        const resolved_act = self.resolveAlias(act_name);
                        return std.mem.eql(u8, resolved_exp, resolved_act);
                    },
                    else => return false,
                }
            },
            .generic => |exp_g| {
                switch (actual) {
                    .generic => |act_g| {
                        if (!std.mem.eql(u8, exp_g.name, act_g.name)) return false;
                        if (exp_g.args.len != act_g.args.len) return false;
                        for (exp_g.args, act_g.args) |ea, aa| {
                            if (!self.typeExprsMatch(ea, aa)) return false;
                        }
                        return true;
                    },
                    else => return false,
                }
            },
            else => return true, // optional, enum, union, fn_type — skip for now
        }
    }

    fn resolveAlias(self: *Checker, name: []const u8) []const u8 {
        if (self.type_decls.get(name)) |td| {
            switch (td.value) {
                .simple => |resolved| return resolved,
                else => return name,
            }
        }
        return name;
    }

    // ── Function signature lookup ─────────────────────────────────

    fn lookupFnSignature(self: *Checker, target: ast.Expr) ?FnSignature {
        switch (target) {
            .field_access => |fa| {
                if (fa.target.* == .identifier) {
                    const mod_name = fa.target.identifier;
                    if (self.modules.get(mod_name)) |mod| {
                        for (mod.functions) |func| {
                            if (std.mem.eql(u8, func.name, fa.field)) {
                                return .{ .name = func.name, .module_name = mod_name, .params = func.params, .return_type = func.return_type };
                            }
                        }
                    }
                    // Built-in modules and processes — return null (skip checking)
                }
                return null;
            },
            .identifier => |name| {
                // Bare function call — look up in current module
                if (self.current_module_name) |mod_name| {
                    if (self.modules.get(mod_name)) |mod| {
                        for (mod.functions) |func| {
                            if (std.mem.eql(u8, func.name, name)) {
                                return .{ .name = func.name, .module_name = mod_name, .params = func.params, .return_type = func.return_type };
                            }
                        }
                    }
                }
                return null;
            },
            else => return null,
        }
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
            .if_stmt => |i| {
                try self.collectCallsFromExpr(i.condition, current_module, callees);
                for (i.body) |s| try self.collectCallsFromStmt(s, current_module, callees);
                if (i.else_body) |eb| {
                    for (eb) |s| try self.collectCallsFromStmt(s, current_module, callees);
                }
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
            .append => |a| {
                try self.collectCallsFromExpr(a.target, current_module, callees);
                try self.collectCallsFromExpr(a.value, current_module, callees);
            },
            .tell_stmt => |t| {
                for (t.args) |arg| try self.collectCallsFromExpr(arg, current_module, callees);
            },
            .expr_stmt => |e| try self.collectCallsFromExpr(e, current_module, callees),
            .watch_stmt => |w| try self.collectCallsFromExpr(w.target, current_module, callees),
            .assert_stmt => |a| try self.collectCallsFromExpr(a.condition, current_module, callees),
            .field_assign => |fa| {
                try self.collectCallsFromExpr(fa.target, current_module, callees);
                try self.collectCallsFromExpr(fa.value, current_module, callees);
            },
            .break_stmt, .continue_stmt, .receive_stmt, .send_stmt => {},
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
                    if (!std.mem.eql(u8, name, "list") and
                        !std.mem.eql(u8, name, "map") and
                        !std.mem.eql(u8, name, "set") and
                        !std.mem.eql(u8, name, "stack") and
                        !std.mem.eql(u8, name, "queue") and
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
            .string_interp => |si| {
                for (si.parts) |part| {
                    switch (part) {
                        .expr => |e| try self.collectCallsFromExpr(e, current_module, callees),
                        .literal => {},
                    }
                }
            },
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
