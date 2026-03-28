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
    enum_decls: std.StringHashMapUnmanaged([]const []const u8), // enum name → variant list
    union_decls: std.StringHashMapUnmanaged([]const ast.UnionVariant), // union name → variant list
    var_types: std.StringHashMapUnmanaged([]const u8), // variable name → type name ("int", "float", "string", "bool", or struct name)
    float_regs: std.AutoHashMapUnmanaged(ir.Reg, void), // registers holding float values
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
            .enum_decls = .{},
            .union_decls = .{},
            .var_types = .{},
            .float_regs = .{},
            .loop_cond_block = null,
            .loop_exit_block = null,
            .process_decls = .{},
            .process_vars = .{},
            .current_process_decl = null,
        };
    }

    fn curBlock(self: *Lower) ?*ir.Block {
        const func = self.current_fn orelse return null;
        const bid = self.current_block_id orelse return null;
        return func.getBlock(bid);
    }

    fn appendInst(self: *Lower, inst: ir.Inst) void {
        if (self.curBlock()) |b| b.append(inst);
    }

    pub fn lowerFile(self: *Lower, file: ast.File) !ir.Program {
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| try self.struct_decls.put(self.alloc, s.name, s),
                .process_decl => |p| try self.process_decls.put(self.alloc, p.name, p),
                .type_decl => |td| {
                    if (td.value == .enum_type) {
                        try self.enum_decls.put(self.alloc, td.name, td.value.enum_type);
                        try self.program.enum_decls.append(self.alloc, .{
                            .name = td.name,
                            .variants = td.value.enum_type,
                        });
                    } else if (td.value == .union_type) {
                        try self.union_decls.put(self.alloc, td.name, td.value.union_type);
                        var variant_infos = std.ArrayListUnmanaged(ir.UnionVariantInfo){};
                        for (td.value.union_type) |v| {
                            const has_value = v.fields.len > 0;
                            const value_type: []const u8 = if (has_value) switch (v.fields[0].type_expr) {
                                .simple => |tn| tn,
                                else => "unknown",
                            } else "void";
                            try variant_infos.append(self.alloc, .{
                                .tag = v.tag,
                                .has_value = has_value,
                                .value_type = value_type,
                            });
                        }
                        try self.program.union_decls.append(self.alloc, .{
                            .name = td.name,
                            .variants = try variant_infos.toOwnedSlice(self.alloc),
                        });
                    }
                },
                else => {},
            }
        }
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
                        .state_type = p.state_type,
                        .state_fields = try state_fields.toOwnedSlice(self.alloc),
                        .handler_names = try handler_names.toOwnedSlice(self.alloc),
                    });
                },
                else => {},
            }
        }
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
                        if (func.doc_comment) |doc| {
                            var example_idx: usize = 0;
                            var line_start: usize = 0;
                            while (line_start < doc.len) {
                                var line_end = line_start;
                                while (line_end < doc.len and doc[line_end] != '\n') line_end += 1;
                                const line_ = doc[line_start..line_end];
                                if (std.mem.indexOf(u8, line_, "@example ")) |idx| {
                                    const example_text = std.mem.trim(u8, line_[idx + 9 ..], " \t\r");
                                    if (example_text.len > 0) {
                                        const assert_src = std.fmt.allocPrint(self.alloc, "assert {s};", .{example_text}) catch "";
                                        var example_parser = @import("parser.zig").Parser.init(assert_src, self.alloc);
                                        if (example_parser.parseStmt()) |stmt| {
                                            const test_name = std.fmt.allocPrint(self.alloc, "@example {s}.{s} #{d}", .{ m.name, func.name, example_idx }) catch "example";
                                            const test_fn_name = std.fmt.allocPrint(self.alloc, "__example_{s}_{d}", .{ func.name, example_idx }) catch "example";
                                            const body = self.alloc.alloc(ast.Stmt, 1) catch continue;
                                            body[0] = stmt;
                                            const example_fn = ast.FnDecl{
                                                .name = test_fn_name,
                                                .params = &.{},
                                                .return_type = .{ .simple = "int" },
                                                .guards = &.{},
                                                .body = body,
                                                .doc_comment = null,
                                                .examples = &.{},
                                                .properties = &.{},
                                                .span = .{ .start = 0, .end = 0 },
                                            };
                                            self.lowerFunction(m.name, example_fn) catch {};
                                            self.program.test_names.append(self.alloc, test_name) catch {};
                                            self.program.test_modules.append(self.alloc, m.name) catch {};
                                            self.program.test_fn_names.append(self.alloc, test_fn_name) catch {};
                                            example_idx += 1;
                                        } else |_| {}
                                    }
                                }
                                line_start = if (line_end < doc.len) line_end + 1 else line_end;
                            }
                        }
                    }
                    for (m.tests, 0..) |t, ti| {
                        const test_fn = ast.FnDecl{
                            .name = std.fmt.allocPrint(self.alloc, "__test_{d}", .{ti}) catch "test",
                            .params = &.{},
                            .return_type = .{ .simple = "int" },
                            .guards = &.{},
                            .body = t.body,
                            .doc_comment = null,
                            .examples = &.{},
                            .properties = &.{},
                            .span = t.span,
                        };
                        try self.lowerFunction(m.name, test_fn);
                        try self.program.test_names.append(self.alloc, t.name);
                        try self.program.test_modules.append(self.alloc, m.name);
                        try self.program.test_fn_names.append(self.alloc, test_fn.name);
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

        self.float_regs = .{};

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (func.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    self.var_types.put(self.alloc, p.name, tn) catch {};
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

        self.float_regs = .{};

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        const skip_state = proc_decl.state_type != null and handler.params.len > 0 and
            std.mem.eql(u8, handler.params[0].name, "state");
        const user_params = if (skip_state) handler.params[1..] else handler.params;
        for (user_params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    self.var_types.put(self.alloc, p.name, tn) catch {};
                },
                else => {},
            }
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = resolveType(handler.return_type);

        self.current_fn = &f;
        self.current_process_decl = proc_decl;
        const entry = f.newBlock();
        self.current_block_id = entry.id;

        for (handler.guards) |guard_expr| {
            const guard_reg = self.lowerExpr(guard_expr);
            const pass_id = f.newBlock().id;
            const fail_id = f.newBlock().id;
            self.appendInst(.{ .branch = .{ .cond = guard_reg, .then_block = pass_id, .else_block = fail_id } });
            self.current_block_id = fail_id;
            const tag_id_reg = f.newReg();
            self.appendInst(.{ .const_int = .{ .dest = tag_id_reg, .value = 1 } });
            const val_reg = f.newReg();
            self.appendInst(.{ .const_int = .{ .dest = val_reg, .value = 99 } });
            const tagged_reg = f.newReg();
            self.appendInst(.{ .call_builtin = .{ .dest = tagged_reg, .name = "make_tagged", .args = blk: {
                const a = self.alloc.alloc(ir.Reg, 2) catch break :blk &.{};
                a[0] = tag_id_reg;
                a[1] = val_reg;
                break :blk a;
            } } });
            self.appendInst(.{ .ret = .{ .value = tagged_reg } });
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
                if (a.value == .call) {
                    if (a.value.call.target.* == .identifier and std.mem.eql(u8, a.value.call.target.identifier, "spawn")) {
                        if (a.value.call.args.len > 0 and a.value.call.args[0] == .string_literal) {
                            const proc_name = a.value.call.args[0].string_literal;
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
                if (self.float_regs.get(reg) != null) {
                    self.var_types.put(self.alloc, a.name, "float") catch {};
                }
                if (self.isStringExpr(a.value)) {
                    self.var_types.put(self.alloc, a.name, "string") catch {};
                }
                if (a.type_expr) |te| {
                    switch (te) {
                        .simple => |tn| self.var_types.put(self.alloc, a.name, tn) catch {},
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

                // Determine if match subject is an enum type
                const subject_enum_variants: ?[]const []const u8 = blk: {
                    if (m.subject == .identifier) {
                        if (self.var_types.get(m.subject.identifier)) |type_name| {
                            if (self.enum_decls.get(type_name)) |variants| {
                                break :blk variants;
                            }
                        }
                    }
                    // Handle field access: a.currency where currency is an enum field
                    if (m.subject == .field_access) {
                        const fa = m.subject.field_access;
                        if (fa.target.* == .identifier) {
                            if (self.var_types.get(fa.target.identifier)) |struct_type| {
                                if (self.struct_decls.get(struct_type)) |sd| {
                                    for (sd.fields) |f| {
                                        if (std.mem.eql(u8, f.name, fa.field)) {
                                            const field_type = switch (f.type_expr) {
                                                .simple => |tn| tn,
                                                else => break,
                                            };
                                            if (self.enum_decls.get(field_type)) |variants| {
                                                break :blk variants;
                                            }
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    break :blk null;
                };

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
                            if (subject_enum_variants) |variants| {
                                // Enum match: compare subject directly against variant index
                                var tag_id: i64 = -1;
                                for (variants, 0..) |variant, i| {
                                    if (std.mem.eql(u8, variant, t.tag)) {
                                        tag_id = @intCast(i);
                                        break;
                                    }
                                }
                                const id_reg = func.newReg();
                                self.appendInst(.{ .const_int = .{ .dest = id_reg, .value = tag_id } });
                                const cmp_reg = func.newReg();
                                self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = subject_reg, .rhs = id_reg } });
                                const arm_id = func.newBlock().id;
                                const next_id = func.newBlock().id;
                                self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                                self.current_block_id = arm_id;
                                for (arm.body) |s| self.lowerStmt(s);
                                self.appendInst(.{ .jump = .{ .target = merge_id } });
                                self.current_block_id = next_id;
                            } else {
                                // Tagged union match (Result, custom unions, etc.): extract tag from tagged value
                                const tag_reg = func.newReg();
                                self.appendInst(.{ .tag_get = .{ .dest = tag_reg, .tagged = subject_reg } });
                                const tag_id = self.resolveTagId(t.tag);
                                const id_reg = func.newReg();
                                self.appendInst(.{ .const_int = .{ .dest = id_reg, .value = tag_id } });
                                const cmp_reg = func.newReg();
                                self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = tag_reg, .rhs = id_reg } });
                                const arm_id = func.newBlock().id;
                                const next_id = func.newBlock().id;
                                self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                                self.current_block_id = arm_id;
                                if (t.bindings.len > 0) {
                                    // Determine if this variant carries a string value
                                    const is_string_variant = blk: {
                                        var uiter = self.union_decls.iterator();
                                        while (uiter.next()) |entry| {
                                            for (entry.value_ptr.*) |variant| {
                                                if (std.mem.eql(u8, variant.tag, t.tag)) {
                                                    if (variant.fields.len > 0) {
                                                        if (variant.fields[0].type_expr == .simple and
                                                            std.mem.eql(u8, variant.fields[0].type_expr.simple, "string"))
                                                        {
                                                            break :blk true;
                                                        }
                                                    }
                                                    break :blk false;
                                                }
                                            }
                                        }
                                        break :blk false;
                                    };
                                    const val_reg = func.newReg();
                                    if (is_string_variant) {
                                        self.appendInst(.{ .tag_value_str = .{ .dest = val_reg, .tagged = subject_reg } });
                                        self.var_types.put(self.alloc, t.bindings[0], "string") catch {};
                                    } else {
                                        self.appendInst(.{ .tag_value = .{ .dest = val_reg, .tagged = subject_reg } });
                                    }
                                    self.appendInst(.{ .store_local = .{ .name = t.bindings[0], .src = val_reg } });
                                    const tag_key = std.fmt.allocPrint(self.alloc, "__tagged_struct_{d}", .{subject_reg}) catch "";
                                    if (self.var_types.get(tag_key)) |struct_type| {
                                        self.var_types.put(self.alloc, t.bindings[0], struct_type) catch {};
                                    }
                                }
                                for (arm.body) |s| self.lowerStmt(s);
                                self.appendInst(.{ .jump = .{ .target = merge_id } });
                                self.current_block_id = next_id;
                            }
                        },
                    }
                }
                self.appendInst(.{ .jump = .{ .target = merge_id } });
                self.current_block_id = merge_id;
            },
            .field_assign => |fa| {
                if (fa.target == .field_access) {
                    const field_name = fa.target.field_access.field;
                    if (fa.target.field_access.target.* == .identifier and
                        std.mem.eql(u8, fa.target.field_access.target.identifier, "state"))
                    {
                        if (self.current_process_decl) |pdecl| {
                            if (pdecl.state_type) |st| {
                                if (self.struct_decls.get(st)) |sd| {
                                    for (sd.fields) |f| {
                                        if (std.mem.eql(u8, f.name, field_name)) {
                                            const val_reg = self.lowerExpr(fa.value);
                                            self.appendInst(.{ .process_state_set = .{ .struct_name = st, .field_name = f.name, .src = val_reg } });
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
            .assert_stmt => |a| {
                const cond_reg = self.lowerExpr(a.condition);
                const dest = func.newReg();
                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "assert_check", .args = blk: {
                    const args = self.alloc.alloc(ir.Reg, 1) catch break :blk &.{};
                    args[0] = cond_reg;
                    break :blk args;
                } } });
            },
            else => {},
        }
    }

    // ── Expressions ──────────────────────────────────────────

    /// Resolve a tag name to its integer ID across enums, unions, and builtins.
    fn resolveTagId(self: *Lower, tag_name: []const u8) i64 {
        // Check enum declarations
        var iter = self.enum_decls.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.*, 0..) |variant, i| {
                if (std.mem.eql(u8, variant, tag_name)) return @intCast(i);
            }
        }
        // Check union declarations
        var uiter = self.union_decls.iterator();
        while (uiter.next()) |entry| {
            for (entry.value_ptr.*, 0..) |variant, i| {
                if (std.mem.eql(u8, variant.tag, tag_name)) return @intCast(i);
            }
        }
        // Built-in tags
        if (std.mem.eql(u8, tag_name, "ok")) return 0;
        if (std.mem.eql(u8, tag_name, "error")) return 1;
        if (std.mem.eql(u8, tag_name, "eof")) return 2;
        return -1;
    }

    fn isStringExpr(self: *Lower, expr: ast.Expr) bool {
        return switch (expr) {
            .string_literal => true,
            .identifier => |name| self.isVarString(name),
            .field_access => |fa| self.isStringFieldAccess(fa),
            .call => |c| {
                if (c.target.* == .field_access) {
                    const mod = c.target.field_access.target;
                    const fn_name = c.target.field_access.field;
                    if (mod.* == .identifier) {
                        const mn = mod.identifier;
                        if (std.mem.eql(u8, mn, "String")) {
                            return std.mem.eql(u8, fn_name, "trim") or std.mem.eql(u8, fn_name, "replace") or
                                std.mem.eql(u8, fn_name, "char_at") or std.mem.eql(u8, fn_name, "slice");
                        }
                        if (std.mem.eql(u8, mn, "Convert")) {
                            return std.mem.eql(u8, fn_name, "to_string") or std.mem.eql(u8, fn_name, "float_to_string");
                        }
                        if (std.mem.eql(u8, mn, "Stream")) {
                            return std.mem.eql(u8, fn_name, "read_line") or std.mem.eql(u8, fn_name, "read_bytes");
                        }
                        if (std.mem.eql(u8, mn, "Env")) return std.mem.eql(u8, fn_name, "get");
                        if (std.mem.eql(u8, mn, "Json")) {
                            return std.mem.eql(u8, fn_name, "get_string") or std.mem.eql(u8, fn_name, "get_object") or
                                std.mem.eql(u8, fn_name, "to_string") or std.mem.eql(u8, fn_name, "build_end");
                        }
                        if (std.mem.eql(u8, mn, "Http")) {
                            return std.mem.eql(u8, fn_name, "req_method") or std.mem.eql(u8, fn_name, "req_path") or
                                std.mem.eql(u8, fn_name, "req_body") or std.mem.eql(u8, fn_name, "req_header") or
                                std.mem.eql(u8, fn_name, "respond") or std.mem.eql(u8, fn_name, "read_request");
                        }
                    }
                }
                return false;
            },
            .binary_op => |op| {
                if (op.op == .add) {
                    return self.isStringExpr(op.left.*) or self.isStringExpr(op.right.*);
                }
                return false;
            },
            else => false,
        };
    }

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
                return dest;
            },
            .tag => |tag_name| {
                // Look up the variant index across all enum declarations
                const dest = func.newReg();
                const tag_id = self.resolveTagId(tag_name);
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = tag_id } });
                return dest;
            },
            .tagged_value => |tv| {
                // Construct a tagged value: :tag{expr} → makeTagged(tag_id, value)
                const dest = func.newReg();
                const tag_id = self.resolveTagId(tv.tag);
                const tag_id_reg = func.newReg();
                self.appendInst(.{ .const_int = .{ .dest = tag_id_reg, .value = tag_id } });
                const val_reg = if (tv.value) |v| self.lowerExpr(v.*) else blk: {
                    const zero = func.newReg();
                    self.appendInst(.{ .const_int = .{ .dest = zero, .value = 0 } });
                    break :blk zero;
                };
                var args = self.alloc.alloc(ir.Reg, 2) catch return dest;
                args[0] = tag_id_reg;
                args[1] = val_reg;
                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "make_tagged", .args = args } });
                return dest;
            },
            .identifier => |name| {
                const dest = func.newReg();
                self.appendInst(.{ .load_local = .{ .dest = dest, .name = name } });
                if (self.isVarFloat(name)) {
                    self.float_regs.put(self.alloc, dest, {}) catch {};
                }
                return dest;
            },
            .binary_op => |op| {
                // String comparison
                if (op.op == .eq or op.op == .neq) {
                    if (self.isStringExpr(op.left.*) or self.isStringExpr(op.right.*)) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const dest = func.newReg();
                        self.appendInst(.{ .string_eq = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
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
                    if (self.isStringExpr(op.left.*) or self.isStringExpr(op.right.*)) {
                        const lhs = self.lowerExpr(op.left.*);
                        const rhs = self.lowerExpr(op.right.*);
                        const dest = func.newReg();
                        var concat_args = std.ArrayListUnmanaged(ir.Reg){};
                        concat_args.append(self.alloc, lhs) catch {};
                        concat_args.append(self.alloc, rhs) catch {};
                        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_concat", .args = concat_args.toOwnedSlice(self.alloc) catch &.{} } });
                        return dest;
                    }
                }
                const lhs = self.lowerExpr(op.left.*);
                const rhs = self.lowerExpr(op.right.*);
                const dest = func.newReg();
                const is_float = self.float_regs.get(lhs) != null or self.float_regs.get(rhs) != null or
                    (op.left.* == .float_literal) or (op.right.* == .float_literal) or
                    (op.left.* == .identifier and self.isVarFloat(op.left.identifier)) or
                    (op.right.* == .identifier and self.isVarFloat(op.right.identifier));
                const inst_val: ir.Inst = if (is_float) switch (op.op) {
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
                self.appendInst(inst_val);
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
                    (op.operand.* == .identifier and self.isVarFloat(op.operand.identifier));
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

                        // Process send
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

                        // User-defined modules take priority
                        var is_user_module = false;
                        for (self.program.functions.items) |f| {
                            if (std.mem.eql(u8, f.module, mod_name)) {
                                is_user_module = true;
                                break;
                            }
                        }
                        if (is_user_module) {
                            self.appendInst(.{ .call = .{ .dest = dest, .module = mod_name, .function = fn_name, .args = args } });
                            return dest;
                        }

                        // Built-in modules — all simplified: just pass registers directly
                        if (std.mem.eql(u8, mod_name, "String")) {
                            if (std.mem.eql(u8, fn_name, "byte_at")) {
                                if (args.len >= 2) {
                                    self.appendInst(.{ .string_byte_at = .{ .dest = dest, .str = args[0], .index = args[1] } });
                                    return dest;
                                }
                            }
                            if (std.mem.eql(u8, fn_name, "slice")) {
                                if (args.len >= 3) {
                                    self.appendInst(.{ .string_slice = .{ .dest = dest, .str = args[0], .start = args[1], .end = args[2] } });
                                    return dest;
                                }
                            }
                            if (std.mem.eql(u8, fn_name, "len")) {
                                if (args.len >= 1) {
                                    self.appendInst(.{ .string_len = .{ .dest = dest, .str = args[0] } });
                                    return dest;
                                }
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "string_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Set")) {
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "set_has_str", .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Map") or std.mem.eql(u8, mod_name, "Stack") or std.mem.eql(u8, mod_name, "Queue")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "{s}_{s}", .{ if (std.mem.eql(u8, mod_name, "Map")) "map" else if (std.mem.eql(u8, mod_name, "Stack")) "stack" else "queue", fn_name }) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stdio")) {
                            if (std.mem.eql(u8, fn_name, "println") or std.mem.eql(u8, fn_name, "print")) {
                                // Each arg is a single register — the backend checks its type
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = fn_name, .args = args } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "stdio_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "File")) {
                            if (std.mem.eql(u8, fn_name, "open")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "file_open", .args = args } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "file_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Stream")) {
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
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "env_get", .args = args } });
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
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "to_int")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_to_int", .args = args } });
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
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "string_to_float")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_to_float", .args = args } });
                                return dest;
                            }
                        }
                        if (std.mem.eql(u8, mod_name, "Process")) {
                            const builtin_name = std.fmt.allocPrint(self.alloc, "process_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Json")) {
                            if (std.mem.eql(u8, fn_name, "parse")) {
                                var struct_name: []const u8 = "unknown";
                                if (c.args.len >= 2 and c.args[1] == .identifier) {
                                    struct_name = c.args[1].identifier;
                                }
                                const builtin_name = std.fmt.allocPrint(self.alloc, "json_parse_struct:{s}", .{struct_name}) catch "json_parse_struct:unknown";
                                // Only pass the data arg, not the struct name
                                const data_args = self.alloc.alloc(ir.Reg, 1) catch return dest;
                                data_args[0] = args[0];
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = data_args } });
                                self.var_types.put(self.alloc, std.fmt.allocPrint(self.alloc, "__tagged_struct_{d}", .{dest}) catch "", struct_name) catch {};
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_object")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "json_build_object", .args = &.{} } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_end")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "json_build_end", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "build_add_string") or std.mem.eql(u8, fn_name, "build_add_int") or std.mem.eql(u8, fn_name, "build_add_bool") or std.mem.eql(u8, fn_name, "build_add_float")) {
                                const builtin_name = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "json_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Http")) {
                            if (std.mem.eql(u8, fn_name, "respond")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_build_response", .args = args } });
                                return dest;
                            }
                            if (std.mem.eql(u8, fn_name, "parse_request")) {
                                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_parse_request", .args = args } });
                                return dest;
                            }
                            const builtin_name = std.fmt.allocPrint(self.alloc, "http_{s}", .{fn_name}) catch fn_name;
                            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
                            return dest;
                        }
                        if (std.mem.eql(u8, mod_name, "Tcp")) {
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
                    if (std.mem.eql(u8, name, "list")) {
                        self.appendInst(.{ .list_new = .{ .dest = dest } });
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "set")) {
                        self.appendInst(.{ .list_new = .{ .dest = dest } });
                        for (c.args) |arg| {
                            const val_reg = self.lowerExpr(arg);
                            // Sets store (ptr, len) pairs for string elements
                            // We need to convert []const u8 to ptr+len for the list
                            // The list stores i64 values, so we store ptr and len separately
                            self.appendInst(.{ .list_append = .{ .list = dest, .value = val_reg } });
                            // Also append length for string elements (by adding a len marker)
                            // For the set_has_str builtin to work, we need ptr+len pairs
                            // Since val_reg is a []const u8 in the new system, the backend
                            // will handle conversion at the list_append boundary
                        }
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "map") or std.mem.eql(u8, name, "stack") or std.mem.eql(u8, name, "queue") or std.mem.eql(u8, name, "spawn")) {
                        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = name, .args = args } });
                        return dest;
                    }
                    self.appendInst(.{ .call = .{ .dest = dest, .module = self.current_module, .function = name, .args = args } });
                    return dest;
                }
                return dest;
            },
            .struct_literal => |sl| {
                const base = func.newReg();
                self.appendInst(.{ .struct_alloc = .{ .dest = base, .struct_name = sl.name } });

                if (self.struct_decls.get(sl.name)) |d| {
                    for (d.fields) |df| {
                        for (sl.fields) |lf| {
                            if (std.mem.eql(u8, lf.name, df.name)) {
                                const val_reg = self.lowerExpr(lf.value);
                                self.appendInst(.{ .struct_store = .{ .base = base, .struct_name = sl.name, .field_name = df.name, .src = val_reg } });
                                break;
                            }
                        }
                    }
                } else {
                    for (sl.fields) |lf| {
                        const val_reg = self.lowerExpr(lf.value);
                        self.appendInst(.{ .struct_store = .{ .base = base, .struct_name = sl.name, .field_name = lf.name, .src = val_reg } });
                    }
                }
                return base;
            },
            .field_access => |fa| {
                if (fa.target.* == .identifier) {
                    const target_name = fa.target.identifier;
                    // Process state field access
                    if (std.mem.eql(u8, target_name, "state")) {
                        if (self.current_process_decl) |pdecl| {
                            if (pdecl.state_type) |st| {
                                if (self.struct_decls.get(st)) |sd| {
                                    for (sd.fields) |f| {
                                        if (std.mem.eql(u8, f.name, fa.field)) {
                                            const dest = func.newReg();
                                            self.appendInst(.{ .process_state_get = .{ .dest = dest, .struct_name = st, .field_name = f.name } });
                                            return dest;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (self.var_types.get(target_name)) |type_name| {
                        if (self.struct_decls.get(type_name)) |sd| {
                            for (sd.fields) |f| {
                                if (std.mem.eql(u8, f.name, fa.field)) {
                                    const base_reg = self.lowerExpr(fa.target.*);
                                    const dest = func.newReg();
                                    self.appendInst(.{ .struct_load = .{ .dest = dest, .base = base_reg, .struct_name = type_name, .field_name = f.name } });
                                    return dest;
                                }
                            }
                        }
                    }
                    if (std.mem.eql(u8, fa.field, "len")) {
                        if (self.isVarString(target_name)) {
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
                if (ia.target.* == .identifier) {
                    if (self.isVarString(ia.target.identifier)) {
                        self.appendInst(.{ .string_index = .{ .dest = dest, .str = target_reg, .index = index_reg } });
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

    fn isVarString(self: *Lower, name: []const u8) bool {
        const t = self.var_types.get(name) orelse return false;
        return std.mem.eql(u8, t, "string");
    }

    fn isVarFloat(self: *Lower, name: []const u8) bool {
        const t = self.var_types.get(name) orelse return false;
        return std.mem.eql(u8, t, "float");
    }

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
