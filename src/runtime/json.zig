const std = @import("std");
const rt = @import("runtime.zig");

// ── JSON scanning ──────────────────────────────────

/// Skip whitespace in JSON bytes.
fn json_skip_ws(src: []const u8, pos: usize) usize {
    var p = pos;
    while (p < src.len and (src[p] == ' ' or src[p] == '\t' or src[p] == '\n' or src[p] == '\r')) p += 1;
    return p;
}

/// Skip a JSON value (string, number, object, array, bool, null) starting at pos.
/// Returns position after the value.
fn json_skip_value(src: []const u8, pos: usize) usize {
    if (pos >= src.len) return pos;
    return switch (src[pos]) {
        '"' => json_skip_string(src, pos),
        '{' => json_skip_balanced(src, pos, '{', '}'),
        '[' => json_skip_balanced(src, pos, '[', ']'),
        't' => @min(pos + 4, src.len), // true
        'f' => @min(pos + 5, src.len), // false
        'n' => @min(pos + 4, src.len), // null
        else => json_skip_number(src, pos),
    };
}

fn json_skip_string(src: []const u8, pos: usize) usize {
    if (pos >= src.len or src[pos] != '"') return pos;
    var p = pos + 1;
    while (p < src.len) {
        if (src[p] == '\\') {
            p += 2;
            continue;
        }
        if (src[p] == '"') return p + 1;
        p += 1;
    }
    return p;
}

fn json_skip_number(src: []const u8, pos: usize) usize {
    var p = pos;
    if (p < src.len and src[p] == '-') p += 1;
    while (p < src.len and src[p] >= '0' and src[p] <= '9') p += 1;
    if (p < src.len and src[p] == '.') {
        p += 1;
        while (p < src.len and src[p] >= '0' and src[p] <= '9') p += 1;
    }
    if (p < src.len and (src[p] == 'e' or src[p] == 'E')) {
        p += 1;
        if (p < src.len and (src[p] == '+' or src[p] == '-')) p += 1;
        while (p < src.len and src[p] >= '0' and src[p] <= '9') p += 1;
    }
    return p;
}

fn json_skip_balanced(src: []const u8, pos: usize, open: u8, close: u8) usize {
    if (pos >= src.len or src[pos] != open) return pos;
    var depth: usize = 1;
    var p = pos + 1;
    while (p < src.len and depth > 0) {
        if (src[p] == '"') {
            p = json_skip_string(src, p);
            continue;
        }
        if (src[p] == open) depth += 1;
        if (src[p] == close) depth -= 1;
        p += 1;
    }
    return p;
}

/// Find a key in a JSON object string. Returns (value_start, value_end) or null.
fn json_find_key(src: []const u8, key: []const u8) ?struct { start: usize, end: usize } {
    var p = json_skip_ws(src, 0);
    if (p >= src.len or src[p] != '{') return null;
    p = json_skip_ws(src, p + 1);
    while (p < src.len and src[p] != '}') {
        // Parse key
        if (src[p] != '"') return null;
        const key_start = p + 1;
        const key_end_pos = json_skip_string(src, p);
        const key_end = key_end_pos - 1;
        p = json_skip_ws(src, key_end_pos);
        // Expect colon
        if (p >= src.len or src[p] != ':') return null;
        p = json_skip_ws(src, p + 1);
        // Value position
        const val_start = p;
        const val_end = json_skip_value(src, p);
        // Check if key matches
        if (key_end > key_start and key_end - key_start == key.len) {
            if (std.mem.eql(u8, src[key_start..key_end], key)) {
                return .{ .start = val_start, .end = val_end };
            }
        }
        p = json_skip_ws(src, val_end);
        if (p < src.len and src[p] == ',') p = json_skip_ws(src, p + 1);
    }
    return null;
}

/// Extract a JSON string value (removes quotes, handles escapes).
fn json_extract_string(src: []const u8, start: usize, end: usize) struct { ptr: usize, len: usize } {
    if (start >= end or src[start] != '"') return .{ .ptr = 0, .len = 0 };
    // Simple case: no escapes
    const inner_start = start + 1;
    const inner_end = end - 1;
    if (inner_end <= inner_start) return .{ .ptr = 0, .len = 0 };
    const inner = src[inner_start..inner_end];
    // Check for escapes
    if (std.mem.indexOfScalar(u8, inner, '\\') == null) {
        return .{ .ptr = @intFromPtr(inner.ptr), .len = inner.len };
    }
    // Has escapes — need to copy and unescape
    const buf = rt.arena_alloc(inner.len) orelse return .{ .ptr = 0, .len = 0 };
    var out: usize = 0;
    var i: usize = 0;
    while (i < inner.len) {
        if (inner[i] == '\\' and i + 1 < inner.len) {
            const c = inner[i + 1];
            const unescaped: u8 = switch (c) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '"' => '"',
                '\\' => '\\',
                '/' => '/',
                else => c,
            };
            buf[out] = unescaped;
            out += 1;
            i += 2;
        } else {
            buf[out] = inner[i];
            out += 1;
            i += 1;
        }
    }
    return .{ .ptr = @intFromPtr(buf), .len = out };
}

