const std = @import("std");
const ast = @import("ast.zig");
const ir = @import("ir.zig");

/// Lowers Verve AST to target-independent IR.

pub const Lower = struct {
    alloc: std.mem.Allocator,
    program: ir.Program,
    current_fn: ?*ir.Function,
    current_block_id: ?ir.BlockId,
    current_module: []const u8,
    struct_decls: std.StringHashMapUnmanaged(ast.StructDecl),
    var_types: std.StringHashMapUnmanaged([]const u8),
    string_lens: std.AutoHashMapUnmanaged(ir.Reg, ir.Reg),
    loop_cond_block: ?ir.BlockId,
    loop_exit_block: ?ir.BlockId,

    pub fn init(alloc: std.mem.Allocator) Lower {
        return .{
            .alloc = alloc,
            .program = ir.Program.init(alloc),
            .current_fn = null,
            .current_block_id = null,
            .current_module = "",
            .struct_decls = .{},
            .var_types = .{},
            .string_lens = .{},
            .loop_cond_block = null,
            .loop_exit_block = null,
        };
    }

    /// Get current block, looking it up by ID (safe across reallocations).
    fn curBlock(self: *Lower) ?*ir.Block {
        const func = self.current_fn orelse return null;
        const bid = self.current_block_id orelse return null;
        return func.getBlock(bid);
    }

    /// Append an instruction to the current block.
    fn appendInst(self: *Lower, inst: ir.Inst) void {
        if (self.curBlock()) |b| b.append(inst);
    }

    pub fn lowerFile(self: *Lower, file: ast.File) !ir.Program {
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| try self.struct_decls.put(self.alloc, s.name, s),
                else => {},
            }
        }
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
                    self.current_module = p.name;
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
        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (func.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    if (self.struct_decls.get(tn) != null) self.var_types.put(self.alloc, p.name, tn) catch {};
                },
                else => {},
            }
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = resolveType(func.return_type);

        self.current_fn = &f;
        const entry = f.newBlock();
        self.current_block_id = entry.id;

        for (func.body) |stmt| self.lowerStmt(stmt);

        self.program.addFunction(f);
        self.current_fn = null;
        self.current_block_id = null;
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
        self.current_block_id = entry.id;

        for (handler.body) |stmt| self.lowerStmt(stmt);

        self.program.addFunction(f);
        self.current_fn = null;
        self.current_block_id = null;
    }

    // ── Statements ───────────────────────────────────────────

    fn lowerStmt(self: *Lower, stmt: ast.Stmt) void {
        const func = self.current_fn orelse return;

        switch (stmt) {
            .return_stmt => |r| {
                if (r.value) |val| {
                    const reg = self.lowerExpr(val);
                    self.appendInst(.{ .ret = .{ .value = reg } });
                } else {
                    self.appendInst(.{ .ret = .{ .value = null } });
                }
            },
            .assign => |a| {
                const reg = self.lowerExpr(a.value);
                self.appendInst(.{ .store_local = .{ .name = a.name, .src = reg } });
                if (a.type_expr) |te| {
                    switch (te) {
                        .simple => |tn| {
                            if (self.struct_decls.get(tn) != null) self.var_types.put(self.alloc, a.name, tn) catch {};
                        },
                        else => {},
                    }
                }
            },
            .if_stmt => |i| {
                const cond_reg = self.lowerExpr(i.condition);
                const then_id = func.newBlock().id;
                const else_id = func.newBlock().id;
                const merge_id = func.newBlock().id;

                self.appendInst(.{ .branch = .{
                    .cond = cond_reg,
                    .then_block = then_id,
                    .else_block = if (i.else_body != null) else_id else merge_id,
                } });

                self.current_block_id = then_id;
                for (i.body) |s| self.lowerStmt(s);
                self.appendInst(.{ .jump = .{ .target = merge_id } });

                if (i.else_body) |eb| {
                    self.current_block_id = else_id;
                    for (eb) |s| self.lowerStmt(s);
                    self.appendInst(.{ .jump = .{ .target = merge_id } });
                }

                self.current_block_id = merge_id;
            },
            .while_stmt => |w| {
                const cond_id = func.newBlock().id;
                const body_id = func.newBlock().id;
                const exit_id = func.newBlock().id;

                self.appendInst(.{ .jump = .{ .target = cond_id } });

                self.current_block_id = cond_id;
                const cond_reg = self.lowerExpr(w.condition);
                self.appendInst(.{ .branch = .{
                    .cond = cond_reg,
                    .then_block = body_id,
                    .else_block = exit_id,
                } });

                const saved_cond = self.loop_cond_block;
                const saved_exit = self.loop_exit_block;
                self.loop_cond_block = cond_id;
                self.loop_exit_block = exit_id;

                self.current_block_id = body_id;
                for (w.body) |s| self.lowerStmt(s);
                self.appendInst(.{ .jump = .{ .target = cond_id } });

                self.loop_cond_block = saved_cond;
                self.loop_exit_block = saved_exit;
                self.current_block_id = exit_id;
            },
            .break_stmt => {
                if (self.loop_exit_block) |exit_id| self.appendInst(.{ .jump = .{ .target = exit_id } });
            },
            .continue_stmt => {
                if (self.loop_cond_block) |cond_id| self.appendInst(.{ .jump = .{ .target = cond_id } });
            },
            .append => |a| {
                const list_reg = self.lowerExpr(a.target);
                const val_reg = self.lowerExpr(a.value);
                self.appendInst(.{ .list_append = .{ .list = list_reg, .value = val_reg } });
            },
            .match_stmt => |m| {
                const subject_reg = self.lowerExpr(m.subject);
                const merge_id = func.newBlock().id;

                for (m.arms) |arm| {
                    switch (arm.pattern) {
                        .wildcard => {
                            for (arm.body) |s| self.lowerStmt(s);
                            self.appendInst(.{ .jump = .{ .target = merge_id } });
                        },
                        .literal => |lit| {
                            const pat_reg = self.lowerExpr(lit);
                            const cmp_reg = func.newReg();
                            self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = subject_reg, .rhs = pat_reg } });
                            const arm_id = func.newBlock().id;
                            const next_id = func.newBlock().id;
                            self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                            self.current_block_id = arm_id;
                            for (arm.body) |s| self.lowerStmt(s);
                            self.appendInst(.{ .jump = .{ .target = merge_id } });
                            self.current_block_id = next_id;
                        },
                        .tag => {
                            self.appendInst(.{ .jump = .{ .target = merge_id } });
                        },
                    }
                }
                self.appendInst(.{ .jump = .{ .target = merge_id } });
                self.current_block_id = merge_id;
            },
            .expr_stmt => |e| {
                _ = self.lowerExpr(e);
            },
            else => {},
        }
    }

    // ── Expressions ──────────────────────────────────────────

    fn lowerExpr(self: *Lower, expr: ast.Expr) ir.Reg {
        const func = self.current_fn orelse return 0;

        switch (expr) {
            .int_literal => |v| {
                const dest = func.newReg();
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = v } });
                return dest;
            },
            .float_literal => |v| {
                const dest = func.newReg();
                self.appendInst(.{ .const_float = .{ .dest = dest, .value = v } });
                return dest;
            },
            .bool_literal => |v| {
                const dest = func.newReg();
                self.appendInst(.{ .const_bool = .{ .dest = dest, .value = v } });
                return dest;
            },
            .string_literal => |v| {
                const dest = func.newReg();
                self.appendInst(.{ .const_string = .{ .dest = dest, .value = v } });
                const len_reg = func.newReg();
                self.appendInst(.{ .const_int = .{ .dest = len_reg, .value = @intCast(v.len) } });
                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                return dest;
            },
            .identifier => |name| {
                const dest = func.newReg();
                self.appendInst(.{ .load_local = .{ .dest = dest, .name = name } });
                return dest;
            },
            .binary_op => |op| {
                // String comparison
                if (op.op == .eq or op.op == .neq) {
                    const is_str_l = (op.left.* == .string_literal);
                    const is_str_r = (op.right.* == .string_literal);
                    if (is_str_l or is_str_r) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const lhs_len = self.string_lens.get(lhs) orelse blk: {
                            const lr = func.newReg();
                            self.appendInst(.{ .string_len = .{ .dest = lr, .str = lhs } });
                            break :blk lr;
                        };
                        const rhs_len = self.string_lens.get(rhs) orelse blk: {
                            const lr = func.newReg();
                            self.appendInst(.{ .string_len = .{ .dest = lr, .str = rhs } });
                            break :blk lr;
                        };
                        const dest = func.newReg();
                        self.appendInst(.{ .string_eq = .{ .dest = dest, .lhs = lhs, .lhs_len = lhs_len, .rhs = rhs, .rhs_len = rhs_len } });
                        if (op.op == .neq) {
                            const neg = func.newReg();
                            self.appendInst(.{ .not_bool = .{ .dest = neg, .operand = dest } });
                            return neg;
                        }
                        return dest;
                    }
                }
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
                self.appendInst(inst);
                return dest;
            },
            .unary_op => |op| {
                const operand = self.lowerExpr(op.operand.*);
                const dest = func.newReg();
                switch (op.op) {
                    .not => self.appendInst(.{ .not_bool = .{ .dest = dest, .operand = operand } }),
                    .sub => self.appendInst(.{ .neg_i64 = .{ .dest = dest, .operand = operand } }),
                    else => {},
                }
                return dest;
            },
            .call => |c| {
                var arg_regs = std.ArrayListUnmanaged(ir.Reg){};
                for (c.args) |arg| {
                    arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
                }
                const args = arg_regs.toOwnedSlice(self.alloc) catch &.{};
                const dest = func.newReg();

                if (c.target.* == .field_access) {
                    const fa = c.target.field_access;
                    if (fa.target.* == .identifier) {
                        const mod_name = fa.target.identifier;
                        const fn_name = fa.field;

                        // String builtins
                        if (std.mem.eql(u8, mod_name, "String")) {
                            if (std.mem.eql(u8, fn_name, "byte_at")) {
                                if (args.len >= 2) {
                                    self.appendInst(.{ .string_byte_at = .{ .dest = dest, .str = args[0], .index = args[1] } });
                                    return dest;
                                }
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "string_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Set")) {
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "set_has", .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Map")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "map_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stack")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "stack_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Queue")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "queue_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stdio")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "stdio_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "File")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "file_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stream")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "stream_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        // User module.function
                        self.appendInst(.{ .call = .{ .dest = dest, .module = mod_name, .function = fn_name, .args = args } });
                        return dest;
                    }
                }
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    // println/print with string length pairs
                    if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
                        var builtin_args = std.ArrayListUnmanaged(ir.Reg){};
                        for (c.args) |arg| {
                            if (arg == .string_literal) {
                                const str_reg = self.lowerExpr(arg);
                                const len_reg = func.newReg();
                                self.appendInst(.{ .const_int = .{ .dest = len_reg, .value = @intCast(arg.string_literal.len) } });
                                builtin_args.append(self.alloc, str_reg) catch {};
                                builtin_args.append(self.alloc, len_reg) catch {};
                            } else {
                                builtin_args.append(self.alloc, self.lowerExpr(arg)) catch {};
                            }
                        }
                        self.appendInst(.{ .call_builtin = .{
                            .dest = dest,
                            .name = name,
                            .args = builtin_args.toOwnedSlice(self.alloc) catch &.{},
                        } });
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "list")) {
                        self.appendInst(.{ .list_new = .{ .dest = dest } });
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "set")) {
                        self.appendInst(.{ .list_new = .{ .dest = dest } });
                        for (c.args) |arg| {
                            const val_reg = self.lowerExpr(arg);
                            self.appendInst(.{ .list_append = .{ .list = dest, .value = val_reg } });
                        }
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "map") or std.mem.eql(u8, name, "stack") or std.mem.eql(u8, name, "queue") or std.mem.eql(u8, name, "spawn")) {
                        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = name, .args = args } });
                        return dest;
                    }
                    // Bare function call — same module
                    self.appendInst(.{ .call = .{ .dest = dest, .module = self.current_module, .function = name, .args = args } });
                    return dest;
                }
                return dest;
            },
            .struct_literal => |sl| {
                const decl = self.struct_decls.get(sl.name);
                const num_fields: u32 = if (decl) |d| @intCast(d.fields.len) else @intCast(sl.fields.len);
                const base = func.newReg();
                self.appendInst(.{ .struct_alloc = .{ .dest = base, .num_fields = num_fields } });

                if (decl) |d| {
                    for (d.fields, 0..) |df, fi| {
                        for (sl.fields) |lf| {
                            if (std.mem.eql(u8, lf.name, df.name)) {
                                const val_reg = self.lowerExpr(lf.value);
                                self.appendInst(.{ .struct_store = .{ .base = base, .field_index = @intCast(fi), .src = val_reg } });
                                break;
                            }
                        }
                    }
                } else {
                    for (sl.fields, 0..) |lf, fi| {
                        const val_reg = self.lowerExpr(lf.value);
                        self.appendInst(.{ .struct_store = .{ .base = base, .field_index = @intCast(fi), .src = val_reg } });
                    }
                }
                return base;
            },
            .field_access => |fa| {
                if (fa.target.* == .identifier) {
                    const target_name = fa.target.identifier;
                    if (self.var_types.get(target_name)) |type_name| {
                        if (self.struct_decls.get(type_name)) |sd| {
                            for (sd.fields, 0..) |f, fi| {
                                if (std.mem.eql(u8, f.name, fa.field)) {
                                    const base_reg = self.lowerExpr(fa.target.*);
                                    const dest = func.newReg();
                                    self.appendInst(.{ .struct_load = .{ .dest = dest, .base = base_reg, .field_index = @intCast(fi) } });
                                    return dest;
                                }
                            }
                        }
                    }
                    if (std.mem.eql(u8, fa.field, "len")) {
                        const list_reg = self.lowerExpr(fa.target.*);
                        const dest = func.newReg();
                        self.appendInst(.{ .list_len = .{ .dest = dest, .list = list_reg } });
                        return dest;
                    }
                }
                const dest = func.newReg();
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            },
            .index_access => |ia| {
                const target_reg = self.lowerExpr(ia.target.*);
                const index_reg = self.lowerExpr(ia.index.*);
                const dest = func.newReg();
                self.appendInst(.{ .list_get = .{ .dest = dest, .list = target_reg, .index = index_reg } });
                return dest;
            },
            else => {
                const dest = func.newReg();
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = 0 } });
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
