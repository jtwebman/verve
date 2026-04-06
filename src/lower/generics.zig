const std = @import("std");
const ast = @import("../ast.zig");
const ir = @import("../ir.zig");
const Lower = @import("lower.zig").Lower;

/// Generate a monomorphized name like "Pair_int" or "Entry_string_int"
pub fn monomorphKey(self: *Lower, base_name: []const u8, type_args: []const ast.TypeExpr) []const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    buf.appendSlice(self.alloc, base_name) catch return base_name;
    for (type_args) |arg| {
        buf.appendSlice(self.alloc, "_") catch {};
        buf.appendSlice(self.alloc, mangleTypeExprName(self, arg)) catch {};
    }
    return buf.toOwnedSlice(self.alloc) catch base_name;
}

fn mangleTypeExprName(self: *Lower, te: ast.TypeExpr) []const u8 {
    return switch (te) {
        .simple => |name| name,
        .generic => |g| monomorphKey(self, g.name, g.args),
        .optional => |inner| blk: {
            const inner_name = mangleTypeExprName(self, inner.*);
            break :blk std.fmt.allocPrint(self.alloc, "optional_{s}", .{inner_name}) catch "optional";
        },
        else => "unknown",
    };
}

/// Get a simple string name for a type expression
pub fn typeExprName(self: *Lower, te: ast.TypeExpr) []const u8 {
    return switch (te) {
        .simple => |name| name,
        .generic => |g| {
            if (self.generic_struct_decls.contains(g.name)) {
                return monomorphKey(self, g.name, g.args);
            }
            return formatGenericTypeName(self, g.name, g.args);
        },
        .optional => |inner| blk: {
            const inner_name = typeExprName(self, inner.*);
            break :blk std.fmt.allocPrint(self.alloc, "optional_{s}", .{inner_name}) catch "optional";
        },
        else => "unknown",
    };
}

/// Resolve a field type expression by substituting type parameters.
/// If type_expr is `.simple` and matches a type param name, substitute with the arg.
pub fn resolveFieldTypeName(self: *Lower, type_expr: ast.TypeExpr, type_params: []const []const u8, type_args: []const ast.TypeExpr) []const u8 {
    switch (type_expr) {
        .simple => |name| {
            for (type_params, 0..) |param, i| {
                if (std.mem.eql(u8, name, param) and i < type_args.len) {
                    return typeExprName(self, type_args[i]);
                }
            }
            return name;
        },
        else => return "unknown",
    }
}

/// Instantiate a generic struct with concrete type args. Returns the monomorphized name.
pub fn instantiateGenericStruct(self: *Lower, base_name: []const u8, type_args: []const ast.TypeExpr) ![]const u8 {
    const key = monomorphKey(self, base_name, type_args);

    // Already instantiated?
    if (self.monomorphized.get(key) != null) return key;

    const generic_def = self.generic_struct_decls.get(base_name) orelse return base_name;

    // Build resolved fields
    var fields = std.ArrayListUnmanaged(ir.StructFieldInfo){};
    for (generic_def.fields) |f| {
        const resolved_type = resolveFieldTypeName(self, f.type_expr, generic_def.type_params, type_args);
        try fields.append(self.alloc, .{ .name = f.name, .type_name = resolved_type });
    }

    // Emit the specialized StructInfo to IR
    try self.program.struct_decls.append(self.alloc, .{
        .name = key,
        .fields = try fields.toOwnedSlice(self.alloc),
    });

    // Create a synthetic AST StructDecl for the lowerer's struct_decls map
    // (needed for field access resolution)
    var ast_fields = std.ArrayListUnmanaged(ast.Field){};
    for (generic_def.fields) |f| {
        const resolved_type = resolveFieldTypeName(self, f.type_expr, generic_def.type_params, type_args);
        try ast_fields.append(self.alloc, .{
            .name = f.name,
            .type_expr = .{ .simple = resolved_type },
            .default_value = f.default_value,
            .span = f.span,
        });
    }
    const mono_decl = ast.StructDecl{
        .name = key,
        .fields = try ast_fields.toOwnedSlice(self.alloc),
        .type_params = &.{},
        .exported = generic_def.exported,
        .span = generic_def.span,
    };
    try self.struct_decls.put(self.alloc, key, mono_decl);
    try self.monomorphized.put(self.alloc, key, {});

    return key;
}

/// Format a generic type name with angle brackets: "list<int>", "map<string, int>"
pub fn formatGenericTypeName(self: *Lower, base: []const u8, args: []const ast.TypeExpr) []const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    buf.appendSlice(self.alloc, base) catch return base;
    buf.appendSlice(self.alloc, "<") catch return base;
    for (args, 0..) |arg, i| {
        if (i > 0) buf.appendSlice(self.alloc, ", ") catch {};
        buf.appendSlice(self.alloc, typeExprName(self, arg)) catch {};
    }
    buf.appendSlice(self.alloc, ">") catch return base;
    return buf.toOwnedSlice(self.alloc) catch base;
}
