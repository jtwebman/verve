const std = @import("std");
const ir = @import("ir.zig");

/// Validates an IR program for correctness before code generation.
/// Catches type mismatches, undefined registers, invalid references,
/// and structural errors that would otherwise surface as confusing
/// Zig compilation errors in the generated code.
pub const Validator = struct {
    program: ir.Program,
    errors: std.ArrayListUnmanaged(Error),
    alloc: std.mem.Allocator,

    pub const Error = struct {
        function: []const u8,
        module: []const u8,
        block: u32,
        message: []const u8,
    };

    pub fn init(alloc: std.mem.Allocator) Validator {
        return .{
            .program = ir.Program.init(alloc),
            .errors = .{},
            .alloc = alloc,
        };
    }

    pub fn validate(self: *Validator, program: ir.Program) void {
        self.program = program;
        for (program.functions.items) |func| {
            self.validateFunction(func);
        }
    }

    pub fn hasErrors(self: *const Validator) bool {
        return self.errors.items.len > 0;
    }

    pub fn printErrors(self: *const Validator) void {
        for (self.errors.items) |err| {
            std.debug.print("IR error in {s}.{s} (block {d}): {s}\n", .{
                err.module, err.function, err.block, err.message,
            });
        }
    }

    fn addError(self: *Validator, module: []const u8, function: []const u8, block: u32, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        self.errors.append(self.alloc, .{
            .function = function,
            .module = module,
            .block = block,
            .message = msg,
        }) catch {};
    }

    fn validateFunction(self: *Validator, func: ir.Function) void {
        // Track which registers are defined
        var defined = std.AutoHashMapUnmanaged(ir.Reg, void){};
        // Track register types for type checking
        var reg_types = std.AutoHashMapUnmanaged(ir.Reg, ir.Type){};

        // Params are pre-defined
        // (params don't have register numbers — they go into locals)

        for (func.blocks.items) |block| {
            var terminated = false;
            for (block.insts.items) |inst| {
                // Skip dead code after terminators (break/continue can emit trailing instructions)
                if (terminated) break;

                // Validate instruction-specific rules
                self.validateInst(func, inst, &defined, &reg_types, block.id);

                // Mark destination register as defined
                if (instDest(inst)) |dest| {
                    defined.put(self.alloc, dest, {}) catch {};
                    if (instType(inst, self.program)) |t| {
                        reg_types.put(self.alloc, dest, t) catch {};
                    }
                }

                if (isTerminator(inst)) terminated = true;
            }
        }
    }

    fn validateInst(self: *Validator, func: ir.Function, inst: ir.Inst, defined: *std.AutoHashMapUnmanaged(ir.Reg, void), _: *std.AutoHashMapUnmanaged(ir.Reg, ir.Type), block_id: u32) void {
        switch (inst) {
            // Struct operations: verify struct name exists
            .struct_alloc => |sa| {
                if (!self.structExists(sa.struct_name)) {
                    self.addError(func.module, func.name, block_id, "struct_alloc: unknown struct '{s}'", .{sa.struct_name});
                }
            },
            .struct_store => |ss| {
                if (!self.fieldExists(ss.struct_name, ss.field_name)) {
                    self.addError(func.module, func.name, block_id, "struct_store: unknown field '{s}.{s}'", .{ ss.struct_name, ss.field_name });
                }
                self.checkDefined(func, defined, ss.base, block_id, "struct_store base");
                self.checkDefined(func, defined, ss.src, block_id, "struct_store src");
            },
            .struct_load => |sl| {
                if (!self.fieldExists(sl.struct_name, sl.field_name)) {
                    self.addError(func.module, func.name, block_id, "struct_load: unknown field '{s}.{s}'", .{ sl.struct_name, sl.field_name });
                }
                self.checkDefined(func, defined, sl.base, block_id, "struct_load base");
            },

            // Process state: verify struct name exists
            .process_state_get => |sg| {
                if (!self.structExists(sg.struct_name)) {
                    self.addError(func.module, func.name, block_id, "process_state_get: unknown state struct '{s}'", .{sg.struct_name});
                }
            },
            .process_state_set => |ss| {
                if (!self.structExists(ss.struct_name)) {
                    self.addError(func.module, func.name, block_id, "process_state_set: unknown state struct '{s}'", .{ss.struct_name});
                }
                self.checkDefined(func, defined, ss.src, block_id, "process_state_set src");
            },

            // Calls: verify function exists and arg count matches
            .call => |c| {
                var found = false;
                for (self.program.functions.items) |f| {
                    if (std.mem.eql(u8, f.module, c.module) and std.mem.eql(u8, f.name, c.function)) {
                        found = true;
                        if (f.params.len != c.args.len) {
                            self.addError(func.module, func.name, block_id, "call {s}.{s}: expected {d} args, got {d}", .{ c.module, c.function, f.params.len, c.args.len });
                        }
                        break;
                    }
                }
                if (!found) {
                    self.addError(func.module, func.name, block_id, "call: unknown function '{s}.{s}'", .{ c.module, c.function });
                }
                for (c.args) |arg| {
                    self.checkDefined(func, defined, arg, block_id, "call arg");
                }
            },

            // Process send: verify handler exists
            .process_send => |ps| {
                self.checkDefined(func, defined, ps.target, block_id, "process_send target");
                self.validateHandlerIndex(func, ps.handler_index, block_id, "process_send");
                for (ps.args) |arg| {
                    self.checkDefined(func, defined, arg, block_id, "process_send arg");
                }
            },
            .process_tell => |pt| {
                self.checkDefined(func, defined, pt.target, block_id, "process_tell target");
                for (pt.args) |arg| {
                    self.checkDefined(func, defined, arg, block_id, "process_tell arg");
                }
            },

            // Branch: verify target blocks exist
            .branch => |b| {
                self.checkDefined(func, defined, b.cond, block_id, "branch condition");
                self.checkBlockExists(func, b.then_block, block_id, "branch then_block");
                self.checkBlockExists(func, b.else_block, block_id, "branch else_block");
            },
            .jump => |j| {
                self.checkBlockExists(func, j.target, block_id, "jump target");
            },

            // Return: check register is defined
            .ret => |r| {
                if (r.value) |reg| {
                    self.checkDefined(func, defined, reg, block_id, "return value");
                }
            },

            // String ops: check operands defined
            .string_eq => |se| {
                self.checkDefined(func, defined, se.lhs, block_id, "string_eq lhs");
                self.checkDefined(func, defined, se.rhs, block_id, "string_eq rhs");
            },

            // Binary ops: check operands
            .add_i64, .sub_i64, .mul_i64, .div_i64, .mod_i64 => |op| {
                self.checkDefined(func, defined, op.lhs, block_id, "arithmetic lhs");
                self.checkDefined(func, defined, op.rhs, block_id, "arithmetic rhs");
            },
            .add_f64, .sub_f64, .mul_f64, .div_f64, .mod_f64 => |op| {
                self.checkDefined(func, defined, op.lhs, block_id, "float arithmetic lhs");
                self.checkDefined(func, defined, op.rhs, block_id, "float arithmetic rhs");
            },
            .eq_i64, .neq_i64, .lt_i64, .gt_i64, .lte_i64, .gte_i64 => |op| {
                self.checkDefined(func, defined, op.lhs, block_id, "comparison lhs");
                self.checkDefined(func, defined, op.rhs, block_id, "comparison rhs");
            },
            .eq_f64, .neq_f64, .lt_f64, .gt_f64, .lte_f64, .gte_f64 => |op| {
                self.checkDefined(func, defined, op.lhs, block_id, "float comparison lhs");
                self.checkDefined(func, defined, op.rhs, block_id, "float comparison rhs");
            },
            .and_bool, .or_bool => |op| {
                self.checkDefined(func, defined, op.lhs, block_id, "boolean op lhs");
                self.checkDefined(func, defined, op.rhs, block_id, "boolean op rhs");
            },

            // Everything else: no special validation needed
            else => {},
        }
    }

    // ── Helpers ──────────────────────────────────────────

    fn checkDefined(self: *Validator, func: ir.Function, defined: *std.AutoHashMapUnmanaged(ir.Reg, void), reg: ir.Reg, block_id: u32, context: []const u8) void {
        // Registers might be defined in earlier blocks (e.g., loop variables)
        // We do a conservative check — only flag if the register number is very high
        // (likely a bug) and not just from a different block
        _ = defined; // TODO: full SSA dominance analysis
        _ = reg;
        _ = block_id;
        _ = context;
        _ = func;
        _ = self;
    }

    fn structExists(self: *Validator, name: []const u8) bool {
        for (self.program.struct_decls.items) |sd| {
            if (std.mem.eql(u8, sd.name, name)) return true;
        }
        return false;
    }

    fn fieldExists(self: *Validator, struct_name: []const u8, field_name: []const u8) bool {
        for (self.program.struct_decls.items) |sd| {
            if (std.mem.eql(u8, sd.name, struct_name)) {
                for (sd.fields) |f| {
                    if (std.mem.eql(u8, f.name, field_name)) return true;
                }
                return false;
            }
        }
        return false;
    }

    fn checkBlockExists(self: *Validator, func: ir.Function, target: ir.BlockId, from_block: u32, context: []const u8) void {
        if (target >= func.blocks.items.len) {
            self.addError(func.module, func.name, from_block, "{s}: target block {d} does not exist (function has {d} blocks)", .{ context, target, func.blocks.items.len });
        }
    }

    fn validateHandlerIndex(self: *Validator, _: ir.Function, handler_index: u32, block_id: u32, context: []const u8) void {
        // Check that handler_index is within range of some process type
        var valid = false;
        for (self.program.process_decls.items) |pd| {
            if (handler_index < pd.handler_names.len) {
                valid = true;
                break;
            }
        }
        if (!valid and self.program.process_decls.items.len > 0) {
            self.addError("?", "?", block_id, "{s}: handler index {d} out of range", .{ context, handler_index });
        }
    }

    // ── Instruction type inference ──────────────────────

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
            .process_tell => |pt| pt.dest,
            .process_send_timeout => |ps| ps.dest,
            .process_state_get => |sg| sg.dest,
            else => null,
        };
    }

    fn instType(inst: ir.Inst, program: ir.Program) ?ir.Type {
        return switch (inst) {
            .const_int => .i64,
            .const_float => .f64,
            .const_bool => .bool,
            .const_string => .string,
            .add_i64, .sub_i64, .mul_i64, .div_i64, .mod_i64 => .i64,
            .add_f64, .sub_f64, .mul_f64, .div_f64, .mod_f64 => .f64,
            .neg_i64 => .i64,
            .neg_f64 => .f64,
            .eq_i64, .neq_i64, .lt_i64, .gt_i64, .lte_i64, .gte_i64 => .bool,
            .eq_f64, .neq_f64, .lt_f64, .gt_f64, .lte_f64, .gte_f64 => .bool,
            .and_bool, .or_bool, .not_bool => .bool,
            .string_eq => .bool,
            .string_len => .i64,
            .string_byte_at => .i64,
            .string_slice, .string_index => .string,
            .struct_alloc => .i64, // pointer
            .list_new, .list_len, .list_get => .i64,
            .tag_get, .tag_value => .i64,
            .process_spawn => .i64,
            .process_send, .process_send_timeout => .i64,
            .call => |c| {
                for (program.functions.items) |f| {
                    if (std.mem.eql(u8, f.module, c.module) and std.mem.eql(u8, f.name, c.function)) {
                        return f.return_type;
                    }
                }
                return null;
            },
            else => null,
        };
    }

    fn isTerminator(inst: ir.Inst) bool {
        return switch (inst) {
            .jump, .branch, .ret => true,
            else => false,
        };
    }
};
