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

        // Check guards are boolean
        for (handler.guards) |guard| {
            try self.checkExprIsBoolean(guard);
        }

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

        // Check guards are boolean
        for (func.guards) |guard| {
            try self.checkExprIsBoolean(guard);
        }

        // Check body
        for (func.body) |stmt| {
            try self.checkStmt(stmt);
        }
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
                try self.current_scope.put(self.alloc, a.name, "unknown");
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
                for (m.arms) |arm| {
                    // Add pattern bindings to scope
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
        // Full type inference would determine if the result is bool
        // For now, check obvious non-boolean cases
        switch (expr) {
            .string_literal => try self.addError("guard/while condition must be boolean, got string", 0, 0),
            .int_literal => try self.addError("guard/while condition must be boolean, got int", 0, 0),
            .float_literal => try self.addError("guard/while condition must be boolean, got float", 0, 0),
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
