const std = @import("std");
const ast = @import("ast.zig");

pub const ParseError = struct {
    message: []const u8,
    pos: usize,
    line: usize,
    col: usize,
};

pub const Parser = struct {
    source: []const u8,
    pos: usize,
    alloc: std.mem.Allocator,
    last_error: ?ParseError,

    pub const Error = error{
        ParseFailed,
        OutOfMemory,
    };

    pub fn init(source: []const u8, alloc: std.mem.Allocator) Parser {
        return .{
            .source = source,
            .pos = 0,
            .alloc = alloc,
            .last_error = null,
        };
    }

    // ── Error reporting ───────────────────────────────────────

    fn fail(self: *Parser, comptime fmt: []const u8, args: anytype) Error {
        const message = std.fmt.allocPrint(self.alloc, fmt, args) catch "error";
        const loc = self.getLineCol(self.pos);
        self.last_error = .{
            .message = message,
            .pos = self.pos,
            .line = loc.line,
            .col = loc.col,
        };
        return error.ParseFailed;
    }

    fn getLineCol(self: *Parser, pos: usize) struct { line: usize, col: usize } {
        var line: usize = 1;
        var col: usize = 1;
        for (self.source[0..@min(pos, self.source.len)]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        return .{ .line = line, .col = col };
    }

    fn peekSnippet(self: *Parser) []const u8 {
        if (self.pos >= self.source.len) return "<end of file>";
        const end = @min(self.pos + 20, self.source.len);
        return self.source[self.pos..end];
    }

    pub fn formatError(self: *Parser) []const u8 {
        if (self.last_error) |err| {
            return std.fmt.allocPrint(self.alloc, "line {d}, col {d}: {s}", .{ err.line, err.col, err.message }) catch "parse error";
        }
        return "unknown parse error";
    }

    // ── Utilities ──────────────────────────────────────────────

    fn peek(self: *Parser) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance(self: *Parser) ?u8 {
        if (self.pos >= self.source.len) return null;
        const c = self.source[self.pos];
        self.pos += 1;
        return c;
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                if (self.pos + 2 < self.source.len and self.source[self.pos + 2] == '/') break;
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn expect(self: *Parser, expected: []const u8) Error!void {
        self.skipWhitespaceAndComments();
        if (self.pos + expected.len > self.source.len) {
            return self.fail("expected '{s}' but reached end of file", .{expected});
        }
        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + expected.len], expected)) {
            return self.fail("expected '{s}' but found '{s}'", .{ expected, self.peekSnippet() });
        }
        self.pos += expected.len;
    }

    fn expectChar(self: *Parser, expected: u8) Error!void {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) {
            return self.fail("expected '{c}' but reached end of file", .{expected});
        }
        if (self.source[self.pos] != expected) {
            return self.fail("expected '{c}' but found '{c}'", .{ expected, self.source[self.pos] });
        }
        self.pos += 1;
    }

    pub fn matchKeyword(self: *Parser, keyword: []const u8) bool {
        self.skipWhitespaceAndComments();
        if (self.pos + keyword.len > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + keyword.len], keyword)) return false;
        if (self.pos + keyword.len < self.source.len) {
            const next = self.source[self.pos + keyword.len];
            if (std.ascii.isAlphanumeric(next) or next == '_') return false;
        }
        self.pos += keyword.len;
        return true;
    }

    fn peekKeyword(self: *Parser, keyword: []const u8) bool {
        const saved = self.pos;
        self.skipWhitespaceAndComments();
        const start = self.pos;
        self.pos = saved;

        if (start + keyword.len > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[start .. start + keyword.len], keyword)) return false;
        if (start + keyword.len < self.source.len) {
            const next = self.source[start + keyword.len];
            if (std.ascii.isAlphanumeric(next) or next == '_') return false;
        }
        return true;
    }

    fn peekChar(self: *Parser, expected: u8) bool {
        const saved = self.pos;
        self.skipWhitespaceAndComments();
        const result = self.pos < self.source.len and self.source[self.pos] == expected;
        self.pos = saved;
        return result;
    }

    // ── Identifiers & Literals ────────────────────────────────

    const reserved_words = [_][]const u8{
        "fn",      "module",   "process", "struct",
        "type",    "receive",  "guard",   "match",
        "while",   "return",   "spawn",   "watch",
        "connect", "append",   "use",     "invariant",
        "enum",    "union",    "import",  "export",
        "break",   "continue", "if",      "else",
        "assert",  "test",
    };

    fn isReserved(word: []const u8) bool {
        for (reserved_words) |kw| {
            if (std.mem.eql(u8, word, kw)) return true;
        }
        return false;
    }

    fn parseIdentifier(self: *Parser) Error![]const u8 {
        self.skipWhitespaceAndComments();
        const start = self.pos;
        if (self.pos >= self.source.len) {
            return self.fail("expected identifier but reached end of file", .{});
        }
        const first = self.source[self.pos];
        if (!std.ascii.isAlphabetic(first) and first != '_') {
            return self.fail("expected identifier but found '{c}'", .{first});
        }
        self.pos += 1;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }
        const word = self.source[start..self.pos];
        if (isReserved(word)) {
            return self.fail("'{s}' is a reserved keyword and cannot be used as an identifier", .{word});
        }
        return word;
    }

    fn parseIntLiteral(self: *Parser) Error!i64 {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) {
            return self.fail("expected number but reached end of file", .{});
        }
        const start = self.pos;
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }
        if (self.pos == start) {
            return self.fail("expected number but found '{c}'", .{self.source[self.pos]});
        }
        return std.fmt.parseInt(i64, self.source[start..self.pos], 10) catch {
            return self.fail("number too large: '{s}'", .{self.source[start..self.pos]});
        };
    }

    fn parseStringLiteral(self: *Parser) Error![]const u8 {
        self.skipWhitespaceAndComments();
        try self.expectChar('"');
        const start = self.pos;
        var has_escapes = false;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                has_escapes = true;
                self.pos += 1;
            }
            self.pos += 1;
        }
        if (self.pos >= self.source.len) {
            return self.fail("unterminated string literal starting at position {d}", .{start - 1});
        }
        const raw = self.source[start..self.pos];
        try self.expectChar('"');
        // If no escapes, return the raw slice (zero-copy)
        if (!has_escapes) return raw;
        // Process escape sequences
        const buf = self.alloc.alloc(u8, raw.len) catch return raw;
        var out: usize = 0;
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                const c = raw[i + 1];
                buf[out] = switch (c) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    '/' => '/',
                    '0' => 0,
                    else => c,
                };
                out += 1;
                i += 2;
            } else {
                buf[out] = raw[i];
                out += 1;
                i += 1;
            }
        }
        return buf[0..out];
    }

    fn parseStringOrInterp(self: *Parser) Error!ast.Expr {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len or self.source[self.pos] != '"') {
            return self.fail("expected '\"'", .{});
        }
        // Scan to check for ${ inside the string (not escaped by \)
        var scan = self.pos + 1;
        var has_interp = false;
        while (scan < self.source.len and self.source[scan] != '"') {
            if (self.source[scan] == '\\') {
                scan += 2;
                continue;
            }
            if (self.source[scan] == '$' and scan + 1 < self.source.len and self.source[scan + 1] == '{') {
                has_interp = true;
                break;
            }
            scan += 1;
        }
        if (!has_interp) {
            return .{ .string_literal = try self.parseStringLiteral() };
        }
        // Parse interpolated string: ${ triggers interpolation
        self.pos += 1; // skip opening "
        var parts: std.ArrayListUnmanaged(ast.StringInterpPart) = .{};
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                // Escape: \${ produces literal ${, other escapes pass through
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '$') {
                    // \$ — literal $
                    const lit_start = self.pos + 1; // skip the backslash
                    self.pos += 2;
                    // Continue collecting literal chars
                    while (self.pos < self.source.len and self.source[self.pos] != '"') {
                        if (self.source[self.pos] == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') break;
                        if (self.source[self.pos] == '\\') break;
                        self.pos += 1;
                    }
                    try parts.append(self.alloc, .{ .literal = self.source[lit_start..self.pos] });
                } else {
                    // Other escape sequence — include as-is
                    const esc_start = self.pos;
                    self.pos += 2;
                    while (self.pos < self.source.len and self.source[self.pos] != '"') {
                        if (self.source[self.pos] == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') break;
                        if (self.source[self.pos] == '\\') break;
                        self.pos += 1;
                    }
                    try parts.append(self.alloc, .{ .literal = self.source[esc_start..self.pos] });
                }
            } else if (self.source[self.pos] == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') {
                self.pos += 2; // skip ${
                const expr = try self.parseExpr();
                if (self.pos >= self.source.len or self.source[self.pos] != '}') {
                    return self.fail("expected '}}' to close interpolation", .{});
                }
                self.pos += 1; // skip }
                try parts.append(self.alloc, .{ .expr = expr });
            } else {
                // Literal text — consume until " or ${ or backslash
                const lit_start = self.pos;
                while (self.pos < self.source.len and self.source[self.pos] != '"' and self.source[self.pos] != '\\') {
                    if (self.source[self.pos] == '$' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '{') break;
                    self.pos += 1;
                }
                try parts.append(self.alloc, .{ .literal = self.source[lit_start..self.pos] });
            }
        }
        if (self.pos >= self.source.len) {
            return self.fail("unterminated interpolated string", .{});
        }
        self.pos += 1; // skip closing "
        return .{ .string_interp = .{ .parts = try parts.toOwnedSlice(self.alloc) } };
    }

    fn parseTag(self: *Parser) Error![]const u8 {
        self.skipWhitespaceAndComments();
        try self.expectChar(':');
        return try self.parseIdentifier();
    }

    // ── Doc Comments ──────────────────────────────────────────

    fn parseDocComment(self: *Parser) Error!?[]const u8 {
        self.skipWhitespaceAndComments();
        if (self.pos + 3 > self.source.len) return null;
        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + 3], "///")) return null;

        const start = self.pos;
        while (self.pos + 3 <= self.source.len and std.mem.eql(u8, self.source[self.pos .. self.pos + 3], "///")) {
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
            }
            if (self.pos < self.source.len) self.pos += 1;
            while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
                self.pos += 1;
            }
        }
        return self.source[start..self.pos];
    }

    // ── Type Expressions ──────────────────────────────────────

    pub fn parseTypeExpr(self: *Parser) Error!ast.TypeExpr {
        self.skipWhitespaceAndComments();

        if (self.matchKeyword("fn")) {
            return try self.parseFnType();
        }

        if (self.matchKeyword("enum")) {
            return try self.parseEnumType();
        }

        if (self.matchKeyword("union")) {
            return try self.parseUnionType();
        }

        // 'process' is reserved but valid as a type name (process<T>)
        const name = if (self.matchKeyword("process"))
            @as([]const u8, "process")
        else
            try self.parseIdentifier();

        if (self.peekChar('<')) {
            try self.expectChar('<');
            var args: std.ArrayListUnmanaged(ast.TypeExpr) = .{};
            try args.append(self.alloc, try self.parseTypeExpr());
            while (self.peekChar(',')) {
                try self.expectChar(',');
                try args.append(self.alloc, try self.parseTypeExpr());
            }
            try self.expectChar('>');
            const owned_args = try args.toOwnedSlice(self.alloc);

            if (self.peekChar('?')) {
                try self.expectChar('?');
                const inner = try self.alloc.create(ast.TypeExpr);
                inner.* = .{ .generic = .{ .name = name, .args = owned_args } };
                return .{ .optional = inner };
            }

            return .{ .generic = .{ .name = name, .args = owned_args } };
        }

        if (self.peekChar('?')) {
            try self.expectChar('?');
            const inner = try self.alloc.create(ast.TypeExpr);
            inner.* = .{ .simple = name };
            return .{ .optional = inner };
        }

        return .{ .simple = name };
    }

    fn parseFnType(self: *Parser) Error!ast.TypeExpr {
        try self.expectChar('(');
        var params: std.ArrayListUnmanaged(ast.TypeExpr) = .{};
        if (!self.peekChar(')')) {
            try params.append(self.alloc, try self.parseTypeExpr());
            while (self.peekChar(',')) {
                try self.expectChar(',');
                try params.append(self.alloc, try self.parseTypeExpr());
            }
        }
        try self.expectChar(')');
        try self.expect("->");
        const ret = try self.alloc.create(ast.TypeExpr);
        ret.* = try self.parseTypeExpr();
        return .{ .fn_type = .{
            .params = try params.toOwnedSlice(self.alloc),
            .return_type = ret,
        } };
    }

    fn parseEnumType(self: *Parser) Error!ast.TypeExpr {
        try self.expectChar('{');
        var variants: std.ArrayListUnmanaged([]const u8) = .{};
        try variants.append(self.alloc, try self.parseIdentifier());
        while (self.peekChar(',')) {
            try self.expectChar(',');
            if (self.peekChar('}')) break;
            try variants.append(self.alloc, try self.parseIdentifier());
        }
        try self.expectChar('}');
        return .{ .enum_type = try variants.toOwnedSlice(self.alloc) };
    }

    fn parseUnionType(self: *Parser) Error!ast.TypeExpr {
        try self.expectChar('{');
        var variants: std.ArrayListUnmanaged(ast.UnionVariant) = .{};
        while (!self.peekChar('}')) {
            const tag = try self.parseTag();
            var fields: std.ArrayListUnmanaged(ast.Field) = .{};
            if (self.peekChar('{')) {
                try self.expectChar('{');
                while (!self.peekChar('}')) {
                    const fname = try self.parseIdentifier();
                    try self.expectChar(':');
                    const ftype = try self.parseTypeExpr();
                    try fields.append(self.alloc, .{ .name = fname, .type_expr = ftype, .default_value = null, .span = .{ .start = 0, .end = 0 } });
                    if (self.peekChar(';')) try self.expectChar(';');
                }
                try self.expectChar('}');
            }
            try variants.append(self.alloc, .{ .tag = tag, .fields = try fields.toOwnedSlice(self.alloc) });
            if (self.peekChar(';')) try self.expectChar(';');
        }
        try self.expectChar('}');
        return .{ .union_type = try variants.toOwnedSlice(self.alloc) };
    }

    // ── Expressions ───────────────────────────────────────────

    pub fn parseExpr(self: *Parser) Error!ast.Expr {
        return try self.parseOr();
    }

    fn parseOr(self: *Parser) Error!ast.Expr {
        var left = try self.parseAnd();
        while (true) {
            self.skipWhitespaceAndComments();
            if (self.pos + 1 < self.source.len and
                self.source[self.pos] == '|' and self.source[self.pos + 1] == '|')
            {
                self.pos += 2;
                const right = try self.parseAnd();
                const lp = try self.alloc.create(ast.Expr);
                lp.* = left;
                const rp = try self.alloc.create(ast.Expr);
                rp.* = right;
                left = .{ .binary_op = .{ .op = .@"or", .left = lp, .right = rp } };
            } else break;
        }
        return left;
    }

    fn parseAnd(self: *Parser) Error!ast.Expr {
        var left = try self.parseComparison();
        while (true) {
            self.skipWhitespaceAndComments();
            if (self.pos + 1 < self.source.len and
                self.source[self.pos] == '&' and self.source[self.pos + 1] == '&')
            {
                self.pos += 2;
                const right = try self.parseComparison();
                const lp = try self.alloc.create(ast.Expr);
                lp.* = left;
                const rp = try self.alloc.create(ast.Expr);
                rp.* = right;
                left = .{ .binary_op = .{ .op = .@"and", .left = lp, .right = rp } };
            } else break;
        }
        return left;
    }

    fn parseComparison(self: *Parser) Error!ast.Expr {
        var left = try self.parseAddSub();
        while (true) {
            self.skipWhitespaceAndComments();
            const op = self.parseComparisonOp() orelse break;
            const right = try self.parseAddSub();
            const lp = try self.alloc.create(ast.Expr);
            lp.* = left;
            const rp = try self.alloc.create(ast.Expr);
            rp.* = right;
            left = .{ .binary_op = .{ .op = op, .left = lp, .right = rp } };
        }
        return left;
    }

    fn parseComparisonOp(self: *Parser) ?ast.Op {
        if (self.pos >= self.source.len) return null;
        if (self.pos + 1 < self.source.len) {
            const two = self.source[self.pos .. self.pos + 2];
            if (std.mem.eql(u8, two, "==")) {
                self.pos += 2;
                return .eq;
            }
            if (std.mem.eql(u8, two, "!=")) {
                self.pos += 2;
                return .neq;
            }
            if (std.mem.eql(u8, two, ">=")) {
                self.pos += 2;
                return .gte;
            }
            if (std.mem.eql(u8, two, "<=")) {
                self.pos += 2;
                return .lte;
            }
            if (std.mem.eql(u8, two, "=>")) return null;
        }
        if (self.source[self.pos] == '>') {
            self.pos += 1;
            return .gt;
        }
        if (self.source[self.pos] == '<') {
            self.pos += 1;
            return .lt;
        }
        return null;
    }

    fn parseAddSub(self: *Parser) Error!ast.Expr {
        var left = try self.parseMulDiv();
        while (true) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;
            const c = self.source[self.pos];
            const op: ast.Op = if (c == '+') .add else if (c == '-') .sub else break;
            self.pos += 1;
            const right = try self.parseMulDiv();
            const lp = try self.alloc.create(ast.Expr);
            lp.* = left;
            const rp = try self.alloc.create(ast.Expr);
            rp.* = right;
            left = .{ .binary_op = .{ .op = op, .left = lp, .right = rp } };
        }
        return left;
    }

    fn parseMulDiv(self: *Parser) Error!ast.Expr {
        var left = try self.parseUnary();
        while (true) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;
            const c = self.source[self.pos];
            const op: ast.Op = if (c == '*') .mul else if (c == '/') .div else if (c == '%') .mod else break;
            self.pos += 1;
            const right = try self.parseUnary();
            const lp = try self.alloc.create(ast.Expr);
            lp.* = left;
            const rp = try self.alloc.create(ast.Expr);
            rp.* = right;
            left = .{ .binary_op = .{ .op = op, .left = lp, .right = rp } };
        }
        return left;
    }

    fn parseUnary(self: *Parser) Error!ast.Expr {
        self.skipWhitespaceAndComments();
        if (self.pos < self.source.len and self.source[self.pos] == '!') {
            self.pos += 1;
            const operand = try self.parsePrimary();
            const op = try self.alloc.create(ast.Expr);
            op.* = operand;
            return .{ .unary_op = .{ .op = .not, .operand = op } };
        }
        if (self.pos < self.source.len and self.source[self.pos] == '-') {
            // Check it's not -> (arrow)
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '>') {
                return try self.parsePrimary();
            }
            self.pos += 1;
            const operand = try self.parsePrimary();
            const op = try self.alloc.create(ast.Expr);
            op.* = operand;
            return .{ .unary_op = .{ .op = .sub, .operand = op } };
        }
        return try self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) Error!ast.Expr {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) {
            return self.fail("expected expression but reached end of file", .{});
        }

        const c = self.source[self.pos];

        if (c == '"') return try self.parseStringOrInterp();
        if (c == ':') {
            const tag_name = try self.parseTag();
            if (self.pos < self.source.len and self.source[self.pos] == '{') {
                self.pos += 1;
                self.skipWhitespaceAndComments();
                if (self.pos < self.source.len and self.source[self.pos] == '}') {
                    // Bare tag variant: :red{}
                    self.pos += 1;
                    return .{ .tagged_value = .{ .tag = tag_name, .value = null } };
                }
                const inner = try self.parseExpr();
                const inner_ptr = try self.alloc.create(ast.Expr);
                inner_ptr.* = inner;
                try self.expectChar('}');
                return .{ .tagged_value = .{ .tag = tag_name, .value = inner_ptr } };
            }
            return .{ .tag = tag_name };
        }

        if (std.ascii.isDigit(c)) {
            const num_start = self.pos;
            const val = try self.parseIntLiteral();
            if (self.pos < self.source.len and self.source[self.pos] == '.') {
                self.pos += 1;
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.pos += 1;
                }
                const fval = std.fmt.parseFloat(f64, self.source[num_start..self.pos]) catch {
                    return self.fail("invalid float literal: '{s}'", .{self.source[num_start..self.pos]});
                };
                return .{ .float_literal = fval };
            }
            return .{ .int_literal = val };
        }

        if (std.ascii.isAlphabetic(c) or c == '_') {
            if (self.matchKeyword("true")) return .{ .bool_literal = true };
            if (self.matchKeyword("false")) return .{ .bool_literal = false };
            if (self.matchKeyword("none")) return .{ .none_literal = {} };
            if (self.matchKeyword("void")) return .{ .void_literal = {} };
            if (self.matchKeyword("spawn")) {
                // spawn ProcessName() — parse as call with process name
                const proc_name = try self.parseIdentifier();
                try self.expectChar('(');
                // TODO: parse constructor args
                try self.expectChar(')');
                return .{ .call = .{
                    .target = blk: {
                        const t = try self.alloc.create(ast.Expr);
                        t.* = .{ .identifier = "spawn" };
                        break :blk t;
                    },
                    .args = blk: {
                        const a = try self.alloc.alloc(ast.Expr, 1);
                        a[0] = .{ .string_literal = proc_name };
                        break :blk a;
                    },
                } };
            }

            const ident = try self.parseIdentifier();
            var expr: ast.Expr = .{ .identifier = ident };

            // Struct literal: Name { field: value, ... }
            // Only if identifier starts with uppercase
            if (ident.len > 0 and std.ascii.isUpper(ident[0]) and self.peekChar('{')) {
                try self.expectChar('{');
                var fields: std.ArrayListUnmanaged(ast.StructLiteralField) = .{};
                while (!self.peekChar('}')) {
                    const fname = try self.parseIdentifier();
                    try self.expectChar(':');
                    const fval = try self.parseExpr();
                    try fields.append(self.alloc, .{ .name = fname, .value = fval });
                    if (self.peekChar(',')) try self.expectChar(',');
                }
                try self.expectChar('}');
                return .{ .struct_literal = .{
                    .name = ident,
                    .fields = try fields.toOwnedSlice(self.alloc),
                } };
            }

            while (self.pos < self.source.len) {
                if (self.peekChar('.')) {
                    try self.expectChar('.');
                    const field = try self.parseIdentifier();
                    const target = try self.alloc.create(ast.Expr);
                    target.* = expr;
                    expr = .{ .field_access = .{ .target = target, .field = field } };
                } else if (self.peekChar('[')) {
                    try self.expectChar('[');
                    const idx = try self.parseExpr();
                    try self.expectChar(']');
                    const target = try self.alloc.create(ast.Expr);
                    target.* = expr;
                    const idx_ptr = try self.alloc.create(ast.Expr);
                    idx_ptr.* = idx;
                    expr = .{ .index_access = .{ .target = target, .index = idx_ptr } };
                } else if (self.peekChar('(')) {
                    try self.expectChar('(');
                    var args: std.ArrayListUnmanaged(ast.Expr) = .{};
                    if (!self.peekChar(')')) {
                        try args.append(self.alloc, try self.parseExpr());
                        while (self.peekChar(',')) {
                            try self.expectChar(',');
                            try args.append(self.alloc, try self.parseExpr());
                        }
                    }
                    try self.expectChar(')');
                    const target = try self.alloc.create(ast.Expr);
                    target.* = expr;
                    expr = .{ .call = .{ .target = target, .args = try args.toOwnedSlice(self.alloc) } };
                } else {
                    break;
                }
            }

            return expr;
        }

        if (c == '(') {
            try self.expectChar('(');
            const inner = try self.parseExpr();
            try self.expectChar(')');
            return inner;
        }

        return self.fail("unexpected character '{c}' — expected expression", .{c});
    }

    // ── Statements ────────────────────────────────────────────

    pub fn parseStmt(self: *Parser) Error!ast.Stmt {
        self.skipWhitespaceAndComments();
        const start = self.pos;

        // Catch extra semicolons
        if (self.pos < self.source.len and self.source[self.pos] == ';') {
            return self.fail("unexpected extra ';' — remove the duplicate semicolon", .{});
        }

        if (self.matchKeyword("return")) {
            if (self.peekChar(';')) {
                try self.expectChar(';');
                return .{ .return_stmt = .{ .value = null, .span = .{ .start = start, .end = self.pos } } };
            }
            const val = try self.parseExpr();
            try self.expectChar(';');
            return .{ .return_stmt = .{ .value = val, .span = .{ .start = start, .end = self.pos } } };
        }

        if (self.matchKeyword("break")) {
            try self.expectChar(';');
            return .{ .break_stmt = .{ .start = start, .end = self.pos } };
        }

        if (self.matchKeyword("continue")) {
            try self.expectChar(';');
            return .{ .continue_stmt = .{ .start = start, .end = self.pos } };
        }

        if (self.matchKeyword("assert")) {
            const condition = try self.parseExpr();
            var message: ?[]const u8 = null;
            if (self.peekChar(',')) {
                try self.expectChar(',');
                message = try self.parseStringLiteral();
            }
            try self.expectChar(';');
            return .{ .assert_stmt = .{
                .condition = condition,
                .message = message,
                .span = .{ .start = start, .end = self.pos },
            } };
        }

        if (self.peekKeyword("if")) {
            _ = self.matchKeyword("if");
            return try self.parseIfStmt();
        }

        if (self.peekKeyword("while")) {
            _ = self.matchKeyword("while");
            return try self.parseWhileStmt();
        }

        if (self.peekKeyword("match")) {
            return try self.parseMatchStmt();
        }

        if (self.matchKeyword("receive")) {
            try self.expectChar(';');
            return .{ .receive_stmt = .{ .start = start, .end = self.pos } };
        }

        if (self.matchKeyword("watch")) {
            const target = try self.parseExpr();
            try self.expectChar(';');
            return .{ .watch_stmt = .{ .target = target, .span = .{ .start = start, .end = self.pos } } };
        }

        if (self.matchKeyword("append")) {
            return try self.parseAppendStmt();
        }

        const expr = try self.parseExpr();

        // Declaration: name: type = value;
        if (expr == .identifier and self.peekChar(':')) {
            self.skipWhitespaceAndComments();
            // Make sure it's : not :: or :tag
            if (self.pos < self.source.len and self.source[self.pos] == ':') {
                // Check next char isn't another : or a letter (which would be a tag)
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] != ':') {
                    try self.expectChar(':');
                    const type_expr = try self.parseTypeExpr();
                    try self.expectChar('=');
                    const value = try self.parseExpr();
                    try self.expectChar(';');
                    return .{ .assign = .{
                        .name = expr.identifier,
                        .type_expr = type_expr,
                        .value = value,
                        .span = .{ .start = start, .end = self.pos },
                    } };
                }
            }
        }

        // Reassignment: name = value; or state.field = value;
        if (self.peekChar('=')) {
            self.skipWhitespaceAndComments();
            if (self.pos + 1 < self.source.len and self.source[self.pos + 1] != '=') {
                try self.expectChar('=');
                const value = try self.parseExpr();
                try self.expectChar(';');
                switch (expr) {
                    .identifier => |id| return .{ .assign = .{
                        .name = id,
                        .type_expr = null,
                        .value = value,
                        .span = .{ .start = start, .end = self.pos },
                    } },
                    .field_access => return .{ .field_assign = .{
                        .target = expr,
                        .value = value,
                        .span = .{ .start = start, .end = self.pos },
                    } },
                    else => return self.fail("left side of assignment must be an identifier or field access", .{}),
                }
            }
        }

        try self.expectChar(';');
        return .{ .expr_stmt = expr };
    }

    fn parseTestDecl(self: *Parser) Error!ast.TestDecl {
        const name = try self.parseStringLiteral();
        try self.expectChar('{');
        var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
        while (!self.peekChar('}')) {
            try body.append(self.alloc, try self.parseStmt());
        }
        try self.expectChar('}');
        return .{
            .name = name,
            .body = try body.toOwnedSlice(self.alloc),
            .span = .{ .start = 0, .end = 0 },
        };
    }

    fn parseIfStmt(self: *Parser) Error!ast.Stmt {
        const start = self.pos;
        const condition = try self.parseExpr();
        try self.expectChar('{');
        var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
        while (!self.peekChar('}')) {
            try body.append(self.alloc, try self.parseStmt());
        }
        try self.expectChar('}');

        var else_body: ?[]const ast.Stmt = null;
        if (self.matchKeyword("else")) {
            if (self.peekKeyword("if")) {
                // else if — parse as single if_stmt in else body
                _ = self.matchKeyword("if");
                var else_stmts: std.ArrayListUnmanaged(ast.Stmt) = .{};
                try else_stmts.append(self.alloc, try self.parseIfStmt());
                else_body = try else_stmts.toOwnedSlice(self.alloc);
            } else {
                try self.expectChar('{');
                var eb: std.ArrayListUnmanaged(ast.Stmt) = .{};
                while (!self.peekChar('}')) {
                    try eb.append(self.alloc, try self.parseStmt());
                }
                try self.expectChar('}');
                else_body = try eb.toOwnedSlice(self.alloc);
            }
        }

        return .{ .if_stmt = .{
            .condition = condition,
            .body = try body.toOwnedSlice(self.alloc),
            .else_body = else_body,
            .span = .{ .start = start, .end = self.pos },
        } };
    }

    fn parseWhileStmt(self: *Parser) Error!ast.Stmt {
        const start = self.pos;
        const condition = try self.parseExpr();
        try self.expectChar('{');
        var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
        while (!self.peekChar('}')) {
            try body.append(self.alloc, try self.parseStmt());
        }
        try self.expectChar('}');
        return .{ .while_stmt = .{ .condition = condition, .body = try body.toOwnedSlice(self.alloc), .span = .{ .start = start, .end = self.pos } } };
    }

    fn parseMatchStmt(self: *Parser) Error!ast.Stmt {
        const start = self.pos;
        _ = self.matchKeyword("match");
        const subject = try self.parseExpr();
        try self.expectChar('{');
        var arms: std.ArrayListUnmanaged(ast.MatchArm) = .{};
        while (!self.peekChar('}')) {
            const pattern = try self.parsePattern();
            try self.expect("=>");
            var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
            if (self.peekChar('{')) {
                try self.expectChar('{');
                while (!self.peekChar('}')) {
                    try body.append(self.alloc, try self.parseStmt());
                }
                try self.expectChar('}');
            } else {
                try body.append(self.alloc, try self.parseStmt());
            }
            try arms.append(self.alloc, .{ .pattern = pattern, .body = try body.toOwnedSlice(self.alloc) });
        }
        try self.expectChar('}');
        return .{ .match_stmt = .{ .subject = subject, .arms = try arms.toOwnedSlice(self.alloc), .span = .{ .start = start, .end = self.pos } } };
    }

    fn parsePattern(self: *Parser) Error!ast.Pattern {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len) {
            return self.fail("expected pattern but reached end of file", .{});
        }

        if (self.source[self.pos] == ':') {
            const tag = try self.parseTag();
            var bindings: std.ArrayListUnmanaged([]const u8) = .{};
            if (self.peekChar('{')) {
                try self.expectChar('{');
                if (!self.peekChar('}')) {
                    try bindings.append(self.alloc, try self.parseIdentifier());
                    while (self.peekChar(',')) {
                        try self.expectChar(',');
                        try bindings.append(self.alloc, try self.parseIdentifier());
                    }
                }
                try self.expectChar('}');
            }
            return .{ .tag = .{ .tag = tag, .bindings = try bindings.toOwnedSlice(self.alloc) } };
        }

        if (self.source[self.pos] == '_') {
            self.pos += 1;
            return .{ .wildcard = {} };
        }

        return .{ .literal = try self.parseExpr() };
    }

    fn parseTellStmt(self: *Parser) Error!ast.Stmt {
        // tell process.Handler(args); — fire and forget
        // Parse the call expression, then wrap as tell_stmt
        const start = self.pos;
        const target_expr = try self.parseExpr();
        try self.expectChar(';');
        // Extract process call info from the parsed expression
        if (target_expr == .call) {
            if (target_expr.call.target.* == .field_access) {
                return .{ .tell_stmt = .{
                    .target = target_expr.call.target.field_access.target.*,
                    .handler = target_expr.call.target.field_access.field,
                    .args = target_expr.call.args,
                    .span = .{ .start = start, .end = self.pos },
                } };
            }
        }
        // Fallback — just execute as expression (tell is fire and forget)
        return .{ .expr_stmt = target_expr };
    }

    fn parseAppendStmt(self: *Parser) Error!ast.Stmt {
        const target = try self.parseExpr();
        try self.expectChar('{');
        const value = try self.parseExpr();
        try self.expectChar(';');
        try self.expectChar('}');
        return .{ .append = .{ .target = target, .value = value, .span = .{ .start = 0, .end = 0 } } };
    }

    // ── Functions ─────────────────────────────────────────────

    pub fn parseFnDecl(self: *Parser, doc: ?[]const u8) Error!ast.FnDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();
        try self.expectChar('(');
        var params: std.ArrayListUnmanaged(ast.Param) = .{};
        if (!self.peekChar(')')) {
            try params.append(self.alloc, try self.parseParam());
            while (self.peekChar(',')) {
                try self.expectChar(',');
                try params.append(self.alloc, try self.parseParam());
            }
        }
        try self.expectChar(')');
        try self.expect("->");
        const return_type = try self.parseTypeExpr();
        try self.expectChar('{');

        var guards: std.ArrayListUnmanaged(ast.Expr) = .{};
        while (self.peekKeyword("guard")) {
            _ = self.matchKeyword("guard");
            try guards.append(self.alloc, try self.parseExpr());
            try self.expectChar(';');
        }

        var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
        while (!self.peekChar('}')) {
            try body.append(self.alloc, try self.parseStmt());
        }
        try self.expectChar('}');

        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.alloc),
            .return_type = return_type,
            .guards = try guards.toOwnedSlice(self.alloc),
            .body = try body.toOwnedSlice(self.alloc),
            .doc_comment = doc,
            .examples = &.{},
            .properties = &.{},
            .span = .{ .start = start, .end = self.pos },
        };
    }

    fn parseParam(self: *Parser) Error!ast.Param {
        const start = self.pos;
        const name = try self.parseIdentifier();
        try self.expectChar(':');
        const type_expr = try self.parseTypeExpr();
        return .{ .name = name, .type_expr = type_expr, .span = .{ .start = start, .end = self.pos } };
    }

    pub fn parseReceiveDecl(self: *Parser, doc: ?[]const u8) Error!ast.ReceiveDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();
        try self.expectChar('(');
        var params: std.ArrayListUnmanaged(ast.Param) = .{};
        if (!self.peekChar(')')) {
            try params.append(self.alloc, try self.parseParam());
            while (self.peekChar(',')) {
                try self.expectChar(',');
                try params.append(self.alloc, try self.parseParam());
            }
        }
        try self.expectChar(')');
        try self.expect("->");
        const return_type = try self.parseTypeExpr();
        try self.expectChar('{');

        var guards: std.ArrayListUnmanaged(ast.Expr) = .{};
        while (self.peekKeyword("guard")) {
            _ = self.matchKeyword("guard");
            try guards.append(self.alloc, try self.parseExpr());
            try self.expectChar(';');
        }

        var body: std.ArrayListUnmanaged(ast.Stmt) = .{};
        while (!self.peekChar('}')) {
            try body.append(self.alloc, try self.parseStmt());
        }
        try self.expectChar('}');

        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.alloc),
            .return_type = return_type,
            .guards = try guards.toOwnedSlice(self.alloc),
            .body = try body.toOwnedSlice(self.alloc),
            .doc_comment = doc,
            .examples = &.{},
            .properties = &.{},
            .span = .{ .start = start, .end = self.pos },
        };
    }

    // ── Top-level Declarations ────────────────────────────────

    pub fn parseModuleDecl(self: *Parser) Error!ast.ModuleDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();
        try self.expectChar('{');

        var imports: std.ArrayListUnmanaged(ast.Import) = .{};
        var constants: std.ArrayListUnmanaged(ast.Assign) = .{};
        var functions: std.ArrayListUnmanaged(ast.FnDecl) = .{};
        var tests: std.ArrayListUnmanaged(ast.TestDecl) = .{};

        while (!self.peekChar('}')) {
            const doc = try self.parseDocComment();
            if (self.matchKeyword("use")) {
                try imports.append(self.alloc, try self.parseImport());
            } else if (self.matchKeyword("test")) {
                try tests.append(self.alloc, try self.parseTestDecl());
            } else if (self.matchKeyword("fn")) {
                try functions.append(self.alloc, try self.parseFnDecl(doc));
            } else {
                // Try to parse a constant declaration: name: type = value;
                const saved = self.pos;
                const maybe_ident = self.parseIdentifier() catch null;
                if (maybe_ident != null and self.peekChar(':')) {
                    try self.expectChar(':');
                    const type_expr = try self.parseTypeExpr();
                    try self.expectChar('=');
                    const value = try self.parseExpr();
                    try self.expectChar(';');
                    try constants.append(self.alloc, .{
                        .name = maybe_ident.?,
                        .type_expr = type_expr,
                        .value = value,
                        .span = .{ .start = saved, .end = self.pos },
                    });
                } else {
                    self.pos = saved;
                    return self.fail("expected 'use', 'fn', or constant declaration inside module '{s}' but found '{s}'", .{ name, self.peekSnippet() });
                }
            }
        }
        try self.expectChar('}');

        return .{
            .name = name,
            .constants = try constants.toOwnedSlice(self.alloc),
            .functions = try functions.toOwnedSlice(self.alloc),
            .tests = try tests.toOwnedSlice(self.alloc),
            .imports = try imports.toOwnedSlice(self.alloc),
            .exported = false,
            .doc_comment = null,
            .span = .{ .start = start, .end = self.pos },
        };
    }

    pub fn parseProcessDecl(self: *Parser) Error!ast.ProcessDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();

        // Parse optional state type: process Counter<CounterState>
        var state_type: ?[]const u8 = null;
        if (self.peekChar('<')) {
            try self.expectChar('<');
            state_type = try self.parseIdentifier();
            try self.expectChar('>');
        }

        // Parse optional annotations: [memory: N] [mailbox: N]
        var memory: ?ast.MemoryBudget = null;
        var mailbox_size: ?i64 = null;
        while (self.peekChar('[')) {
            try self.expectChar('[');
            if (self.matchKeyword("memory")) {
                try self.expectChar(':');
                if (self.matchKeyword("unbounded")) {
                    memory = .unbounded;
                } else {
                    memory = .{ .sized = try self.parseExpr() };
                }
            } else if (self.matchKeyword("mailbox")) {
                try self.expectChar(':');
                const size_expr = try self.parseExpr();
                if (size_expr == .int_literal) {
                    mailbox_size = size_expr.int_literal;
                }
            } else {
                return self.fail("expected 'memory' or 'mailbox' in process annotation but found '{s}'", .{self.peekSnippet()});
            }
            try self.expectChar(']');
        }

        try self.expectChar('{');

        var receive_handlers: std.ArrayListUnmanaged(ast.ReceiveDecl) = .{};
        var invariants: std.ArrayListUnmanaged(ast.Expr) = .{};

        while (!self.peekChar('}')) {
            const doc = try self.parseDocComment();
            if (self.matchKeyword("invariant")) {
                try self.expectChar('{');
                while (!self.peekChar('}')) {
                    try invariants.append(self.alloc, try self.parseExpr());
                    try self.expectChar(';');
                }
                try self.expectChar('}');
            } else if (self.matchKeyword("receive")) {
                try receive_handlers.append(self.alloc, try self.parseReceiveDecl(doc));
            } else {
                return self.fail("expected 'invariant' or 'receive' inside process '{s}' but found '{s}'", .{ name, self.peekSnippet() });
            }
        }
        try self.expectChar('}');

        return .{
            .name = name,
            .memory = memory,
            .mailbox_size = mailbox_size,
            .state_type = state_type,
            .receive_handlers = try receive_handlers.toOwnedSlice(self.alloc),
            .invariants = try invariants.toOwnedSlice(self.alloc),
            .exported = false,
            .doc_comment = null,
            .span = .{ .start = start, .end = self.pos },
        };
    }

    fn parseImport(self: *Parser) Error!ast.Import {
        const module_name = try self.parseIdentifier();
        try self.expectChar('{');
        var symbols: std.ArrayListUnmanaged([]const u8) = .{};
        try symbols.append(self.alloc, try self.parseIdentifier());
        while (self.peekChar(',')) {
            try self.expectChar(',');
            if (self.peekChar('}')) break;
            try symbols.append(self.alloc, try self.parseIdentifier());
        }
        try self.expectChar('}');
        try self.expectChar(';');
        return .{
            .module_name = module_name,
            .symbols = try symbols.toOwnedSlice(self.alloc),
            .span = .{ .start = 0, .end = 0 },
        };
    }

    pub fn parseStructDecl(self: *Parser) Error!ast.StructDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();
        var type_params: std.ArrayListUnmanaged([]const u8) = .{};
        if (self.peekChar('<')) {
            try self.expectChar('<');
            try type_params.append(self.alloc, try self.parseIdentifier());
            while (self.peekChar(',')) {
                try self.expectChar(',');
                try type_params.append(self.alloc, try self.parseIdentifier());
            }
            try self.expectChar('>');
        }

        try self.expectChar('{');
        var fields: std.ArrayListUnmanaged(ast.Field) = .{};
        while (!self.peekChar('}')) {
            const field_start = self.pos;
            const fname = try self.parseIdentifier();
            try self.expectChar(':');
            const ftype = try self.parseTypeExpr();
            var field_default: ?ast.Expr = null;
            if (self.peekChar('=')) {
                try self.expectChar('=');
                field_default = try self.parseExpr();
            }
            try self.expectChar(';');
            try fields.append(self.alloc, .{ .name = fname, .type_expr = ftype, .default_value = field_default, .span = .{ .start = field_start, .end = self.pos } });
        }
        try self.expectChar('}');

        return .{
            .name = name,
            .fields = try fields.toOwnedSlice(self.alloc),
            .type_params = try type_params.toOwnedSlice(self.alloc),
            .exported = false,
            .span = .{ .start = start, .end = self.pos },
        };
    }

    pub fn parseTypeDecl(self: *Parser) Error!ast.TypeDecl {
        const start = self.pos;
        const name = try self.parseIdentifier();
        try self.expectChar('=');
        const value = try self.parseTypeExpr();
        try self.expectChar(';');
        return .{ .name = name, .value = value, .exported = false, .span = .{ .start = start, .end = self.pos } };
    }

    // ── File (entry point) ────────────────────────────────────

    pub fn parseFile(self: *Parser) Error!ast.File {
        var imports: std.ArrayListUnmanaged(ast.FileImport) = .{};
        var decls: std.ArrayListUnmanaged(ast.Decl) = .{};

        while (self.pos < self.source.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.source.len) break;

            // Parse imports (must come before declarations)
            if (self.matchKeyword("import")) {
                const path = try self.parseStringLiteral();
                try self.expectChar(';');
                try imports.append(self.alloc, .{ .path = path, .span = .{ .start = 0, .end = 0 } });
                continue;
            }

            // Parse doc comment before declaration
            const doc = try self.parseDocComment();

            // Check for export keyword
            const exported = self.matchKeyword("export");

            if (self.matchKeyword("module")) {
                var mod = try self.parseModuleDecl();
                mod.exported = exported;
                mod.doc_comment = doc;
                try decls.append(self.alloc, .{ .module_decl = mod });
            } else if (self.matchKeyword("process")) {
                var proc = try self.parseProcessDecl();
                proc.exported = exported;
                proc.doc_comment = doc;
                try decls.append(self.alloc, .{ .process_decl = proc });
            } else if (self.matchKeyword("struct")) {
                var s = try self.parseStructDecl();
                s.exported = exported;
                try decls.append(self.alloc, .{ .struct_decl = s });
            } else if (self.matchKeyword("type")) {
                var t = try self.parseTypeDecl();
                t.exported = exported;
                try decls.append(self.alloc, .{ .type_decl = t });
            } else {
                if (exported) {
                    return self.fail("'export' must be followed by 'module', 'process', 'struct', or 'type' but found '{s}'", .{self.peekSnippet()});
                }
                return self.fail("expected 'module', 'process', 'struct', 'type', 'import', or 'export' at top level but found '{s}'", .{self.peekSnippet()});
            }
        }
        return .{ .imports = try imports.toOwnedSlice(self.alloc), .decls = try decls.toOwnedSlice(self.alloc) };
    }
};
