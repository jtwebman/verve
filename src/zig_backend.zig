const std = @import("std");
const ir = @import("ir.zig");

/// Zig code emitter backend.
/// Consumes target-independent IR, emits Zig source code.
/// Compile with `zig build-exe` for native binary.
pub const ZigBackend = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8),
    indent: usize,
    program: ir.Program,

    pub fn init(alloc: std.mem.Allocator) ZigBackend {
        return .{
            .alloc = alloc,
            .out = .{},
            .indent = 0,
            .program = ir.Program.init(alloc),
        };
    }

    fn write(self: *ZigBackend, s: []const u8) void {
        self.out.appendSlice(self.alloc, s) catch {};
    }

    fn writeFmt(self: *ZigBackend, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        self.write(s);
    }

    fn writeIndent(self: *ZigBackend) void {
        var i: usize = 0;
        while (i < self.indent) : (i += 1) self.write("    ");
    }

    fn line(self: *ZigBackend, s: []const u8) void {
        self.writeIndent();
        self.write(s);
        self.write("\n");
    }

    fn lineFmt(self: *ZigBackend, comptime fmt: []const u8, args: anytype) void {
        self.writeIndent();
        self.writeFmt(fmt, args);
        self.write("\n");
    }

    /// Zig variable name for an IR register.
    fn regName(self: *ZigBackend, reg: ir.Reg) []const u8 {
        return std.fmt.allocPrint(self.alloc, "r{d}", .{reg}) catch "r0";
    }

    // ── Emit program ─────────────────────────────────────────

    const runtime_source = @embedFile("verve_runtime.zig");

    pub fn emit(self: *ZigBackend, program: ir.Program) void {
        self.program = program;
        // Import runtime
        self.line("const std = @import(\"std\");");
        self.line("const rt = @import(\"verve_runtime.zig\");");
        self.line("");
        // Emit Zig struct definitions for Json.parse typed parsing
        for (program.struct_decls.items) |sd| {
            self.writeFmt("const VerveStruct_{s} = struct {{\n", .{sd.name});
            self.indent += 1;
            for (sd.fields) |f| {
                self.writeIndent();
                if (std.mem.eql(u8, f.type_name, "int")) {
                    self.writeFmt("{s}: i64 = 0,\n", .{f.name});
                } else if (std.mem.eql(u8, f.type_name, "float")) {
                    self.writeFmt("{s}: f64 = 0.0,\n", .{f.name});
                } else if (std.mem.eql(u8, f.type_name, "bool")) {
                    self.writeFmt("{s}: bool = false,\n", .{f.name});
                } else if (std.mem.eql(u8, f.type_name, "string")) {
                    self.writeFmt("{s}: []const u8 = \"\",\n", .{f.name});
                } else {
                    self.writeFmt("{s}: i64 = 0,\n", .{f.name});
                }
            }
            self.indent -= 1;
            self.line("};");
            self.line("");

            // Emit parse function: takes (data_ptr, data_len), returns tagged Result
            // On success: allocates Verve struct [N]i64, populates fields, wraps in :ok
            // On failure: returns :error
            self.writeFmt("fn verve_json_parse_{s}(data_ptr: i64, data_len: i64) i64 {{\n", .{sd.name});
            self.indent += 1;
            self.line("const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(data_ptr))))));");
            self.line("const len: usize = @intCast(@as(u64, @bitCast(data_len)));");
            self.line("const slice = ptr[0..len];");
            self.writeFmt("const parsed = std.json.parseFromSlice(VerveStruct_{s}, std.heap.page_allocator, slice, .{{ .ignore_unknown_fields = true }}) catch return rt.makeTagged(1, 0);\n", .{sd.name});
            self.line("const val = parsed.value;");

            // Allocate Verve struct (array of i64)
            self.lineFmt("const struct_mem = rt.arena_alloc({d} * @sizeOf(i64)) orelse return rt.makeTagged(1, 0);", .{sd.fields.len});
            self.line("const fields = @as([*]i64, @ptrCast(@alignCast(struct_mem)));");

            // Copy each field
            for (sd.fields, 0..) |f, fi| {
                if (std.mem.eql(u8, f.type_name, "int")) {
                    self.lineFmt("fields[{d}] = val.{s};", .{ fi, f.name });
                } else if (std.mem.eql(u8, f.type_name, "float")) {
                    self.lineFmt("fields[{d}] = @bitCast(val.{s});", .{ fi, f.name });
                } else if (std.mem.eql(u8, f.type_name, "bool")) {
                    self.lineFmt("fields[{d}] = if (val.{s}) @as(i64, 1) else @as(i64, 0);", .{ fi, f.name });
                } else if (std.mem.eql(u8, f.type_name, "string")) {
                    // Copy to null-terminated buffer (std.json slices aren't null-terminated)
                    self.writeFmt("    {{ const sv = val.{s}; if (sv.len == 0) {{ fields[{d}] = @intCast(@intFromPtr(@as([*]const u8, \"\"))); }} else if (rt.arena_alloc(sv.len + 1)) |sb| {{ @memcpy(sb[0..sv.len], sv); sb[sv.len] = 0; fields[{d}] = @intCast(@intFromPtr(sb)); }} else {{ fields[{d}] = 0; }} }}\n", .{ f.name, fi, fi, fi });
                } else {
                    self.lineFmt("fields[{d}] = 0;", .{fi});
                }
            }

            self.line("return rt.makeTagged(0, @intCast(@intFromPtr(fields)));");
            self.indent -= 1;
            self.line("}");
            self.line("");
        }

        // Emit per-process dispatch functions + register in dispatch table
        if (program.process_decls.items.len > 0) {
            for (program.process_decls.items, 0..) |pd, pdi| {
                self.writeFmt("fn verve_dispatch_{d}(handler_id: i64, args: [*]const i64, arg_count: i64) i64 {{\n", .{pdi});
                self.indent += 1;
                self.line("_ = arg_count;");
                self.line("_ = &args;");
                self.line("return switch (handler_id) {");
                self.indent += 1;
                for (pd.handler_names, 0..) |hname, hi| {
                    self.writeIndent();
                    self.writeFmt("{d} => verve_{s}_{s}(", .{ hi, pd.name, hname });
                    var param_count: usize = 0;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            param_count = f.params.len;
                            break;
                        }
                    }
                    for (0..param_count) |pi| {
                        if (pi > 0) self.write(", ");
                        self.writeFmt("args[{d}]", .{pi});
                    }
                    self.write("),\n");
                }
                self.line("else => rt.makeTagged(1, 0),");
                self.indent -= 1;
                self.line("};");
                self.indent -= 1;
                self.line("}");
                self.line("");
            }

            // Register dispatch functions in runtime table
            self.line("fn verve_init_dispatch() void {");
            self.indent += 1;
            self.lineFmt("rt.ensureProcessCapacity({d});", .{program.process_decls.items.len});
            for (program.process_decls.items, 0..) |_, pdi| {
                self.writeFmt("    rt.dispatch_table[{d}] = &verve_dispatch_{d};\n", .{ pdi, pdi });
            }
            self.indent -= 1;
            self.line("}");
            self.line("");
        }

        // Emit functions (non-main first, main last for Zig ordering)
        for (program.functions.items) |func| {
            if (!std.mem.eql(u8, func.name, "main")) {
                self.emitFunction(func, false);
                self.line("");
            }
        }
        // Check if main is a process handler — emit as regular function too
        var main_is_process = false;
        for (program.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "main")) {
                for (program.process_decls.items) |pd| {
                    if (std.mem.eql(u8, pd.name, func.module)) {
                        main_is_process = true;
                        // Emit as regular function for dispatch table
                        self.emitFunction(func, false);
                        self.line("");
                        break;
                    }
                }
            }
        }
        // Emit main entry point
        for (program.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "main")) {
                if (main_is_process) {
                    // Process main: spawn process, set current, call handler
                    self.emitProcessMainWrapper(func);
                } else {
                    self.emitFunction(func, true);
                }
            }
        }
    }

    /// Emit a test runner program — calls each test function, reports pass/fail.
    pub fn emitTestRunner(self: *ZigBackend, program: ir.Program) void {
        self.program = program;
        self.line("const std = @import(\"std\");");
        self.line("const rt = @import(\"verve_runtime.zig\");");
        self.line("");

        // Emit struct definitions (needed for typed JSON tests etc.)
        for (program.struct_decls.items) |sd| {
            self.writeFmt("const VerveStruct_{s} = struct {{\n", .{sd.name});
            self.indent += 1;
            for (sd.fields) |f| {
                self.writeIndent();
                if (std.mem.eql(u8, f.type_name, "int")) self.writeFmt("{s}: i64 = 0,\n", .{f.name}) else if (std.mem.eql(u8, f.type_name, "float")) self.writeFmt("{s}: f64 = 0.0,\n", .{f.name}) else if (std.mem.eql(u8, f.type_name, "bool")) self.writeFmt("{s}: bool = false,\n", .{f.name}) else if (std.mem.eql(u8, f.type_name, "string")) self.writeFmt("{s}: []const u8 = \"\",\n", .{f.name}) else self.writeFmt("{s}: i64 = 0,\n", .{f.name});
            }
            self.indent -= 1;
            self.line("};");
            self.line("");
        }

        // Emit dispatch init if processes exist
        if (program.process_decls.items.len > 0) {
            for (program.process_decls.items, 0..) |pd, pdi| {
                self.writeFmt("fn verve_dispatch_{d}(handler_id: i64, args_ptr: [*]const i64, arg_count: i64) i64 {{\n", .{pdi});
                self.indent += 1;
                self.line("_ = arg_count;");
                self.line("_ = &args_ptr;");
                self.line("return switch (handler_id) {");
                self.indent += 1;
                for (pd.handler_names, 0..) |hname, hi| {
                    self.writeIndent();
                    self.writeFmt("{d} => verve_{s}_{s}(", .{ hi, pd.name, hname });
                    var param_count: usize = 0;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            param_count = f.params.len;
                            break;
                        }
                    }
                    for (0..param_count) |pi| {
                        if (pi > 0) self.write(", ");
                        self.writeFmt("args_ptr[{d}]", .{pi});
                    }
                    self.write("),\n");
                }
                self.line("else => rt.makeTagged(1, 0),");
                self.indent -= 1;
                self.line("};");
                self.indent -= 1;
                self.line("}");
                self.line("");
            }
            self.line("fn verve_init_dispatch() void {");
            self.indent += 1;
            self.lineFmt("rt.ensureProcessCapacity({d});", .{program.process_decls.items.len});
            for (program.process_decls.items, 0..) |_, pdi| {
                self.writeFmt("    rt.dispatch_table[{d}] = &verve_dispatch_{d};\n", .{ pdi, pdi });
            }
            self.indent -= 1;
            self.line("}");
            self.line("");
        }

        // Emit all functions (including test functions)
        for (program.functions.items) |func| {
            self.emitFunction(func, false);
            self.line("");
        }

        // Emit test runner main
        self.line("pub fn main() void {");
        self.indent += 1;
        self.line("rt.verve_runtime_init();");
        if (program.process_decls.items.len > 0) {
            self.line("verve_init_dispatch();");
        }
        self.lineFmt("var passed: i64 = 0;", .{});
        self.lineFmt("var failed: i64 = 0;", .{});

        for (program.test_names.items, 0..) |test_name, ti| {
            const module = program.test_modules.items[ti];
            const fn_name = program.test_fn_names.items[ti];
            // Reset assert counter
            self.line("rt.assert_fail_count = 0;");
            // Call test function
            self.writeFmt("    _ = verve_{s}_{s}();\n", .{ module, fn_name });
            // Check results
            self.line("if (rt.assert_fail_count == 0) {");
            self.indent += 1;
            self.writeFmt("rt.verve_write(1, \"PASS: {s}\\n\", {d});\n", .{ test_name, test_name.len + 7 });
            self.line("passed += 1;");
            self.indent -= 1;
            self.line("} else {");
            self.indent += 1;
            self.writeFmt("rt.verve_write(1, \"FAIL: {s}\\n\", {d});\n", .{ test_name, test_name.len + 7 });
            self.line("failed += 1;");
            self.indent -= 1;
            self.line("}");
        }

        // Print summary
        self.line("{");
        self.indent += 1;
        self.line("var buf: [128]u8 = undefined;");
        self.line("const s = std.fmt.bufPrint(&buf, \"\\n{d} passed, {d} failed\\n\", .{passed, failed}) catch \"?\";");
        self.line("rt.verve_write(1, s.ptr, @intCast(s.len));");
        self.indent -= 1;
        self.line("}");
        self.line("if (failed > 0) std.process.exit(1);");

        self.indent -= 1;
        self.line("}");
    }

    fn emitFunction(self: *ZigBackend, func: ir.Function, is_entry: bool) void {
        if (is_entry) {
            self.line("pub fn main() void {");
            self.indent += 1;
            self.line("rt.verve_runtime_init();");
            // Initialize process dispatch table
            if (self.program.process_decls.items.len > 0) {
                self.line("verve_init_dispatch();");
            }
            // Build command-line args as list of null-terminated string pointers
            self.line("var verve_args_list = rt.List.init();");
            self.line("var proc_args = std.process.argsWithAllocator(std.heap.page_allocator) catch return;");
            self.line("_ = proc_args.skip(); // skip program name");
            self.line("while (proc_args.next()) |arg| {");
            self.indent += 1;
            self.line("verve_args_list.append(@intCast(@intFromPtr(arg.ptr)));");
            self.indent -= 1;
            self.line("}");
            self.indent -= 1;
        } else {
            self.writeIndent();
            self.writeFmt("fn verve_{s}_{s}(", .{ func.module, func.name });
            for (func.params, 0..) |param, i| {
                if (i > 0) self.write(", ");
                self.writeFmt("param_{s}: i64", .{param.name});
            }
            self.write(") i64 {\n");
        }
        self.indent += 1;

        // Declare all registers as variables
        var max_reg: ir.Reg = 0;
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                const dest = instDest(inst);
                if (dest) |d| {
                    if (d >= max_reg) max_reg = d + 1;
                }
                // string_slice has a second dest register
                if (inst == .string_slice) {
                    if (inst.string_slice.dest_len >= max_reg) max_reg = inst.string_slice.dest_len + 1;
                }
            }
        }
        if (max_reg > 0) {
            var r: ir.Reg = 0;
            while (r < max_reg) : (r += 1) {
                self.lineFmt("var {s}: i64 = 0;", .{self.regName(r)});
                self.lineFmt("_ = &{s};", .{self.regName(r)});
            }
        }

        // Declare local variables map (name → value)
        self.line("var locals: [256]i64 = undefined;");
        self.line("_ = &locals;");

        // Track local name → index mapping
        // We'll use a simple approach: assign indices sequentially
        var local_count: usize = 0;
        var local_names: [128][]const u8 = undefined;

        // Map param names to locals
        if (is_entry) {
            // Entry point: store args list
            for (func.params) |param| {
                if (std.mem.eql(u8, param.name, "args")) {
                    self.lineFmt("locals[{d}] = @intCast(@intFromPtr(&verve_args_list));", .{local_count});
                }
                local_names[local_count] = param.name;
                local_count += 1;
            }
        } else if (!is_entry) {
            for (func.params) |param| {
                self.lineFmt("locals[{d}] = param_{s};", .{ local_count, param.name });
                local_names[local_count] = param.name;
                local_count += 1;
            }
        } else {
            // Entry point: just reserve slots for declared params (unused)
            for (func.params) |param| {
                local_names[local_count] = param.name;
                local_count += 1;
            }
        }

        // Emit blocks as labeled sections using a state machine
        self.line("var block: u32 = 0;");
        self.line("_ = &block;");
        self.line("while (true) {");
        self.indent += 1;
        self.line("switch (block) {");
        self.indent += 1;

        for (func.blocks.items) |block| {
            self.lineFmt("{d} => {{", .{block.id});
            self.indent += 1;

            var terminated = false;
            for (block.insts.items) |inst| {
                if (terminated) break; // skip dead code after terminator
                self.emitInst(inst, &local_names, &local_count, is_entry);
                if (isTerminator(inst)) terminated = true;
            }

            if (!terminated) {
                self.lineFmt("block = {d};", .{block.id + 1});
            }

            self.indent -= 1;
            self.line("},");
        }

        self.line("else => break,");
        self.indent -= 1;
        self.line("}");
        self.indent -= 1;
        self.line("}");

        if (!is_entry) {
            self.line("return 0;");
        }

        self.indent -= 1;
        self.line("}");
    }

    fn emitProcessMainWrapper(self: *ZigBackend, func: ir.Function) void {
        self.line("pub fn main() void {");
        self.indent += 1;
        self.line("rt.verve_runtime_init();");
        // Initialize process dispatch table
        self.line("verve_init_dispatch();");
        // Find process type index
        for (self.program.process_decls.items, 0..) |pd, pdi| {
            if (std.mem.eql(u8, pd.name, func.module)) {
                self.lineFmt("const pid = rt.verve_spawn({d});", .{pdi});
                self.line("rt.current_process_id = pid;");
                break;
            }
        }
        self.writeFmt("    const result = verve_{s}_{s}(", .{ func.module, func.name });
        for (func.params, 0..) |_, i| {
            if (i > 0) self.write(", ");
            self.write("0");
        }
        self.write(");\n");
        self.line("if (result != 0) {");
        self.indent += 1;
        self.line("std.posix.exit(@intCast(@as(u64, @bitCast(result))));");
        self.indent -= 1;
        self.line("}");
        self.indent -= 1;
        self.line("}");
    }

    fn emitInst(self: *ZigBackend, inst: ir.Inst, local_names: *[128][]const u8, local_count: *usize, is_entry: bool) void {
        switch (inst) {
            .const_int => |c| self.lineFmt("{s} = {d};", .{ self.regName(c.dest), c.value }),
            .const_bool => |c| self.lineFmt("{s} = {d};", .{ self.regName(c.dest), @as(i64, if (c.value) 1 else 0) }),
            .const_string => |c| {
                // Store string as pointer cast to i64
                self.writeIndent();
                self.writeFmt("{s} = @intCast(@intFromPtr(@as([*]const u8, \"", .{self.regName(c.dest)});
                // Escape the string
                for (c.value) |byte| {
                    if (byte == '"') {
                        self.write("\\\"");
                    } else if (byte == '\\') {
                        self.write("\\\\");
                    } else if (byte == '\n') {
                        self.write("\\n");
                    } else if (byte >= 32 and byte < 127) {
                        self.out.append(self.alloc, byte) catch {};
                    } else {
                        self.writeFmt("\\x{x:0>2}", .{byte});
                    }
                }
                self.write("\")));\n");
            },
            .const_float => |cf| {
                // Store float as bit-cast i64 — all runtime functions expect i64
                self.lineFmt("{s} = @bitCast(@as(f64, {d}));", .{ self.regName(cf.dest), cf.value });
            },

            .add_i64 => |op| self.lineFmt("{s} = rt.verve_add_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_i64 => |op| self.lineFmt("{s} = rt.verve_sub_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_i64 => |op| self.lineFmt("{s} = rt.verve_mul_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_i64 => |op| self.lineFmt("{s} = rt.verve_div_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mod_i64 => |op| self.lineFmt("{s} = rt.verve_mod_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_i64 => |op| self.lineFmt("{s} = rt.verve_neg_checked({s});", .{ self.regName(op.dest), self.regName(op.operand) }),

            // Float arithmetic — bitcast i64 <-> f64, let Zig handle the math
            .add_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) + @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) - @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) * @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) / @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mod_f64 => |op| self.lineFmt("{s} = @bitCast(@mod(@as(f64, @bitCast({s})), @as(f64, @bitCast({s}))));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_f64 => |op| self.lineFmt("{s} = @bitCast(-@as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.operand) }),

            // Float comparison — returns bool as i64 (0 or 1)
            .eq_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) == @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) != @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) < @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) > @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) <= @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) >= @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .eq_i64 => |op| self.lineFmt("{s} = if ({s} == {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_i64 => |op| self.lineFmt("{s} = if ({s} != {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_i64 => |op| self.lineFmt("{s} = if ({s} < {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_i64 => |op| self.lineFmt("{s} = if ({s} > {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_i64 => |op| self.lineFmt("{s} = if ({s} <= {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_i64 => |op| self.lineFmt("{s} = if ({s} >= {s}) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .and_bool => |op| self.lineFmt("{s} = if ({s} != 0 and {s} != 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .or_bool => |op| self.lineFmt("{s} = if ({s} != 0 or {s} != 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .not_bool => |op| self.lineFmt("{s} = if ({s} == 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.operand) }),

            .store_local => |s| {
                const idx = self.findOrAddLocal(s.name, local_names, local_count);
                self.lineFmt("locals[{d}] = {s};", .{ idx, self.regName(s.src) });
            },
            .load_local => |l| {
                const idx = self.findOrAddLocal(l.name, local_names, local_count);
                self.lineFmt("{s} = locals[{d}];", .{ self.regName(l.dest), idx });
            },

            .jump => |j| self.lineFmt("block = {d}; continue;", .{j.target}),
            .branch => |b| self.lineFmt("block = if ({s} != 0) {d} else {d}; continue;", .{ self.regName(b.cond), b.then_block, b.else_block }),
            .ret => |r| {
                if (is_entry) {
                    if (r.value) |reg| {
                        self.lineFmt("std.posix.exit(@intCast(@as(u64, @bitCast({s}))));", .{self.regName(reg)});
                    } else {
                        self.line("return;");
                    }
                } else {
                    if (r.value) |reg| {
                        self.lineFmt("return {s};", .{self.regName(reg)});
                    } else {
                        self.line("return 0;");
                    }
                }
            },

            .call => |c| {
                self.writeIndent();
                self.writeFmt("{s} = verve_{s}_{s}(", .{ self.regName(c.dest), c.module, c.function });
                for (c.args, 0..) |arg, i| {
                    if (i > 0) self.write(", ");
                    self.write(self.regName(arg));
                }
                self.write(");\n");
            },
            .call_builtin => |c| self.emitBuiltin(c.dest, c.name, c.args),

            .struct_alloc => |sa| {
                // Allocate struct as array on heap
                self.lineFmt("{s} = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, {d}) catch &.{{}}).ptr));", .{ self.regName(sa.dest), sa.num_fields });
            },
            .struct_store => |ss| {
                self.lineFmt("@as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[{d}] = {s};", .{ self.regName(ss.base), ss.field_index, self.regName(ss.src) });
            },
            .struct_load => |sl| {
                self.lineFmt("{s} = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[{d}];", .{ self.regName(sl.dest), self.regName(sl.base), sl.field_index });
            },

            .list_new => |ln| {
                self.lineFmt("var list_{d} = rt.List.init();", .{ln.dest});
                self.lineFmt("{s} = @intCast(@intFromPtr(&list_{d}));", .{ self.regName(ln.dest), ln.dest });
            },
            .list_append => |la| {
                self.lineFmt("@as(*rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).append({s});", .{ self.regName(la.list), self.regName(la.value) });
            },
            .list_len => |ll| {
                self.lineFmt("{s} = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).len;", .{ self.regName(ll.dest), self.regName(ll.list) });
            },
            .list_get => |lg| {
                self.lineFmt("{s} = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).get({s});", .{ self.regName(lg.dest), self.regName(lg.list), self.regName(lg.index) });
            },

            .tag_get => |tg| {
                self.lineFmt("{s} = rt.getTag({s});", .{ self.regName(tg.dest), self.regName(tg.tagged) });
            },
            .tag_value => |tv| {
                self.lineFmt("{s} = rt.getTagValue({s});", .{ self.regName(tv.dest), self.regName(tv.tagged) });
            },

            .string_byte_at => |sb| {
                // Returns byte VALUE as i64 (for String.byte_at)
                self.lineFmt("{s} = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[", .{ self.regName(sb.dest), self.regName(sb.str) });
                self.writeFmt("@intCast(@as(u64, @bitCast({s})))];\n", .{self.regName(sb.index)});
            },
            .string_slice => |ss| {
                // dest_ptr = str + start, dest_len = end - start
                self.lineFmt("{s} = {s} +% {s};", .{ self.regName(ss.dest_ptr), self.regName(ss.str), self.regName(ss.start) });
                self.lineFmt("{s} = {s} -% {s};", .{ self.regName(ss.dest_len), self.regName(ss.end), self.regName(ss.start) });
            },
            .string_index => |si| {
                // Returns POINTER to byte (for s[i] string indexing — single-char string)
                self.lineFmt("{s} = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))) + @as(usize, @intCast(@as(u64, @bitCast({s}))))));", .{ self.regName(si.dest), self.regName(si.str), self.regName(si.index) });
            },
            .string_len => |sl| {
                // Compute string length using strlen (null-safe)
                self.lineFmt("if ({s} == 0) {{ {s} = 0; }} else {{ const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; {s} = @intCast(sl); }}", .{ self.regName(sl.str), self.regName(sl.dest), self.regName(sl.str), self.regName(sl.dest) });
            },
            .string_eq => |se| {
                self.lineFmt("{s} = if (rt.strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s}, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s})) @as(i64, 1) else @as(i64, 0);", .{
                    self.regName(se.dest),
                    self.regName(se.lhs),
                    self.regName(se.lhs_len),
                    self.regName(se.rhs),
                    self.regName(se.rhs_len),
                });
            },

            .process_spawn => |ps| {
                self.lineFmt("{s} = rt.verve_spawn({d});", .{ self.regName(ps.dest), ps.process_type });
            },
            .process_send => |ps| {
                // Build args array, call verve_send
                if (ps.args.len > 0) {
                    self.writeIndent();
                    self.writeFmt("{{ const send_args = [_]i64{{ ", .{});
                    for (ps.args, 0..) |arg, i| {
                        if (i > 0) self.write(", ");
                        self.write(self.regName(arg));
                    }
                    self.writeFmt(" }}; {s} = rt.verve_send({s}, {d}, &send_args, {d}); }}\n", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index, ps.args.len });
                } else {
                    self.lineFmt("{{ const send_args = [_]i64{{0}}; {s} = rt.verve_send({s}, {d}, &send_args, 0); }}", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index });
                }
            },
            .process_tell => |pt| {
                if (pt.args.len > 0) {
                    self.writeIndent();
                    self.writeFmt("{{ const tell_args = [_]i64{{ ", .{});
                    for (pt.args, 0..) |arg, i| {
                        if (i > 0) self.write(", ");
                        self.write(self.regName(arg));
                    }
                    self.writeFmt(" }}; rt.verve_tell({s}, {d}, &tell_args, {d}); }}\n", .{ self.regName(pt.target), pt.handler_index, pt.args.len });
                } else {
                    self.lineFmt("{{ const tell_args = [_]i64{{0}}; rt.verve_tell({s}, {d}, &tell_args, 0); }}", .{ self.regName(pt.target), pt.handler_index });
                }
            },
            .process_state_get => |sg| {
                self.lineFmt("{s} = rt.verve_state_get({d});", .{ self.regName(sg.dest), sg.field_index });
            },
            .process_state_set => |ss| {
                self.lineFmt("rt.verve_state_set({d}, {s});", .{ ss.field_index, self.regName(ss.src) });
            },
            .process_watch => |pw| {
                self.lineFmt("rt.verve_watch({s});", .{self.regName(pw.target)});
            },
            .process_send_timeout => |ps| {
                if (ps.args.len > 0) {
                    self.writeIndent();
                    self.writeFmt("{{ const send_args = [_]i64{{ ", .{});
                    for (ps.args, 0..) |arg, i| {
                        if (i > 0) self.write(", ");
                        self.write(self.regName(arg));
                    }
                    self.writeFmt(" }}; {s} = rt.verve_send_timeout({s}, {d}, &send_args, {d}, {s}); }}\n", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index, ps.args.len, self.regName(ps.timeout_ms) });
                } else {
                    self.lineFmt("{{ const send_args = [_]i64{{0}}; {s} = rt.verve_send_timeout({s}, {d}, &send_args, 0, {s}); }}", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index, self.regName(ps.timeout_ms) });
                }
            },

            .break_loop, .continue_loop => {},
        }
    }

    fn emitBuiltin(self: *ZigBackend, dest: ir.Reg, name: []const u8, args: []const ir.Reg) void {
        if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
            const newline = std.mem.eql(u8, name, "println");
            var i: usize = 0;
            while (i + 1 < args.len) {
                // If len == -1, it's an integer — format it. Otherwise it's a string.
                self.lineFmt("if ({s} == -1) {{ var buf: [32]u8 = undefined; const s = std.fmt.bufPrint(&buf, \"{{d}}\", .{{{s}}}) catch \"?\"; rt.verve_write(1, s.ptr, @intCast(s.len)); }} else {{ rt.verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s}); }}", .{ self.regName(args[i + 1]), self.regName(args[i]), self.regName(args[i]), self.regName(args[i + 1]) });
                i += 2;
            }
            if (newline) {
                self.line("rt.verve_write(1, \"\\n\", 1);");
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "string_is_digit")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[0]; {s} = if (b >= '0' and b <= '9') @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_alpha")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[0]; {s} = if ((b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_whitespace")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[0]; {s} = if (b == ' ' or b == '\\t' or b == '\\n' or b == '\\r') @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_alnum")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[0]; {s} = if ((b >= '0' and b <= '9') or (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z')) @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_slice")) {
            if (args.len >= 3) {
                self.lineFmt("{s} = {s} + {s};", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "set_has") or std.mem.eql(u8, name, "set_has_str")) {
            if (std.mem.eql(u8, name, "set_has_str") and args.len >= 3) {
                // args: set, needle_ptr, needle_len — set stores (ptr, len) pairs
                self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si + 1 < list.len) : (si += 2) {{ const eptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(list.get(si))))))); const elen = list.get(si + 1); const nptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); if (rt.strEql(eptr, elen, nptr, {s})) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(dest) });
            } else if (args.len >= 2) {
                // Integer set — simple equality
                self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si < list.len) : (si += 1) {{ if (list.get(si) == {s}) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "file_open")) {
            // args: path_ptr, path_len, mode_ptr, ...
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.fileOpen({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "stream_read_all")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.streamReadAll({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "stream_write")) {
            if (args.len >= 2) {
                // args: stream_ptr, data_ptr (+ data_len from next arg)
                if (args.len >= 3) {
                    self.lineFmt("rt.stream_write({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
                } else {
                    self.lineFmt("rt.stream_write({s}, {s}, 0);", .{ self.regName(args[0]), self.regName(args[1]) });
                }
                self.lineFmt("{s} = 0;", .{self.regName(dest)});
            }
        } else if (std.mem.eql(u8, name, "stream_write_line")) {
            if (args.len >= 2) {
                if (args.len >= 3) {
                    self.lineFmt("rt.stream_write_line({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
                } else {
                    self.lineFmt("rt.stream_write_line({s}, {s}, 0);", .{ self.regName(args[0]), self.regName(args[1]) });
                }
                self.lineFmt("{s} = 0;", .{self.regName(dest)});
            }
        } else if (std.mem.eql(u8, name, "stream_read_bytes")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.stream_read_bytes({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "stream_read_bytes_len")) {
            self.lineFmt("{s} = rt.stream_read_bytes_len();", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "stream_read_line")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.stream_read_line({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "stream_close")) {
            if (args.len >= 1) {
                self.lineFmt("rt.stream_close({s});", .{self.regName(args[0])});
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "math_abs")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_abs({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_min")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_min({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "math_max")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_max({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "math_clamp")) {
            if (args.len >= 3) self.lineFmt("{s} = rt.math_clamp({s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
        } else if (std.mem.eql(u8, name, "math_pow")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_pow({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "math_sqrt")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_sqrt({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_log2")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_log2({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_abs_f")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_abs_f({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_floor")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_floor({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_ceil")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_ceil({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_round")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_round({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_sin")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_sin({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_cos")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_cos({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_tan")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_tan({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_sqrt_f")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_sqrt_f({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_pow_f")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_pow_f({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "math_log")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_log({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_log10")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_log10({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_exp")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.math_exp({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "math_min_f")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_min_f({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "math_max_f")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.math_max_f({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "convert_to_float")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.convert_to_float({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "convert_to_int_f")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.convert_to_int_f({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "float_to_string")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.float_to_string({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "string_to_float")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.string_to_float({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "env_get")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.env_get({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "system_exit")) {
            if (args.len >= 1) self.lineFmt("rt.system_exit({s});", .{self.regName(args[0])});
        } else if (std.mem.eql(u8, name, "system_time_ms")) {
            self.lineFmt("{s} = rt.system_time_ms();", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "int_to_string")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.int_to_string({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "string_to_int")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.string_to_int({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "json_get_string") or std.mem.eql(u8, name, "json_get_string_len") or
            std.mem.eql(u8, name, "json_get_int") or std.mem.eql(u8, name, "json_get_float") or
            std.mem.eql(u8, name, "json_get_bool") or std.mem.eql(u8, name, "json_get_object") or
            std.mem.eql(u8, name, "json_get_object_len") or
            std.mem.eql(u8, name, "json_get_array") or std.mem.eql(u8, name, "json_get_array_len"))
        {
            if (args.len >= 4) {
                self.lineFmt("{s} = rt.{s}({s}, {s}, {s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]) });
            }
        } else if (std.mem.eql(u8, name, "json_to_int") or std.mem.eql(u8, name, "json_to_float") or
            std.mem.eql(u8, name, "json_to_bool") or std.mem.eql(u8, name, "json_to_string") or
            std.mem.eql(u8, name, "json_to_string_len"))
        {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.{s}({s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "assert_check")) {
            if (args.len >= 1) self.lineFmt("rt.assert_check({s});", .{self.regName(args[0])});
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "process_exit")) {
            self.line("rt.verve_exit_self();");
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.startsWith(u8, name, "json_parse_struct:")) {
            const struct_name = name["json_parse_struct:".len..];
            if (args.len >= 2) {
                self.lineFmt("{s} = verve_json_parse_{s}({s}, {s});", .{ self.regName(dest), struct_name, self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "json_build_object")) {
            self.lineFmt("{s} = rt.json_build_object();", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_end")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.json_build_end({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "json_build_end_len")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.json_build_end_len({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "json_build_add_string")) {
            if (args.len >= 5) self.lineFmt("rt.json_build_add_string({s}, {s}, {s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]), self.regName(args[4]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_int")) {
            if (args.len >= 4) self.lineFmt("rt.json_build_add_int({s}, {s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_bool")) {
            if (args.len >= 4) self.lineFmt("rt.json_build_add_bool({s}, {s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "http_parse_request")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.http_parse_request({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "http_req_method") or std.mem.eql(u8, name, "http_req_method_len") or
            std.mem.eql(u8, name, "http_req_path") or std.mem.eql(u8, name, "http_req_path_len") or
            std.mem.eql(u8, name, "http_req_body") or std.mem.eql(u8, name, "http_req_body_len"))
        {
            if (args.len >= 1) self.lineFmt("{s} = rt.{s}({s});", .{ self.regName(dest), name, self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "http_req_header") or std.mem.eql(u8, name, "http_req_header_len")) {
            if (args.len >= 3) self.lineFmt("{s} = rt.{s}({s}, {s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
        } else if (std.mem.eql(u8, name, "http_build_response") or std.mem.eql(u8, name, "http_build_response_len")) {
            if (args.len >= 5) self.lineFmt("{s} = rt.{s}({s}, {s}, {s}, {s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]), self.regName(args[4]) });
        } else if (std.mem.eql(u8, name, "tcp_open")) {
            if (args.len >= 3) {
                self.lineFmt("{s} = rt.tcp_open({s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            }
        } else if (std.mem.eql(u8, name, "tcp_listen")) {
            if (args.len >= 3) {
                self.lineFmt("{s} = rt.tcp_listen({s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            }
        } else if (std.mem.eql(u8, name, "tcp_accept")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.tcp_accept({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "string_concat")) {
            if (args.len >= 4) {
                self.lineFmt("{s} = rt.verve_string_concat({s}, {s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]), self.regName(args[3]) });
            }
        } else if (std.mem.eql(u8, name, "string_len")) {
            if (args.len >= 1) {
                self.lineFmt("if ({s} == 0) {{ {s} = 0; }} else {{ const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; {s} = @intCast(sl); }}", .{ self.regName(args[0]), self.regName(dest), self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_contains") or std.mem.eql(u8, name, "string_split") or std.mem.eql(u8, name, "string_trim") or std.mem.eql(u8, name, "string_replace") or std.mem.eql(u8, name, "string_starts_with") or std.mem.eql(u8, name, "string_ends_with") or std.mem.eql(u8, name, "string_char_at") or std.mem.eql(u8, name, "string_char_len") or std.mem.eql(u8, name, "string_chars")) {
            // String builtins not yet implemented in compiler — return 0
            self.lineFmt("{s} = 0; // TODO: {s}", .{ self.regName(dest), name });
        } else if (std.mem.eql(u8, name, "tcp_port")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.tcp_port({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "make_tagged")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.makeTagged({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else {
            self.lineFmt("{s} = 0; // unknown builtin: {s}", .{ self.regName(dest), name });
        }
    }

    fn findStringLen(self: *ZigBackend, reg: ir.Reg) ?ir.Reg {
        // String length is typically reg+1 (convention from lowering)
        _ = self;
        _ = reg;
        return null; // TODO: proper string length tracking
    }

    fn findOrAddLocal(self: *ZigBackend, name: []const u8, local_names: *[128][]const u8, local_count: *usize) usize {
        _ = self;
        var i: usize = 0;
        while (i < local_count.*) : (i += 1) {
            if (std.mem.eql(u8, local_names[i], name)) return i;
        }
        local_names[local_count.*] = name;
        local_count.* += 1;
        return local_count.* - 1;
    }

    fn instDest(inst: ir.Inst) ?ir.Reg {
        return switch (inst) {
            .const_int => |c| c.dest,
            .const_float => |c| c.dest,
            .const_bool => |c| c.dest,
            .const_string => |c| c.dest,
            .add_i64, .sub_i64, .mul_i64, .div_i64, .mod_i64 => |op| op.dest,
            .add_f64, .sub_f64, .mul_f64, .div_f64, .mod_f64 => |op| op.dest,
            .eq_i64, .neq_i64, .lt_i64, .gt_i64, .lte_i64, .gte_i64 => |op| op.dest,
            .eq_f64, .neq_f64, .lt_f64, .gt_f64, .lte_f64, .gte_f64 => |op| op.dest,
            .and_bool, .or_bool => |op| op.dest,
            .neg_i64, .neg_f64, .not_bool => |op| op.dest,
            .load_local => |l| l.dest,
            .call => |c| c.dest,
            .call_builtin => |c| c.dest,
            .struct_alloc => |sa| sa.dest,
            .struct_load => |sl| sl.dest,
            .list_new => |ln| ln.dest,
            .list_len => |ll| ll.dest,
            .list_get => |lg| lg.dest,
            .tag_get => |tg| tg.dest,
            .tag_value => |tv| tv.dest,
            .string_byte_at => |sb| sb.dest,
            .string_slice => |ss| ss.dest_ptr,
            // Note: string_slice also writes to dest_len but we handle that via max_reg scan
            .string_index => |si| si.dest,
            .string_len => |sl| sl.dest,
            .string_eq => |se| se.dest,
            .process_spawn => |ps| ps.dest,
            .process_send => |ps| ps.dest,
            .process_send_timeout => |ps| ps.dest,
            .process_state_get => |sg| sg.dest,
            else => null,
        };
    }

    fn isTerminator(inst: ir.Inst) bool {
        return switch (inst) {
            .jump, .branch, .ret => true,
            else => false,
        };
    }

    /// Get the emitted Zig source code.
    pub fn getSource(self: *ZigBackend) []const u8 {
        return self.out.items;
    }

    /// Write to file, compile with zig, produce binary.
    pub fn build(self: *ZigBackend, output_path: []const u8, zig_path: []const u8) !void {
        const zig_source = self.getSource();

        // Write .zig source
        const src_path = try std.fmt.allocPrint(self.alloc, "{s}.zig", .{output_path});
        const src_file = try std.fs.cwd().createFile(src_path, .{});
        try src_file.writeAll(zig_source);
        src_file.close();

        // Write runtime library alongside generated code
        const src_dir = std.fs.path.dirname(src_path) orelse ".";
        const rt_path = try std.fmt.allocPrint(self.alloc, "{s}/verve_runtime.zig", .{src_dir});
        const rt_file = try std.fs.cwd().createFile(rt_path, .{});
        try rt_file.writeAll(runtime_source);
        rt_file.close();

        // Compile with zig
        const emit_flag = try std.fmt.allocPrint(self.alloc, "-femit-bin={s}", .{output_path});
        var child = std.process.Child.init(
            &.{ zig_path, "build-exe", src_path, emit_flag },
            self.alloc,
        );
        child.stderr_behavior = .Pipe;
        try child.spawn();
        var stderr_buf: [8192]u8 = undefined;
        const stderr_n = if (child.stderr) |stderr| stderr.readAll(&stderr_buf) catch 0 else 0;
        const term = try child.wait();

        if (term != .Exited or term.Exited != 0) {
            if (stderr_n > 0) {
                std.debug.print("Zig compilation error:\n{s}\n", .{stderr_buf[0..stderr_n]});
            }
            return error.CompilationFailed;
        }

        // Clean up build artifacts
        std.fs.cwd().deleteFile(rt_path) catch {};
        std.fs.cwd().deleteTree(".zig-cache") catch {};
        const o_path = try std.fmt.allocPrint(self.alloc, "{s}.o", .{output_path});
        std.fs.cwd().deleteFile(o_path) catch {};
    }
};
