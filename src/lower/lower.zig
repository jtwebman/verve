const std = @import("std");
const ast = @import("../ast.zig");
const ir = @import("../ir.zig");
const builtins = @import("builtins.zig");
const generics = @import("generics.zig");

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
    generic_struct_decls: std.StringHashMapUnmanaged(ast.StructDecl), // base name → generic struct def
    monomorphized: std.StringHashMapUnmanaged(void), // "Pair_int" → () — tracks emitted specializations
    pending_generic_name: ?[]const u8, // set during assignment to pass monomorphized name to struct literal
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
            .generic_struct_decls = .{},
            .monomorphized = .{},
            .pending_generic_name = null,
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

    pub fn appendInst(self: *Lower, inst: ir.Inst) void {
        if (self.curBlock()) |b| b.append(inst);
    }

    pub fn lowerFile(self: *Lower, file: ast.File) !ir.Program {
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| {
                    if (s.type_params.len > 0) {
                        // Generic struct — store for on-demand instantiation
                        try self.generic_struct_decls.put(self.alloc, s.name, s);
                    } else {
                        try self.struct_decls.put(self.alloc, s.name, s);
                    }
                },
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
                        .mailbox_size = if (p.mailbox_size) |s| @intCast(s) else 64,
                    });
                },
                else => {},
            }
        }
        for (file.decls) |decl| {
            switch (decl) {
                .struct_decl => |s| {
                    // Skip generic structs — they're instantiated on demand
                    if (s.type_params.len > 0) continue;
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
                                        var example_parser = @import("../parser.zig").Parser.init(assert_src, self.alloc);
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
        self.fixupRegTypes();
        return self.program;
    }

    fn lowerFunction(self: *Lower, module: []const u8, func: ast.FnDecl) !void {
        var f = ir.Function.init(module, func.name, self.alloc);

        self.float_regs = .{};

        var params = std.ArrayListUnmanaged(ir.Function.Param){};
        for (func.params) |p| {
            try params.append(self.alloc, .{ .name = p.name, .type_ = self.resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    self.var_types.put(self.alloc, p.name, tn) catch {};
                },
                .generic => |g| {
                    if (std.mem.eql(u8, g.name, "pid") and g.args.len == 1 and g.args[0] == .simple) {
                        self.process_vars.put(self.alloc, p.name, g.args[0].simple) catch {};
                    } else if (self.generic_struct_decls.get(g.name) != null) {
                        const mono_name = generics.instantiateGenericStruct(self, g.name, g.args) catch g.name;
                        self.var_types.put(self.alloc, p.name, mono_name) catch {};
                    }
                },
                else => {},
            }
        }
        f.params = try params.toOwnedSlice(self.alloc);
        f.return_type = self.resolveType(func.return_type);

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
            try params.append(self.alloc, .{ .name = p.name, .type_ = self.resolveType(p.type_expr) });
            switch (p.type_expr) {
                .simple => |tn| {
                    self.var_types.put(self.alloc, p.name, tn) catch {};
                },
                else => {},
            }
        }
        f.params = try params.toOwnedSlice(self.alloc);
        const resolved_ret = self.resolveType(handler.return_type);
        // Non-main handlers always return tagged values (pointers) at runtime.
        // Main handler returns its declared type directly.
        if (std.mem.eql(u8, handler.name, "main")) {
            f.return_type = resolved_ret;
        } else {
            f.return_type = .ptr;
        }

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
            const tag_id_reg = f.newReg(.i64);
            self.appendInst(.{ .const_int = .{ .dest = tag_id_reg, .value = 1 } });
            const val_reg = f.newReg(.i64);
            self.appendInst(.{ .const_int = .{ .dest = val_reg, .value = 99 } });
            const tagged_reg = f.newReg(.ptr);
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
                                    const dest = func.newReg(.i64);
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
                // If type annotation is generic, instantiate and set context
                if (a.type_expr) |te| {
                    if (te == .generic) {
                        const g = te.generic;
                        if (std.mem.eql(u8, g.name, "pid") and g.args.len == 1 and g.args[0] == .simple) {
                            self.process_vars.put(self.alloc, a.name, g.args[0].simple) catch {};
                        } else if (self.generic_struct_decls.get(g.name) != null) {
                            const mono_name = generics.instantiateGenericStruct(self, g.name, g.args) catch g.name;
                            self.pending_generic_name = mono_name;
                            self.var_types.put(self.alloc, a.name, mono_name) catch {};
                        }
                    }
                }
                var reg = self.lowerExpr(a.value);
                self.pending_generic_name = null;
                // Optional type: wrap non-none values in :some{value}
                if (a.type_expr) |te| {
                    if (te == .optional and a.value != .none_literal) {
                        const wrapped = func.newReg(.ptr);
                        const tag_reg = func.newReg(.i64);
                        self.appendInst(.{ .const_int = .{ .dest = tag_reg, .value = 0 } }); // some=0
                        self.appendInst(.{ .call_builtin = .{ .dest = wrapped, .name = "make_tagged", .args = self.allocRegs(&.{ tag_reg, reg }) } });
                        reg = wrapped;
                    }
                }
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
                        .generic => |g| {
                            // User-defined generics handled above; track collection types
                            if (self.generic_struct_decls.get(g.name) == null) {
                                const full_name = generics.formatGenericTypeName(self, g.name, g.args);
                                self.var_types.put(self.alloc, a.name, full_name) catch {};
                            }
                        },
                        .optional => |inner| {
                            const inner_name = generics.typeExprName(self, inner.*);
                            const opt_name = std.fmt.allocPrint(self.alloc, "optional_{s}", .{inner_name}) catch "__optional";
                            self.var_types.put(self.alloc, a.name, opt_name) catch {};
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
                self.appendInst(.{ .yield_check = {} }); // preemption point at loop back-edge
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
                            if (lit == .none_literal) {
                                // none pattern: check tag == 1 (none tag)
                                const tag_reg = func.newReg(.i64);
                                self.appendInst(.{ .tag_get = .{ .dest = tag_reg, .tagged = subject_reg } });
                                const one_reg = func.newReg(.i64);
                                self.appendInst(.{ .const_int = .{ .dest = one_reg, .value = 1 } });
                                const cmp_reg = func.newReg(.bool);
                                self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = tag_reg, .rhs = one_reg } });
                                const arm_id = func.newBlock().id;
                                const next_id = func.newBlock().id;
                                self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                                self.current_block_id = arm_id;
                                for (arm.body) |s| self.lowerStmt(s);
                                self.appendInst(.{ .jump = .{ .target = merge_id } });
                                self.current_block_id = next_id;
                                continue;
                            }
                            const pat_reg = self.lowerExpr(lit);
                            const cmp_reg = func.newReg(.bool);
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
                                const id_reg = func.newReg(.i64);
                                self.appendInst(.{ .const_int = .{ .dest = id_reg, .value = tag_id } });
                                const cmp_reg = func.newReg(.bool);
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
                                const tag_reg = func.newReg(.i64);
                                self.appendInst(.{ .tag_get = .{ .dest = tag_reg, .tagged = subject_reg } });
                                const tag_id = self.resolveTagId(t.tag);
                                const id_reg = func.newReg(.i64);
                                self.appendInst(.{ .const_int = .{ .dest = id_reg, .value = tag_id } });
                                const cmp_reg = func.newReg(.bool);
                                self.appendInst(.{ .eq_i64 = .{ .dest = cmp_reg, .lhs = tag_reg, .rhs = id_reg } });
                                const arm_id = func.newBlock().id;
                                const next_id = func.newBlock().id;
                                self.appendInst(.{ .branch = .{ .cond = cmp_reg, .then_block = arm_id, .else_block = next_id } });
                                self.current_block_id = arm_id;
                                if (t.bindings.len > 0) {
                                    // Determine if this variant carries a string value
                                    const is_string_variant = blk: {
                                        // Check union declarations
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
                                        // Check optional types: :some on optional_string
                                        if (std.mem.eql(u8, t.tag, "some")) {
                                            if (m.subject == .identifier) {
                                                if (self.var_types.get(m.subject.identifier)) |vt| {
                                                    if (std.mem.eql(u8, vt, "optional_string")) break :blk true;
                                                }
                                            }
                                        }
                                        break :blk false;
                                    };
                                    // Determine payload type: struct → ptr, string → string, else → i64
                                    const tag_key = std.fmt.allocPrint(self.alloc, "__tagged_struct_{d}", .{subject_reg}) catch "";
                                    const is_struct_payload = self.var_types.get(tag_key) != null;
                                    const val_type: ir.Type = if (is_string_variant) .string else if (is_struct_payload) .ptr else .i64;
                                    const val_reg = func.newReg(val_type);
                                    if (is_string_variant) {
                                        self.appendInst(.{ .tag_value_str = .{ .dest = val_reg, .tagged = subject_reg } });
                                        self.var_types.put(self.alloc, t.bindings[0], "string") catch {};
                                    } else {
                                        self.appendInst(.{ .tag_value = .{ .dest = val_reg, .tagged = subject_reg } });
                                    }
                                    self.appendInst(.{ .store_local = .{ .name = t.bindings[0], .src = val_reg } });
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
                const dest = func.newReg(.i64);
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

    /// Get the to_string builtin name for an expression, with type hint if available.
    /// Returns "to_string:Currency" for enum vars, "to_string:Account" for struct vars, etc.
    fn toStringBuiltinName(self: *Lower, expr: ast.Expr) []const u8 {
        if (expr == .identifier) {
            if (self.var_types.get(expr.identifier)) |type_name| {
                return std.fmt.allocPrint(self.alloc, "to_string:{s}", .{type_name}) catch "to_string";
            }
        }
        if (expr == .field_access) {
            const fa = expr.field_access;
            if (fa.target.* == .identifier) {
                if (self.var_types.get(fa.target.identifier)) |struct_type| {
                    if (self.struct_decls.get(struct_type)) |sd| {
                        for (sd.fields) |f| {
                            if (std.mem.eql(u8, f.name, fa.field)) {
                                const field_type = switch (f.type_expr) {
                                    .simple => |tn| tn,
                                    else => break,
                                };
                                return std.fmt.allocPrint(self.alloc, "to_string:{s}", .{field_type}) catch "to_string";
                            }
                        }
                    }
                }
            }
        }
        return "to_string";
    }

    fn isStringExpr(self: *Lower, expr: ast.Expr) bool {
        return switch (expr) {
            .string_literal, .string_interp => true,
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

    /// Lower Process.send / Process.send_timeout / Process.tell calls.
    /// First arg is a handler reference (field_access: pid.Handler), rest are handler args.
    fn lowerProcessCall(self: *Lower, call_name: []const u8, call_args: []const ast.Expr, dest: ir.Reg) ir.Reg {
        const func = self.current_fn orelse return dest;
        if (call_args.len == 0) return dest;

        // First arg must be a handler reference: counter.Inc
        const handler_ref = call_args[0];
        if (handler_ref != .field_access) return dest;
        const fa = handler_ref.field_access;

        // Resolve the pid register and handler index
        const target_reg = self.lowerExpr(fa.target.*);
        const handler_name = fa.field;

        // Look up process type from pid variable
        var handler_index: ?u32 = null;
        var handler_decl: ?ast.ReceiveDecl = null;
        if (fa.target.* == .identifier) {
            if (self.process_vars.get(fa.target.identifier)) |proc_type| {
                if (self.process_decls.get(proc_type)) |pdecl| {
                    for (pdecl.receive_handlers, 0..) |h, hi| {
                        if (std.mem.eql(u8, h.name, handler_name)) {
                            handler_index = @intCast(hi);
                            handler_decl = h;
                            break;
                        }
                    }
                }
            }
        }
        const hi = handler_index orelse return dest;

        // Resolve handler param types for native-width message encoding
        var param_types = std.ArrayListUnmanaged(ir.Type){};
        if (handler_decl) |hd| {
            for (hd.params) |p| {
                param_types.append(self.alloc, self.resolveType(p.type_expr)) catch {};
            }
        }

        // Lower handler arguments (everything after the handler reference)
        var arg_regs = std.ArrayListUnmanaged(ir.Reg){};
        const handler_args = call_args[1..];

        const ptypes = param_types.toOwnedSlice(self.alloc) catch &.{};

        if (std.mem.eql(u8, call_name, "send_timeout")) {
            // Second arg (index 0 in handler_args) is timeout_ms, rest are handler args
            // Syntax: Process.send_timeout(pid.Handler, timeout_ms, args...)
            if (handler_args.len > 0) {
                const timeout_reg = self.lowerExpr(handler_args[0]);
                for (handler_args[1..]) |arg| {
                    arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
                }
                self.appendInst(.{ .process_send_timeout = .{
                    .dest = dest,
                    .target = target_reg,
                    .handler_index = hi,
                    .args = arg_regs.toOwnedSlice(self.alloc) catch &.{},
                    .timeout_ms = timeout_reg,
                    .param_types = ptypes,
                } });
            } else {
                // No timeout specified — use 0 (no deadline, same as send)
                const timeout_reg = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = timeout_reg, .value = 0 } });
                self.appendInst(.{ .process_send_timeout = .{
                    .dest = dest,
                    .target = target_reg,
                    .handler_index = hi,
                    .args = &.{},
                    .timeout_ms = timeout_reg,
                    .param_types = ptypes,
                } });
            }
        } else {
            // send or tell — lower all handler args
            for (handler_args) |arg| {
                arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
            }
            const args = arg_regs.toOwnedSlice(self.alloc) catch &.{};

            if (std.mem.eql(u8, call_name, "tell")) {
                self.appendInst(.{ .process_tell = .{
                    .dest = dest,
                    .target = target_reg,
                    .handler_index = hi,
                    .args = args,
                    .param_types = ptypes,
                } });
            } else {
                self.appendInst(.{ .process_send = .{
                    .dest = dest,
                    .target = target_reg,
                    .handler_index = hi,
                    .args = args,
                    .param_types = ptypes,
                } });
            }
        }
        return dest;
    }

    fn lowerExpr(self: *Lower, expr: ast.Expr) ir.Reg {
        const func = self.current_fn orelse return 0;

        switch (expr) {
            .int_literal => |v| {
                const dest = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = v } });
                return dest;
            },
            .float_literal => |v| {
                const dest = func.newReg(.f64);
                self.appendInst(.{ .const_float = .{ .dest = dest, .value = v } });
                self.float_regs.put(self.alloc, dest, {}) catch {};
                return dest;
            },
            .bool_literal => |v| {
                const dest = func.newReg(.bool);
                self.appendInst(.{ .const_bool = .{ .dest = dest, .value = v } });
                return dest;
            },
            .string_literal => |v| {
                const dest = func.newReg(.string);
                self.appendInst(.{ .const_string = .{ .dest = dest, .value = v } });
                return dest;
            },
            .string_interp => |si| {
                // Lower each part to a string, then concat them all
                var result: ?ir.Reg = null;
                for (si.parts) |part| {
                    const part_reg = switch (part) {
                        .literal => |lit| blk: {
                            const r = func.newReg(.string);
                            self.appendInst(.{ .const_string = .{ .dest = r, .value = lit } });
                            break :blk r;
                        },
                        .expr => |e| blk: {
                            const r = self.lowerExpr(e);
                            if (!self.isStringExpr(e)) {
                                const conv = func.newReg(.string);
                                const builtin_name = self.toStringBuiltinName(e);
                                self.appendInst(.{ .call_builtin = .{ .dest = conv, .name = builtin_name, .args = self.allocRegs(&.{r}) } });
                                break :blk conv;
                            }
                            break :blk r;
                        },
                    };
                    if (result) |prev| {
                        const concat = func.newReg(.string);
                        self.appendInst(.{ .call_builtin = .{ .dest = concat, .name = "string_concat", .args = self.allocRegs(&.{ prev, part_reg }) } });
                        result = concat;
                    } else {
                        result = part_reg;
                    }
                }
                return result orelse blk: {
                    const empty = func.newReg(.string);
                    self.appendInst(.{ .const_string = .{ .dest = empty, .value = "" } });
                    break :blk empty;
                };
            },
            .tag => |tag_name| {
                // Look up the variant index across all enum declarations
                const dest = func.newReg(.i64);
                const tag_id = self.resolveTagId(tag_name);
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = tag_id } });
                return dest;
            },
            .tagged_value => |tv| {
                // Construct a tagged value: :tag{expr} → makeTagged(tag_id, value)
                const dest = func.newReg(.ptr);
                const tag_id = self.resolveTagId(tv.tag);
                const tag_id_reg = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = tag_id_reg, .value = tag_id } });
                const val_reg = if (tv.value) |v| self.lowerExpr(v.*) else blk: {
                    const zero = func.newReg(.i64);
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
                const dest = func.newReg(self.varIrType(name));
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
                        const dest = func.newReg(.bool);
                        self.appendInst(.{ .string_eq = .{ .dest = dest, .lhs = lhs, .rhs = rhs } });
                        if (op.op == .neq) {
                            const neg = func.newReg(.bool);
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
                        const dest = func.newReg(.string);
                        var concat_args = std.ArrayListUnmanaged(ir.Reg){};
                        concat_args.append(self.alloc, lhs) catch {};
                        concat_args.append(self.alloc, rhs) catch {};
                        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "string_concat", .args = concat_args.toOwnedSlice(self.alloc) catch &.{} } });
                        return dest;
                    }
                }
                const lhs = self.lowerExpr(op.left.*);
                const rhs = self.lowerExpr(op.right.*);
                const is_float = self.float_regs.get(lhs) != null or self.float_regs.get(rhs) != null or
                    (op.left.* == .float_literal) or (op.right.* == .float_literal) or
                    (op.left.* == .identifier and self.isVarFloat(op.left.identifier)) or
                    (op.right.* == .identifier and self.isVarFloat(op.right.identifier));
                const is_cmp = op.op == .eq or op.op == .neq or op.op == .lt or op.op == .gt or op.op == .lte or op.op == .gte;
                const is_bool_op = op.op == .@"and" or op.op == .@"or" or op.op == .not;
                const dest_type: ir.Type = if (is_cmp or is_bool_op) .bool else if (is_float) .f64 else .i64;
                const dest = func.newReg(dest_type);
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
                const is_float_op = self.float_regs.get(operand) != null or
                    (op.operand.* == .float_literal) or
                    (op.operand.* == .identifier and self.isVarFloat(op.operand.identifier));
                const dest_type: ir.Type = if (op.op == .not) .bool else if (is_float_op) .f64 else .i64;
                const dest = func.newReg(dest_type);
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
                const dest = func.newReg(.i64);

                // Process.send / Process.send_timeout / Process.tell — handle before generic arg lowering
                if (c.target.* == .field_access) {
                    const fa = c.target.field_access;
                    if (fa.target.* == .identifier and std.mem.eql(u8, fa.target.identifier, "Process")) {
                        if (std.mem.eql(u8, fa.field, "send") or std.mem.eql(u8, fa.field, "send_timeout") or std.mem.eql(u8, fa.field, "tell")) {
                            return self.lowerProcessCall(fa.field, c.args, dest);
                        }
                    }
                }

                var arg_regs = std.ArrayListUnmanaged(ir.Reg){};
                for (c.args) |arg| {
                    arg_regs.append(self.alloc, self.lowerExpr(arg)) catch {};
                }
                const args = arg_regs.toOwnedSlice(self.alloc) catch &.{};

                if (c.target.* == .field_access) {
                    const fa = c.target.field_access;
                    if (fa.target.* == .identifier) {
                        const mod_name = fa.target.identifier;
                        const fn_name = fa.field;

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

                        // Built-in modules
                        if (builtins.lowerBuiltinModuleCall(self, mod_name, fn_name, args, c.args, dest)) |result| {
                            return result;
                        }
                        // User module.function
                        self.appendInst(.{ .call = .{ .dest = dest, .module = mod_name, .function = fn_name, .args = args } });
                        return dest;
                    }
                }
                if (c.target.* == .identifier) {
                    const name = c.target.identifier;
                    if (std.mem.eql(u8, name, "list")) {
                        func.reg_types.items[dest] = .ptr;
                        self.appendInst(.{ .list_new = .{ .dest = dest } });
                        return dest;
                    }
                    if (std.mem.eql(u8, name, "set")) {
                        func.reg_types.items[dest] = .ptr;
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
                // Resolve name: use monomorphized name for generic structs
                const struct_name = if (self.generic_struct_decls.get(sl.name) != null)
                    (self.pending_generic_name orelse sl.name)
                else
                    sl.name;

                const base = func.newReg(.ptr);
                self.appendInst(.{ .struct_alloc = .{ .dest = base, .struct_name = struct_name } });

                if (self.struct_decls.get(struct_name)) |d| {
                    for (d.fields) |df| {
                        for (sl.fields) |lf| {
                            if (std.mem.eql(u8, lf.name, df.name)) {
                                const val_reg = self.lowerExpr(lf.value);
                                self.appendInst(.{ .struct_store = .{ .base = base, .struct_name = struct_name, .field_name = df.name, .src = val_reg } });
                                break;
                            }
                        }
                    }
                } else {
                    for (sl.fields) |lf| {
                        const val_reg = self.lowerExpr(lf.value);
                        self.appendInst(.{ .struct_store = .{ .base = base, .struct_name = struct_name, .field_name = lf.name, .src = val_reg } });
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
                                            const dest = func.newReg(self.fieldIrType(st, f.name));
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
                                    const dest = func.newReg(self.fieldIrType(type_name, f.name));
                                    self.appendInst(.{ .struct_load = .{ .dest = dest, .base = base_reg, .struct_name = type_name, .field_name = f.name } });
                                    return dest;
                                }
                            }
                        }
                    }
                    if (std.mem.eql(u8, fa.field, "len")) {
                        if (self.isVarString(target_name)) {
                            const str_reg = self.lowerExpr(fa.target.*);
                            const dest = func.newReg(.i64);
                            self.appendInst(.{ .string_len = .{ .dest = dest, .str = str_reg } });
                            return dest;
                        }
                        const list_reg = self.lowerExpr(fa.target.*);
                        const dest = func.newReg(.i64);
                        self.appendInst(.{ .list_len = .{ .dest = dest, .list = list_reg } });
                        return dest;
                    }
                }
                const dest = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            },
            .index_access => |ia| {
                const target_reg = self.lowerExpr(ia.target.*);
                const index_reg = self.lowerExpr(ia.index.*);
                const is_str_idx = ia.target.* == .identifier and self.isVarString(ia.target.identifier);
                const dest = func.newReg(if (is_str_idx) .string else .i64);
                if (ia.target.* == .identifier) {
                    if (self.isVarString(ia.target.identifier)) {
                        self.appendInst(.{ .string_index = .{ .dest = dest, .str = target_reg, .index = index_reg } });
                        return dest;
                    }
                }
                self.appendInst(.{ .list_get = .{ .dest = dest, .list = target_reg, .index = index_reg } });
                return dest;
            },
            .none_literal => {
                // none → makeTagged(1, 0)
                const dest = func.newReg(.ptr);
                const tag_reg = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = tag_reg, .value = 1 } });
                const zero_reg = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = zero_reg, .value = 0 } });
                var args = self.alloc.alloc(ir.Reg, 2) catch return dest;
                args[0] = tag_reg;
                args[1] = zero_reg;
                self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "make_tagged", .args = args } });
                return dest;
            },
            else => {
                const dest = func.newReg(.i64);
                self.appendInst(.{ .const_int = .{ .dest = dest, .value = 0 } });
                return dest;
            },
        }
    }

    /// Map a variable name to its ir.Type using var_types tracking.
    fn varIrType(self: *Lower, name: []const u8) ir.Type {
        const t = self.var_types.get(name) orelse return .i64;
        if (std.mem.eql(u8, t, "string")) return .string;
        if (std.mem.eql(u8, t, "float")) return .f64;
        if (std.mem.eql(u8, t, "bool")) return .bool;
        if (std.mem.eql(u8, t, "int")) return .i64;
        if (std.mem.eql(u8, t, "stream")) return .ptr;
        if (self.struct_decls.contains(t)) return .ptr;
        return .i64;
    }

    /// Map a struct field to its ir.Type using the program's struct_decls.
    fn fieldIrType(self: *Lower, struct_name: []const u8, field_name: []const u8) ir.Type {
        for (self.program.struct_decls.items) |sd| {
            if (std.mem.eql(u8, sd.name, struct_name)) {
                for (sd.fields) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) {
                        if (std.mem.eql(u8, f.type_name, "string")) return .string;
                        if (std.mem.eql(u8, f.type_name, "float")) return .f64;
                        if (std.mem.eql(u8, f.type_name, "bool")) return .bool;
                        if (std.mem.eql(u8, f.type_name, "stream")) return .ptr;
                        return .i64;
                    }
                }
            }
        }
        return .i64;
    }

    fn isVarString(self: *Lower, name: []const u8) bool {
        const t = self.var_types.get(name) orelse return false;
        return std.mem.eql(u8, t, "string");
    }

    fn isVarFloat(self: *Lower, name: []const u8) bool {
        const t = self.var_types.get(name) orelse return false;
        return std.mem.eql(u8, t, "float");
    }

    fn isVarBool(self: *Lower, name: []const u8) bool {
        const t = self.var_types.get(name) orelse return false;
        return std.mem.eql(u8, t, "bool");
    }

    fn allocRegs(self: *Lower, regs: []const ir.Reg) []const ir.Reg {
        const slice = self.alloc.alloc(ir.Reg, regs.len) catch return &.{};
        @memcpy(slice, regs);
        return slice;
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

    /// Post-lowering fixup: patches register types that couldn't be determined at newReg() time.
    /// Handles: call return types (forward refs), tag_value propagation, load_local propagation.
    fn fixupRegTypes(self: *Lower) void {
        for (self.program.functions.items) |*func| {
            const rt = func.reg_types.items;
            if (rt.len == 0) continue;

            // Build local_type_map from params
            var local_types = std.StringHashMapUnmanaged(ir.Type){};
            for (func.params) |p| {
                const pt = if (p.type_ == .void) ir.Type.ptr else p.type_;
                local_types.put(self.alloc, p.name, pt) catch {};
            }

            for (func.blocks.items) |block| {
                for (block.insts.items) |inst| {
                    switch (inst) {
                        .call => |c| {
                            if (c.dest >= rt.len) continue;
                            // Look up callee's return type
                            for (self.program.functions.items) |f| {
                                if (std.mem.eql(u8, f.module, c.module) and std.mem.eql(u8, f.name, c.function)) {
                                    const ret = f.return_type;
                                    if (ret != .void) rt[c.dest] = ret;
                                    break;
                                }
                            }
                        },
                        .call_builtin => |c| {
                            if (c.dest >= rt.len) continue;
                            rt[c.dest] = builtinIrType(c.name);
                        },
                        .env_load => |e| {
                            if (e.dest >= rt.len) continue;
                            if (std.mem.eql(u8, e.type_name, "string")) {
                                rt[e.dest] = .string;
                            } else if (std.mem.eql(u8, e.type_name, "float")) {
                                rt[e.dest] = .f64;
                            } else if (std.mem.eql(u8, e.type_name, "bool")) {
                                rt[e.dest] = .bool;
                            }
                        },
                        .process_send => |ps| {
                            if (ps.dest < rt.len) rt[ps.dest] = .ptr;
                        },
                        .process_tell => |pt| {
                            if (pt.dest < rt.len) rt[pt.dest] = .ptr;
                        },
                        .process_send_timeout => |ps| {
                            if (ps.dest < rt.len) rt[ps.dest] = .ptr;
                        },
                        .store_local => |s| {
                            if (s.src < rt.len) {
                                local_types.put(self.alloc, s.name, rt[s.src]) catch {};
                            }
                        },
                        .load_local => |l| {
                            if (l.dest >= rt.len) continue;
                            if (local_types.get(l.name)) |lt| {
                                rt[l.dest] = lt;
                            }
                        },
                        else => {},
                    }
                }
            }
        }
    }

    fn resolveType(self: *Lower, type_expr: ast.TypeExpr) ir.Type {
        switch (type_expr) {
            .simple => |name| {
                if (std.mem.eql(u8, name, "int")) return .i64;
                if (std.mem.eql(u8, name, "int8")) return .i8;
                if (std.mem.eql(u8, name, "int16")) return .i16;
                if (std.mem.eql(u8, name, "int32")) return .i32;
                if (std.mem.eql(u8, name, "int64")) return .i64;
                if (std.mem.eql(u8, name, "uint8")) return .u8;
                if (std.mem.eql(u8, name, "uint16")) return .u16;
                if (std.mem.eql(u8, name, "uint32")) return .u32;
                if (std.mem.eql(u8, name, "uint64")) return .u64;
                if (std.mem.eql(u8, name, "float")) return .f64;
                if (std.mem.eql(u8, name, "bool")) return .bool;
                if (std.mem.eql(u8, name, "string")) return .string;
                if (std.mem.eql(u8, name, "stream")) return .ptr;
                // Enums are integer-backed
                if (self.enum_decls.contains(name)) return .i64;
                // Structs/unions are pointer-backed
                if (self.struct_decls.get(name) != null) return .ptr;
                if (self.union_decls.contains(name)) return .ptr;
                return .void;
            },
            .generic => |g| {
                if (std.mem.eql(u8, g.name, "pid")) return .pid;
                return .void;
            },
            else => return .void,
        }
    }
};

