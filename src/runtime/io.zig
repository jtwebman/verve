const std = @import("std");
const rt = @import("runtime.zig");

// ── Streams ────────────────────────────────────────

/// Unified stream type for file and TCP I/O.
/// Stored as heap-allocated struct, passed around as i64 pointer.
pub const VerveStream = struct {
    kind: Kind,
    fd: std.posix.fd_t,
    /// Buffered read data for line-oriented reading from sockets/files
    read_buf: [4096]u8,
    read_pos: usize,
    read_len: usize,
    /// For file streams: memory-mapped content
    file_data: ?[*]const u8,
    file_len: usize,
    file_pos: usize,
    closed: bool,

    pub const Kind = enum { file_read, file_write, tcp_client, tcp_listener };

    pub fn streamPtr(self: *VerveStream) i64 {
        return @intCast(@intFromPtr(self));
    }
};

pub fn toStream(ptr: i64) ?*VerveStream {
    if (ptr == 0) return null;
    return @as(*VerveStream, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
}

pub fn stream_write(stream_ptr: i64, data: []const u8) void {
    const t = rt.profile.begin();
    defer rt.profile.end(.write, t);

    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    switch (s.kind) {
        .tcp_client => {
            var written: usize = 0;
            while (written < data.len) {
                written += std.posix.write(s.fd, data[written..]) catch return;
            }
        },
        .file_write => {
            _ = std.posix.write(s.fd, data) catch {};
        },
        else => {},
    }
}

pub fn stream_write_line(stream_ptr: i64, data: []const u8) void {
    stream_write(stream_ptr, data);
    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    switch (s.kind) {
        .tcp_client, .file_write => {
            _ = std.posix.write(s.fd, "\n") catch {};
        },
        else => {},
    }
}

/// Read one line from a stream. Returns the line as []const u8.
/// Returns "" on EOF.
pub fn stream_read_line(stream_ptr: i64) []const u8 {
    const s = toStream(stream_ptr) orelse return "";
    if (s.closed) return "";
    switch (s.kind) {
        .file_read => {
            const data = s.file_data orelse return "";
            if (s.file_pos >= s.file_len) return "";
            var end = s.file_pos;
            while (end < s.file_len and data[end] != '\n') : (end += 1) {}
            const line_len = end - s.file_pos;
            const buf_mem = rt.arena_alloc(line_len) orelse return "";
            const buf = @as([*]u8, buf_mem);
            @memcpy(buf[0..line_len], data[s.file_pos..end]);
            s.file_pos = if (end < s.file_len) end + 1 else end;
            return buf[0..line_len];
        },
        .tcp_client => {
            const line_mem = rt.arena_alloc(4096) orelse return "";
            var line_buf = @as([*]u8, line_mem)[0..4096];
            var line_len: usize = 0;
            while (true) {
                while (s.read_pos < s.read_len) {
                    const byte = s.read_buf[s.read_pos];
                    s.read_pos += 1;
                    if (byte == '\n') {
                        return line_buf[0..line_len];
                    }
                    if (line_len < line_buf.len - 1) {
                        line_buf[line_len] = byte;
                        line_len += 1;
                    }
                }
                const n = std.posix.read(s.fd, &s.read_buf) catch return "";
                if (n == 0) {
                    if (line_len > 0) return line_buf[0..line_len];
                    return "";
                }
                s.read_pos = 0;
                s.read_len = n;
            }
        },
        else => return "",
    }
}

/// Read all remaining data from a stream. Returns []const u8.
pub fn stream_read_all_new(stream_ptr: i64) []const u8 {
    const s = toStream(stream_ptr) orelse return "";
    if (s.closed) return "";
    switch (s.kind) {
        .file_read => {
            const data = s.file_data orelse return "";
            const remaining = data[s.file_pos..s.file_len];
            s.file_pos = s.file_len;
            return remaining;
        },
        .tcp_client => {
            var buf = std.ArrayList(u8).init(std.heap.page_allocator);
            if (s.read_pos < s.read_len) {
                buf.appendSlice(s.read_buf[s.read_pos..s.read_len]) catch return "";
                s.read_pos = s.read_len;
            }
            var tmp: [4096]u8 = undefined;
            while (true) {
                const n = std.posix.read(s.fd, &tmp) catch break;
                if (n == 0) break;
                buf.appendSlice(tmp[0..n]) catch break;
            }
            return buf.items;
        },
        else => return "",
    }
}

pub fn stream_close(stream_ptr: i64) void {
    const t = rt.profile.begin();
    defer rt.profile.end(.close, t);

    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    s.closed = true;
    switch (s.kind) {
        .tcp_client, .tcp_listener => {
            std.posix.close(s.fd);
            std.heap.page_allocator.destroy(s);
        },
        .file_write => std.posix.close(s.fd),
        .file_read => {},
    }
}

/// Read up to `max_bytes` from a stream. Returns []const u8.
pub fn stream_read_bytes(stream_ptr: i64, max: i64) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.read, t);

    const s = toStream(stream_ptr) orelse return "";
    if (s.closed) return "";
    const max_usize: usize = @intCast(@as(u64, @bitCast(max)));
    const buf = rt.arena_alloc(max_usize) orelse return "";
    var total: usize = 0;
    switch (s.kind) {
        .tcp_client => {
            while (s.read_pos < s.read_len and total < max_usize) {
                buf[total] = s.read_buf[s.read_pos];
                s.read_pos += 1;
                total += 1;
            }
            if (total < max_usize) {
                const n = std.posix.read(s.fd, buf[total..max_usize]) catch 0;
                total += n;
            }
        },
        else => {},
    }
    return buf[0..total];
}

// ── IO helpers (stdio, files) ─────────────────────

pub fn verve_write(fd: i64, s: []const u8) void {
    _ = fd;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn verve_write_int(fd: i64, val: i64) void {
    _ = fd;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn verve_write_float(fd: i64, val: i64) void {
    _ = fd;
    var buf: [64]u8 = undefined;
    const f: f64 = @bitCast(val);
    const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return;
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch 0;
}

pub fn fileOpen(path: []const u8) i64 {
    const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024) catch return rt.makeTagged(1, 0);
    const stream_mem = rt.arena_alloc(3 * @sizeOf(i64)) orelse return rt.makeTagged(1, 0);
    const stream = @as([*]i64, @ptrCast(@alignCast(stream_mem)));
    stream[0] = @intCast(@intFromPtr(data.ptr));
    stream[1] = @intCast(data.len);
    stream[2] = 0;
    return rt.makeTagged(0, @intCast(@intFromPtr(stream)));
}

pub fn streamReadAll(stream_ptr: i64) []const u8 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(s[0]))))));
    const len: usize = @intCast(@as(u64, @bitCast(s[1])));
    return ptr[0..len];
}
