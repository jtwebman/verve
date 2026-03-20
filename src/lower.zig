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
    // Loop context for break/continue
    loop_cond_block: ?ir.BlockId,
    loop_exit_block: ?ir.BlockId,
    // Struct declarations for field lookup
    struct_decls: std.StringHashMapUnmanaged(ast.StructDecl),
    // Variable name → struct type name (for field access resolution)
    var_types: std.StringHashMapUnmanaged([]const u8),
    // Register → string length (for string operations)
    string_lens: std.AutoHashMapUnmanaged(ir.Reg, ir.Reg),

    pub fn init(alloc: std.mem.Allocator) Lower {
        return .{
            .alloc = alloc,
            .program = ir.Program.init(alloc),
            .current_fn = null,
            .current_block = null,
            .current_module = "",
            .struct_decls = .{},
            .var_types = .{},
            .string_lens = .{},
            .loop_cond_block = null,
            .loop_exit_block = null,
        };
    }

    /// Lower an entire file to IR.
    pub fn lowerFile(self: *Lower, file: ast.File) !ir.Program {
        // Collect struct declarations first
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| {
                    try self.struct_decls.put(self.alloc, s.name, s);
                },
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

        // Store params as locals and track struct types
        for (func.params) |p| {
            const reg = f.newReg();
            entry.append(.{ .load_local = .{ .dest = reg, .name = p.name } });
            // Track struct-typed parameters
            switch (p.type_expr) {
                .simple => |type_name| {
                    if (self.struct_decls.get(type_name) != null) {
                        self.var_types.put(self.alloc, p.name, type_name) catch {};
                    }
                },
                else => {},
            }
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
                // Track struct type for field access
                if (a.type_expr) |te| {
                    switch (te) {
                        .simple => |type_name| {
                            if (self.struct_decls.get(type_name) != null) {
                                self.var_types.put(self.alloc, a.name, type_name) catch {};
                            }
                        },
                        else => {},
                    }
                }
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

                // Body — set loop context for break/continue
                const saved_cond = self.loop_cond_block;
                const saved_exit = self.loop_exit_block;
                self.loop_cond_block = cond_block.id;
                self.loop_exit_block = exit_block.id;

                self.current_block = body_block;
                for (w.body) |s| self.lowerStmt(s);
                if (self.current_block) |cb| {
                    cb.append(.{ .jump = .{ .target = cond_block.id } });
                }

                self.loop_cond_block = saved_cond;
                self.loop_exit_block = saved_exit;
                self.current_block = exit_block;
            },
            .break_stmt => {
                if (self.loop_exit_block) |exit_id| {
                    block.append(.{ .jump = .{ .target = exit_id } });
                }
            },
            .continue_stmt => {
                if (self.loop_cond_block) |cond_id| {
                    block.append(.{ .jump = .{ .target = cond_id } });
                }
            },
            .append => |a| {
                const list_reg = self.lowerExpr(a.target);
                const val_reg = self.lowerExpr(a.value);
                block.append(.{ .list_append = .{ .list = list_reg, .value = val_reg } });
            },
            .match_stmt => |m| {
                const subject_reg = self.lowerExpr(m.subject);
                const merge_block = func.newBlock();

                for (m.arms) |arm| {
                    switch (arm.pattern) {
                        .wildcard => {
                            // Default arm — just execute body
                            for (arm.body) |s| self.lowerStmt(s);
                            if (self.current_block) |cb| {
                                cb.append(.{ .jump = .{ .target = merge_block.id } });
                            }
                        },
                        .literal => |lit| {
                            const pat_reg = self.lowerExpr(lit);
                            const cmp_reg = func.newReg();
                            // Compare subject with pattern
                            if (self.current_block) |cb| {
                                cb.append(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = subject_reg, .rhs = pat_reg } });
                            }
                            const arm_block = func.newBlock();
                            const next_block = func.newBlock();
                            if (self.current_block) |cb| {
                                cb.append(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_block.id, .else_block = next_block.id } });
                            }
                            self.current_block = arm_block;
                            for (arm.body) |s| self.lowerStmt(s);
                            if (self.current_block) |cb| {
                                cb.append(.{ .jump = .{ .target = merge_block.id } });
                            }
                            self.current_block = next_block;
                        },
                        .tag => {
                            // Tag matching — skip for now
                            if (self.current_block) |cb| {
                                cb.append(.{ .jump = .{ .target = merge_block.id } });
                            }
                        },
                    }
                }
                // Fall through to merge
                if (self.current_block) |cb| {
                    cb.append(.{ .jump = .{ .target = merge_block.id } });
                }
                self.current_block = merge_block;
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
                // Track string length for later string ops
                const len_reg = func.newReg();
                block.append(.{ .const_int = .{ .dest = len_reg, .value = @intCast(v.len) } });
                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                return dest;
            },
            .identifier => |name| {
                const dest = func.newReg();
                block.append(.{ .load_local = .{ .dest = dest, .name = name } });
                return dest;
            },
            .binary_op => |op| {
                // Check for string comparison
                if (op.op == .eq or op.op == .neq) {
                    const is_str_l = (op.left.* == .string_literal);
                    const is_str_r = (op.right.* == .string_literal);
                    if (is_str_l or is_str_r) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const lhs_len = self.string_lens.get(lhs) orelse blk: {
                            const lr = func.newReg();
                            block.append(.{ .string_len = .{ .dest = lr, .str = lhs } });
                            break :blk lr;
                        };
                        const rhs_len = self.string_lens.get(rhs) orelse blk: {
                            const lr = func.newReg();
                            block.append(.{ .string_len = .{ .dest = lr, .str = rhs } });
                            break :blk lr;
                        };
                        const dest = func.newReg();
                        block.append(.{ .string_eq = .{ .dest = dest, .lhs = lhs, .lhs_len = lhs_len, .rhs = rhs, .rhs_len = rhs_len } });
                        if (op.op == .neq) {
                            const neg = func.newReg();
                            block.append(.{ .not_bool = .{ .dest = neg, .operand = dest } });
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
                        const mod_name = fa.target.identifier;
                        const fn_name = fa.field;

                        // String built-in functions → IR instructions
                        if (std.mem.eql(u8, mod_name, "String")) {
                            if (std.mem.eql(u8, fn_name, "byte_at")) {
                                if (args.len >= 2) {
                                    block.append(.{ .string_byte_at = .{ .dest = dest, .str = args[0], .index = args[1] } });
                                    return dest;
                                }
                            }
                            if (std.mem.eql(u8, fn_name, "is_alpha")) {
                                // byte_at(s, 0), then check if (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
                                // Simplified: emit as call_builtin, backend handles it
                                block.append(.{ .call_builtin = .{ .dest = dest, .name = "string_is_alpha", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "is_digit")) {
                                block.append(.{ .call_builtin = .{ .dest = dest, .name = "string_is_digit", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "is_whitespace")) {
                                block.append(.{ .call_builtin = .{ .dest = dest, .name = "string_is_whitespace", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "is_alnum")) {
                                block.append(.{ .call_builtin = .{ .dest = dest, .name = "string_is_alnum", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "slice")) {
                                block.append(.{ .call_builtin = .{ .dest = dest, .name = "string_slice", .args = args } });
                                return dest;
                            }
                            // Other String functions → generic call
                            block.append(.{ .call_builtin = .{ .dest = dest, .name = fn_name, .args = args } });
                            return dest;
                        }

                        // Set.has → builtin
                        if (std.mem.eql(u8, mod_name, "Set")) {
                            block.append(.{ .call_builtin = .{ .dest = dest, .name = "set_has", .args = args } });
                            return dest;
                        }

                        // User-defined module.function call
                        block.append(.{ .call = .{
                            .dest = dest,
                            .module = mod_name,
                            .function = fn_name,
                            .args = args,
                        } });
                        return dest;
                    }
                }
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    // println/print: for each string arg, pass (addr, len) pair
                    if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
                        // Build arg list with (addr, len) pairs for strings
                        var builtin_args = std.ArrayListUnmanaged(ir.Reg){};
                        for (c.args) |arg| {
                            if (arg == .string_literal) {
                                const str_reg = self.lowerExpr(arg);
                                const len_reg = func.newReg();
                                block.append(.{ .const_int = .{ .dest = len_reg, .value = @intCast(arg.string_literal.len) } });
                                builtin_args.append(self.alloc, str_reg) catch {};
                                builtin_args.append(self.alloc, len_reg) catch {};
                            } else if (arg == .int_literal) {
                                // For int args, we'd need to convert to string at runtime
                                // For now just pass the int value
                                builtin_args.append(self.alloc, self.lowerExpr(arg)) catch {};
                            } else {
                                builtin_args.append(self.alloc, self.lowerExpr(arg)) catch {};
                            }
                        }
                        block.append(.{ .call_builtin = .{
                            .dest = dest,
                            .name = name,
                            .args = builtin_args.toOwnedSlice(self.alloc) catch &.{},
                        } });
                        return dest;
                    }
                    // list() creates a new list
                    if (std.mem.eql(u8, name, "list")) {
                        const list_dest = func.newReg();
                        block.append(.{ .list_new = .{ .dest = list_dest } });
                        return list_dest;
                    }
                    // Other builtins
                    if (
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
            .struct_literal => |sl| {
                // Look up struct declaration for field order
                const decl = self.struct_decls.get(sl.name);
                const num_fields: u32 = if (decl) |d| @intCast(d.fields.len) else @intCast(sl.fields.len);

                // Allocate struct slots
                const base = func.newReg();
                block.append(.{ .struct_alloc = .{ .dest = base, .num_fields = num_fields } });

                // Store fields in declaration order
                if (decl) |d| {
                    for (d.fields, 0..) |df, fi| {
                        // Find matching literal field
                        for (sl.fields) |lf| {
                            if (std.mem.eql(u8, lf.name, df.name)) {
                                const val_reg = self.lowerExpr(lf.value);
                                block.append(.{ .struct_store = .{
                                    .base = base,
                                    .field_index = @intCast(fi),
                                    .src = val_reg,
                                } });
                                break;
                            }
                        }
                    }
                } else {
                    // No decl found — store in literal order
                    for (sl.fields, 0..) |lf, fi| {
                        const val_reg = self.lowerExpr(lf.value);
                        block.append(.{ .struct_store = .{
                            .base = base,
                            .field_index = @intCast(fi),
                            .src = val_reg,
                        } });
                    }
                }
                return base;
            },
            .field_access => |fa| {
                // Check if this is a value.field (struct access)
                if (fa.target.* == .identifier) {
                    const target_name = fa.target.identifier;
                    // Check if it's a variable with a known struct type
                    if (self.var_types.get(target_name)) |type_name| {
                        if (self.struct_decls.get(type_name)) |sd| {
                            // Find field index
                            for (sd.fields, 0..) |f, fi| {
                                if (std.mem.eql(u8, f.name, fa.field)) {
                                    const base_reg = self.lowerExpr(fa.target.*);
                                    const dest = func.newReg();
                                    block.append(.{ .struct_load = .{
                                        .dest = dest,
                                        .base = base_reg,
                                        .field_index = @intCast(fi),
                                    } });
                                    return dest;
                                }
                            }
                        }
                    }
                }
                // Check for .len (list length)
                if (std.mem.eql(u8, fa.field, "len")) {
                    const list_reg = self.lowerExpr(fa.target.*);
                    const dest = func.newReg();
                    block.append(.{ .list_len = .{ .dest = dest, .list = list_reg } });
                    return dest;
                }

                // Not a struct field or .len — return 0
                const dest = func.newReg();
                block.append(.{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            },
            .index_access => |ia| {
                const target_reg = self.lowerExpr(ia.target.*);
                const index_reg = self.lowerExpr(ia.index.*);
                const dest = func.newReg();
                block.append(.{ .list_get = .{ .dest = dest, .list = target_reg, .index = index_reg } });
                return dest;
            },
            else => {
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
