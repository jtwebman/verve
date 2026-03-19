const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;

pub const Loader = struct {
    alloc: std.mem.Allocator,
    loaded_files: std.StringHashMapUnmanaged(ast.File),

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

        var parser = Parser.init(source, self.alloc);
        const file = parser.parseFile() catch {
            return error.ParseFailed;
        };

        try self.loaded_files.put(self.alloc, file_path, file);

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
};