/// Map a call_builtin name to its return ir.Type.
fn builtinIrType(name: []const u8) ir.Type {
    // Pointer-returning builtins
    const ptr_builtins = [_][]const u8{
        "file_open",          "tcp_open",        "tcp_listen",       "tcp_accept",
        "http_parse_request", "http_client_get", "http_client_post", "http_client_request",
        "make_tagged",        "sb_new",          "process_self",     "json_build_object",
        "map",                "stack",           "queue",
    };
    for (ptr_builtins) |b| {
        if (std.mem.eql(u8, name, b)) return .ptr;
    }
    if (std.mem.startsWith(u8, name, "json_parse_struct:")) return .ptr;

    // String-returning builtins
    const str_builtins = [_][]const u8{
        "string_concat",        "string_trim",         "string_replace",              "string_char_at",
        "int_to_string",        "float_to_string",     "bool_to_string",              "to_string",
        "collection_to_string", "stream_read_line",    "stream_read_bytes",           "stream_read_all",
        "http_read_request",    "http_req_method",     "http_req_path",               "http_req_body",
        "http_req_header",      "http_build_response", "http_build_response_chunked", "http_resp_body",
        "http_resp_header",     "json_get_string",     "json_get_object",             "json_to_string",
        "json_build_end",       "sb_to_string",        "env_get",                     "stdio_read_line",
    };
    for (str_builtins) |b| {
        if (std.mem.eql(u8, name, b)) return .string;
    }
    if (std.mem.startsWith(u8, name, "json_stringify_struct:")) return .string;
    if (std.mem.startsWith(u8, name, "to_string:")) return .string;

    // Float-returning builtins
    const float_builtins = [_][]const u8{
        "math_abs_f",      "math_sin",   "math_cos",   "math_tan",
        "math_sqrt_f",     "math_pow_f", "math_log",   "math_log10",
        "math_exp",        "math_min_f", "math_max_f", "convert_to_float",
        "string_to_float",
    };
    for (float_builtins) |b| {
        if (std.mem.eql(u8, name, b)) return .f64;
    }

    // Bool-returning builtins
    const bool_builtins = [_][]const u8{
        "string_contains", "string_starts_with", "string_ends_with",
        "string_is_digit", "string_is_alpha",    "string_is_whitespace",
        "string_is_alnum", "string_to_bool",
    };
    for (bool_builtins) |b| {
        if (std.mem.eql(u8, name, b)) return .bool;
    }

    return .i64;
}
