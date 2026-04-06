const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;

pub const Loader = struct {
    alloc: std.mem.Allocator,
    loaded_files: std.StringHashMapUnmanaged(ast.File),
    loaded_sources: std.StringHashMapUnmanaged([]const u8),
    entry_source: []const u8 = "",

    pub const Error = error{
        FileNotFound,
        ParseFailed,
        CircularImport,
        OutOfMemory,
    };

    pub fn init(alloc: std.mem.Allocator) Loader {
        return .{
            .alloc = alloc,
            .loaded_files = .{},
            .loaded_sources = .{},
        };
    }

    /// Load an entry file and all its imports recursively.
    /// Returns a merged File with:
    /// - All declarations from the entry file (exported or not)
    /// - Only exported declarations from imported files
    pub fn loadFile(self: *Loader, file_path: []const u8) Error!ast.File {
        // Parse the entry file and all imports
        try self.parseRecursive(file_path, &.{});

        // Build merged declarations
        var all_decls: std.ArrayListUnmanaged(ast.Decl) = .{};

        const entry_file = self.loaded_files.get(file_path) orelse return error.FileNotFound;

        // First: add exported decls from all imported files
        try self.addImportedDecls(&all_decls, entry_file, file_path);

        // Last: add all decls from entry file (exported or not — it's our file)
        for (entry_file.decls) |decl| {
            try all_decls.append(self.alloc, decl);
        }

        return .{
            .imports = &.{},
            .decls = try all_decls.toOwnedSlice(self.alloc),
        };
    }

    fn addImportedDecls(self: *Loader, all_decls: *std.ArrayListUnmanaged(ast.Decl), file: ast.File, file_path: []const u8) Error!void {
        const dir = std.fs.path.dirname(file_path) orelse ".";

        for (file.imports) |imp| {
            const resolved = std.fs.path.resolve(self.alloc, &.{ dir, imp.path }) catch {
                return error.FileNotFound;
            };
            const imported_file = self.loaded_files.get(resolved) orelse continue;

            // Recursively add that file's imports too
            try self.addImportedDecls(all_decls, imported_file, resolved);

            // Only exported declarations from imported files
            for (imported_file.decls) |decl| {
                const is_exported = switch (decl) {
                    .module_decl => |m| m.exported,
                    .process_decl => |p| p.exported,
                    .struct_decl => |s| s.exported,
                    .type_decl => |t| t.exported,
                };
                if (is_exported) {
                    try all_decls.append(self.alloc, decl);
                }
            }
        }
    }

    fn parseRecursive(self: *Loader, file_path: []const u8, import_chain: []const []const u8) Error!void {
        // Circular import check
        for (import_chain) |prev| {
            if (std.mem.eql(u8, prev, file_path)) {
                return error.CircularImport;
            }
        }

        // Already loaded
        if (self.loaded_files.get(file_path) != null) return;

        // Read and parse
        const source = std.fs.cwd().readFileAlloc(self.alloc, file_path, 1024 * 1024) catch {
            return error.FileNotFound;
        };

        // Store entry file source for error reporting
        if (import_chain.len == 0) {
            self.entry_source = source;
        }

        var parser = Parser.init(source, self.alloc);
        var file = parser.parseFile() catch {
            std.debug.print("  {s}: {s}\n", .{ file_path, parser.formatError() });
            return error.ParseFailed;
        };
        annotateFileSpans(&file, file_path);

        try self.loaded_files.put(self.alloc, file_path, file);
        try self.loaded_sources.put(self.alloc, file_path, source);

        // Recursively load imports
        const dir = std.fs.path.dirname(file_path) orelse ".";

        var new_chain_buf: [64][]const u8 = undefined;
        var chain_len: usize = 0;
        for (import_chain) |item| {
            new_chain_buf[chain_len] = item;
            chain_len += 1;
        }
        new_chain_buf[chain_len] = file_path;
        chain_len += 1;

        for (file.imports) |imp| {
            const resolved = std.fs.path.resolve(self.alloc, &.{ dir, imp.path }) catch {
                return error.FileNotFound;
            };
            try self.parseRecursive(resolved, new_chain_buf[0..chain_len]);
        }
    }

    fn annotateFileSpans(file: *ast.File, file_path: []const u8) void {
        for (file.imports) |*imp| annotateSpan(&@constCast(imp).span, file_path);
        for (file.decls) |*decl| annotateDecl(@constCast(decl), file_path);
    }

    fn annotateDecl(decl: *ast.Decl, file_path: []const u8) void {
        switch (decl.*) {
            .module_decl => |*m| {
                annotateSpan(&m.span, file_path);
                for (m.constants) |*assign| annotateSpan(&@constCast(assign).span, file_path);
                for (m.functions) |*func| annotateFnDecl(@constCast(func), file_path);
                for (m.tests) |*test_decl| {
                    annotateSpan(&@constCast(test_decl).span, file_path);
                    annotateStmts(test_decl.body, file_path);
                }
                for (m.imports) |*imp| annotateSpan(&@constCast(imp).span, file_path);
            },
            .process_decl => |*p| {
                annotateSpan(&p.span, file_path);
                for (p.receive_handlers) |*handler| annotateReceiveDecl(@constCast(handler), file_path);
            },
            .type_decl => |*t| annotateSpan(&t.span, file_path),
            .struct_decl => |*s| {
                annotateSpan(&s.span, file_path);
                for (s.fields) |*field| annotateSpan(&@constCast(field).span, file_path);
            },
        }
    }

    fn annotateFnDecl(func: *ast.FnDecl, file_path: []const u8) void {
        annotateSpan(&func.span, file_path);
        for (func.params) |*param| annotateSpan(&@constCast(param).span, file_path);
        annotateStmts(func.body, file_path);
    }

    fn annotateReceiveDecl(handler: *ast.ReceiveDecl, file_path: []const u8) void {
        annotateSpan(&handler.span, file_path);
        for (handler.params) |*param| annotateSpan(&@constCast(param).span, file_path);
        annotateStmts(handler.body, file_path);
    }

    fn annotateStmts(stmts: []const ast.Stmt, file_path: []const u8) void {
        for (stmts) |*stmt| annotateStmt(@constCast(stmt), file_path);
    }

    fn annotateStmt(stmt: *ast.Stmt, file_path: []const u8) void {
        switch (stmt.*) {
            .assign => |*assign| annotateSpan(&assign.span, file_path),
            .field_assign => |*assign| annotateSpan(&assign.span, file_path),
            .append => |*append| annotateSpan(&append.span, file_path),
            .match_stmt => |*match_stmt| {
                annotateSpan(&match_stmt.span, file_path);
                for (match_stmt.arms) |*arm| annotateStmts(arm.body, file_path);
            },
            .if_stmt => |*if_stmt| {
                annotateSpan(&if_stmt.span, file_path);
                annotateStmts(if_stmt.body, file_path);
                if (if_stmt.else_body) |else_body| annotateStmts(else_body, file_path);
            },
            .while_stmt => |*while_stmt| {
                annotateSpan(&while_stmt.span, file_path);
                annotateStmts(while_stmt.body, file_path);
            },
            .send_stmt => |*send_stmt| annotateSpan(&send_stmt.span, file_path),
            .return_stmt => |*return_stmt| annotateSpan(&return_stmt.span, file_path),
            .break_stmt => |*span| annotateSpan(span, file_path),
            .continue_stmt => |*span| annotateSpan(span, file_path),
            .receive_stmt => |*span| annotateSpan(span, file_path),
            .watch_stmt => |*watch_stmt| annotateSpan(&watch_stmt.span, file_path),
            .assert_stmt => |*assert_stmt| annotateSpan(&assert_stmt.span, file_path),
            .expr_stmt => {},
        }
    }

    fn annotateSpan(span: *const ast.Span, file_path: []const u8) void {
        @constCast(span).file_path = file_path;
    }
};
