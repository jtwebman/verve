const std = @import("std");
const ast = @import("ast.zig");
const ir = @import("ir.zig");

/// Lowers Verve AST to target-independent IR.
/// No OS-specific operations. Pure SSA construction.

pub const Lower = struct {
    alloc: std.mem.Allocator,
    program: ir.Program,
    // Current compilation state
    current_fn: ?*ir.Function,
    current_block: ?*ir.Block,
    current_module: []const u8,

    pub fn init(alloc: std.mem.Allocator) Lower {
        return .{
            .alloc = alloc,
            .program = ir.Program.init(alloc),
            .current_fn = null,
            .current_block = null,
            .current_module = "",
        };
    }

    /// Lower an entire file to IR.
    pub fn lowerFile(self: *Lower, file: ast.File) !ir.Program {
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    self.current_module = m.name;
                    for (m.functions) |func| {
                        try self.lowerFunction(m.name, func);
                        if (std.mem.eql(u8, func.name, "main")) {
                            self.program.entry_module = m.name;
                        }
                    }
                },
                .process_decl => |p| {
                    for (p.receive_handlers) |handler| {
                        try self.lowerHandler(p.name, handler);
                        if (std.mem.eql(u8, handler.name, "main")) {
                            self.program.entry_module = p.name;
                        }
                    }
                },
                else => {},
            }
        }
        return self.program;
    }

    fn lowerFunction(self: *Lower, module: []const u8, func: ast.FnDecl) !void {
        var f = ir.Function.init(module, func.name, self.alloc);

        // Build params
        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (func.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = resolveType(func.return_type);

        // Create entry block
        self.current_fn = &f;
        const entry = f.newBlock();
        self.current_block = entry;

        // Store params as locals
        for (func.params) |p| {
            const reg = f.newReg();
            entry.append(.{ .load_local = .{ .dest = reg, .name = p.name } });
        }

        // Lower body
        for (func.body) |stmt| {
            self.lowerStmt(stmt);
        }

        self.program.addFunction(f);
        self.current_fn = null;
        self.current_block = null;
    }

    fn lowerHandler(self: *Lower, module: []const u8, handler: ast.ReceiveDecl) !void {
        var f = ir.Function.init(module, handler.name, self.alloc);

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (handler.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = resolveType(handler.return_type);

        self.current_fn = &f;
        const entry = f.newBlock();
        self.current_block = entry;

        for (handler.body) |stmt| {
            self.lowerStmt(stmt);
        }

        self.program.addFunction(f);
        self.current_fn = null;
        self.current_block = null;
    }

    // ── Statements ───────────────────────────────────────────

    fn lowerStmt(self: *Lower, stmt: ast.Stmt) void {
        const func = self.current_fn orelse return;
        const block = self.current_block orelse return;

        switch (stmt) {
            .return_stmt => |r| {
                if (r.value) |val| {
                    const reg = self.lowerExpr(val);
                    block.append(.{ .ret = .{ .value = reg } });
                } else {
                    block.append(.{ .ret = .{ .value = null } });
                }
            },
            .assign => |a| {
                const reg = self.lowerExpr(a.value);
                block.append(.{ .store_local = .{ .name = a.name, .src = reg } });
            },
            .if_stmt => |i| {
                const cond_reg = self.lowerExpr(i.condition);
                const then_block = func.newBlock();
                const else_block = func.newBlock();
                const merge_block = func.newBlock();

                block.append(.{ .branch = .{
                    .cond = cond_reg,
                    .then_block = then_block.id,
                    .else_block = if (i.else_body != null) else_block.id else merge_block.id,
                } });

                // Then
                self.current_block = then_block;
                for (i.body) |s| self.lowerStmt(s);
                if (self.current_block) |cb| {
                    cb.append(.{ .jump = .{ .target = merge_block.id } });
                }

                // Else
                if (i.else_body) |eb| {
                    self.current_block = else_block;
                    for (eb) |s| self.lowerStmt(s);
                    if (self.current_block) |cb| {
                        cb.append(.{ .jump = .{ .target = merge_block.id } });
                    }
                }

                self.current_block = merge_block;
            },
            .while_stmt => |w| {
                const cond_block = func.newBlock();
                const body_block = func.newBlock();
                const exit_block = func.newBlock();

                block.append(.{ .jump = .{ .target = cond_block.id } });

                // Condition
                self.current_block = cond_block;
                const cond_reg = self.lowerExpr(w.condition);
                cond_block.append(.{ .branch = .{
                    .cond = cond_reg,
                    .then_block = body_block.id,
                    .else_block = exit_block.id,
                } });

                // Body
                self.current_block = body_block;
                for (w.body) |s| self.lowerStmt(s);
                if (self.current_block) |cb| {
                    cb.append(.{ .jump = .{ .target = cond_block.id } });
                }

                self.current_block = exit_block;
            },
            .expr_stmt => |e| {
                _ = self.lowerExpr(e);
            },
            else => {},
        }
    }

    // ── Expressions ──────────────────────────────────────────
    // Each expression returns a Reg holding its result.

    fn lowerExpr(self: *Lower, expr: ast.Expr) ir.Reg {
        const func = self.current_fn orelse return 0;
        const block = self.current_block orelse return 0;

        switch (expr) {
            .int_literal => |v| {
                const dest = func.newReg();
                block.append(.{ .const_int = .{ .dest = dest, .value = v } });
                return dest;
            },
            .float_literal => |v| {
                const dest = func.newReg();
                block.append(.{ .const_float = .{ .dest = dest, .value = v } });
                return dest;
            },
            .bool_literal => |v| {
                const dest = func.newReg();
                block.append(.{ .const_bool = .{ .dest = dest, .value = v } });
                return dest;
            },
            .string_literal => |v| {
                const dest = func.newReg();
                block.append(.{ .const_string = .{ .dest = dest, .value = v } });
                return dest;
            },
            .identifier => |name| {
                const dest = func.newReg();
                block.append(.{ .load_local = .{ .dest = dest, .name = name } });
                return dest;
            },
            .binary_op => |op| {
                const lhs = self.lowerExpr(op.left.*);
                const rhs = self.lowerExpr(op.right.*);
                const dest = func.newReg();
                const inst: ir.Inst = switch (op.op) {
                    .add => .{ .add_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .sub => .{ .sub_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .mul => .{ .mul_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .div => .{ .div_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .mod => .{ .mod_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .eq => .{ .eq_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .neq => .{ .neq_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .lt => .{ .lt_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .gt => .{ .gt_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .lte => .{ .lte_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .gte => .{ .gte_i64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .@"and" => .{ .and_bool = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .@"or" => .{ .or_bool = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .not => .{ .not_bool = .{ .dest = dest, .operand = lhs } },
                };
                block.append(inst);
                return dest;
            },
            .unary_op => |op| {
                const operand = self.lowerExpr(op.operand.*);
                const dest = func.newReg();
                switch (op.op) {
                    .not => block.append(.{ .not_bool = .{ .dest = dest, .operand = operand } }),
                    .sub => block.append(.{ .neg_i64 = .{ .dest = dest, .operand = operand } }),
                    else => {},
                }
                return dest;
            },
            .call => |c| {
                // Evaluate args
                var arg_regs = std.ArrayListUnmanaged(ir.Reg){};
                for (c.args) |arg| {
                    arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
                }
                const args = arg_regs.toOwnedSlice(self.alloc) catch &.{};
                const dest = func.newReg();

                if (c.target.* == .field_access) {
                    const fa = c.target.field_access;
                    if (fa.target.* == .identifier) {
                        block.append(.{ .call = .{
                            .dest = dest,
                            .module = fa.target.identifier,
                            .function = fa.field,
                            .args = args,
                        } });
                        return dest;
                    }
                }
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    // Check if it's a built-in function
                    if (std.mem.eql(u8, name, "println") or
                        std.mem.eql(u8, name, "print") or
                        std.mem.eql(u8, name, "list") or
                        std.mem.eql(u8, name, "map") or
                        std.mem.eql(u8, name, "set") or
                        std.mem.eql(u8, name, "stack") or
                        std.mem.eql(u8, name, "queue") or
                        std.mem.eql(u8, name, "spawn"))
                    {
                        block.append(.{ .call_builtin = .{
                            .dest = dest,
                            .name = name,
                            .args = args,
                        } });
                        return dest;
                    }
                    // Bare function call — qualify with current module
                    block.append(.{ .call = .{
                        .dest = dest,
                        .module = self.current_module,
                        .function = name,
                        .args = args,
                    } });
                    return dest;
                }
                return dest;
            },
            else => {
                // Unsupported expression — return 0
                const dest = func.newReg();
                block.append(.{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            },
        }
    }

    fn resolveType(type_expr: ast.TypeExpr) ir.Type {
        switch (type_expr) {
            .simple => |name| {
                if (std.mem.eql(u8, name, "int")) return .i64;
                if (std.mem.eql(u8, name, "float")) return .f64;
                if (std.mem.eql(u8, name, "bool")) return .bool;
                if (std.mem.eql(u8, name, "string")) return .string;
                return .void;
            },
            else => return .void,
        }
    }
};
