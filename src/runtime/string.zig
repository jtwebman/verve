const std = @import("std");
const rt = @import("runtime.zig");

pub fn string_contains(haystack: []const u8, needle: []const u8) i64 {
    if (std.mem.indexOf(u8, haystack, needle) != null) return 1;
    return 0;
}

pub fn string_starts_with(str: []const u8, prefix: []const u8) i64 {
    if (std.mem.startsWith(u8, str, prefix)) return 1;
    return 0;
}

pub fn string_ends_with(str: []const u8, suffix: []const u8) i64 {
    if (std.mem.endsWith(u8, str, suffix)) return 1;
    return 0;
}

pub fn string_trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n\r");
}

pub fn string_replace(str: []const u8, old: []const u8, new: []const u8) []const u8 {
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, str, pos, old)) |idx| {
        count += 1;
        pos = idx + old.len;
    }
    if (count == 0) return str;
    const result_len = str.len - (count * old.len) + (count * new.len);
    const buf = rt.arena_alloc(result_len) orelse return str;
    var out: usize = 0;
    pos = 0;
    while (std.mem.indexOfPos(u8, str, pos, old)) |idx| {
        @memcpy(buf[out .. out + (idx - pos)], str[pos..idx]);
        out += idx - pos;
        @memcpy(buf[out .. out + new.len], new);
        out += new.len;
        pos = idx + old.len;
    }
    @memcpy(buf[out .. out + (str.len - pos)], str[pos..]);
    out += str.len - pos;
    return buf[0..out];
}

pub fn string_char_at(str: []const u8, idx: i64) []const u8 {
    if (idx < 0) return "";
    const i: usize = @intCast(idx);
    if (i >= str.len) return "";
    return str[i .. i + 1];
}

pub fn string_char_len(str: []const u8) i64 {
    return @intCast(str.len);
}

/// Return list of single-character strings stored as (ptr+len) pairs in a List.
pub fn string_chars(str: []const u8) i64 {
    const list_mem = rt.arena_alloc(@sizeOf(rt.List)) orelse return 0;
    const list = @as(*rt.List, @ptrCast(@alignCast(list_mem)));
    list.* = rt.List.init();
    for (0..str.len) |i| {
        list.append(@intCast(@intFromPtr(&str[i])));
        list.append(1);
    }
    return @intCast(@intFromPtr(list));
}

/// Split a string by delimiter. Returns pointer to a List of (ptr, len) pairs.
pub fn string_split(str: []const u8, delim: []const u8) i64 {
    const list_mem = rt.arena_alloc(@sizeOf(rt.List)) orelse return 0;
    const list = @as(*rt.List, @ptrCast(@alignCast(list_mem)));
    list.* = rt.List.init();
    if (delim.len == 0) {
        list.append(@intCast(@intFromPtr(str.ptr)));
        list.append(@intCast(str.len));
        return @intCast(@intFromPtr(list));
    }
    var pos: usize = 0;
    while (pos <= str.len) {
        if (std.mem.indexOfPos(u8, str, pos, delim)) |idx| {
            const part = str[pos..idx];
            list.append(@intCast(@intFromPtr(part.ptr)));
            list.append(@intCast(part.len));
            pos = idx + delim.len;
        } else {
            const part = str[pos..];
            list.append(@intCast(@intFromPtr(part.ptr)));
            list.append(@intCast(part.len));
            break;
        }
    }
    return @intCast(@intFromPtr(list));
}

pub fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Concatenate two strings. Returns new []const u8.
pub fn verve_string_concat(a: []const u8, b: []const u8) []const u8 {
    const total = a.len + b.len;
    const buf_ptr = rt.arena_alloc(total) orelse return "";
    const buf = @as([*]u8, buf_ptr)[0..total];
    @memcpy(buf[0..a.len], a);
    @memcpy(buf[a.len..total], b);
    return buf;
}
