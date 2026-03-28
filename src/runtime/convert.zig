const std = @import("std");
const rt = @import("runtime.zig");

// ── Type conversion functions ────────────────────────

pub fn convert_to_float(x: i64) f64 {
    return @floatFromInt(x);
}

pub fn convert_to_int_f(x: f64) i64 {
    return @intFromFloat(x);
}

pub fn float_to_string(val: f64) []const u8 {
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return "";
    const result_mem = rt.arena_alloc(s.len) orelse return "";
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    return result[0..s.len];
}

pub fn string_to_float(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0.0;
}

pub fn int_to_string(val: i64) []const u8 {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return "";
    const result_mem = rt.arena_alloc(s.len) orelse return "";
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    return result[0..s.len];
}

pub fn string_to_int(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch 0;
}

pub fn bool_to_string(val: bool) []const u8 {
    return if (val) "true" else "false";
}

/// Format a collection summary: "list<int>(3)"
pub fn collection_to_string(type_label: []const u8, count: i64) []const u8 {
    var buf: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}({d})", .{ type_label, count }) catch return type_label;
    const result_mem = rt.arena_alloc(s.len) orelse return type_label;
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    return result[0..s.len];
}
