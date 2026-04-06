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

pub fn string_to_bool(s: []const u8) bool {
    if (std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "t")) return true;
    return false;
}

/// Format a collection summary: "list<int>(3)"
pub fn collection_to_string(type_label: []const u8, count: i64) []const u8 {
    var buf: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}({d})", .{ type_label, count }) catch return "";
    const result_mem = rt.arena_alloc(s.len) orelse return "";
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    return result[0..s.len];
}

test "convert string helpers format values" {
    try std.testing.expectEqualStrings("42", int_to_string(42));
    try std.testing.expectEqualStrings("true", bool_to_string(true));
    try std.testing.expectEqualStrings("list<int>(3)", collection_to_string("list<int>", 3));
    try std.testing.expect(string_to_bool("true"));
    try std.testing.expectEqual(@as(i64, 12), string_to_int("12"));
}
