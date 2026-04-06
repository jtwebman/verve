const std = @import("std");
const ast = @import("../ast.zig");
const ir = @import("../ir.zig");
const Lower = @import("lower.zig").Lower;

/// Dispatches built-in module calls (Timer, StringBuilder, String, etc.).
/// Returns `dest` when a builtin matches, `null` when nothing matches.
pub fn lowerBuiltinModuleCall(
    self: *Lower,
    mod_name: []const u8,
    fn_name: []const u8,
    args: []const ir.Reg,
    call_args: []const ast.Expr,
    dest: ir.Reg,
) ?ir.Reg {
    if (std.mem.eql(u8, mod_name, "Timer")) {
        const builtin_name = std.fmt.allocPrint(self.alloc, "timer_{s}", .{fn_name}) catch fn_name;
        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
        return dest;
    }
    if (std.mem.eql(u8, mod_name, "StringBuilder")) {
        if (std.mem.eql(u8, fn_name, "new") and args.len == 0) {
            const func = self.current_fn orelse return dest;
            const zero_reg = func.newReg(.i64);
            self.appendInst(.{ .const_int = .{ .dest = zero_reg, .value = 0 } });
            const default_args = self.alloc.alloc(ir.Reg, 1) catch return dest;
            default_args[0] = zero_reg;
            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "sb_new", .args = default_args } });
            return dest;
        }
        const builtin_name = std.fmt.allocPrint(self.alloc, "sb_{s}", .{fn_name}) catch fn_name;
        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
        return dest;
    }
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
        if (std.mem.eql(u8, fn_name, "env_int") or
            std.mem.eql(u8, fn_name, "env_float") or
            std.mem.eql(u8, fn_name, "env_bool") or
            std.mem.eql(u8, fn_name, "env_string"))
        {
            // Extract type suffix: "env_int" → "int"
            const type_name = fn_name[4..]; // skip "env_"
            // Extract env var name from first AST arg (must be string literal)
            const env_name = if (call_args.len >= 1 and call_args[0] == .string_literal) call_args[0].string_literal else "UNKNOWN";
            // Register env var declaration with defaults
            var decl = ir.EnvVarDecl{
                .env_name = env_name,
                .type_name = type_name,
                .has_default = call_args.len >= 2,
            };
            if (call_args.len >= 2) {
                if (std.mem.eql(u8, type_name, "int")) {
                    if (call_args[1] == .int_literal) decl.default_int = call_args[1].int_literal;
                    if (call_args[1] == .unary_op and call_args[1].unary_op.op == .sub and call_args[1].unary_op.operand.* == .int_literal)
                        decl.default_int = -call_args[1].unary_op.operand.int_literal;
                } else if (std.mem.eql(u8, type_name, "float")) {
                    if (call_args[1] == .float_literal) decl.default_float = call_args[1].float_literal;
                } else if (std.mem.eql(u8, type_name, "bool")) {
                    if (call_args[1] == .bool_literal) decl.default_bool = call_args[1].bool_literal;
                } else if (std.mem.eql(u8, type_name, "string")) {
                    if (call_args[1] == .string_literal) decl.default_string = call_args[1].string_literal;
                }
            }
            // Deduplicate: only add if not already registered
            var found = false;
            for (self.program.env_decls.items) |existing| {
                if (std.mem.eql(u8, existing.env_name, env_name)) {
                    found = true;
                    break;
                }
            }
            if (!found) self.program.env_decls.append(self.alloc, decl) catch {};
            // Emit env_load instruction — reads from pre-validated global
            self.appendInst(.{ .env_load = .{ .dest = dest, .env_name = env_name, .type_name = type_name } });
            // Track register types for codegen
            if (std.mem.eql(u8, type_name, "float")) self.float_regs.put(self.alloc, dest, {}) catch {};
            if (std.mem.eql(u8, type_name, "string")) self.var_types.put(self.alloc, std.fmt.allocPrint(self.alloc, "__env_{d}", .{dest}) catch "", "string") catch {};
            return dest;
        }
        const builtin_name = std.fmt.allocPrint(self.alloc, "process_{s}", .{fn_name}) catch fn_name;
        self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
        return dest;
    }
    if (std.mem.eql(u8, mod_name, "Json")) {
        if (std.mem.eql(u8, fn_name, "stringify")) {
            var struct_name: []const u8 = "unknown";
            // Resolve struct type from variable name
            if (call_args.len >= 1 and call_args[0] == .identifier) {
                if (self.var_types.get(call_args[0].identifier)) |tn| {
                    struct_name = tn;
                }
            }
            const builtin_name = std.fmt.allocPrint(self.alloc, "json_stringify_struct:{s}", .{struct_name}) catch "json_stringify_struct:unknown";
            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
            return dest;
        }
        if (std.mem.eql(u8, fn_name, "parse")) {
            var struct_name: []const u8 = "unknown";
            if (call_args.len >= 2 and call_args[1] == .identifier) {
                struct_name = call_args[1].identifier;
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
        if (std.mem.eql(u8, fn_name, "respond_chunked")) {
            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_build_response_chunked", .args = args } });
            return dest;
        }
        if (std.mem.eql(u8, fn_name, "parse_request")) {
            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = "http_parse_request", .args = args } });
            return dest;
        }
        if (std.mem.eql(u8, fn_name, "get") or std.mem.eql(u8, fn_name, "post") or std.mem.eql(u8, fn_name, "request")) {
            const builtin_name = std.fmt.allocPrint(self.alloc, "http_client_{s}", .{fn_name}) catch fn_name;
            self.appendInst(.{ .call_builtin = .{ .dest = dest, .name = builtin_name, .args = args } });
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
    return null;
}
