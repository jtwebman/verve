const std = @import("std");
const rt = @import("runtime.zig");

const StringBuilder = struct {
    buffer: [*]u8,
    len: usize,
    cap: usize,
    failed: bool = false,

    fn init(cap: usize) StringBuilder {
        const actual_cap = if (cap == 0) 256 else cap;
        const raw = rt.arena_alloc(actual_cap) orelse {
            return .{ .buffer = undefined, .len = 0, .cap = 0, .failed = true };
        };
        return .{ .buffer = @ptrCast(@alignCast(raw)), .len = 0, .cap = actual_cap };
    }

    fn ensureCapacity(self: *StringBuilder, additional: usize) void {
        if (self.cap == 0) {
            self.failed = true;
            return;
        }
        const needed = self.len + additional;
        if (needed <= self.cap) return;
        var new_cap = self.cap;
        while (new_cap < needed) new_cap *= 2;
        const raw = rt.arena_alloc(new_cap) orelse {
            self.failed = true;
            return;
        };
        const new_buf: [*]u8 = @ptrCast(@alignCast(raw));
        if (self.len > 0) @memcpy(new_buf[0..self.len], self.buffer[0..self.len]);
        self.buffer = new_buf;
        self.cap = new_cap;
    }

    fn appendBytes(self: *StringBuilder, data: []const u8) void {
        if (data.len == 0 or self.failed) return;
        if (self.cap == 0) {
            self.failed = true;
            return;
        }
        self.ensureCapacity(data.len);
        if (self.failed or self.len + data.len > self.cap) {
            self.failed = true;
            return;
        }
        @memcpy(self.buffer[self.len .. self.len + data.len], data);
        self.len += data.len;
    }

    fn toSlice(self: *const StringBuilder) []const u8 {
        if (self.failed or self.len == 0 or self.cap == 0) return "";
        return self.buffer[0..self.len];
    }
};

fn sbFromI64(val: i64) ?*StringBuilder {
    const ptr: usize = @intCast(@as(u64, @bitCast(val)));
    if (ptr == 0) return null;
    return @as(*StringBuilder, @ptrFromInt(ptr));
}

pub fn verve_sb_new(cap: i64) usize {
    const raw = rt.arena_alloc(@sizeOf(StringBuilder)) orelse return 0;
    const sb: *StringBuilder = @ptrCast(@alignCast(raw));
    const actual_cap: usize = if (cap <= 0) 0 else @intCast(cap);
    sb.* = StringBuilder.init(actual_cap);
    return @intFromPtr(sb);
}

pub fn verve_sb_append(sb_val: i64, data: []const u8) void {
    const sb = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    sb.appendBytes(data);
}

pub fn verve_sb_append_int(sb_val: i64, val: i64) void {
    const sb = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    sb.appendBytes(s);
}

pub fn verve_sb_append_float(sb_val: i64, val: f64) void {
    const sb = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    sb.appendBytes(s);
}

pub fn verve_sb_to_string(sb_val: i64) []const u8 {
    const sb_ptr = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    const sb: *const StringBuilder = sb_ptr;
    return sb.toSlice();
}

pub fn verve_sb_len(sb_val: i64) i64 {
    const sb_ptr = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    const sb: *const StringBuilder = sb_ptr;
    return @intCast(sb.len);
}

pub fn verve_sb_clear(sb_val: i64) void {
    const sb = sbFromI64(sb_val) orelse rt.runtimeFail("Verve runtime error: invalid string builder handle");
    sb.len = 0;
}

test "string builder appends and grows" {
    const sb_val = verve_sb_new(4);
    verve_sb_append(@intCast(sb_val), "ab");
    verve_sb_append(@intCast(sb_val), "cdef");
    try std.testing.expectEqualStrings("abcdef", verve_sb_to_string(@intCast(sb_val)));
    try std.testing.expectEqual(@as(i64, 6), verve_sb_len(@intCast(sb_val)));
}

test "string builder clear resets length" {
    const sb_val = verve_sb_new(0);
    verve_sb_append(@intCast(sb_val), "hello");
    verve_sb_clear(@intCast(sb_val));
    try std.testing.expectEqual(@as(i64, 0), verve_sb_len(@intCast(sb_val)));
    try std.testing.expectEqualStrings("", verve_sb_to_string(@intCast(sb_val)));
}
