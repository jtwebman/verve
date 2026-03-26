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
    string_vars: std.StringHashMapUnmanaged(void), // variables known to be strings
    string_lens: std.AutoHashMapUnmanaged(ir.Reg, ir.Reg),
    float_regs: std.AutoHashMapUnmanaged(ir.Reg, void), // registers holding float values
    float_vars: std.StringHashMapUnmanaged(void), // variables known to be floats
    loop_cond_block: ?ir.BlockId,
    loop_exit_block: ?ir.BlockId,
    // Process support
    process_decls: std.StringHashMapUnmanaged(ast.ProcessDecl),
    process_vars: std.StringHashMapUnmanaged([]const u8), // var name -> process type name
    current_process_decl: ?ast.ProcessDecl,

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
            .string_vars = .{},
            .float_regs = .{},
            .float_vars = .{},
            .loop_cond_block = null,
            .loop_exit_block = null,
            .process_decls = .{},
            .process_vars = .{},
            .current_process_decl = null,
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
                .process_decl => |p| try self.process_decls.put(self.alloc, p.name, p),
                else => {},
            }
        }
        // Build process_decls in program for backend
        for (file.decls) |decl| {
            switch (decl) {
                .process_decl => |p| {
                    var state_fields = std.ArrayListUnmanaged(ir.StateFieldInfo){};
                    if (p.state_type) |st| {
                        if (self.struct_decls.get(st)) |sd| {
                            for (sd.fields) |f| {
                                try state_fields.append(self.alloc, .{ .name = f.name });
                            }
                        }
                    }
                    var handler_names = std.ArrayListUnmanaged([]const u8){};
                    for (p.receive_handlers) |h| {
                        try handler_names.append(self.alloc, h.name);
                    }
                    try self.program.process_decls.append(self.alloc, .{
                        .name = p.name,
                        .state_fields = try state_fields.toOwnedSlice(self.alloc),
                        .handler_names = try handler_names.toOwnedSlice(self.alloc),
                    });
                },
                else => {},
            }
        }
        // Build struct_decls in program for backend (used by Json.parse typed parsing)
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| {
                    var fields = std.ArrayListUnmanaged(ir.StructFieldInfo){};
                    for (s.fields) |f| {
                        const type_name: []const u8 = switch (f.type_expr) {
                            .simple => |tn| tn,
                            else => "unknown",
                        };
                        try fields.append(self.alloc, .{ .name = f.name, .type_name = type_name });
                    }
                    try self.program.struct_decls.append(self.alloc, .{
                        .name = s.name,
                        .fields = try fields.toOwnedSlice(self.alloc),
                    });
                },
                else => {},
            }
        }
        for (file.decls) |decl| {
            switch (decl) {
                .module_decl => |m| {
                    self.current_module = m.name;
                    self.current_process_decl = null;
                    for (m.functions) |func| {
                        try self.lowerFunction(m.name, func);
                        if (std.mem.eql(u8, func.name, "main")) {
                            self.program.entry_module = m.name;
                        }
                    }
                },
                .process_decl => |p| {
                    self.current_module = p.name;
                    self.current_process_decl = p;
                    for (p.receive_handlers) |handler| {
                        try self.lowerHandler(p.name, handler, p);
                        if (std.mem.eql(u8, handler.name, "main")) {
                            self.program.entry_module = p.name;
                        }
                    }
                    self.current_process_decl = null;
                },
                else => {},
            }
        }
        return self.program;
    }

    fn lowerFunction(self: *Lower, module: []const u8, func: ast.FnDecl) !void {
        var f = ir.Function.init(module, func.name, self.alloc);

        // Reset per-function state BEFORE processing params
        self.string_lens = .{};
        self.string_vars = .{};
        self.float_regs = .{};
        self.float_vars = .{};

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (func.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    if (self.struct_decls.get(tn) != null) self.var_types.put(self.alloc, p.name, tn) catch {};
                    if (std.mem.eql(u8, tn, "string")) self.string_vars.put(self.alloc, p.name, {}) catch {};
                    if (std.mem.eql(u8, tn, "float")) self.float_vars.put(self.alloc, p.name, {}) catch {};
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

    fn lowerHandler(self: *Lower, module: []const u8, handler: ast.ReceiveDecl, proc_decl: ast.ProcessDecl) !void {
        var f = ir.Function.init(module, handler.name, self.alloc);

        // Reset per-function state
        self.string_lens = .{};
        self.string_vars = .{};

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        const skip_state = proc_decl.state_type != null and handler.params.len > 0 and
            std.mem.eql(u8, handler.params[0].name, "state");
        const user_params = if (skip_state) handler.params[1..] else handler.params;
        for (user_params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = resolveType(handler.return_type);

        self.current_fn = &f;
        self.current_process_decl = proc_decl;
        const entry = f.newBlock();
        self.current_block_id = entry.id;

        // Emit guard checks — if any guard fails, return makeTagged(1, guard_failed_tag)
        for (handler.guards) |guard_expr| {
            const guard_reg = self.lowerExpr(guard_expr);
            const pass_id = f.newBlock().id;
            const fail_id = f.newBlock().id;
            self.appendInst(.{ .branch = .{ .cond = guard_reg, .then_block = pass_id, .else_block = fail_id } });
            // Fail block: return tagged error(:guard_failed)
            self.current_block_id = fail_id;
            const tag_id_reg = f.newReg();
            self.appendInst(.{ .const_int = .{ .dest = tag_id_reg, .value = 1 } }); // 1 = error tag
            const val_reg = f.newReg();
            self.appendInst(.{ .const_int = .{ .dest = val_reg, .value = 99 } }); // 99 = guard_failed sentinel
            const tagged_reg = f.newReg();
            self.appendInst(.{ .call_builtin = .{ .dest = tagged_reg, .name = "make_tagged", .args = blk: {
                const a = self.alloc.alloc(ir.Reg, 2) catch break :blk &.{};
                a[0] = tag_id_reg;
                a[1] = val_reg;
                break :blk a;
            } } });
            self.appendInst(.{ .ret = .{ .value = tagged_reg } });
            // Continue in pass block
            self.current_block_id = pass_id;
        }

        for (handler.body) |stmt| self.lowerStmt(stmt);

        self.program.addFunction(f);
        self.current_fn = null;
        self.current_block_id = null;
        self.current_process_decl = null;
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
                // Check if value is spawn — intercept before lowerExpr
                if (a.value == .call) {
                    if (a.value.call.target.* == .identifier and std.mem.eql(u8, a.value.call.target.identifier, "spawn")) {
                        // spawn ProcessName() — args[0] is string_literal with process name
                        if (a.value.call.args.len > 0 and a.value.call.args[0] == .string_literal) {
                            const proc_name = a.value.call.args[0].string_literal;
                            // Find process type index
                            for (self.program.process_decls.items, 0..) |pd, pi| {
                                if (std.mem.eql(u8, pd.name, proc_name)) {
                                    const dest = func.newReg();
                                    self.appendInst(.{ .process_spawn = .{ .dest = dest, .process_type = @intCast(pi) } });
                                    self.appendInst(.{ .store_local = .{ .name = a.name, .src = dest } });
                                    self.process_vars.put(self.alloc, a.name, proc_name) catch {};
                                    break;
                                }
                            }
                            return;
                        }
                    }
                }
                const reg = self.lowerExpr(a.value);
                self.appendInst(.{ .store_local = .{ .name = a.name, .src = reg } });
                // Store string length if the value has one tracked
                // Propagate float tracking from register to variable
                if (self.float_regs.get(reg) != null) {
                    self.float_vars.put(self.alloc, a.name, {}) catch {};
                }
                if (self.string_lens.get(reg)) |len_reg| {
                    const len_name = std.fmt.allocPrint(self.alloc, "{s}__len", .{a.name}) catch a.name;
                    self.appendInst(.{ .store_local = .{ .name = len_name, .src = len_reg } });
                }
                if (a.type_expr) |te| {
                    switch (te) {
                        .simple => |tn| {
                            if (self.struct_decls.get(tn) != null) self.var_types.put(self.alloc, a.name, tn) catch {};
                            if (std.mem.eql(u8, tn, "string")) self.string_vars.put(self.alloc, a.name, {}) catch {};
                            if (std.mem.eql(u8, tn, "float")) self.float_vars.put(self.alloc, a.name, {}) catch {};
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
            .tell_stmt => |t| {
                const target_reg = self.lowerExpr(t.target);
                var arg_regs = std.ArrayListUnmanaged(ir.Reg){};
                for (t.args) |arg| {
                    arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
                }
                // Resolve handler index from process type
                if (t.target == .identifier) {
                    if (self.process_vars.get(t.target.identifier)) |proc_type| {
                        if (self.process_decls.get(proc_type)) |pdecl| {
                            for (pdecl.receive_handlers, 0..) |h, hi| {
                                if (std.mem.eql(u8, h.name, t.handler)) {
                                    self.appendInst(.{ .process_tell = .{
                                        .target = target_reg,
                                        .handler_index = @intCast(hi),
                                        .args = arg_regs.toOwnedSlice(self.alloc) catch &.{},
                                    } });
                                    break;
                                }
                            }
                        }
                    }
                }
            },
            .watch_stmt => |w| {
                const target_reg = self.lowerExpr(w.target);
                self.appendInst(.{ .process_watch = .{ .target = target_reg } });
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
                        .tag => |t| {
                            // Tag matching: check tag_id
                            const tag_reg = func.newReg();
                            self.appendInst(.{ .tag_get = .{ .dest = tag_reg, .tagged = subject_reg } });
                            // Map tag name to id: ok=0, error=1, eof=2
                            const tag_id: i64 = if (std.mem.eql(u8, t.tag, "ok")) 0 else if (std.mem.eql(u8, t.tag, "error")) 1 else if (std.mem.eql(u8, t.tag, "eof")) 2 else -1;
                            const id_reg = func.newReg();
                            self.appendInst(.{ .const_int = .{ .dest = id_reg, .value = tag_id } });
                            const cmp_reg = func.newReg();
                            self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = tag_reg, .rhs = id_reg } });
                            const arm_id = func.newBlock().id;
                            const next_id = func.newBlock().id;
                            self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                            self.current_block_id = arm_id;
                            // Bind inner value to variable names
                            if (t.bindings.len > 0) {
                                const val_reg = func.newReg();
                                self.appendInst(.{ .tag_value = .{ .dest = val_reg, .tagged = subject_reg } });
                                self.appendInst(.{ .store_local = .{ .name = t.bindings[0], .src = val_reg } });
                                // Propagate struct type from tagged result to binding
                                const tag_key = std.fmt.allocPrint(self.alloc, "__tagged_struct_{d}", .{subject_reg}) catch "";
                                if (self.var_types.get(tag_key)) |struct_type| {
                                    self.var_types.put(self.alloc, t.bindings[0], struct_type) catch {};
                                }
                            }
                            for (arm.body) |s| self.lowerStmt(s);
                            self.appendInst(.{ .jump = .{ .target = merge_id } });
                            self.current_block_id = next_id;
                        },
                    }
                }
                self.appendInst(.{ .jump = .{ .target = merge_id } });
                self.current_block_id = merge_id;
            },
            .field_assign => |fa| {
                // state.field = expr; → process_state_set
                if (fa.target == .field_access) {
                    const field_name = fa.target.field_access.field;
                    if (fa.target.field_access.target.* == .identifier and
                        std.mem.eql(u8, fa.target.field_access.target.identifier, "state"))
                    {
                        if (self.current_process_decl) |pdecl| {
                            if (pdecl.state_type) |st| {
                                if (self.struct_decls.get(st)) |sd| {
                                    for (sd.fields, 0..) |f, fi| {
                                        if (std.mem.eql(u8, f.name, field_name)) {
                                            const val_reg = self.lowerExpr(fa.value);
                                            self.appendInst(.{ .process_state_set = .{ .field_index = @intCast(fi), .src = val_reg } });
                                            return;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
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
                self.float_regs.put(self.alloc, dest, {}) catch {};
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
                // Load string length for known string variables
                if (self.string_vars.get(name) != null) {
                    const len_name = std.fmt.allocPrint(self.alloc, "{s}__len", .{name}) catch name;
                    const len_reg = func.newReg();
                    self.appendInst(.{ .load_local = .{ .dest = len_reg, .name = len_name } });
                    self.string_lens.put(self.alloc, dest, len_reg) catch {};
                }
                if (self.float_vars.get(name) != null) {
                    self.float_regs.put(self.alloc, dest, {}) catch {};
                }
                return dest;
            },
            .binary_op => |op| {
                // String comparison — detect if either side is a string
                if (op.op == .eq or op.op == .neq) {
                    const is_str_l = (op.left.* == .string_literal) or
                        (op.left.* == .identifier and self.string_vars.get(op.left.identifier) != null) or
                        (op.left.* == .field_access and self.isStringFieldAccess(op.left.field_access));
                    const is_str_r = (op.right.* == .string_literal) or
                        (op.right.* == .identifier and self.string_vars.get(op.right.identifier) != null) or
                        (op.right.* == .field_access and self.isStringFieldAccess(op.right.field_access));
                    if (is_str_l or is_str_r) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const lhs_len = self.getStringLen(func, lhs);
                        const rhs_len = self.getStringLen(func, rhs);
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
                // String concatenation with +
                if (op.op == .add) {
                    const is_str_l = (op.left.* == .string_literal) or
                        (op.left.* == .identifier and self.string_vars.get(op.left.identifier) != null) or
                        (op.left.* == .field_access and self.isStringFieldAccess(op.left.field_access));
                    const is_str_r = (op.right.* == .string_literal) or
                        (op.right.* == .identifier and self.string_vars.get(op.right.identifier) != null) or
                        (op.right.* == .field_access and self.isStringFieldAccess(op.right.field_access));
                    if (is_str_l or is_str_r) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const lhs_len = self.getStringLen(func, lhs);
                        const rhs_len = self.getStringLen(func, rhs);
                        const dest = func.newReg();
                        var concat_args = std.ArrayListUnmanaged(ir.Reg){};
                        concat_args.append(self.alloc, lhs) catch {};
                        concat_args.append(self.alloc, lhs_len) catch {};
                        concat_args.append(self.alloc, rhs) catch {};
                        concat_args.append(self.alloc, rhs_len) catch {};
                        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_concat", .args = concat_args.toOwnedSlice(self.alloc) catch &.{} } });
                        // Result length = lhs_len + rhs_len
                        const result_len = func.newReg();
                        self.appendInst(.{ .add_i64 = .{ .dest = result_len, .lhs = lhs_len, .rhs = rhs_len } });
                        self.string_lens.put(self.alloc, dest, result_len) catch {};
                        return dest;
                    }
                }
                const lhs = self.lowerExpr(op.left.*);
                const rhs = self.lowerExpr(op.right.*);
                const dest = func.newReg();
                const is_float = self.float_regs.get(lhs) != null or self.float_regs.get(rhs) != null or
                    (op.left.* == .float_literal) or (op.right.* == .float_literal) or
                    (op.left.* == .identifier and self.float_vars.get(op.left.identifier) != null) or
                    (op.right.* == .identifier and self.float_vars.get(op.right.identifier) != null);
                const inst: ir.Inst = if (is_float) switch (op.op) {
                    .add => .{ .add_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .sub => .{ .sub_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .mul => .{ .mul_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .div => .{ .div_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .mod => .{ .mod_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .eq => .{ .eq_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .neq => .{ .neq_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .lt => .{ .lt_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .gt => .{ .gt_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .lte => .{ .lte_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .gte => .{ .gte_f64 = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .@"and" => .{ .and_bool = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .@"or" => .{ .or_bool = .{ .dest = dest, .lhs = lhs, .rhs = rhs } },
                    .not => .{ .not_bool = .{ .dest = dest, .operand = lhs } },
                } else switch (op.op) {
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
                // Float arithmetic produces float results
                if (is_float and op.op != .eq and op.op != .neq and op.op != .lt and
                    op.op != .gt and op.op != .lte and op.op != .gte)
                {
                    self.float_regs.put(self.alloc, dest, {}) catch {};
                }
                return dest;
            },
            .unary_op => |op| {
                const operand = self.lowerExpr(op.operand.*);
                const dest = func.newReg();
                const is_float_op = self.float_regs.get(operand) != null or
                    (op.operand.* == .float_literal) or
                    (op.operand.* == .identifier and self.float_vars.get(op.operand.identifier) != null);
                switch (op.op) {
                    .not => self.appendInst(.{ .not_bool = .{ .dest = dest, .operand = operand } }),
                    .sub => {
                        if (is_float_op) {
                            self.appendInst(.{ .neg_f64 = .{ .dest = dest, .operand = operand } });
                            self.float_regs.put(self.alloc, dest, {}) catch {};
                        } else {
                            self.appendInst(.{ .neg_i64 = .{ .dest = dest, .operand = operand } });
                        }
                    },
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

                        // Process send: counter.Increment() -> process_send
                        if (self.process_vars.get(mod_name)) |proc_type| {
                            if (self.process_decls.get(proc_type)) |pdecl| {
                                for (pdecl.receive_handlers, 0..) |h, hi| {
                                    if (std.mem.eql(u8, h.name, fn_name)) {
                                        const target_reg = self.lowerExpr(fa.target.*);
                                        self.appendInst(.{ .process_send = .{
                                            .dest = dest,
                                            .target = target_reg,
                                            .handler_index = @intCast(hi),
                                            .args = args,
                                        } });
                                        return dest;
                                    }
                                }
                            }
                        }

                        // String builtins
                        if (std.mem.eql(u8, mod_name, "String")) {
                            if (std.mem.eql(u8, fn_name, "byte_at")) {
                                if (args.len >= 2) {
                                    self.appendInst(.{ .string_byte_at = .{ .dest = dest, .str = args[0], .index = args[1] } });
                                    return dest;
                                }
                            }
                            if (std.mem.eql(u8, fn_name, "slice")) {
                                if (args.len >= 3) {
                                    const len_reg = func.newReg();
                                    self.appendInst(.{ .string_slice = .{
                                        .dest_ptr = dest,
                                        .dest_len = len_reg,
                                        .str = args[0],
                                        .start = args[1],
                                        .end = args[2],
                                    } });
                                    self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                    return dest;
                                }
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "string_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Set")) {
                            // For Set.has, also pass the needle's length
                            var set_args = std.ArrayListUnmanaged(ir.Reg){};
                            set_args.append(self.alloc, args[0]) catch {}; // set
                            if (args.len >= 2) {
                                set_args.append(self.alloc, args[1]) catch {}; // needle ptr
                                const needle_len = self.getStringLen(func, args[1]);
                                set_args.append(self.alloc, needle_len) catch {}; // needle len
                            }
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "set_has_str", .args = set_args.toOwnedSlice(self.alloc) catch &.{} } });
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
                            if (std.mem.eql(u8, fn_name, "open")) {
                                // File.open(path, mode) — need path + length
                                var file_args = std.ArrayListUnmanaged(ir.Reg){};
                                for (c.args, 0..) |arg, ai| {
                                    const areg = self.lowerExpr(arg);
                                    file_args.append(self.alloc, areg) catch {};
                                    // Add length for string args
                                    if (arg == .string_literal) {
                                        const lr = func.newReg();
                                        self.appendInst(.{ .const_int = .{ .dest = lr, .value = @intCast(arg.string_literal.len) } });
                                        file_args.append(self.alloc, lr) catch {};
                                    } else if (ai == 0) {
                                        // Path variable — need its length. For now use string_len
                                        const lr = func.newReg();
                                        self.appendInst(.{ .string_len = .{ .dest = lr, .str = areg } });
                                        file_args.append(self.alloc, lr) catch {};
                                    }
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "file_open", .args = file_args.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "file_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stream")) {
                            if (std.mem.eql(u8, fn_name, "write") or std.mem.eql(u8, fn_name, "write_line")) {
                                // Stream.write(stream, data) — need stream_ptr, data_ptr, data_len
                                var stream_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    stream_args.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                }
                                if (c.args.len >= 2) {
                                    const data_reg = self.lowerExpr(c.args[1]);
                                    stream_args.append(self.alloc, data_reg) catch {};
                                    // Add string length
                                    const len_reg = self.getStringLen(func, data_reg);
                                    stream_args.append(self.alloc, len_reg) catch {};
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "stream_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = stream_args.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "read_bytes")) {
                                // Stream.read_bytes(stream, max) → string
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "stream_read_bytes", .args = args } });
                                const len_reg = func.newReg();
                                self.appendInst(.{ .call_builtin = .{ .dest = len_reg, .name = "stream_read_bytes_len", .args = &.{} } });
                                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "read_line")) {
                                // Stream.read_line returns a string — track its length
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "stream_read_line", .args = args } });
                                // Compute string length of the result
                                const len_reg = func.newReg();
                                self.appendInst(.{ .string_len = .{ .dest = len_reg, .str = dest } });
                                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "stream_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Math")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "math_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Env")) {
                            if (std.mem.eql(u8, fn_name, "get")) {
                                // Env.get(name) — need name ptr + len
                                var env_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const name_reg = self.lowerExpr(c.args[0]);
                                    env_args.append(self.alloc, name_reg) catch {};
                                    if (c.args[0] == .string_literal) {
                                        const lr = func.newReg();
                                        self.appendInst(.{ .const_int = .{ .dest = lr, .value = @intCast(c.args[0].string_literal.len) } });
                                        env_args.append(self.alloc, lr) catch {};
                                    } else {
                                        const lr = func.newReg();
                                        self.appendInst(.{ .string_len = .{ .dest = lr, .str = name_reg } });
                                        env_args.append(self.alloc, lr) catch {};
                                    }
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "env_get", .args = env_args.toOwnedSlice(self.alloc) catch &.{} } });
                                // Track result as string
                                const len_reg = func.newReg();
                                self.appendInst(.{ .string_len = .{ .dest = len_reg, .str = dest } });
                                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "env_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "System")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "system_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Convert")) {
                            if (std.mem.eql(u8, fn_name, "to_string")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "int_to_string", .args = args } });
                                const len_reg = func.newReg();
                                self.appendInst(.{ .string_len = .{ .dest = len_reg, .str = dest } });
                                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "to_int")) {
                                // Convert.to_int(str) — need ptr + len
                                var conv_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const str_reg = self.lowerExpr(c.args[0]);
                                    conv_args.append(self.alloc, str_reg) catch {};
                                    const lr = self.getStringLen(func, str_reg);
                                    conv_args.append(self.alloc, lr) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_to_int", .args = conv_args.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "to_float")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "convert_to_float", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "to_int_f")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "convert_to_int_f", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "float_to_string")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "float_to_string", .args = args } });
                                const len_reg = func.newReg();
                                self.appendInst(.{ .string_len = .{ .dest = len_reg, .str = dest } });
                                self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "string_to_float")) {
                                var conv_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const str_reg = self.lowerExpr(c.args[0]);
                                    conv_args.append(self.alloc, str_reg) catch {};
                                    const lr = self.getStringLen(func, str_reg);
                                    conv_args.append(self.alloc, lr) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_to_float", .args = conv_args.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                        }
                        if (std.mem.eql(u8, mod_name, "Process")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "process_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Json")) {
                            // Json functions take (json_ptr, json_len, key_ptr, key_len) or (json_ptr, json_len)
                            if (std.mem.eql(u8, fn_name, "get_string") or std.mem.eql(u8, fn_name, "get_int") or
                                std.mem.eql(u8, fn_name, "get_float") or std.mem.eql(u8, fn_name, "get_bool") or
                                std.mem.eql(u8, fn_name, "get_object") or std.mem.eql(u8, fn_name, "get_array") or
                                std.mem.eql(u8, fn_name, "get_array_len"))
                            {
                                // Two string args: json data + key name
                                var json_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const data_reg = self.lowerExpr(c.args[0]);
                                    json_args.append(self.alloc, data_reg) catch {};
                                    json_args.append(self.alloc, self.getStringLen(func, data_reg)) catch {};
                                }
                                if (c.args.len >= 2) {
                                    const key_reg = self.lowerExpr(c.args[1]);
                                    json_args.append(self.alloc, key_reg) catch {};
                                    json_args.append(self.alloc, self.getStringLen(func, key_reg)) catch {};
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = json_args.toOwnedSlice(self.alloc) catch &.{} } });
                                // Track string results
                                if (std.mem.eql(u8, fn_name, "get_string") or std.mem.eql(u8, fn_name, "get_object")) {
                                    // Emit a companion call for the length
                                    const len_dest = func.newReg();
                                    var len_args = std.ArrayListUnmanaged(ir.Reg){};
                                    if (c.args.len >= 1) {
                                        const data_reg2 = self.lowerExpr(c.args[0]);
                                        len_args.append(self.alloc, data_reg2) catch {};
                                        len_args.append(self.alloc, self.getStringLen(func, data_reg2)) catch {};
                                    }
                                    if (c.args.len >= 2) {
                                        const key_reg2 = self.lowerExpr(c.args[1]);
                                        len_args.append(self.alloc, key_reg2) catch {};
                                        len_args.append(self.alloc, self.getStringLen(func, key_reg2)) catch {};
                                    }
                                    const len_name = std.fmt.allocPrint(self.alloc, "json_{s}_len", .{fn_name}) catch fn_name;
                                    self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = len_name, .args = len_args.toOwnedSlice(self.alloc) catch &.{} } });
                                    self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                }
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "to_int") or std.mem.eql(u8, fn_name, "to_float") or
                                std.mem.eql(u8, fn_name, "to_bool") or std.mem.eql(u8, fn_name, "to_string"))
                            {
                                // Single string arg: json value
                                var json_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const data_reg = self.lowerExpr(c.args[0]);
                                    json_args.append(self.alloc, data_reg) catch {};
                                    json_args.append(self.alloc, self.getStringLen(func, data_reg)) catch {};
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = json_args.toOwnedSlice(self.alloc) catch &.{} } });
                                if (std.mem.eql(u8, fn_name, "to_string")) {
                                    const len_dest = func.newReg();
                                    var len_args = std.ArrayListUnmanaged(ir.Reg){};
                                    if (c.args.len >= 1) {
                                        const data_reg2 = self.lowerExpr(c.args[0]);
                                        len_args.append(self.alloc, data_reg2) catch {};
                                        len_args.append(self.alloc, self.getStringLen(func, data_reg2)) catch {};
                                    }
                                    self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = "json_to_string_len", .args = len_args.toOwnedSlice(self.alloc) catch &.{} } });
                                    self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                }
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "parse")) {
                                // Json.parse(data, StructName) — typed struct parsing
                                // Second arg is a struct type name (identifier)
                                var json_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const d = self.lowerExpr(c.args[0]);
                                    json_args.append(self.alloc, d) catch {};
                                    json_args.append(self.alloc, self.getStringLen(func, d)) catch {};
                                }
                                // Get struct name from second argument (must be identifier)
                                var struct_name: []const u8 = "unknown";
                                if (c.args.len >= 2 and c.args[1] == .identifier) {
                                    struct_name = c.args[1].identifier;
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "json_parse_struct:{s}", .{struct_name}) catch "json_parse_struct:unknown";
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = json_args.toOwnedSlice(self.alloc) catch &.{} } });
                                // Track the tagged result as carrying this struct type
                                // When match extracts :ok{user}, user will be typed as this struct
                                self.var_types.put(self.alloc, std.fmt.allocPrint(self.alloc, "__tagged_struct_{d}", .{dest}) catch "", struct_name) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_object")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "json_build_object", .args = &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_end")) {
                                // Returns string — track length
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "json_build_end", .args = args } });
                                const len_dest = func.newReg();
                                self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = "json_build_end_len", .args = args } });
                                self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_add_string")) {
                                // (builder, key, value) — need key_ptr+len, val_ptr+len
                                var ba = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) ba.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const k = self.lowerExpr(c.args[1]);
                                    ba.append(self.alloc, k) catch {};
                                    ba.append(self.alloc, self.getStringLen(func, k)) catch {};
                                }
                                if (c.args.len >= 3) {
                                    const v = self.lowerExpr(c.args[2]);
                                    ba.append(self.alloc, v) catch {};
                                    ba.append(self.alloc, self.getStringLen(func, v)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "json_build_add_string", .args = ba.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_add_int") or std.mem.eql(u8, fn_name, "build_add_bool")) {
                                // (builder, key, value) — need key_ptr+len, value as i64
                                var ba = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) ba.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const k = self.lowerExpr(c.args[1]);
                                    ba.append(self.alloc, k) catch {};
                                    ba.append(self.alloc, self.getStringLen(func, k)) catch {};
                                }
                                if (c.args.len >= 3) ba.append(self.alloc, self.lowerExpr(c.args[2])) catch {};
                                const bname = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = bname, .args = ba.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Http")) {
                            if (std.mem.eql(u8, fn_name, "parse_request")) {
                                // Http.parse_request(data) — need data_ptr + data_len
                                var ha = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const d = self.lowerExpr(c.args[0]);
                                    ha.append(self.alloc, d) catch {};
                                    ha.append(self.alloc, self.getStringLen(func, d)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_parse_request", .args = ha.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "req_method") or std.mem.eql(u8, fn_name, "req_path") or std.mem.eql(u8, fn_name, "req_body")) {
                                // Takes request handle, returns string
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = std.fmt.allocPrint(self.alloc, "http_{s}", .{fn_name}) catch fn_name, .args = args } });
                                const len_dest = func.newReg();
                                self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = std.fmt.allocPrint(self.alloc, "http_{s}_len", .{fn_name}) catch fn_name, .args = args } });
                                self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "req_header")) {
                                // Http.req_header(req, "Header-Name") — need handle + key_ptr + key_len
                                var ha = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) ha.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const k = self.lowerExpr(c.args[1]);
                                    ha.append(self.alloc, k) catch {};
                                    ha.append(self.alloc, self.getStringLen(func, k)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_req_header", .args = ha.toOwnedSlice(self.alloc) catch &.{} } });
                                const len_dest = func.newReg();
                                var la = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) la.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const k2 = self.lowerExpr(c.args[1]);
                                    la.append(self.alloc, k2) catch {};
                                    la.append(self.alloc, self.getStringLen(func, k2)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = "http_req_header_len", .args = la.toOwnedSlice(self.alloc) catch &.{} } });
                                self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "respond")) {
                                // Http.respond(status, content_type, body) — need ct_ptr+len, body_ptr+len
                                var ha = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) ha.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const ct = self.lowerExpr(c.args[1]);
                                    ha.append(self.alloc, ct) catch {};
                                    ha.append(self.alloc, self.getStringLen(func, ct)) catch {};
                                }
                                if (c.args.len >= 3) {
                                    const bd = self.lowerExpr(c.args[2]);
                                    ha.append(self.alloc, bd) catch {};
                                    ha.append(self.alloc, self.getStringLen(func, bd)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_build_response", .args = ha.toOwnedSlice(self.alloc) catch &.{} } });
                                const len_dest = func.newReg();
                                // Re-emit args for len call
                                var la = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) la.append(self.alloc, self.lowerExpr(c.args[0])) catch {};
                                if (c.args.len >= 2) {
                                    const ct2 = self.lowerExpr(c.args[1]);
                                    la.append(self.alloc, ct2) catch {};
                                    la.append(self.alloc, self.getStringLen(func, ct2)) catch {};
                                }
                                if (c.args.len >= 3) {
                                    const bd2 = self.lowerExpr(c.args[2]);
                                    la.append(self.alloc, bd2) catch {};
                                    la.append(self.alloc, self.getStringLen(func, bd2)) catch {};
                                }
                                self.appendInst(.{ .call_builtin = .{ .dest = len_dest, .name = "http_build_response_len", .args = la.toOwnedSlice(self.alloc) catch &.{} } });
                                self.string_lens.put(self.alloc, dest, len_dest) catch {};
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "http_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Tcp")) {
                            // Tcp.connect(host, port), Tcp.listen(host, port), Tcp.accept(listener)
                            if (std.mem.eql(u8, fn_name, "open") or std.mem.eql(u8, fn_name, "listen")) {
                                // Need host ptr + host len + port
                                var tcp_args = std.ArrayListUnmanaged(ir.Reg){};
                                if (c.args.len >= 1) {
                                    const host_reg = self.lowerExpr(c.args[0]);
                                    tcp_args.append(self.alloc, host_reg) catch {};
                                    // Add host string length
                                    if (c.args[0] == .string_literal) {
                                        const lr = func.newReg();
                                        self.appendInst(.{ .const_int = .{ .dest = lr, .value = @intCast(c.args[0].string_literal.len) } });
                                        tcp_args.append(self.alloc, lr) catch {};
                                    } else {
                                        const lr = func.newReg();
                                        self.appendInst(.{ .string_len = .{ .dest = lr, .str = host_reg } });
                                        tcp_args.append(self.alloc, lr) catch {};
                                    }
                                }
                                if (c.args.len >= 2) {
                                    tcp_args.append(self.alloc, self.lowerExpr(c.args[1])) catch {};
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "tcp_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = tcp_args.toOwnedSlice(self.alloc) catch &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "accept")) {
                                // Tcp.accept(listener_stream) — pass stream ptr directly
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "tcp_accept", .args = args } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "tcp_{s}", .{fn_name}) catch fn_name;
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
                    // println/print: pass (ptr, len) pairs for all string args
                    if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
                        var builtin_args = std.ArrayListUnmanaged(ir.Reg){};
                        for (c.args) |arg| {
                            const arg_reg = self.lowerExpr(arg);
                            builtin_args.append(self.alloc, arg_reg) catch {};
                            // Add string length for string args, 0 for non-string
                            const is_string = (arg == .string_literal) or
                                (arg == .identifier and self.string_vars.get(arg.identifier) != null) or
                                (arg == .field_access and self.isStringFieldAccess(arg.field_access)) or
                                (self.string_lens.get(arg_reg) != null);
                            if (is_string) {
                                if (self.string_lens.get(arg_reg)) |lr| {
                                    builtin_args.append(self.alloc, lr) catch {};
                                } else {
                                    const lr = func.newReg();
                                    self.appendInst(.{ .string_len = .{ .dest = lr, .str = arg_reg } });
                                    builtin_args.append(self.alloc, lr) catch {};
                                }
                            } else {
                                // Non-string: mark with -1 so backend knows to format as int
                                const marker = func.newReg();
                                self.appendInst(.{ .const_int = .{ .dest = marker, .value = -1 } });
                                builtin_args.append(self.alloc, marker) catch {};
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
                            // Also append length for string elements
                            const len_reg = self.getStringLen(func, val_reg);
                            self.appendInst(.{ .list_append = .{ .list = dest, .value = len_reg } });
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
                    // Process state field access: state.field → process_state_get
                    if (std.mem.eql(u8, target_name, "state")) {
                        if (self.current_process_decl) |pdecl| {
                            if (pdecl.state_type) |st| {
                                if (self.struct_decls.get(st)) |sd| {
                                    for (sd.fields, 0..) |f, fi| {
                                        if (std.mem.eql(u8, f.name, fa.field)) {
                                            const dest = func.newReg();
                                            self.appendInst(.{ .process_state_get = .{ .dest = dest, .field_index = @intCast(fi) } });
                                            return dest;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (self.var_types.get(target_name)) |type_name| {
                        if (self.struct_decls.get(type_name)) |sd| {
                            for (sd.fields, 0..) |f, fi| {
                                if (std.mem.eql(u8, f.name, fa.field)) {
                                    const base_reg = self.lowerExpr(fa.target.*);
                                    const dest = func.newReg();
                                    self.appendInst(.{ .struct_load = .{ .dest = dest, .base = base_reg, .field_index = @intCast(fi) } });
                                    // If this field is a string type, track it
                                    if (f.type_expr == .simple and std.mem.eql(u8, f.type_expr.simple, "string")) {
                                        // Use strlen at runtime since struct doesn't store length
                                        const len_reg = func.newReg();
                                        self.appendInst(.{ .string_len = .{ .dest = len_reg, .str = dest } });
                                        self.string_lens.put(self.alloc, dest, len_reg) catch {};
                                    }
                                    return dest;
                                }
                            }
                        }
                    }
                    if (std.mem.eql(u8, fa.field, "len")) {
                        // Check if it's a string .len or list .len
                        if (self.string_vars.get(target_name) != null) {
                            const str_reg = self.lowerExpr(fa.target.*);
                            const dest = func.newReg();
                            self.appendInst(.{ .string_len = .{ .dest = dest, .str = str_reg } });
                            return dest;
                        }
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
                // Check if target is a known string variable — use byte access
                if (ia.target.* == .identifier) {
                    if (self.string_vars.get(ia.target.identifier) != null) {
                        // s[i] returns a single-char string (pointer), not byte value
                        self.appendInst(.{ .string_index = .{ .dest = dest, .str = target_reg, .index = index_reg } });
                        // The result is a 1-byte string
                        const len_reg = func.newReg();
                        self.appendInst(.{ .const_int = .{ .dest = len_reg, .value = 1 } });
                        self.string_lens.put(self.alloc, dest, len_reg) catch {};
                        return dest;
                    }
                }
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

    /// Get the string length register for a value. Uses tracked length if available,
    /// otherwise emits a string_len instruction (strlen at runtime).
    fn isStringFieldAccess(self: *Lower, fa: ast.FieldAccess) bool {
        if (fa.target.* == .identifier) {
            if (self.var_types.get(fa.target.identifier)) |type_name| {
                if (self.struct_decls.get(type_name)) |sd| {
                    for (sd.fields) |f| {
                        if (std.mem.eql(u8, f.name, fa.field)) {
                            return f.type_expr == .simple and std.mem.eql(u8, f.type_expr.simple, "string");
                        }
                    }
                }
            }
        }
        return false;
    }

    fn getStringLen(self: *Lower, func: *ir.Function, str_reg: ir.Reg) ir.Reg {
        if (self.string_lens.get(str_reg)) |lr| return lr;
        const lr = func.newReg();
        self.appendInst(.{ .string_len = .{ .dest = lr, .str = str_reg } });
        return lr;
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