// ── JSON public API ────────────────────────────────

/// Get a string value from a JSON object by key.
pub fn json_get_string(json: []const u8, key: []const u8) []const u8 {
    const found = json_find_key(json, key) orelse return "";
    const result = json_extract_string(json, found.start, found.end);
    return rt.sliceFromPair(result.ptr, result.len);
}

/// Get an int value from a JSON object by key.
pub fn json_get_int(json: []const u8, key: []const u8) i64 {
    const found = json_find_key(json, key) orelse return 0;
    const num_str = json[found.start..found.end];
    return std.fmt.parseInt(i64, num_str, 10) catch 0;
}

/// Get a float value from a JSON object by key (returned as bitcast i64).
pub fn json_get_float(json: []const u8, key: []const u8) i64 {
    const checked = @import("checked.zig");
    const found = json_find_key(json, key) orelse return checked.i64_from_f64(0.0);
    const num_str = json[found.start..found.end];
    const f = std.fmt.parseFloat(f64, num_str) catch return checked.i64_from_f64(0.0);
    return checked.i64_from_f64(f);
}

/// Get a bool value from a JSON object by key.
pub fn json_get_bool(json: []const u8, key: []const u8) i64 {
    const found = json_find_key(json, key) orelse return 0;
    if (found.end - found.start >= 4 and std.mem.eql(u8, json[found.start .. found.start + 4], "true")) return 1;
    return 0;
}

/// Get a sub-object from a JSON object by key (returns JSON string).
pub fn json_get_object(json: []const u8, key: []const u8) []const u8 {
    const found = json_find_key(json, key) orelse return "";
    return json[found.start..found.end];
}

/// Parse a single JSON value string as int.
pub fn json_to_int(json: []const u8) i64 {
    const trimmed = std.mem.trim(u8, json, " \t\n\r");
    return std.fmt.parseInt(i64, trimmed, 10) catch 0;
}

/// Parse a single JSON value string as float (returned as bitcast i64).
pub fn json_to_float(json: []const u8) i64 {
    const checked = @import("checked.zig");
    const trimmed = std.mem.trim(u8, json, " \t\n\r");
    const f = std.fmt.parseFloat(f64, trimmed) catch return checked.i64_from_f64(0.0);
    return checked.i64_from_f64(f);
}

/// Parse a single JSON value string as bool.
pub fn json_to_bool(json: []const u8) i64 {
    const trimmed = std.mem.trim(u8, json, " \t\n\r");
    if (trimmed.len >= 4 and std.mem.eql(u8, trimmed[0..4], "true")) return 1;
    return 0;
}

/// Unquote a JSON string value.
pub fn json_to_string(json: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, json, " \t\n\r");
    const result = json_extract_string(trimmed, 0, trimmed.len);
    return rt.sliceFromPair(result.ptr, result.len);
}

/// Split a JSON array into a List of (ptr, len) pairs for each element.
pub fn json_get_array(json: []const u8, key: []const u8) i64 {
    const found = json_find_key(json, key) orelse return 0;
    return json_split_array(json, found.start, found.end);
}

pub fn json_get_array_len(json: []const u8, key: []const u8) i64 {
    const found = json_find_key(json, key) orelse return 0;
    return json_count_array(json, found.start, found.end);
}

fn json_count_array(src: []const u8, start: usize, end: usize) i64 {
    _ = end;
    var p = json_skip_ws(src, start);
    if (p >= src.len or src[p] != '[') return 0;
    p = json_skip_ws(src, p + 1);
    if (p < src.len and src[p] == ']') return 0;
    var count: i64 = 0;
    while (p < src.len and src[p] != ']') {
        _ = json_skip_value(src, p);
        count += 1;
        p = json_skip_ws(src, json_skip_value(src, p));
        if (p < src.len and src[p] == ',') p = json_skip_ws(src, p + 1);
    }
    return count;
}

