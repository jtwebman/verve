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

    const RegType = enum { int, float, boolean, string };

    fn regTypeFromIr(t: ir.Type) RegType {
        return switch (t) {
            .i64 => .int,
            .f64 => .float,
            .bool => .boolean,
            .string => .string,
            .void => .int,
        };
    }

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
            local_type_map.put(self.alloc, param.name, regTypeFromIr(param.type_)) catch {};
        }

        // First pass: determine types from direct sources
        for (func.blocks.items) |block| {
            for (block.insts.items) |inst| {
                switch (inst) {
                    .const_string => |c| types[c.dest] = .string,
                    .const_float => |c| types[c.dest] = .float,
                    .const_bool => |c| types[c.dest] = .boolean,
                    .add_f64, .sub_f64, .mul_f64, .div_f64, .mod_f64 => |op| types[op.dest] = .float,
                    .neg_f64 => |op| types[op.dest] = .float,
                    .eq_i64, .neq_i64, .lt_i64, .gt_i64, .lte_i64, .gte_i64 => |op| types[op.dest] = .boolean,
                    .eq_f64, .neq_f64, .lt_f64, .gt_f64, .lte_f64, .gte_f64 => |op| types[op.dest] = .boolean,
                    .and_bool, .or_bool => |op| types[op.dest] = .boolean,
                    .not_bool => |op| types[op.dest] = .boolean,
                    .string_eq => |se| types[se.dest] = .boolean,
                    .string_slice => |ss| types[ss.dest] = .string,
                    .string_index => |si| types[si.dest] = .string,
                    .call_builtin => |c| {
                        const rt = builtinReturnType(c.name);
                        if (rt != .int) types[c.dest] = rt;
                    },
                    .call => |c| {
                        for (self.program.functions.items) |f| {
                            if (std.mem.eql(u8, f.module, c.module) and std.mem.eql(u8, f.name, c.function)) {
                                types[c.dest] = regTypeFromIr(f.return_type);
                                break;
                            }
                        }
                    },
                    .struct_load => |sl| {
                        types[sl.dest] = self.lookupFieldType(sl.struct_name, sl.field_name);
                    },
                    .process_state_get => |sg| {
                        types[sg.dest] = self.lookupFieldType(sg.struct_name, sg.field_name);
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
                        if (s.src < types.len) {
                            local_type_map.put(self.alloc, s.name, types[s.src]) catch {};
                        }
                    },
                    .load_local => |l| {
                        if (local_type_map.get(l.name)) |lt| {
                            if (l.dest < types.len) {
                                types[l.dest] = lt;
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        return types;
    }

    /// Emit state struct allocation for a process after spawn.
    fn emitStateInit(self: *ZigBackend, process_name: []const u8, pid_reg: []const u8) void {
        for (self.program.process_decls.items) |pd| {
            if (std.mem.eql(u8, pd.name, process_name)) {
                if (pd.state_type) |st| {
                    // Allocate typed state struct, set pointer on the process
                    self.writeIndent();
                    self.writeFmt("{{ const _st = std.heap.page_allocator.create(VerveStruct_{s}) catch unreachable; _st.* = .{{}}; ", .{st});
                    self.writeFmt("rt.process_table[@intCast(@as(u64, @bitCast({s})) - 1)].state_ptr = @intFromPtr(_st); }}\n", .{pid_reg});
                }
                break;
            }
        }
    }

    fn lookupFieldType(self: *ZigBackend, struct_name: []const u8, field_name: []const u8) RegType {
        for (self.program.struct_decls.items) |sd| {
            if (std.mem.eql(u8, sd.name, struct_name)) {
                for (sd.fields) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) {
                        if (std.mem.eql(u8, f.type_name, "string")) return .string;
                        if (std.mem.eql(u8, f.type_name, "float")) return .float;
                        if (std.mem.eql(u8, f.type_name, "bool")) return .boolean;
                        return .int;
                    }
                }
            }
        }
        return .int;
    }

    // ── Builtin registry ────────────────────────────────────

    /// Describes how to emit a builtin call.
    const BuiltinSpec = struct {
        /// Runtime function name (null = same as builtin name, "!" = custom handler)
        rt_name: ?[]const u8 = null,
        min_args: u8 = 0,
        /// If true, emit `dest = 0;` after the call (void builtins)
        void_result: bool = false,
        /// Return type for register type tracking
        returns: RegType = .int,
    };

    const S = BuiltinSpec;
    const builtin_specs = std.StaticStringMap(BuiltinSpec).initComptime(.{
        // ── Math (int) ──────────────────────────────
        .{ "math_abs", S{ .min_args = 1 } },
        .{ "math_min", S{ .min_args = 2 } },
        .{ "math_max", S{ .min_args = 2 } },
        .{ "math_clamp", S{ .min_args = 3 } },
        .{ "math_pow", S{ .min_args = 2 } },
        .{ "math_sqrt", S{ .min_args = 1 } },
        .{ "math_log2", S{ .min_args = 1 } },
        // ── Math (float) ────────────────────────────
        .{ "math_abs_f", S{ .min_args = 1, .returns = .float } },
        .{ "math_floor", S{ .min_args = 1 } },
        .{ "math_ceil", S{ .min_args = 1 } },
        .{ "math_round", S{ .min_args = 1 } },
        .{ "math_sin", S{ .min_args = 1, .returns = .float } },
        .{ "math_cos", S{ .min_args = 1, .returns = .float } },
        .{ "math_tan", S{ .min_args = 1, .returns = .float } },
        .{ "math_sqrt_f", S{ .min_args = 1, .returns = .float } },
        .{ "math_pow_f", S{ .min_args = 2, .returns = .float } },
        .{ "math_log", S{ .min_args = 1, .returns = .float } },
        .{ "math_log10", S{ .min_args = 1, .returns = .float } },
        .{ "math_exp", S{ .min_args = 1, .returns = .float } },
        .{ "math_min_f", S{ .min_args = 2, .returns = .float } },
        .{ "math_max_f", S{ .min_args = 2, .returns = .float } },
        // ── Convert ─────────────────────────────────
        .{ "convert_to_float", S{ .min_args = 1, .returns = .float } },
        .{ "convert_to_int_f", S{ .min_args = 1 } },
        .{ "float_to_string", S{ .min_args = 1, .returns = .string } },
        .{ "string_to_float", S{ .min_args = 1, .returns = .float } },
        .{ "int_to_string", S{ .min_args = 1, .returns = .string } },
        .{ "string_to_int", S{ .min_args = 1 } },
        // ── String ──────────────────────────────────
        .{ "string_concat", S{ .rt_name = "verve_string_concat", .min_args = 2, .returns = .string } },
        .{ "string_trim", S{ .min_args = 1, .returns = .string } },
        .{ "string_replace", S{ .min_args = 3, .returns = .string } },
        .{ "string_char_at", S{ .min_args = 2, .returns = .string } },
        .{ "string_char_len", S{ .min_args = 1 } },
        .{ "string_split", S{ .min_args = 2 } },
        .{ "string_chars", S{ .min_args = 1 } },
        // ── String predicates (return bool) ─────────
        .{ "string_contains", S{ .rt_name = "!", .min_args = 2, .returns = .boolean } },
        .{ "string_starts_with", S{ .rt_name = "!", .min_args = 2, .returns = .boolean } },
        .{ "string_ends_with", S{ .rt_name = "!", .min_args = 2, .returns = .boolean } },
        // ── Env / System ────────────────────────────
        .{ "env_get", S{ .min_args = 1, .returns = .string } },
        .{ "system_exit", S{ .min_args = 1 } },
        .{ "system_time_ms", S{} },
        // ── Stream ──────────────────────────────────
        .{ "stream_read_line", S{ .min_args = 1, .returns = .string } },
        .{ "stream_read_bytes", S{ .min_args = 2, .returns = .string } },
        .{ "stream_read_all", S{ .rt_name = "streamReadAll", .min_args = 1, .returns = .string } },
        .{ "stream_write", S{ .min_args = 2, .void_result = true } },
        .{ "stream_write_line", S{ .min_args = 2, .void_result = true } },
        .{ "stream_close", S{ .min_args = 1, .void_result = true } },
        // ── File ────────────────────────────────────
        .{ "file_open", S{ .rt_name = "fileOpen", .min_args = 1 } },
        // ── TCP ─────────────────────────────────────
        .{ "tcp_open", S{ .min_args = 2 } },
        .{ "tcp_listen", S{ .min_args = 2 } },
        .{ "tcp_accept", S{ .min_args = 1 } },
        .{ "tcp_port", S{ .min_args = 1 } },
        // ── HTTP ────────────────────────────────────
        .{ "http_parse_request", S{ .min_args = 1 } },
        .{ "http_req_method", S{ .min_args = 1, .returns = .string } },
        .{ "http_req_path", S{ .min_args = 1, .returns = .string } },
        .{ "http_req_body", S{ .min_args = 1, .returns = .string } },
        .{ "http_req_header", S{ .min_args = 2, .returns = .string } },
        .{ "http_build_response", S{ .min_args = 3, .returns = .string } },
        // ── JSON ────────────────────────────────────
        .{ "json_get_string", S{ .min_args = 2, .returns = .string } },
        .{ "json_get_object", S{ .min_args = 2, .returns = .string } },
        .{ "json_get_int", S{ .min_args = 2 } },
        .{ "json_get_float", S{ .min_args = 2 } },
        .{ "json_get_bool", S{ .min_args = 2 } },
        .{ "json_get_array", S{ .min_args = 2 } },
        .{ "json_get_array_len", S{ .min_args = 2 } },
        .{ "json_to_int", S{ .min_args = 1 } },
        .{ "json_to_float", S{ .min_args = 1 } },
        .{ "json_to_bool", S{ .min_args = 1 } },
        .{ "json_to_string", S{ .min_args = 1, .returns = .string } },
        .{ "json_build_object", S{} },
        .{ "json_build_end", S{ .min_args = 1, .returns = .string } },
        .{ "json_build_add_string", S{ .min_args = 3, .void_result = true } },
        .{ "json_build_add_int", S{ .min_args = 3, .void_result = true } },
        .{ "json_build_add_float", S{ .min_args = 3, .void_result = true } },
        // ── Tags / Process ──────────────────────────
        .{ "make_tagged", S{ .rt_name = "makeTagged", .min_args = 2 } },
        .{ "process_exit", S{ .rt_name = "!", .void_result = true } },
        // ── Custom handlers (rt_name = "!") ─────────
        .{ "println", S{ .rt_name = "!" } },
        .{ "print", S{ .rt_name = "!" } },
        .{ "println_float", S{ .rt_name = "!" } },
        .{ "print_float", S{ .rt_name = "!" } },
        .{ "string_is_digit", S{ .rt_name = "!", .returns = .boolean } },
        .{ "string_is_alpha", S{ .rt_name = "!", .returns = .boolean } },
        .{ "string_is_whitespace", S{ .rt_name = "!", .returns = .boolean } },
        .{ "string_is_alnum", S{ .rt_name = "!", .returns = .boolean } },
        .{ "set_has", S{ .rt_name = "!" } },
        .{ "set_has_str", S{ .rt_name = "!" } },
        .{ "string_len", S{ .rt_name = "!" } },
        .{ "assert_check", S{ .rt_name = "!", .void_result = true } },
        .{ "json_build_add_bool", S{ .rt_name = "!", .void_result = true } },
    });

    fn builtinReturnType(name: []const u8) RegType {
        if (builtin_specs.get(name)) |spec| return spec.returns;
        return .int;
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

            // Allocate typed struct and copy parsed values
            self.writeFmt("const _sp = std.heap.page_allocator.create(VerveStruct_{s}) catch return rt.makeTagged(1, 0);\n", .{sd.name});
            for (sd.fields) |f| {
                if (std.mem.eql(u8, f.type_name, "string")) {
                    // Copy string data into arena so it survives json parser cleanup
                    self.writeFmt("    _sp.{s} = blk: {{ const sv = val.{s}; if (sv.len == 0) break :blk \"\"; const sb = rt.arena_alloc(sv.len) orelse break :blk \"\"; @memcpy(sb[0..sv.len], sv); break :blk sb[0..sv.len]; }};\n", .{ f.name, f.name });
                } else {
                    self.lineFmt("_sp.{s} = val.{s};", .{ f.name, f.name });
                }
            }

            self.line("return rt.makeTagged(0, @intCast(@intFromPtr(_sp)));");
            self.indent -= 1;
            self.line("}");
            self.line("");
        }

        // Emit per-process dispatch functions (binary message protocol)
        if (program.process_decls.items.len > 0) {
            for (program.process_decls.items, 0..) |pd, pdi| {
                self.writeFmt("fn verve_dispatch_{d}(_msg_ptr: [*]const u8, _msg_len: usize) i64 {{\n", .{pdi});
                self.indent += 1;
                self.line("_ = _msg_len;");
                self.line("const _hid = _msg_ptr[0];");
                self.line("return switch (_hid) {");
                self.indent += 1;
                for (pd.handler_names, 0..) |hname, hi| {
                    // Find handler function for param types
                    var handler_func: ?ir.Function = null;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            handler_func = f;
                            break;
                        }
                    }
                    if (handler_func) |hf| {
                        if (hf.params.len == 0) {
                            self.lineFmt("{d} => verve_{s}_{s}(),", .{ hi, pd.name, hname });
                        } else {
                            self.lineFmt("{d} => blk: {{", .{hi});
                            self.indent += 1;
                            // Decode params from binary message: skip header (2 bytes: handler_id + param_count)
                            self.line("var _pos: usize = 2;");
                            for (hf.params) |param| {
                                self.emitMsgDecode(param);
                            }
                            // Call handler with decoded params
                            self.writeIndent();
                            self.writeFmt("break :blk verve_{s}_{s}(", .{ pd.name, hname });
                            for (hf.params, 0..) |param, pi| {
                                if (pi > 0) self.write(", ");
                                self.writeFmt("_p_{s}", .{param.name});
                            }
                            self.write(");\n");
                            self.indent -= 1;
                            self.line("},");
                        }
                    } else {
                        self.lineFmt("{d} => verve_{s}_{s}(),", .{ hi, pd.name, hname });
                    }
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

        // Emit dispatch init if processes exist (same binary protocol as emit())
        if (program.process_decls.items.len > 0) {
            for (program.process_decls.items, 0..) |pd, pdi| {
                self.writeFmt("fn verve_dispatch_{d}(_msg_ptr: [*]const u8, _msg_len: usize) i64 {{\n", .{pdi});
                self.indent += 1;
                self.line("_ = _msg_len;");
                self.line("const _hid = _msg_ptr[0];");
                self.line("return switch (_hid) {");
                self.indent += 1;
                for (pd.handler_names, 0..) |hname, hi| {
                    var handler_func: ?ir.Function = null;
                    for (program.functions.items) |f| {
                        if (std.mem.eql(u8, f.module, pd.name) and std.mem.eql(u8, f.name, hname)) {
                            handler_func = f;
                            break;
                        }
                    }
                    if (handler_func) |hf| {
                        if (hf.params.len == 0) {
                            self.lineFmt("{d} => verve_{s}_{s}(),", .{ hi, pd.name, hname });
                        } else {
                            self.lineFmt("{d} => blk: {{", .{hi});
                            self.indent += 1;
                            self.line("var _pos: usize = 2;");
                            for (hf.params) |param| {
                                self.emitMsgDecode(param);
                            }
                            self.writeIndent();
                            self.writeFmt("break :blk verve_{s}_{s}(", .{ pd.name, hname });
                            for (hf.params, 0..) |param, pi| {
                                if (pi > 0) self.write(", ");
                                self.writeFmt("_p_{s}", .{param.name});
                            }
                            self.write(");\n");
                            self.indent -= 1;
                            self.line("},");
                        }
                    } else {
                        self.lineFmt("{d} => verve_{s}_{s}(),", .{ hi, pd.name, hname });
                    }
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
                } else if (param.type_ == .f64) {
                    self.writeFmt("param_{s}: f64", .{param.name});
                } else if (param.type_ == .bool) {
                    self.writeFmt("param_{s}: bool", .{param.name});
                } else {
                    self.writeFmt("param_{s}: i64", .{param.name});
                }
            }
            // Return type
            if (func.return_type == .f64) {
                self.write(") f64 {\n");
            } else if (func.return_type == .bool) {
                self.write(") bool {\n");
            } else {
                self.write(") i64 {\n");
            }
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
                } else if (r < reg_types.len and reg_types[r] == .float) {
                    self.lineFmt("var {s}: f64 = 0.0;", .{self.regName(r)});
                } else if (r < reg_types.len and reg_types[r] == .boolean) {
                    self.lineFmt("var {s}: bool = false;", .{self.regName(r)});
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
        self.line("var locals_float: [256]f64 = .{0.0} ** 256;");
        self.line("_ = &locals_float;");
        self.line("var locals_bool: [256]bool = .{false} ** 256;");
        self.line("_ = &locals_bool;");

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
                local_types[local_count] = regTypeFromIr(param.type_);
                local_count += 1;
            }
        } else {
            for (func.params) |param| {
                const pt = regTypeFromIr(param.type_);
                if (pt == .string) {
                    self.lineFmt("locals_str[{d}] = param_{s};", .{ local_count, param.name });
                } else if (pt == .float) {
                    self.lineFmt("locals_float[{d}] = param_{s};", .{ local_count, param.name });
                } else if (pt == .boolean) {
                    self.lineFmt("locals_bool[{d}] = param_{s};", .{ local_count, param.name });
                } else {
                    self.lineFmt("locals_int[{d}] = param_{s};", .{ local_count, param.name });
                }
                local_names[local_count] = param.name;
                local_types[local_count] = pt;
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
            if (func.return_type == .f64) {
                self.line("return 0.0;");
            } else if (func.return_type == .bool) {
                self.line("return false;");
            } else {
                self.line("return 0;");
            }
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
                if (pd.state_type) |st| {
                    self.lineFmt("{{ const _st = std.heap.page_allocator.create(VerveStruct_{s}) catch unreachable; _st.* = .{{}}; rt.process_table[@intCast(@as(u64, @bitCast(pid)) - 1)].state_ptr = @intFromPtr(_st); }}", .{st});
                }
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
            .const_bool => |c| self.lineFmt("{s} = {s};", .{ self.regName(c.dest), if (c.value) "true" else "false" }),
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
                self.lineFmt("{s} = {d};", .{ self.regName(cf.dest), cf.value });
            },

            .add_i64 => |op| self.lineFmt("{s} = rt.verve_add_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_i64 => |op| self.lineFmt("{s} = rt.verve_sub_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_i64 => |op| self.lineFmt("{s} = rt.verve_mul_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_i64 => |op| self.lineFmt("{s} = rt.verve_div_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mod_i64 => |op| self.lineFmt("{s} = rt.verve_mod_checked({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_i64 => |op| self.lineFmt("{s} = rt.verve_neg_checked({s});", .{ self.regName(op.dest), self.regName(op.operand) }),

            .add_f64 => |op| self.lineFmt("{s} = {s} + {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_f64 => |op| self.lineFmt("{s} = {s} - {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_f64 => |op| self.lineFmt("{s} = {s} * {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_f64 => |op| {
                self.lineFmt("{s} = {s} / {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) });
                self.lineFmt("{s} = rt.float_check_f64({s});", .{ self.regName(op.dest), self.regName(op.dest) });
            },
            .mod_f64 => |op| self.lineFmt("{s} = @mod({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_f64 => |op| self.lineFmt("{s} = -{s};", .{ self.regName(op.dest), self.regName(op.operand) }),

            .eq_f64 => |op| self.lineFmt("{s} = ({s} == {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_f64 => |op| self.lineFmt("{s} = ({s} != {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_f64 => |op| self.lineFmt("{s} = ({s} < {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_f64 => |op| self.lineFmt("{s} = ({s} > {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_f64 => |op| self.lineFmt("{s} = ({s} <= {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_f64 => |op| self.lineFmt("{s} = ({s} >= {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .eq_i64 => |op| self.lineFmt("{s} = (rt.verve_eq({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neq_i64 => |op| self.lineFmt("{s} = (rt.verve_neq({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lt_i64 => |op| self.lineFmt("{s} = (rt.verve_lt({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gt_i64 => |op| self.lineFmt("{s} = (rt.verve_gt({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .lte_i64 => |op| self.lineFmt("{s} = (rt.verve_lte({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .gte_i64 => |op| self.lineFmt("{s} = (rt.verve_gte({s}, {s}) != 0);", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),

            .and_bool => |op| self.lineFmt("{s} = {s} and {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .or_bool => |op| self.lineFmt("{s} = {s} or {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .not_bool => |op| self.lineFmt("{s} = !{s};", .{ self.regName(op.dest), self.regName(op.operand) }),

            .store_local => |s| {
                const idx = self.findOrAddLocal(s.name, local_names, local_count);
                const src_type = getRegType(reg_types, s.src);
                if (src_type == .string) {
                    self.lineFmt("locals_str[{d}] = {s};", .{ idx, self.regName(s.src) });
                } else if (src_type == .float) {
                    self.lineFmt("locals_float[{d}] = {s};", .{ idx, self.regName(s.src) });
                } else if (src_type == .boolean) {
                    self.lineFmt("locals_bool[{d}] = {s};", .{ idx, self.regName(s.src) });
                } else {
                    self.lineFmt("locals_int[{d}] = {s};", .{ idx, self.regName(s.src) });
                }
                local_types[idx] = src_type;
            },
            .load_local => |l| {
                const idx = self.findOrAddLocal(l.name, local_names, local_count);
                if (local_types[idx] == .string) {
                    self.lineFmt("{s} = locals_str[{d}];", .{ self.regName(l.dest), idx });
                } else if (local_types[idx] == .float) {
                    self.lineFmt("{s} = locals_float[{d}];", .{ self.regName(l.dest), idx });
                } else if (local_types[idx] == .boolean) {
                    self.lineFmt("{s} = locals_bool[{d}];", .{ self.regName(l.dest), idx });
                } else {
                    self.lineFmt("{s} = locals_int[{d}];", .{ self.regName(l.dest), idx });
                }
            },

            .jump => |j| self.lineFmt("block = {d}; continue;", .{j.target}),
            .branch => |b| {
                if (getRegType(reg_types, b.cond) == .boolean) {
                    self.lineFmt("block = if ({s}) {d} else {d}; continue;", .{ self.regName(b.cond), b.then_block, b.else_block });
                } else {
                    self.lineFmt("block = if ({s} != 0) {d} else {d}; continue;", .{ self.regName(b.cond), b.then_block, b.else_block });
                }
            },
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
                // Allocate typed struct with default values
                self.lineFmt("{{ const _sp = std.heap.page_allocator.create(VerveStruct_{s}) catch unreachable; _sp.* = .{{}}; {s} = @intCast(@intFromPtr(_sp)); }}", .{ sa.struct_name, self.regName(sa.dest) });
            },
            .struct_store => |ss| {
                // Direct typed field assignment — no slot arithmetic or bitcasting
                self.lineFmt("@as(*VerveStruct_{s}, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).{s} = {s};", .{ ss.struct_name, self.regName(ss.base), ss.field_name, self.regName(ss.src) });
            },
            .struct_load => |sl| {
                // Direct typed field access
                self.lineFmt("{s} = @as(*const VerveStruct_{s}, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).{s};", .{ self.regName(sl.dest), sl.struct_name, self.regName(sl.base), sl.field_name });
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
                self.lineFmt("{s} = std.mem.eql(u8, {s}, {s});", .{
                    self.regName(se.dest),
                    self.regName(se.lhs),
                    self.regName(se.rhs),
                });
            },

            .process_spawn => |ps| {
                self.lineFmt("{s} = rt.verve_spawn({d});", .{ self.regName(ps.dest), ps.process_type });
                // Allocate typed state struct if this process type has state
                if (ps.process_type < self.program.process_decls.items.len) {
                    const pd = self.program.process_decls.items[ps.process_type];
                    if (pd.state_fields.len > 0) {
                        // Find state struct name from the process declaration
                        // The state struct name matches the process's state_fields source
                        // We need it from the IR — look up via the process name's struct_decl
                        self.emitStateInit(pd.name, self.regName(ps.dest));
                    }
                }
            },
            .process_send => |ps| {
                self.writeIndent();
                self.write("{\n");
                self.indent += 1;
                self.line("var _msg_buf: [8192]u8 = undefined;");
                self.lineFmt("_msg_buf[0] = {d};", .{ps.handler_index});
                self.lineFmt("_msg_buf[1] = {d};", .{ps.args.len});
                if (ps.args.len > 0) {
                    self.line("var _mpos: usize = 2;");
                    for (ps.args) |arg| self.emitMsgEncode(arg, reg_types);
                    self.lineFmt("{s} = rt.verve_send({s}, &_msg_buf, _mpos);", .{ self.regName(ps.dest), self.regName(ps.target) });
                } else {
                    self.lineFmt("{s} = rt.verve_send({s}, &_msg_buf, 2);", .{ self.regName(ps.dest), self.regName(ps.target) });
                }
                self.indent -= 1;
                self.line("}");
            },
            .process_tell => |pt| {
                self.writeIndent();
                self.write("{\n");
                self.indent += 1;
                self.line("var _msg_buf: [8192]u8 = undefined;");
                self.lineFmt("_msg_buf[0] = {d};", .{pt.handler_index});
                self.lineFmt("_msg_buf[1] = {d};", .{pt.args.len});
                if (pt.args.len > 0) {
                    self.line("var _mpos: usize = 2;");
                    for (pt.args) |arg| self.emitMsgEncode(arg, reg_types);
                    self.lineFmt("rt.verve_tell({s}, &_msg_buf, _mpos);", .{self.regName(pt.target)});
                } else {
                    self.lineFmt("rt.verve_tell({s}, &_msg_buf, 2);", .{self.regName(pt.target)});
                }
                self.indent -= 1;
                self.line("}");
            },
            .process_state_get => |sg| {
                // Direct typed field access on process state struct
                self.lineFmt("{s} = @as(*const VerveStruct_{s}, @ptrFromInt(rt.verve_state_ptr())).{s};", .{ self.regName(sg.dest), sg.struct_name, sg.field_name });
            },
            .process_state_set => |ss| {
                self.lineFmt("@as(*VerveStruct_{s}, @ptrFromInt(rt.verve_state_ptr())).{s} = {s};", .{ ss.struct_name, ss.field_name, self.regName(ss.src) });
            },
            .process_watch => |pw| {
                self.lineFmt("rt.verve_watch({s});", .{self.regName(pw.target)});
            },
            .process_send_timeout => |ps| {
                self.writeIndent();
                self.write("{\n");
                self.indent += 1;
                self.line("var _msg_buf: [8192]u8 = undefined;");
                self.lineFmt("_msg_buf[0] = {d};", .{ps.handler_index});
                self.lineFmt("_msg_buf[1] = {d};", .{ps.args.len});
                if (ps.args.len > 0) {
                    self.line("var _mpos: usize = 2;");
                    for (ps.args) |arg| self.emitMsgEncode(arg, reg_types);
                    self.lineFmt("{s} = rt.verve_send_timeout({s}, &_msg_buf, _mpos, {s});", .{ self.regName(ps.dest), self.regName(ps.target), self.regName(ps.timeout_ms) });
                } else {
                    self.lineFmt("{s} = rt.verve_send_timeout({s}, &_msg_buf, 2, {s});", .{ self.regName(ps.dest), self.regName(ps.target), self.regName(ps.timeout_ms) });
                }
                self.indent -= 1;
                self.line("}");
            },

            .break_loop, .continue_loop => {},
        }
    }

    fn emitBuiltin(self: *ZigBackend, dest: ir.Reg, name: []const u8, args: []const ir.Reg, reg_types: []const RegType) void {
        // Special prefix: json_parse_struct:StructName
        if (std.mem.startsWith(u8, name, "json_parse_struct:")) {
            const struct_name = name["json_parse_struct:".len..];
            if (args.len >= 1) {
                self.lineFmt("{s} = verve_json_parse_{s}({s});", .{ self.regName(dest), struct_name, self.regName(args[0]) });
            }
            return;
        }

        const spec = builtin_specs.get(name) orelse {
            self.lineFmt("{s} = 0; // unknown builtin: {s}", .{ self.regName(dest), name });
            return;
        };

        // Custom handlers (rt_name = "!")
        if (spec.rt_name) |rn| {
            if (std.mem.eql(u8, rn, "!")) {
                self.emitCustomBuiltin(dest, name, args, reg_types);
                return;
            }
        }

        // Data-driven emission: dest = rt.fn_name(args...)
        if (args.len >= spec.min_args) {
            const rt_fn = spec.rt_name orelse name;
            if (spec.void_result) {
                // Void call: rt.fn(args...); dest = 0;
                self.writeIndent();
                self.writeFmt("rt.{s}(", .{rt_fn});
                for (args[0..spec.min_args], 0..) |arg, i| {
                    if (i > 0) self.write(", ");
                    self.write(self.regName(arg));
                }
                self.write(");\n");
            } else {
                // Value call: dest = rt.fn(args...);
                self.writeIndent();
                self.writeFmt("{s} = rt.{s}(", .{ self.regName(dest), rt_fn });
                for (args[0..spec.min_args], 0..) |arg, i| {
                    if (i > 0) self.write(", ");
                    self.write(self.regName(arg));
                }
                self.write(");\n");
            }
        }
        if (spec.void_result) {
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        }
    }

    /// Handle builtins that need custom emission logic.
    fn emitCustomBuiltin(self: *ZigBackend, dest: ir.Reg, name: []const u8, args: []const ir.Reg, reg_types: []const RegType) void {
        if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
            const newline = std.mem.eql(u8, name, "println");
            for (args) |arg| {
                switch (getRegType(reg_types, arg)) {
                    .string => self.lineFmt("rt.verve_write(1, {s});", .{self.regName(arg)}),
                    .float => self.lineFmt("{{ var _buf: [64]u8 = undefined; const _s = std.fmt.bufPrint(&_buf, \"{{d}}\", .{{{s}}}) catch \"?\"; rt.verve_write(1, _s); }}", .{self.regName(arg)}),
                    .boolean => self.lineFmt("rt.verve_write(1, if ({s}) \"true\" else \"false\");", .{self.regName(arg)}),
                    .int => self.lineFmt("{{ var _buf: [32]u8 = undefined; const _s = std.fmt.bufPrint(&_buf, \"{{d}}\", .{{{s}}}) catch \"?\"; rt.verve_write(1, _s); }}", .{self.regName(arg)}),
                }
            }
            if (newline) self.line("rt.verve_write(1, \"\\n\");");
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "println_float") or std.mem.eql(u8, name, "print_float")) {
            if (args.len >= 1) self.lineFmt("rt.verve_write_float(1, {s});", .{self.regName(args[0])});
            if (std.mem.eql(u8, name, "println_float")) self.line("rt.verve_write(1, \"\\n\");");
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "string_is_digit")) {
            if (args.len >= 1) self.lineFmt("{{ const _b = {s}[0]; {s} = (_b >= '0' and _b <= '9'); }}", .{ self.regName(args[0]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "string_is_alpha")) {
            if (args.len >= 1) self.lineFmt("{{ const _b = {s}[0]; {s} = ((_b >= 'A' and _b <= 'Z') or (_b >= 'a' and _b <= 'z')); }}", .{ self.regName(args[0]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "string_is_whitespace")) {
            if (args.len >= 1) self.lineFmt("{{ const _b = {s}[0]; {s} = (_b == ' ' or _b == '\\t' or _b == '\\n' or _b == '\\r'); }}", .{ self.regName(args[0]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "string_is_alnum")) {
            if (args.len >= 1) self.lineFmt("{{ const _b = {s}[0]; {s} = ((_b >= '0' and _b <= '9') or (_b >= 'A' and _b <= 'Z') or (_b >= 'a' and _b <= 'z')); }}", .{ self.regName(args[0]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "string_contains") or std.mem.eql(u8, name, "string_starts_with") or std.mem.eql(u8, name, "string_ends_with")) {
            if (args.len >= 2) self.lineFmt("{s} = (rt.{s}({s}, {s}) != 0);", .{ self.regName(dest), name, self.regName(args[0]), self.regName(args[1]) });
        } else if (std.mem.eql(u8, name, "set_has_str")) {
            if (args.len >= 2) self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si + 1 < list.len) : (si += 2) {{ const esl = rt.sliceFromPair(list.get(si), list.get(si + 1)); if (std.mem.eql(u8, esl, {s})) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "set_has")) {
            if (args.len >= 2) self.lineFmt("{{ const list = @as(*const rt.List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; var si: i64 = 0; while (si < list.len) : (si += 1) {{ if (list.get(si) == {s}) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
        } else if (std.mem.eql(u8, name, "string_len")) {
            if (args.len >= 1) self.lineFmt("{s} = @intCast({s}.len);", .{ self.regName(dest), self.regName(args[0]) });
        } else if (std.mem.eql(u8, name, "assert_check")) {
            if (args.len >= 1) {
                if (getRegType(reg_types, args[0]) == .boolean) {
                    self.lineFmt("rt.assert_check(if ({s}) @as(i64, 1) else @as(i64, 0));", .{self.regName(args[0])});
                } else {
                    self.lineFmt("rt.assert_check({s});", .{self.regName(args[0])});
                }
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "json_build_add_bool")) {
            if (args.len >= 3) {
                if (getRegType(reg_types, args[2]) == .boolean) {
                    self.lineFmt("rt.json_build_add_bool({s}, {s}, if ({s}) @as(i64, 1) else @as(i64, 0));", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
                } else {
                    self.lineFmt("rt.json_build_add_bool({s}, {s}, {s});", .{ self.regName(args[0]), self.regName(args[1]), self.regName(args[2]) });
                }
            }
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        } else if (std.mem.eql(u8, name, "process_exit")) {
            self.line("rt.verve_exit_self();");
            self.lineFmt("{s} = 0;", .{self.regName(dest)});
        }
    }

    /// Emit binary message decode for a single parameter from _msg_ptr at _pos.
    fn emitMsgDecode(self: *ZigBackend, param: ir.Function.Param) void {
        // Skip the type tag byte (1 byte)
        self.line("_pos += 1;");
        if (param.type_ == .string) {
            // Read u32 length, then copy bytes into arena (message buffer is temporary)
            self.writeFmt("    const _p_{s}_len", .{param.name});
            self.write(": usize = @as(u32, @bitCast([4]u8{ _msg_ptr[_pos], _msg_ptr[_pos+1], _msg_ptr[_pos+2], _msg_ptr[_pos+3] }));\n");
            self.line("_pos += 4;");
            self.writeIndent();
            self.writeFmt("const _p_{s}", .{param.name});
            self.writeFmt(": []const u8 = _s_{s}: {{ const _sb = rt.arena_alloc(_p_{s}_len) orelse break :_s_{s} \"\"; ", .{ param.name, param.name, param.name });
            self.writeFmt("@memcpy(_sb[0.._p_{s}_len], _msg_ptr[_pos.._pos + _p_{s}_len]); ", .{ param.name, param.name });
            self.writeFmt("break :_s_{s} _sb[0.._p_{s}_len]; }};\n", .{ param.name, param.name });
            self.writeFmt("    _pos += _p_{s}_len;\n", .{param.name});
        } else if (param.type_ == .f64) {
            // Read 8 bytes as f64
            self.lineFmt("const _p_{s}: f64 = @bitCast([8]u8{{ _msg_ptr[_pos], _msg_ptr[_pos+1], _msg_ptr[_pos+2], _msg_ptr[_pos+3], _msg_ptr[_pos+4], _msg_ptr[_pos+5], _msg_ptr[_pos+6], _msg_ptr[_pos+7] }});", .{param.name});
            self.line("_pos += 8;");
        } else if (param.type_ == .bool) {
            // Read 1 byte
            self.lineFmt("const _p_{s}: bool = (_msg_ptr[_pos] != 0);", .{param.name});
            self.line("_pos += 1;");
        } else {
            // Read 8 bytes as i64 (little-endian)
            self.lineFmt("const _p_{s}: i64 = @bitCast([8]u8{{ _msg_ptr[_pos], _msg_ptr[_pos+1], _msg_ptr[_pos+2], _msg_ptr[_pos+3], _msg_ptr[_pos+4], _msg_ptr[_pos+5], _msg_ptr[_pos+6], _msg_ptr[_pos+7] }});", .{param.name});
            self.line("_pos += 8;");
        }
    }

    /// Emit binary message encode for a single parameter. Writes to _msg_buf at _mpos.
    fn emitMsgEncode(self: *ZigBackend, reg: ir.Reg, reg_types: []const RegType) void {
        const t = getRegType(reg_types, reg);
        if (t == .string) {
            self.lineFmt("_msg_buf[_mpos] = 3; _mpos += 1;", .{}); // ArgType.string
            self.lineFmt("const _slen: u32 = @intCast({s}.len);", .{self.regName(reg)});
            self.line("_msg_buf[_mpos] = @truncate(_slen); _msg_buf[_mpos+1] = @truncate(_slen >> 8); _msg_buf[_mpos+2] = @truncate(_slen >> 16); _msg_buf[_mpos+3] = @truncate(_slen >> 24); _mpos += 4;");
            self.lineFmt("@memcpy(_msg_buf[_mpos.._mpos + {s}.len], {s}); _mpos += {s}.len;", .{ self.regName(reg), self.regName(reg), self.regName(reg) });
        } else if (t == .float) {
            self.lineFmt("_msg_buf[_mpos] = 1; _mpos += 1;", .{}); // ArgType.float
            self.lineFmt("const _fb: [8]u8 = @bitCast({s}); @memcpy(_msg_buf[_mpos.._mpos+8], &_fb); _mpos += 8;", .{self.regName(reg)});
        } else if (t == .boolean) {
            self.lineFmt("_msg_buf[_mpos] = 2; _mpos += 1;", .{}); // ArgType.boolean
            self.lineFmt("_msg_buf[_mpos] = if ({s}) 1 else 0; _mpos += 1;", .{self.regName(reg)});
        } else {
            self.lineFmt("_msg_buf[_mpos] = 0; _mpos += 1;", .{}); // ArgType.int
            self.lineFmt("const _ib: [8]u8 = @bitCast({s}); @memcpy(_msg_buf[_mpos.._mpos+8], &_ib); _mpos += 8;", .{self.regName(reg)});
        }
    }

    /// Emit process message args array, expanding string []const u8 to (ptr, len) i64 pairs.
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

        // Put source + runtime in unique dir per build to avoid parallel collisions
        const build_dir = try std.fmt.allocPrint(self.alloc, "{s}_build", .{output_path});
        std.fs.cwd().makePath(build_dir) catch {};

        const src_path = try std.fmt.allocPrint(self.alloc, "{s}/main.zig", .{build_dir});
        const src_file = try std.fs.cwd().createFile(src_path, .{});
        try src_file.writeAll(zig_source);
        src_file.close();

        const rt_path = try std.fmt.allocPrint(self.alloc, "{s}/verve_runtime.zig", .{build_dir});
        const rt_file = try std.fs.cwd().createFile(rt_path, .{});
        try rt_file.writeAll(runtime_source);
        rt_file.close();

        const emit_flag = try std.fmt.allocPrint(self.alloc, "-femit-bin={s}", .{output_path});
        const cache_dir = try std.fmt.allocPrint(self.alloc, "{s}_cache", .{output_path});
        var child = std.process.Child.init(
            &.{ zig_path, "build-exe", src_path, emit_flag, "--cache-dir", cache_dir },
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

        std.fs.cwd().deleteTree(build_dir) catch {};
        const o_path = try std.fmt.allocPrint(self.alloc, "{s}.o", .{output_path});
        std.fs.cwd().deleteFile(o_path) catch {};
    }
};
