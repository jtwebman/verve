const std = @import("std");
const ast = @import("ast.zig");

pub const MAX_LINE_LENGTH: usize = 120;

pub const Formatter = struct {
    alloc: std.mem.Allocator,
    output: std.ArrayListUnmanaged(u8),
    indent: usize,

    pub fn init(alloc: std.mem.Allocator) Formatter {
        return .{
            .alloc = alloc,
            .output = .{},
            .indent = 0,
        };
    }

    pub fn format(self: *Formatter, file: ast.File) ![]const u8 {
        // Imports first
        for (file.imports) |imp| {
            try self.write("import \"");
            try self.write(imp.path);
            try self.write("\";\n");
        }
        if (file.imports.len > 0) {
            try self.write("\n");
        }

        // Declarations
        for (file.decls, 0..) |decl, i| {
            if (i > 0) try self.write("\n");
            switch (decl) {
                .type_decl => |t| try self.formatTypeDecl(t),
                .struct_decl => |s| try self.formatStructDecl(s),
                .module_decl => |m| try self.formatModuleDecl(m),
                .process_decl => |p| try self.formatProcessDecl(p),
            }
        }

        return self.output.items;
    }

    // ── Declarations ──────────────────────────────────────────

    fn formatTypeDecl(self: *Formatter, t: ast.TypeDecl) !void {
        if (t.exported) try self.write("export ");
        try self.write("type ");
        try self.write(t.name);
        try self.write(" = ");
        try self.formatTypeExpr(t.value);
        try self.write(";\n");
    }

    fn formatStructDecl(self: *Formatter, s: ast.StructDecl) !void {
        if (s.exported) try self.write("export ");
        try self.write("struct ");
        try self.write(s.name);
        if (s.type_params.len > 0) {
            try self.write("<");
            for (s.type_params, 0..) |tp, i| {
                if (i > 0) try self.write(", ");
                try self.write(tp);
            }
            try self.write(">");
        }
        try self.write(" {\n");
        self.indent += 1;
        for (s.fields) |field| {
            try self.writeIndent();
            try self.write(field.name);
            try self.write(": ");
            try self.formatTypeExpr(field.type_expr);
            try self.write(";\n");
        }
        self.indent -= 1;
        try self.write("}\n");
    }

    fn formatModuleDecl(self: *Formatter, m: ast.ModuleDecl) !void {
        if (m.doc_comment) |doc| {
            var lines = std.mem.splitScalar(u8, std.mem.trimRight(u8, doc, &[_]u8{ '\n', ' ', '\t' }), '\n');
            while (lines.next()) |line| {
                try self.write(std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' }));
                try self.write("\n");
            }
        }
        if (m.exported) try self.write("export ");
        try self.write("module ");
        try self.write(m.name);
        try self.write(" {\n");
        self.indent += 1;

        for (m.constants) |c| {
            try self.writeIndent();
            try self.write(c.name);
            if (c.type_expr) |te| {
                try self.write(": ");
                try self.formatTypeExpr(te);
            }
            try self.write(" = ");
            try self.formatExpr(c.value);
            try self.write(";\n");
        }
        if (m.constants.len > 0 and (m.imports.len > 0 or m.functions.len > 0)) {
            try self.write("\n");
        }

        for (m.imports) |imp| {
            try self.writeIndent();
            try self.write("use ");
            try self.write(imp.module_name);
            try self.write(" { ");
            for (imp.symbols, 0..) |sym, i| {
                if (i > 0) try self.write(", ");
                try self.write(sym);
            }
            try self.write(" };\n");
        }
        if (m.imports.len > 0 and m.functions.len > 0) {
            try self.write("\n");
        }

        for (m.functions, 0..) |func, i| {
            if (i > 0) try self.write("\n");
            try self.formatFnDecl(func);
        }

        for (m.tests, 0..) |t, i| {
            if (i > 0 or m.functions.len > 0) try self.write("\n");
            try self.writeIndent();
            try self.write("test \"");
            try self.write(t.name);
            try self.write("\" {\n");
            self.indent += 1;
            for (t.body) |s| try self.formatStmt(s);
            self.indent -= 1;
            try self.writeIndent();
            try self.write("}\n");
        }

        self.indent -= 1;
        try self.write("}\n");
    }

    fn formatProcessDecl(self: *Formatter, p: ast.ProcessDecl) !void {
        if (p.doc_comment) |doc| {
            var lines = std.mem.splitScalar(u8, std.mem.trimRight(u8, doc, &[_]u8{ '\n', ' ', '\t' }), '\n');
            while (lines.next()) |line| {
                try self.write(std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' }));
                try self.write("\n");
            }
        }
        if (p.exported) try self.write("export ");
        try self.write("process ");
        try self.write(p.name);
        if (p.memory) |mem| {
            switch (mem) {
                .sized => |expr| {
                    try self.write(" [memory: ");
                    try self.formatExpr(expr);
                    try self.write("]");
                },
                .unbounded => try self.write(" [memory: unbounded]"),
            }
        }
        try self.write(" {\n");
        self.indent += 1;

        if (p.state_fields.len > 0) {
            try self.writeIndent();
            try self.write("state {\n");
            self.indent += 1;
            for (p.state_fields) |field| {
                try self.writeIndent();
                try self.write(field.name);
                try self.write(": ");
                try self.formatTypeExpr(field.type_expr);
                if (field.default_value) |dv| {
                    try self.write(" = ");
                    try self.formatExpr(dv);
                }
                try self.write(";\n");
            }
            self.indent -= 1;
            try self.writeIndent();
            try self.write("}\n");
        }

        if (p.invariants.len > 0) {
            try self.write("\n");
            try self.writeIndent();
            try self.write("invariant {\n");
            self.indent += 1;
            for (p.invariants) |inv| {
                try self.writeIndent();
                try self.formatExpr(inv);
                try self.write(";\n");
            }
            self.indent -= 1;
            try self.writeIndent();
            try self.write("}\n");
        }

        for (p.receive_handlers, 0..) |handler, i| {
            if (i > 0 or p.state_fields.len > 0 or p.invariants.len > 0) try self.write("\n");
            try self.formatReceiveDecl(handler);
        }

        self.indent -= 1;
        try self.write("}\n");
    }

    fn formatFnDecl(self: *Formatter, func: ast.FnDecl) !void {
        if (func.doc_comment) |doc| {
            // Split doc into lines and re-indent
            var lines = std.mem.splitScalar(u8, std.mem.trimRight(u8, doc, &[_]u8{ '\n', ' ', '\t' }), '\n');
            while (lines.next()) |line| {
                try self.writeIndent();
                try self.write(std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' }));
                try self.write("\n");
            }
        }
        try self.writeIndent();
        try self.write("fn ");
        try self.write(func.name);
        try self.write("(");
        try self.formatParams(func.params);
        try self.write(") -> ");
        try self.formatTypeExpr(func.return_type);
        try self.write(" {\n");
        self.indent += 1;

        for (func.guards) |guard| {
            try self.writeIndent();
            try self.write("guard ");
            try self.formatExpr(guard);
            try self.write(";\n");
        }

        for (func.body) |stmt| {
            try self.formatStmt(stmt);
        }

        self.indent -= 1;
        try self.writeIndent();
        try self.write("}\n");
    }

    fn formatReceiveDecl(self: *Formatter, handler: ast.ReceiveDecl) !void {
        if (handler.doc_comment) |doc| {
            var lines = std.mem.splitScalar(u8, std.mem.trimRight(u8, doc, &[_]u8{ '\n', ' ', '\t' }), '\n');
            while (lines.next()) |line| {
                try self.writeIndent();
                try self.write(std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' }));
                try self.write("\n");
            }
        }
        try self.writeIndent();
        try self.write("receive ");
        try self.write(handler.name);
        try self.write("(");
        try self.formatParams(handler.params);
        try self.write(") -> ");
        try self.formatTypeExpr(handler.return_type);
        try self.write(" {\n");
        self.indent += 1;

        for (handler.guards) |guard| {
            try self.writeIndent();
            try self.write("guard ");
            try self.formatExpr(guard);
            try self.write(";\n");
        }

        for (handler.body) |stmt| {
            try self.formatStmt(stmt);
        }

        self.indent -= 1;
        try self.writeIndent();
        try self.write("}\n");
    }

    fn formatParams(self: *Formatter, params: []const ast.Param) !void {
        if (params.len == 0) return;

        // Measure single-line version
        const start_col = self.currentCol();
        var measure_len: usize = start_col;
        for (params, 0..) |param, i| {
            if (i > 0) measure_len += 2; // ", "
            measure_len += param.name.len + 2; // "name: "
            measure_len += self.typeExprLen(param.type_expr);
        }
        measure_len += 1; // closing paren

        if (measure_len <= MAX_LINE_LENGTH) {
            // Single line
            for (params, 0..) |param, i| {
                if (i > 0) try self.write(", ");
                try self.write(param.name);
                try self.write(": ");
                try self.formatTypeExpr(param.type_expr);
            }
        } else {
            // Wrap: one param per line
            try self.write("\n");
            self.indent += 1;
            for (params, 0..) |param, i| {
                try self.writeIndent();
                try self.write(param.name);
                try self.write(": ");
                try self.formatTypeExpr(param.type_expr);
                if (i < params.len - 1) try self.write(",");
                try self.write("\n");
            }
            self.indent -= 1;
            try self.writeIndent();
        }
    }

    fn currentCol(self: *Formatter) usize {
        // Find the last newline and count chars since
        var i = self.output.items.len;
        while (i > 0) {
            i -= 1;
            if (self.output.items[i] == '\n') return self.output.items.len - i - 1;
        }
        return self.output.items.len;
    }

    fn typeExprLen(self: *Formatter, t: ast.TypeExpr) usize {
        _ = self;
        return switch (t) {
            .simple => |name| name.len,
            .generic => |g| g.name.len + 2 + g.args.len * 4, // rough estimate
            .optional => 6,
            else => 10,
        };
    }

    // ── Type expressions ──────────────────────────────────────

    fn formatTypeExpr(self: *Formatter, t: ast.TypeExpr) !void {
        switch (t) {
            .simple => |name| try self.write(name),
            .generic => |g| {
                try self.write(g.name);
                try self.write("<");
                for (g.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.formatTypeExpr(arg);
                }
                try self.write(">");
            },
            .optional => |inner| {
                try self.formatTypeExpr(inner.*);
                try self.write("?");
            },
            .enum_type => |variants| {
                try self.write("enum { ");
                for (variants, 0..) |v, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(v);
                }
                try self.write(" }");
            },
            .union_type => |variants| {
                try self.write("union {\n");
                self.indent += 1;
                for (variants) |v| {
                    try self.writeIndent();
                    try self.write(":");
                    try self.write(v.tag);
                    if (v.fields.len > 0) {
                        try self.write(" { ");
                        for (v.fields, 0..) |f, i| {
                            if (i > 0) try self.write("; ");
                            try self.write(f.name);
                            try self.write(": ");
                            try self.formatTypeExpr(f.type_expr);
                        }
                        try self.write(" }");
                    }
                    try self.write(";\n");
                }
                self.indent -= 1;
                try self.writeIndent();
                try self.write("}");
            },
            .constrained => |c| {
                try self.formatTypeExpr(c.base.*);
                try self.write(" { ... }");
            },
            .fn_type => |f| {
                try self.write("fn(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try self.write(", ");
                    try self.formatTypeExpr(p);
                }
                try self.write(") -> ");
                try self.formatTypeExpr(f.return_type.*);
            },
        }
    }

    // ── Statements ────────────────────────────────────────────

    fn formatStmt(self: *Formatter, stmt: ast.Stmt) !void {
        switch (stmt) {
            .assign => |a| {
                try self.writeIndent();
                try self.write(a.name);
                try self.write(" = ");
                try self.formatExpr(a.value);
                try self.write(";\n");
            },
            .return_stmt => |r| {
                try self.writeIndent();
                if (r.value) |val| {
                    try self.write("return ");
                    try self.formatExpr(val);
                    try self.write(";\n");
                } else {
                    try self.write("return;\n");
                }
            },
            .if_stmt => |i| {
                try self.writeIndent();
                try self.write("if ");
                try self.formatExpr(i.condition);
                try self.write(" {\n");
                self.indent += 1;
                for (i.body) |s| try self.formatStmt(s);
                self.indent -= 1;
                if (i.else_body) |eb| {
                    // Check if else body is a single if_stmt (else if chain)
                    if (eb.len == 1 and eb[0] == .if_stmt) {
                        try self.writeIndent();
                        try self.write("} else ");
                        // Format the if without indent (it will add its own)
                        const inner = eb[0].if_stmt;
                        try self.write("if ");
                        try self.formatExpr(inner.condition);
                        try self.write(" {\n");
                        self.indent += 1;
                        for (inner.body) |s| try self.formatStmt(s);
                        self.indent -= 1;
                        if (inner.else_body) |ieb| {
                            try self.writeIndent();
                            try self.write("} else {\n");
                            self.indent += 1;
                            for (ieb) |s| try self.formatStmt(s);
                            self.indent -= 1;
                        }
                        try self.writeIndent();
                        try self.write("}\n");
                    } else {
                        try self.writeIndent();
                        try self.write("} else {\n");
                        self.indent += 1;
                        for (eb) |s| try self.formatStmt(s);
                        self.indent -= 1;
                        try self.writeIndent();
                        try self.write("}\n");
                    }
                } else {
                    try self.writeIndent();
                    try self.write("}\n");
                }
            },
            .while_stmt => |w| {
                try self.writeIndent();
                try self.write("while ");
                try self.formatExpr(w.condition);
                try self.write(" {\n");
                self.indent += 1;
                for (w.body) |s| try self.formatStmt(s);
                self.indent -= 1;
                try self.writeIndent();
                try self.write("}\n");
            },
            .match_stmt => |m| {
                try self.writeIndent();
                try self.write("match ");
                try self.formatExpr(m.subject);
                try self.write(" {\n");
                self.indent += 1;
                for (m.arms) |arm| {
                    try self.writeIndent();
                    try self.formatPattern(arm.pattern);
                    try self.write(" => ");
                    if (arm.body.len == 1) {
                        try self.formatStmtInline(arm.body[0]);
                    } else {
                        try self.write("{\n");
                        self.indent += 1;
                        for (arm.body) |s| try self.formatStmt(s);
                        self.indent -= 1;
                        try self.writeIndent();
                        try self.write("}\n");
                    }
                }
                self.indent -= 1;
                try self.writeIndent();
                try self.write("}\n");
            },
            .transition => |t| {
                try self.writeIndent();
                try self.write("transition ");
                try self.formatExpr(t.target);
                try self.write(" { ");
                for (t.fields) |f| {
                    if (f.name) |name| {
                        try self.write(name);
                        try self.write(": ");
                    }
                    try self.formatExpr(f.value);
                    try self.write("; ");
                }
                try self.write("}\n");
            },
            .append => |a| {
                try self.writeIndent();
                try self.write("append ");
                try self.formatExpr(a.target);
                try self.write(" { ");
                try self.formatExpr(a.value);
                try self.write("; }\n");
            },
            .tell_stmt => |t| {
                try self.writeIndent();
                try self.write("tell ");
                try self.formatExpr(t.target);
                try self.write(".");
                try self.write(t.handler);
                try self.write("(");
                for (t.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.formatExpr(arg);
                }
                try self.write(");\n");
            },
            .break_stmt => {
                try self.writeIndent();
                try self.write("break;\n");
            },
            .continue_stmt => {
                try self.writeIndent();
                try self.write("continue;\n");
            },
            .assert_stmt => |a| {
                try self.writeIndent();
                try self.write("assert ");
                try self.formatExpr(a.condition);
                if (a.message) |msg| {
                    try self.write(", \"");
                    try self.write(msg);
                    try self.write("\"");
                }
                try self.write(";\n");
            },
            .receive_stmt => {
                try self.writeIndent();
                try self.write("receive;\n");
            },
            .watch_stmt => |w| {
                try self.writeIndent();
                try self.write("watch ");
                try self.formatExpr(w.target);
                try self.write(";\n");
            },
            .expr_stmt => |e| {
                try self.writeIndent();
                try self.formatExpr(e);
                try self.write(";\n");
            },
            .send_stmt => {},
        }
    }

    fn formatStmtInline(self: *Formatter, stmt: ast.Stmt) error{OutOfMemory}!void {
        switch (stmt) {
            .return_stmt => |r| {
                if (r.value) |val| {
                    try self.write("return ");
                    try self.formatExpr(val);
                    try self.write(";\n");
                } else {
                    try self.write("return;\n");
                }
            },
            .expr_stmt => |e| {
                try self.formatExpr(e);
                try self.write(";\n");
            },
            else => {
                try self.write("{\n");
                self.indent += 1;
                try self.formatStmt(stmt);
                self.indent -= 1;
                try self.writeIndent();
                try self.write("}\n");
            },
        }
    }

    fn formatPattern(self: *Formatter, p: ast.Pattern) !void {
        switch (p) {
            .tag => |t| {
                try self.write(":");
                try self.write(t.tag);
                if (t.bindings.len > 0) {
                    try self.write("{");
                    for (t.bindings, 0..) |b, i| {
                        if (i > 0) try self.write(", ");
                        try self.write(b);
                    }
                    try self.write("}");
                }
            },
            .literal => |e| try self.formatExpr(e),
            .wildcard => try self.write("_"),
        }
    }

    // ── Expressions ───────────────────────────────────────────

    fn formatExpr(self: *Formatter, expr: ast.Expr) !void {
        switch (expr) {
            .int_literal => |v| {
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "?";
                try self.write(s);
            },
            .float_literal => |v| {
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "?";
                try self.write(s);
            },
            .string_literal => |v| {
                try self.write("\"");
                try self.write(v);
                try self.write("\"");
            },
            .string_interp => |si| {
                try self.write("\"");
                for (si.parts) |part| {
                    switch (part) {
                        .literal => |lit| try self.write(lit),
                        .expr => |e| {
                            try self.write("${");
                            try self.formatExpr(e);
                            try self.write("}");
                        },
                    }
                }
                try self.write("\"");
            },
            .bool_literal => |v| try self.write(if (v) "true" else "false"),
            .tag => |v| {
                try self.write(":");
                try self.write(v);
            },
            .identifier => |v| try self.write(v),
            .none_literal => try self.write("none"),
            .void_literal => try self.write("void"),
            .binary_op => |op| {
                try self.formatExpr(op.left.*);
                try self.write(switch (op.op) {
                    .add => " + ",
                    .sub => " - ",
                    .mul => " * ",
                    .div => " / ",
                    .mod => " % ",
                    .eq => " == ",
                    .neq => " != ",
                    .lt => " < ",
                    .gt => " > ",
                    .lte => " <= ",
                    .gte => " >= ",
                    .@"and" => " && ",
                    .@"or" => " || ",
                    .not => "!",
                });
                try self.formatExpr(op.right.*);
            },
            .unary_op => |op| {
                try self.write("!");
                try self.formatExpr(op.operand.*);
            },
            .field_access => |fa| {
                try self.formatExpr(fa.target.*);
                try self.write(".");
                try self.write(fa.field);
            },
            .index_access => |ia| {
                try self.formatExpr(ia.target.*);
                try self.write("[");
                try self.formatExpr(ia.index.*);
                try self.write("]");
            },
            .call => |c| {
                try self.formatExpr(c.target.*);
                try self.write("(");
                for (c.args, 0..) |arg, i| {
                    if (i > 0) try self.write(", ");
                    try self.formatExpr(arg);
                }
                try self.write(")");
            },
            .struct_literal => |sl| {
                try self.write(sl.name);
                try self.write(" { ");
                for (sl.fields, 0..) |f, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(f.name);
                    try self.write(": ");
                    try self.formatExpr(f.value);
                }
                try self.write(" }");
            },
            .match_expr => {},
        }
    }

    // ── Output helpers ────────────────────────────────────────

    fn write(self: *Formatter, s: []const u8) !void {
        try self.output.appendSlice(self.alloc, s);
    }

    fn writeIndent(self: *Formatter) !void {
        var i: usize = 0;
        while (i < self.indent) : (i += 1) {
            try self.output.appendSlice(self.alloc, "\t");
        }
    }
};
