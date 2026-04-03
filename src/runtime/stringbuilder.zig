const std = @import("std");
const rt = @import("runtime.zig");

const StringBuilder = struct {
    buffer: [*]u8,
    len: usize,
    cap: usize,

    fn init(cap: usize) StringBuilder {
        const actual_cap = if (cap == 0) 256 else cap;
        const raw = rt.arena_alloc(actual_cap) orelse return .{ .buffer = undefined, .len = 0, .cap = 0 };
        return .{ .buffer = @ptrCast(@alignCast(raw)), .len = 0, .cap = actual_cap };
    }

    fn ensureCapacity(self: *StringBuilder, additional: usize) void {
        const needed = self.len + additional;
        if (needed <= self.cap) return;
        var new_cap = self.cap;
        while (new_cap < needed) new_cap *= 2;
        const raw = rt.arena_alloc(new_cap) orelse return;
        const new_buf: [*]u8 = @ptrCast(@alignCast(raw));
        if (self.len > 0) @memcpy(new_buf[0..self.len], self.buffer[0..self.len]);
        self.buffer = new_buf;
        self.cap = new_cap;
    }

    fn appendBytes(self: *StringBuilder, data: []const u8) void {
        if (data.len == 0) return;
        if (self.cap == 0) return; // alloc failed
        self.ensureCapacity(data.len);
        if (self.len + data.len > self.cap) return; // grow failed
        @memcpy(self.buffer[self.len .. self.len + data.len], data);
        self.len += data.len;
    }

    fn toSlice(self: *const StringBuilder) []const u8 {
        if (self.len == 0 or self.cap == 0) return "";
        return self.buffer[0..self.len];
    }
};

pub fn verve_sb_new(cap: i64) usize {
    const raw = rt.arena_alloc(@sizeOf(StringBuilder)) orelse return 0;
    const sb: *StringBuilder = @ptrCast(@alignCast(raw));
    const actual_cap: usize = if (cap <= 0) 0 else @intCast(cap);
    sb.* = StringBuilder.init(actual_cap);
    return @intFromPtr(sb);
}

pub fn verve_sb_append(ptr: usize, data: []const u8) void {
    if (ptr == 0) return;
    const sb: *StringBuilder = @ptrFromInt(ptr);
    sb.appendBytes(data);
}

pub fn verve_sb_append_int(ptr: usize, val: i64) void {
    if (ptr == 0) return;
    const sb: *StringBuilder = @ptrFromInt(ptr);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    sb.appendBytes(s);
}

pub fn verve_sb_append_float(ptr: usize, val: f64) void {
    if (ptr == 0) return;
    const sb: *StringBuilder = @ptrFromInt(ptr);
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    sb.appendBytes(s);
}

pub fn verve_sb_to_string(ptr: usize) []const u8 {
    if (ptr == 0) return "";
    const sb: *const StringBuilder = @ptrFromInt(ptr);
    return sb.toSlice();
}

pub fn verve_sb_len(ptr: usize) i64 {
    if (ptr == 0) return 0;
    const sb: *const StringBuilder = @ptrFromInt(ptr);
    return @intCast(sb.len);
}

pub fn verve_sb_clear(ptr: usize) void {
    if (ptr == 0) return;
    const sb: *StringBuilder = @ptrFromInt(ptr);
    sb.len = 0;
}