fn json_split_array(src: []const u8, start: usize, end: usize) i64 {
    _ = end;
    var p = json_skip_ws(src, start);
    if (p >= src.len or src[p] != '[') return 0;
    p = json_skip_ws(src, p + 1);

    // Build a list: pairs of (ptr, len) for each element as string
    // Allocate List struct in arena so pointer survives
    const list_mem = rt.arena_alloc(@sizeOf(rt.List)) orelse return 0;
    const list = @as(*rt.List, @ptrCast(@alignCast(list_mem)));
    list.* = rt.List.init();
    while (p < src.len and src[p] != ']') {
        const elem_start = p;
        const elem_end = json_skip_value(src, p);
        // Store element as (ptr, len) pair in the list
        list.append(@intCast(@intFromPtr(src[elem_start..elem_end].ptr)));
        list.append(@intCast(elem_end - elem_start));
        p = json_skip_ws(src, elem_end);
        if (p < src.len and src[p] == ',') p = json_skip_ws(src, p + 1);
    }
    return @intCast(@intFromPtr(list));
}

// ── JSON builder (stringify) ───────────────────────

/// A growable JSON string buffer allocated in the arena.
pub const JsonBuilder = struct {
    buf: [*]u8,
    len: usize,
    cap: usize,

    pub fn init() JsonBuilder {
        const initial_cap: usize = 256;
        const mem = rt.arena_alloc(initial_cap) orelse return .{ .buf = undefined, .len = 0, .cap = 0 };
        return .{ .buf = mem, .len = 0, .cap = initial_cap };
    }

    pub fn append(self: *JsonBuilder, data: []const u8) void {
        if (self.cap == 0) return;
        // Simple: if it fits, copy. Otherwise truncate (arena can't realloc easily).
        const remaining = self.cap - self.len;
        const to_copy = @min(data.len, remaining);
        @memcpy(self.buf[self.len .. self.len + to_copy], data[0..to_copy]);
        self.len += to_copy;
    }

    pub fn appendByte(self: *JsonBuilder, b: u8) void {
        if (self.len < self.cap) {
            self.buf[self.len] = b;
            self.len += 1;
        }
    }

    pub fn appendInt(self: *JsonBuilder, val: i64) void {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
        self.append(s);
    }

    pub fn appendFloat(self: *JsonBuilder, val: f64) void {
        var tmp: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
        self.append(s);
    }

    pub fn appendQuotedString(self: *JsonBuilder, str: []const u8) void {
        self.appendByte('"');
        for (str) |c| {
            switch (c) {
                '"' => self.append("\\\""),
                '\\' => self.append("\\\\"),
                '\n' => self.append("\\n"),
                '\t' => self.append("\\t"),
                '\r' => self.append("\\r"),
                else => self.appendByte(c),
            }
        }
        self.appendByte('"');
    }

    pub fn result(self: *JsonBuilder) struct { ptr: usize, len: usize } {
        return .{ .ptr = @intFromPtr(self.buf), .len = self.len };
    }
};

/// Start building a JSON object. Returns a builder handle (pointer to JsonBuilder in arena).
pub fn json_build_object() usize {
    const mem = rt.arena_alloc(@sizeOf(JsonBuilder)) orelse return 0;
    const b = @as(*JsonBuilder, @ptrCast(@alignCast(mem)));
    b.* = JsonBuilder.init();
    b.appendByte('{');
    return @intFromPtr(b);
}

/// Add a string field to a JSON builder.
pub fn json_build_add_string(builder_ptr: usize, key: []const u8, val: []const u8) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.appendQuotedString(val);
}

/// Add an int field to a JSON builder.
pub fn json_build_add_int(builder_ptr: usize, key: []const u8, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.appendInt(val);
}

/// Add a float field to a JSON builder.
pub fn json_build_add_float(builder_ptr: usize, key: []const u8, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    const checked = @import("checked.zig");
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.appendFloat(checked.f64_from_i64(val));
}

/// Add a bool field to a JSON builder.
pub fn json_build_add_bool(builder_ptr: usize, key: []const u8, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.append(if (val != 0) "true" else "false");
}

/// Add a null field to a JSON builder.
pub fn json_build_add_null(builder_ptr: usize, key: []const u8) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.append("null");
}

/// Add a raw JSON value (sub-object, sub-array) to a JSON builder.
pub fn json_build_add_raw(builder_ptr: usize, key: []const u8, val: []const u8) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(key);
    b.appendByte(':');
    b.append(val);
}

/// Finish building a JSON object. Returns the JSON string as []const u8.
pub fn json_build_end(builder_ptr: usize) []const u8 {
    if (builder_ptr == 0) return "";
    const b = @as(*JsonBuilder, @ptrFromInt(builder_ptr));
    b.appendByte('}');
    const res = b.result();
    return rt.sliceFromPair(res.ptr, res.len);
}
