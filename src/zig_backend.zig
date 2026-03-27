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

    // ── Register type tracking ───────────────────────────────

    const RegType = enum { int, string };

    /// Determine the type of each register in a function by scanning all instructions.
    /// Also tracks local variable types for load_local propagation.
    fn buildRegTypes(self: *ZigBackend, func: ir.Function) []RegType {
        var max_reg: ir.Reg = 0;
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                if (instDest(inst)) |d| {
                    if (d >= max_reg) max_reg = d + 1;
                }
            }
        }
        if (max_reg == 0) return &.{};
        const types = self.alloc.alloc(RegType, max_reg) catch return &.{};
        @memset(types, .int);

        // Build local name → type map by scanning store_local instructions
        var local_type_map = std.StringHashMapUnmanaged(RegType){};

        // Params set initial local types
        for (func.params) |param| {
            if (param.type_ == .string) {
                local_type_map.put(self.alloc, param.name, .string) catch {};
            }
        }

        // First pass: determine types from direct sources
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                switch (inst) {
                    .const_string => |c| types[c.dest] = .string,
                    .string_slice => |ss| types[ss.dest] = .string,
                    .string_index => |si| types[si.dest] = .string,
                    .call_builtin => |c| {
                        if (builtinReturnsString(c.name)) types[c.dest] = .string;
                    },
                    .call => |c| {
                        for (self.program.functions.items) |f| {
                            if (std.mem.eql(u8, f.module, c.module) and std.mem.eql(u8, f.name, c.function)) {
                                if (f.return_type == .string) types[c.dest] = .string;
                                break;
                            }
                        }
                    },
                    .struct_load => |sl| {
                        if (sl.is_string) types[sl.dest] = .string;
                    },
                    .process_state_get => |sg| {
                        if (sg.is_string) types[sg.dest] = .string;
                    },
                    else => {},
                }
            }
        }

        // Second pass: propagate through store_local / load_local
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                switch (inst) {
                    .store_local => |s| {
                        if (s.src < types.len and types[s.src] == .string) {
                            local_type_map.put(self.alloc, s.name, .string) catch {};
                        }
                    },
                    .load_local => |l| {
                        if (local_type_map.get(l.name)) |lt| {
                            if (lt == .string and l.dest < types.len) {
                                types[l.dest] = .string;
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        return types;
    }

    fn builtinReturnsString(name: []const u8) bool {
        const string_builtins = [_][]const u8{
            "string_concat",     "string_trim",     "string_replace",      "string_char_at",
            "int_to_string",     "float_to_string", "env_get",             "stream_read_line",
            "stream_read_bytes", "stream_read_all", "http_req_method",     "http_req_path",
            "http_req_body",     "http_req_header", "http_build_response", "json_get_string",
            "json_get_object",   "json_to_string",  "json_build_end",
        };
        for (string_builtins) |b| {
            if (std.mem.eql(u8, name, b)) return true;
        }
        return false;
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

            // Emit parse function for Json.parse typed struct parsing
            self.writeFmt("fn verve_json_parse_{s}(data: []const u8) i64 {{\n", .{sd.name});
            self.indent += 1;
            self.writeFmt("const parsed = std.json.parseFromSlice(VerveStruct_{s}, std.heap.page_allocator, data, .{{ .ignore_unknown_fields = true }}) catch return rt.makeTagged(1, 0);\n", .{sd.name});
            self.line("const val = parsed.value;");

            // Allocate Verve struct (string fields take 2 slots: ptr + len)
            var total_slots: u32 = 0;
            for (sd.fields) |f| {
                if (std.mem.eql(u8, f.type_name, "string")) {
                    total_slots += 2;
                } else {
                    total_slots += 1;
                }
            }
            self.lineFmt("const struct_mem = rt.arena_alloc({d} * @sizeOf(i64)) orelse return rt.makeTagged(1, 0);", .{total_slots});
            self.line("const fields = @as([*]i64, @ptrCast(@alignCast(struct_mem)));");

            var slot: u32 = 0;
            for (sd.fields) |f| {
                if (std.mem.eql(u8, f.type_name, "int")) {
                    self.lineFmt("fields[{d}] = val.{s};", .{ slot, f.name });
                    slot += 1;
                } else if (std.mem.eql(u8, f.type_name, "float")) {
                    self.lineFmt("fields[{d}] = @bitCast(val.{s});", .{ slot, f.name });
                    slot += 1;
                } else if (std.mem.eql(u8, f.type_name, "bool")) {
                    self.lineFmt("fields[{d}] = if (val.{s}) @as(i64, 1) else @as(i64, 0);", .{ slot, f.name });
                    slot += 1;
                } else if (std.mem.eql(u8, f.type_name, "string")) {
                    self.writeFmt("    {{ const sv = val.{s}; if (sv.len == 0) {{ fields[{d}] = 0; fields[{d}] = 0; }} else if (rt.arena_alloc(sv.len)) |sb| {{ @memcpy(sb[0..sv.len], sv); fields[{d}] = @intCast(@intFromPtr(sb)); fields[{d}] = @intCast(sv.len); }} else {{ fields[{d}] = 0; fields[{d}] = 0; }} }}\n", .{ f.name, slot, slot + 1, slot, slot + 1, slot, slot + 1 });
                    slot += 2;
                } else {
                    self.lineFmt("fields[{d}] = 0;", .{slot});
                    slot += 1;
                }
            }

            self.line("return rt.makeTagged(0, @intCast(@intFromPtr(fields)));");
            self.indent -= 1;
            self.line("}");
            self.line("");
        }

        // Emit per-process dispatch functions
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
                    // Find the function to get param types
                    var handler_func: ?ir.Function = null;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            handler_func = f;
                            break;
                        }
                    }
                    if (handler_func) |hf| {
                        var arg_idx: usize = 0;
                        for (hf.params, 0..) |param, pi| {
                            if (pi > 0) self.write(", ");
                            if (param.type_ == .string) {
                                // String params: convert (ptr, len) pair from args to []const u8
                                self.writeFmt("rt.sliceFromPair(args[{d}], args[{d}])", .{ arg_idx, arg_idx + 1 });
                                arg_idx += 2;
                            } else {
                                self.writeFmt("args[{d}]", .{arg_idx});
                                arg_idx += 1;
                            }
                        }
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

        // Emit functions (non-main first, main last for Zig ordering)
        for (program.functions.items) |func| {
            if (!std.mem.eql(u8, func.name, "main")) {
                self.emitFunction(func, false);
                self.line("");
            }
        }
        // Check if main is a process handler
        var main_is_process = false;
        for (program.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "main")) {
                for (program.process_decls.items) |pd| {
                    if (std.mem.eql(u8, pd.name, func.module)) {
                        main_is_process = true;
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
                    self.emitProcessMainWrapper(func);
                } else {
                    self.emitFunction(func, true);
                }
            }
        }
    }

    /// Emit a test runner program.
    pub fn emitTestRunner(self: *ZigBackend, program: ir.Program) void {
        self.program = program;
        self.line("const std = @import(\"std\");");
        self.line("const rt = @import(\"verve_runtime.zig\");");
        self.line("");

        // Emit struct definitions
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
                    var handler_func: ?ir.Function = null;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            handler_func = f;
                            break;
                        }
                    }
                    if (handler_func) |hf| {
                        var arg_idx: usize = 0;
                        for (hf.params, 0..) |param, pi| {
                            if (pi > 0) self.write(", ");
                            if (param.type_ == .string) {
                                self.writeFmt("rt.sliceFromPair(args_ptr[{d}], args_ptr[{d}])", .{ arg_idx, arg_idx + 1 });
                                arg_idx += 2;
                            } else {
                                self.writeFmt("args_ptr[{d}]", .{arg_idx});
                                arg_idx += 1;
                            }
                        }
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

        // Emit all functions
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
            self.line("rt.assert_fail_count = 0;");
            self.writeFmt("    _ = verve_{s}_{s}();\n", .{ module, fn_name });
            self.line("if (rt.assert_fail_count == 0) {");
            self.indent += 1;
            self.writeFmt("rt.verve_write(1, \"PASS: {s}\\n\");\n", .{test_name});
            self.line("passed += 1;");
            self.indent -= 1;
            self.line("} else {");
            self.indent += 1;
            self.writeFmt("rt.verve_write(1, \"FAIL: {s}\\n\");\n", .{test_name});
            self.line("failed += 1;");
            self.indent -= 1;
            self.line("}");
        }

        self.line("{");
        self.indent += 1;
        self.line("var buf: [128]u8 = undefined;");
        self.line("const s = std.fmt.bufPrint(&buf, \"\\n{d} passed, {d} failed\\n\", .{passed, failed}) catch \"?\";");
        self.line("rt.verve_write(1, s);");
        self.indent -= 1;
        self.line("}");
        self.line("if (failed > 0) std.process.exit(1);");

        self.indent -= 1;
        self.line("}");
    }

    fn emitFunction(self: *ZigBackend, func: ir.Function, is_entry: bool) void {
        const reg_types = self.buildRegTypes(func);

        if (is_entry) {
            self.line("pub fn main() void {");
            self.indent += 1;
            self.line("rt.verve_runtime_init();");
            if (self.program.process_decls.items.len > 0) {
                self.line("verve_init_dispatch();");
            }
            self.line("var verve_args_list = rt.List.init();");
            self.line("var proc_args = std.process.argsWithAllocator(std.heap.page_allocator) catch return;");
            self.line("_ = proc_args.skip();");
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
                if (param.type_ == .string) {
                    self.writeFmt("param_{s}: []const u8", .{param.name});
                } else {
                    self.writeFmt("param_{s}: i64", .{param.name});
                }
            }
            self.write(") i64 {\n");
        }
        self.indent += 1;

        // Declare all registers as variables with correct types
        var max_reg: ir.Reg = 0;
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                if (instDest(inst)) |d| {
                    if (d >= max_reg) max_reg = d + 1;
                }
            }
        }
        if (max_reg > 0) {
            var r: ir.Reg = 0;
            while (r < max_reg) : (r += 1) {
                if (r < reg_types.len and reg_types[r] == .string) {
                    self.lineFmt("var {s}: []const u8 = \"\";", .{self.regName(r)});
                } else {
                    self.lineFmt("var {s}: i64 = 0;", .{self.regName(r)});
                }
                self.lineFmt("_ = &{s};", .{self.regName(r)});
            }
        }

        // Declare local variable arrays — separate for ints and strings
        self.line("var locals_int: [256]i64 = undefined;");
        self.line("_ = &locals_int;");
        self.line("var locals_str: [256][]const u8 = .{\"\"} ** 256;");
        self.line("_ = &locals_str;");

        // Track local name → index mapping and types
        var local_count: usize = 0;
        var local_names: [128][]const u8 = undefined;
        var local_types: [128]RegType = undefined;
        @memset(&local_types, .int);

        // Map param names to locals
        if (is_entry) {
            for (func.params) |param| {
                if (std.mem.eql(u8, param.name, "args")) {
                    self.lineFmt("locals_int[{d}] = @intCast(@intFromPtr(&verve_args_list));", .{local_count});
                }
                local_names[local_count] = param.name;
                local_types[local_count] = if (param.type_ == .string) .string else .int;
                local_count += 1;
            }
        } else {
            for (func.params) |param| {
                if (param.type_ == .string) {
                    self.lineFmt("locals_str[{d}] = param_{s};", .{ local_count, param.name });
                    local_types[local_count] = .string;
                } else {
                    self.lineFmt("locals_int[{d}] = param_{s};", .{ local_count, param.name });
                    local_types[local_count] = .int;
                }
                local_names[local_count] = param.name;
                local_count += 1;
            }
        }

        // Emit blocks
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
                if (terminated) break;
                self.emitInst(inst, &local_names, &local_count, &local_types, reg_types, is_entry);
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
        self.line("verve_init_dispatch();");
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

    fn getRegType(reg_types: []const RegType, reg: ir.Reg) RegType {
        if (reg < reg_types.len) return reg_types[reg];
        return .int;
    }

    fn emitInst(self: *ZigBackend, inst: ir.Inst, local_names: *[128][]const u8, local_count: *usize, local_types: *[128]RegType, reg_types: []const RegType, is_entry: bool) void {
        switch (inst) {
            .const_int => |c| self.lineFmt("{s} = {d};", .{ self.regName(c.dest), c.value }),
            .const_bool => |c| self.lineFmt("{s} = {d};", .{ self.regName(c.dest), @as(i64, if (c.value) 1 else 0) }),
            .const_string => |c| {
                // String register — assign directly as []const u8
                self.writeIndent();
                self.writeFmt("{s} = \"", .{self.regName(c.dest)});
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
                self.write("\";\n");
            },
            .const_float => |cf| {
                self.lineFmt("{s} = @bitCast(@as(f64, {d}));", .{ self.regName(cf.dest), cf.value });
            },

            .add_i64 => |op| self.lineFmt("{s} = rt.verve_add_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_i64 => |op| self.lineFmt("{s} = rt.verve_sub_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_i64 => |op| self.lineFmt("{s} = rt.verve_mul_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_i64 => |op| self.lineFmt("{s} = rt.verve_div_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mod_i64 => |op| self.lineFmt("{s} = rt.verve_mod_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_i64 => |op| self.lineFmt("{s} = rt.verve_neg_checked({s});", .{ self.regName(op.dest), self.regName(op.operand) }),

            .add_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) + @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) - @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_f64 => |op| self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) * @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_f64 => |op| {
                self.lineFmt("{s} = @bitCast(@as(f64, @bitCast({s})) / @as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) });
                self.lineFmt("{s} = rt.float_check({s});", .{ self.regName(op.dest), self.regName(op.dest) });
            },
            .mod_f64 => |op| self.lineFmt("{s} = @bitCast(@mod(@as(f64, @bitCast({s})), @as(f64, @bitCast({s}))));", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_f64 => |op| self.lineFmt("{s} = @bitCast(-@as(f64, @bitCast({s})));", .{ self.regName(op.dest), self.regName(op.operand) }),

            .eq_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) == @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) != @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) < @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) > @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) <= @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_f64 => |op| self.lineFmt("{s} = if (@as(f64, @bitCast({s})) >= @as(f64, @bitCast({s}))) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .eq_i64 => |op| self.lineFmt("{s} = rt.verve_eq({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_i64 => |op| self.lineFmt("{s} = rt.verve_neq({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_i64 => |op| self.lineFmt("{s} = rt.verve_lt({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_i64 => |op| self.lineFmt("{s} = rt.verve_gt({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_i64 => |op| self.lineFmt("{s} = rt.verve_lte({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_i64 => |op| self.lineFmt("{s} = rt.verve_gte({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .and_bool => |op| self.lineFmt("{s} = if ({s} != 0 and {s} != 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .or_bool => |op| self.lineFmt("{s} = if ({s} != 0 or {s} != 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .not_bool => |op| self.lineFmt("{s} = if ({s} == 0) @as(i64, 1) else @as(i64, 0);", .{ self.regName(op.dest), self.regName(op.operand) }),

            .store_local => |s| {
                const idx = self.findOrAddLocal(s.name, local_names, local_count);
                const src_type = getRegType(reg_types, s.src);
                if (src_type == .string) {
                    self.lineFmt("locals_str[{d}] = {s};", .{ idx, self.regName(s.src) });
                    local_types[idx] = .string;
                } else {
                    self.lineFmt("locals_int[{d}] = {s};", .{ idx, self.regName(s.src) });
                    local_types[idx] = .int;
                }
            },
            .load_local => |l| {
                const idx = self.findOrAddLocal(l.name, local_names, local_count);
                if (local_types[idx] == .string) {
                    self.lineFmt("{s} = locals_str[{d}];", .{ self.regName(l.dest), idx });
                } else {
                    self.lineFmt("{s} = locals_int[{d}];", .{ self.regName(l.dest), idx });
                }
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
            .call_builtin => |c| self.emitBuiltin(c.dest, c.name, c.args, reg_types),

            .struct_alloc => |sa| {
                self.lineFmt("{s} = @intCast(@intFromPtr((std.heap.page_allocator.alloc(i64, {d}) catch &.{{}}).ptr));", .{ self.regName(sa.dest), sa.num_fields });
            },
            .struct_store => |ss| {
                if (ss.is_string) {
                    // Convert []const u8 to (ptr, len) pair in adjacent slots
                    self.lineFmt("{{ const _ss = {s}; const _base = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); _base[{d}] = @intCast(@intFromPtr(_ss.ptr)); _base[{d}] = @intCast(_ss.len); }}", .{ self.regName(ss.src), self.regName(ss.base), ss.field_index, ss.field_index + 1 });
                } else {
                    self.lineFmt("@as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[{d}] = {s};", .{ self.regName(ss.base), ss.field_index, self.regName(ss.src) });
                }
            },
            .struct_load => |sl| {
                if (sl.is_string) {
                    // Load (ptr, len) pair from adjacent slots, convert to []const u8
                    self.lineFmt("{{ const _base = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); {s} = rt.sliceFromPair(_base[{d}], _base[{d}]); }}", .{ self.regName(sl.base), self.regName(sl.dest), sl.field_index, sl.field_index + 1 });
                } else {
                    self.lineFmt("{s} = @as([*]const i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[{d}];", .{ self.regName(sl.dest), self.regName(sl.base), sl.field_index });
                }
            },

            .list_new => |ln| {
                self.lineFmt("{{ const lm = rt.arena_alloc(@sizeOf(rt.List)) orelse @as([*]u8, undefined); const lp = @as(*rt.List, @ptrCast(@alignCast(lm))); lp.* = rt.List.init(); {s} = @intCast(@intFromPtr(lp)); }}", .{self.regName(ln.dest)});
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
                self.lineFmt("{s} = {s}[@intCast(@as(u64, @bitCast({s})))];", .{ self.regName(sb.dest), self.regName(sb.str), self.regName(sb.index) });
            },
            .string_slice => |ss| {
                // dest = str[start..end] — str is []const u8, start/end are i64
                self.lineFmt("{s} = {s}[@intCast(@as(u64, @bitCast({s})))..@intCast(@as(u64, @bitCast({s})))];", .{ self.regName(ss.dest), self.regName(ss.str), self.regName(ss.start), self.regName(ss.end) });
            },
            .string_index => |si| {
                // s[i] → single-char string slice
                self.lineFmt("{{ const _si: usize = @intCast(@as(u64, @bitCast({s}))); {s} = {s}[_si .. _si + 1]; }}", .{ self.regName(si.index), self.regName(si.dest), self.regName(si.str) });
            },
            .string_len => |sl| {
                // str is []const u8, just get .len
                self.lineFmt("{s} = @intCast({s}.len);", .{ self.regName(sl.dest), self.regName(sl.str) });
            },
            .string_eq => |se| {
                // Both are []const u8, use std.mem.eql
                self.lineFmt("{s} = if (std.mem.eql(u8, {s}, {s})) @as(i64, 1) else @as(i64, 0);", .{
                    self.regName(se.dest),
                    self.regName(se.lhs),
                    self.regName(se.rhs),
                });
            },

            .process_spawn => |ps| {
                self.lineFmt("{s} = rt.verve_spawn({d});", .{ self.regName(ps.dest), ps.process_type });
            },
            .process_send => |ps| {
                // String args need expansion to (ptr, len) i64 pairs
                self.emitProcessArgs(ps.args, reg_types);
                const total = self.countProcessArgs(ps.args, reg_types);
                self.lineFmt("{s} = rt.verve_send({s}, {d}, &_proc_args, {d});", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index, total });
                self.line("}");
            },
            .process_tell => |pt| {
                self.emitProcessArgs(pt.args, reg_types);
                const total = self.countProcessArgs(pt.args, reg_types);
                self.lineFmt("rt.verve_tell({s}, {d}, &_proc_args, {d});", .{ self.regName(pt.target), pt.handler_index, total });
                self.line("}");
            },
            .process_state_get => |sg| {
                if (sg.is_string) {
                    // Load ptr+len from adjacent state slots, convert to []const u8
                    self.lineFmt("{s} = rt.sliceFromPair(rt.verve_state_get({d}), rt.verve_state_get({d}));", .{ self.regName(sg.dest), sg.field_index, sg.field_index + 1 });
                } else {
                    self.lineFmt("{s} = rt.verve_state_get({d});", .{ self.regName(sg.dest), sg.field_index });
                }
            },
            .process_state_set => |ss| {
                if (ss.is_string) {
                    // Convert []const u8 to ptr+len, store in adjacent state slots
                    self.lineFmt("{{ const _sv = {s}; rt.verve_state_set({d}, @intCast(@intFromPtr(_sv.ptr))); rt.verve_state_set({d}, @intCast(_sv.len)); }}", .{ self.regName(ss.src), ss.field_index, ss.field_index + 1 });
                } else {
                    self.lineFmt("rt.verve_state_set({d}, {s});", .{ ss.field_index, self.regName(ss.src) });
                }
            },
            .process_watch => |pw| {
                self.lineFmt("rt.verve_watch({s});", .{self.regName(pw.target)});
            },
            .process_send_timeout => |ps| {
                self.emitProcessArgs(ps.args, reg_types);
                const total = self.countProcessArgs(ps.args, reg_types);
                self.lineFmt("{s} = rt.verve_send_timeout({s}, {d}, &_proc_args, {d}, {s});", .{ self.regName(ps.dest), self.regName(ps.target), ps.handler_index, total, self.regName(ps.timeout_ms) });
                self.line("}");
            },

            .break_loop, .continue_loop => {},
        }
    }

    fn emitBuiltin(self: *ZigBackend, dest: ir.Reg, name: []const u8, args: []const ir.Reg, reg_types: []const RegType) void {
        if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
            const newline = std.mem.eql(u8, name, "println");
            // Each arg is a single register. Check its type to decide how to print.
            for (args) |arg| {
                const t = getRegType(reg_types, arg);
                if (t == .string) {
                    self.lineFmt("rt.verve_write(1, {s});", .{self.regName(arg)});
                } else {
                    // Integer — format it
                    self.lineFmt("{{ var _buf: [32]u8 = undefined; const _s = std.fmt.bufPrint(&_buf, \"{{d}}\", .{{{s}}}) catch \"?\"; rt.verve_write(1, _s); }}", .{self.regName(arg)});
                }
            }
            if (newline) {
                self.line("rt.verve_write(1, \"\\n\");");
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "println_float")) {
            if (args.len >= 1) {
                self.lineFmt("rt.verve_write_float(1, {s});", .{self.regName(args[0])});
                self.line("rt.verve_write(1, \"\\n\");");
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "print_float")) {
            if (args.len >= 1) {
                self.lineFmt("rt.verve_write_float(1, {s});", .{self.regName(args[0])});
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "string_is_digit")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const _b = {s}[0]; {s} = if (_b >= '0' and _b <= '9') @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_alpha")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const _b = {s}[0]; {s} = if ((_b >= 'A' and _b <= 'Z') or (_b >= 'a' and _b <= 'z')) @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_whitespace")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const _b = {s}[0]; {s} = if (_b == ' ' or _b == '\\t' or _b == '\\n' or _b == '\\r') @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "string_is_alnum")) {
            if (args.len >= 1) {
                self.lineFmt("{{ const _b = {s}[0]; {s} = if ((_b >= '0' and _b <= '9') or (_b >= 'A' and _b <= 'Z') or (_b >= 'a' and _b <= 'z')) @as(i64, 1) else @as(i64, 0); }}", .{ self.regName(args[0]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "set_has") or std.mem.eql(u8, name, "set_has_str")) {
            if (std.mem.eql(u8, name, "set_has_str") and args.len >= 2) {
                self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si + 1 < list.len) : (si += 2) {{ const esl = rt.sliceFromPair(list.get(si), list.get(si + 1)); if (std.mem.eql(u8, esl, {s})) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
            } else if (args.len >= 2) {
                self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si < list.len) : (si += 1) {{ if (list.get(si) == {s}) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "file_open")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.fileOpen({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "stream_read_all")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.streamReadAll({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "stream_write")) {
            if (args.len >= 2) {
                self.lineFmt("rt.stream_write({s}, {s});", .{ self.regName(args[0]), self.regName(args[1]) });
                self.lineFmt("{s} = 0;", .{self.regName(dest)});
            }
        } else if (std.mem.eql(u8, name, "stream_write_line")) {
            if (args.len >= 2) {
                self.lineFmt("rt.stream_write_line({s}, {s});", .{ self.regName(args[0]), self.regName(args[1]) });
                self.lineFmt("{s} = 0;", .{self.regName(dest)});
            }
        } else if (std.mem.eql(u8, name, "stream_read_bytes")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.stream_read_bytes({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
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
            if (args.len >= 1) self.lineFmt("{s} = rt.string_to_float({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "env_get")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.env_get({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "system_exit")) {
            if (args.len >= 1) self.lineFmt("rt.system_exit({s});", .{self.regName(args[0])});
        } else if (std.mem.eql(u8, name, "system_time_ms")) {
            self.lineFmt("{s} = rt.system_time_ms();", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "int_to_string")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.int_to_string({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "string_to_int")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.string_to_int({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "string_concat")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.verve_string_concat({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "string_len")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = @intCast({s}.len);", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "string_contains") or std.mem.eql(u8, name, "string_starts_with") or std.mem.eql(u8, name, "string_ends_with")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.{s}({s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "string_trim")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.string_trim({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "string_replace")) {
            if (args.len >= 3) {
                self.lineFmt("{s} = rt.string_replace({s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            }
        } else if (std.mem.eql(u8, name, "string_char_at")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.string_char_at({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "string_char_len")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.string_char_len({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "string_split")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.string_split({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "string_chars")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.string_chars({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "json_get_string") or std.mem.eql(u8, name, "json_get_object")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.{s}({s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "json_get_int") or std.mem.eql(u8, name, "json_get_float") or
            std.mem.eql(u8, name, "json_get_bool") or
            std.mem.eql(u8, name, "json_get_array") or std.mem.eql(u8, name, "json_get_array_len"))
        {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.{s}({s}, {s});", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "json_to_int") or std.mem.eql(u8, name, "json_to_float") or
            std.mem.eql(u8, name, "json_to_bool") or std.mem.eql(u8, name, "json_to_string"))
        {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.{s}({s});", .{ self.regName(dest), name, self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "assert_check")) {
            if (args.len >= 1) self.lineFmt("rt.assert_check({s});", .{self.regName(args[0])});
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "process_exit")) {
            self.line("rt.verve_exit_self();");
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.startsWith(u8, name, "json_parse_struct:")) {
            const struct_name = name["json_parse_struct:".len..];
            if (args.len >= 1) {
                self.lineFmt("{s} = verve_json_parse_{s}({s});", .{ self.regName(dest), struct_name, self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "json_build_object")) {
            self.lineFmt("{s} = rt.json_build_object();", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_end")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.json_build_end({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "json_build_add_string")) {
            if (args.len >= 3) self.lineFmt("rt.json_build_add_string({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_int")) {
            if (args.len >= 3) self.lineFmt("rt.json_build_add_int({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_float")) {
            if (args.len >= 3) self.lineFmt("rt.json_build_add_float({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_bool")) {
            if (args.len >= 3) self.lineFmt("rt.json_build_add_bool({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "http_parse_request")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.http_parse_request({s});", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "http_req_method") or std.mem.eql(u8, name, "http_req_path") or std.mem.eql(u8, name, "http_req_body")) {
            if (args.len >= 1) self.lineFmt("{s} = rt.{s}({s});", .{ self.regName(dest), name, self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "http_req_header")) {
            if (args.len >= 2) self.lineFmt("{s} = rt.http_req_header({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "http_build_response")) {
            if (args.len >= 3) self.lineFmt("{s} = rt.http_build_response({s}, {s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
        } else if (std.mem.eql(u8, name, "tcp_open")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.tcp_open({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "tcp_listen")) {
            if (args.len >= 2) {
                self.lineFmt("{s} = rt.tcp_listen({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "tcp_accept")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = rt.tcp_accept({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
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

    /// Emit process message args array, expanding string []const u8 to (ptr, len) i64 pairs.
    fn emitProcessArgs(self: *ZigBackend, args: []const ir.Reg, reg_types: []const RegType) void {
        if (args.len == 0) {
            self.line("{ const _proc_args = [_]i64{0};");
            return;
        }
        self.writeIndent();
        self.write("{ ");
        // Count total i64 slots needed
        const total = self.countProcessArgs(args, reg_types);
        self.writeFmt("var _proc_args: [{d}]i64 = undefined; ", .{total});
        var slot: usize = 0;
        for (args) |arg| {
            if (getRegType(reg_types, arg) == .string) {
                self.writeFmt("_proc_args[{d}] = @intCast(@intFromPtr({s}.ptr)); _proc_args[{d}] = @intCast({s}.len); ", .{ slot, self.regName(arg), slot + 1, self.regName(arg) });
                slot += 2;
            } else {
                self.writeFmt("_proc_args[{d}] = {s}; ", .{ slot, self.regName(arg) });
                slot += 1;
            }
        }
        self.write("\n");
    }

    fn countProcessArgs(self: *ZigBackend, args: []const ir.Reg, reg_types: []const RegType) usize {
        _ = self;
        var total: usize = 0;
        for (args) |arg| {
            if (getRegType(reg_types, arg) == .string) {
                total += 2;
            } else {
                total += 1;
            }
        }
        return if (total == 0) 1 else total; // at least 1 for empty args
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
            .string_slice => |ss| ss.dest,
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

        const src_path = try std.fmt.allocPrint(self.alloc, "{s}.zig", .{output_path});
        const src_file = try std.fs.cwd().createFile(src_path, .{});
        try src_file.writeAll(zig_source);
        src_file.close();

        const src_dir = std.fs.path.dirname(src_path) orelse ".";
        const rt_path = try std.fmt.allocPrint(self.alloc, "{s}/verve_runtime.zig", .{src_dir});
        const rt_file = try std.fs.cwd().createFile(rt_path, .{});
        try rt_file.writeAll(runtime_source);
        rt_file.close();

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

        std.fs.cwd().deleteFile(rt_path) catch {};
        std.fs.cwd().deleteTree(".zig-cache") catch {};
        const o_path = try std.fmt.allocPrint(self.alloc, "{s}.o", .{output_path});
        std.fs.cwd().deleteFile(o_path) catch {};
    }
};
