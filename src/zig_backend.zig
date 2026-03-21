const std = @import("std");
const ir = @import("ir.zig");

/// Zig code emitter backend.
/// Consumes target-independent IR, emits Zig source code.
/// Compile with `zig build-exe` for native binary.

pub const ZigBackend = struct {
    alloc: std.mem.Allocator,
    out: std.ArrayListUnmanaged(u8),
    indent: usize,

    pub fn init(alloc: std.mem.Allocator) ZigBackend {
        return .{
            .alloc = alloc,
            .out = .{},
            .indent = 0,
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

    pub fn emit(self: *ZigBackend, program: ir.Program) void {
        // Preamble
        self.line("const std = @import(\"std\");");
        self.line("");
        self.line("// ── Runtime helpers ──────────────────────────────");
        self.line("fn verve_write(fd: i64, ptr: [*]const u8, len: i64) void {");
        self.indent += 1;
        self.line("const f = std.posix.STDOUT_FILENO;");
        self.line("_ = fd;");
        self.line("const actual_len: usize = if (len > 0) @intCast(@as(u64, @bitCast(len))) else blk: { var l: usize = 0; while (ptr[l] != 0) l += 1; break :blk l; };");
        self.line("const slice = ptr[0..actual_len];");
        self.line("_ = std.posix.write(f, slice) catch 0;");
        self.indent -= 1;
        self.line("}");
        self.line("");
        self.line("const List = struct {");
        self.indent += 1;
        self.line("items: [*]i64,");
        self.line("len: i64,");
        self.line("cap: i64,");
        self.line("pub fn init() List {");
        self.indent += 1;
        self.line("const mem = std.heap.page_allocator.alloc(i64, 256) catch return .{ .items = undefined, .len = 0, .cap = 0 };");
        self.line("return .{ .items = @constCast(mem.ptr), .len = 0, .cap = 256 };");
        self.indent -= 1;
        self.line("}");
        self.line("pub fn append(self: *List, val: i64) void {");
        self.indent += 1;
        self.line("const idx: usize = @intCast(@as(u64, @bitCast(self.len)));");
        self.line("self.items[idx] = val;");
        self.line("self.len += 1;");
        self.indent -= 1;
        self.line("}");
        self.line("pub fn get(self: *const List, idx: i64) i64 {");
        self.indent += 1;
        self.line("return self.items[@intCast(@as(u64, @bitCast(idx)))];");
        self.indent -= 1;
        self.line("}");
        self.indent -= 1;
        self.line("};");
        self.line("");
        // Tagged values: tag_id (0=ok, 1=error, 2=eof), value
        self.line("const Tagged = struct { tag: i64, value: i64 };");
        self.line("fn makeTagged(tag: i64, value: i64) i64 {");
        self.indent += 1;
        self.line("const t = std.heap.page_allocator.create(Tagged) catch return 0;");
        self.line("t.* = .{ .tag = tag, .value = value };");
        self.line("return @intCast(@intFromPtr(t));");
        self.indent -= 1;
        self.line("}");
        self.line("fn getTag(ptr: i64) i64 {");
        self.indent += 1;
        self.line("if (ptr == 0) return -1;");
        self.line("return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).tag;");
        self.indent -= 1;
        self.line("}");
        self.line("fn getTagValue(ptr: i64) i64 {");
        self.indent += 1;
        self.line("if (ptr == 0) return 0;");
        self.line("return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).value;");
        self.indent -= 1;
        self.line("}");
        self.line("");
        self.line("fn fileOpen(path_ptr: i64, path_len: i64) i64 {");
        self.indent += 1;
        self.line("const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(path_ptr))))));");
        self.line("const len: usize = if (path_len > 0) @intCast(@as(u64, @bitCast(path_len))) else blk: { var l: usize = 0; while (ptr[l] != 0) l += 1; break :blk l; };");
        self.line("const path = ptr[0..len];");
        self.line("const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024) catch return makeTagged(1, 0);");
        self.line("// Store data ptr and len as a stream (two i64s)");
        self.line("const stream = std.heap.page_allocator.alloc(i64, 3) catch return makeTagged(1, 0);");
        self.line("stream[0] = @intCast(@intFromPtr(data.ptr));");
        self.line("stream[1] = @intCast(data.len);");
        self.line("stream[2] = 0; // read position");
        self.line("return makeTagged(0, @intCast(@intFromPtr(stream.ptr)));");
        self.indent -= 1;
        self.line("}");
        self.line("");
        self.line("fn streamReadAll(stream_ptr: i64) i64 {");
        self.indent += 1;
        self.line("const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));");
        self.line("return s[0]; // return data ptr");
        self.indent -= 1;
        self.line("}");
        self.line("fn streamReadAllLen(stream_ptr: i64) i64 {");
        self.indent += 1;
        self.line("const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));");
        self.line("return s[1]; // return data len");
        self.indent -= 1;
        self.line("}");
        self.line("");

        self.line("fn strEql(a: [*]const u8, a_len: i64, b: [*]const u8, b_len: i64) bool {");
        self.indent += 1;
        self.line("if (a_len != b_len) return false;");
        self.line("const len: usize = @intCast(@as(u64, @bitCast(a_len)));");
        self.line("return std.mem.eql(u8, a[0..len], b[0..len]);");
        self.indent -= 1;
        self.line("}");
        self.line("");

        // Emit functions (non-main first, main last for Zig ordering)
        for (program.functions.items) |func| {
            if (!std.mem.eql(u8, func.name, "main")) {
                self.emitFunction(func, false);
                self.line("");
            }
        }
        // Emit main
        for (program.functions.items) |func| {
            if (std.mem.eql(u8, func.name, "main")) {
                self.emitFunction(func, true);
            }
        }
    }

    fn emitFunction(self: *ZigBackend, func: ir.Function, is_entry: bool) void {
        if (is_entry) {
            self.line("pub fn main() void {");
            self.indent += 1;
            // Build command-line args as list of null-terminated string pointers
            self.line("var verve_args_list = List.init();");
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
            .const_float => {},

            .add_i64 => |op| self.lineFmt("{s} = {s} +% {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .sub_i64 => |op| self.lineFmt("{s} = {s} -% {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mul_i64 => |op| self.lineFmt("{s} = {s} *% {s};", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .div_i64 => |op| self.lineFmt("{s} = @divTrunc({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .mod_i64 => |op| self.lineFmt("{s} = @mod({s}, {s});", .{ self.regName(op.dest), self.regName(op.lhs), self.regName(op.rhs) }),
            .neg_i64 => |op| self.lineFmt("{s} = -%({s});", .{ self.regName(op.dest), self.regName(op.operand) }),

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
                self.lineFmt("var list_{d} = List.init();", .{ln.dest});
                self.lineFmt("{s} = @intCast(@intFromPtr(&list_{d}));", .{ self.regName(ln.dest), ln.dest });
            },
            .list_append => |la| {
                self.lineFmt("@as(*List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).append({s});", .{ self.regName(la.list), self.regName(la.value) });
            },
            .list_len => |ll| {
                self.lineFmt("{s} = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).len;", .{ self.regName(ll.dest), self.regName(ll.list) });
            },
            .list_get => |lg| {
                self.lineFmt("{s} = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))).get({s});", .{ self.regName(lg.dest), self.regName(lg.list), self.regName(lg.index) });
            },

            .tag_get => |tg| {
                self.lineFmt("{s} = getTag({s});", .{ self.regName(tg.dest), self.regName(tg.tagged) });
            },
            .tag_value => |tv| {
                self.lineFmt("{s} = getTagValue({s});", .{ self.regName(tv.dest), self.regName(tv.tagged) });
            },

            .string_byte_at => |sb| {
                // Returns byte VALUE as i64 (for String.byte_at)
                self.lineFmt("{s} = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))))[", .{ self.regName(sb.dest), self.regName(sb.str) });
                self.writeFmt("@intCast(@as(u64, @bitCast({s})))];\n", .{self.regName(sb.index)});
            },
            .string_index => |si| {
                // Returns POINTER to byte (for s[i] string indexing — single-char string)
                self.lineFmt("{s} = @intCast(@intFromPtr(@as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))) + @as(usize, @intCast(@as(u64, @bitCast({s}))))));", .{ self.regName(si.dest), self.regName(si.str), self.regName(si.index) });
            },
            .string_len => |sl| {
                // Compute string length using strlen (null-terminated fallback)
                self.lineFmt("{{ const sp = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var sl: usize = 0; while (sp[sl] != 0) sl += 1; {s} = @intCast(sl); }}", .{ self.regName(sl.str), self.regName(sl.dest) });
            },
            .string_eq => |se| {
                self.lineFmt("{s} = if (strEql(@ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s}, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s})) @as(i64, 1) else @as(i64, 0);", .{
                    self.regName(se.dest),
                    self.regName(se.lhs),
                    self.regName(se.lhs_len),
                    self.regName(se.rhs),
                    self.regName(se.rhs_len),
                });
            },

            .break_loop, .continue_loop => {},
        }
    }

    fn emitBuiltin(self: *ZigBackend, dest: ir.Reg, name: []const u8, args: []const ir.Reg) void {
        if (std.mem.eql(u8, name, "println") or std.mem.eql(u8, name, "print")) {
            const newline = std.mem.eql(u8, name, "println");
            var i: usize = 0;
            while (i + 1 < args.len) {
                self.lineFmt("verve_write(1, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s}))))), {s});", .{ self.regName(args[i]), self.regName(args[i + 1]) });
                i += 2;
            }
            if (newline) {
                self.line("verve_write(1, \"\\n\", 1);");
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
        } else if (std.mem.eql(u8, name, "set_has")) {
            if (args.len >= 2) {
                // Use string comparison (strEql) for set elements — they're string pointers
                self.lineFmt("{{ const list = @as(*const List, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var found: i64 = 0; const needle_ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast({s})))))); var needle_len: usize = 0; while (needle_ptr[needle_len] != 0) needle_len += 1; var si: i64 = 0; while (si < list.len) : (si += 1) {{ const elem = list.get(si); const eptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(elem)))))); var elen: usize = 0; while (eptr[elen] != 0) elen += 1; if (strEql(eptr, @intCast(elen), needle_ptr, @intCast(needle_len))) {{ found = 1; break; }} }} {s} = found; }}", .{ self.regName(args[0]), self.regName(args[1]), self.regName(dest) });
            }
        } else if (std.mem.eql(u8, name, "file_open")) {
            // args: path_ptr, path_len, mode_ptr, ...
            if (args.len >= 2) {
                self.lineFmt("{s} = fileOpen({s}, {s});", .{ self.regName(dest), self.regName(args[0]), self.regName(args[1]) });
            }
        } else if (std.mem.eql(u8, name, "stream_read_all")) {
            if (args.len >= 1) {
                self.lineFmt("{s} = streamReadAll({s});", .{ self.regName(dest), self.regName(args[0]) });
            }
        } else if (std.mem.eql(u8, name, "stream_close")) {
            self.lineFmt("{s} = 0; // stream close (no-op)", .{self.regName(dest)});
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
            .eq_i64, .neq_i64, .lt_i64, .gt_i64, .lte_i64, .gte_i64 => |op| op.dest,
            .and_bool, .or_bool => |op| op.dest,
            .neg_i64, .not_bool => |op| op.dest,
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
            .string_index => |si| si.dest,
            .string_len => |sl| sl.dest,
            .string_eq => |se| se.dest,
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

        // Compile with zig
        // Use -femit-bin to control output path
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

        // Keep .zig source for debugging (TODO: clean up in production)
        // std.fs.cwd().deleteFile(src_path) catch {};
        std.fs.cwd().deleteTree(".zig-cache") catch {};
        // Delete the .o file if it exists
        const o_path = try std.fmt.allocPrint(self.alloc, "{s}.o", .{output_path});
        std.fs.cwd().deleteFile(o_path) catch {};
    }
};
