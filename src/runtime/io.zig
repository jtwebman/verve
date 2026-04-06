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
    closed: bool,

    pub const Kind = enum { file_read, file_write, tcp_client, tcp_listener };

    pub fn streamPtr(self: *VerveStream) usize {
        return @intFromPtr(self);
    }
};

pub fn toStreamFromI64(val: i64) ?*VerveStream {
    const ptr: usize = @intCast(@as(u64, @bitCast(val)));
    if (ptr == 0) return null;
    return @as(*VerveStream, @ptrFromInt(ptr));
}

pub fn toStream(ptr: usize) ?*VerveStream {
    if (ptr == 0) return null;
    return @as(*VerveStream, @ptrFromInt(ptr));
}

pub fn stream_write(stream_val: i64, data: []const u8) void {
    const t = rt.profile.begin();
    defer rt.profile.end(.write, t);

    const s = toStreamFromI64(stream_val) orelse return;
    if (s.closed) return;
    switch (s.kind) {
        .tcp_client, .file_write => {
            var written: usize = 0;
            while (written < data.len) {
                written += std.posix.write(s.fd, data[written..]) catch return;
            }
        },
        else => {},
    }
}

pub fn stream_write_line(stream_val: i64, data: []const u8) void {
    stream_write(stream_val, data);
    const s = toStreamFromI64(stream_val) orelse return;
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
pub fn stream_read_line(stream_val: i64) []const u8 {
    const s = toStreamFromI64(stream_val) orelse return "";
    if (s.closed) return "";
    switch (s.kind) {
        .file_read, .tcp_client => {
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
pub fn stream_read_all(stream_val: i64) []const u8 {
    const s = toStreamFromI64(stream_val) orelse return "";
    if (s.closed) return "";
    switch (s.kind) {
        .file_read, .tcp_client => {
            const alloc = std.heap.page_allocator;
            var cap: usize = 8192;
            var buf = alloc.alloc(u8, cap) catch return "";
            var len: usize = 0;

            // Flush any buffered data first
            if (s.read_pos < s.read_len) {
                const buffered = s.read_len - s.read_pos;
                @memcpy(buf[0..buffered], s.read_buf[s.read_pos..s.read_len]);
                len = buffered;
                s.read_pos = s.read_len;
            }

            while (true) {
                if (len == cap) {
                    const new_cap = cap * 2;
                    const new_buf = alloc.alloc(u8, new_cap) catch break;
                    @memcpy(new_buf[0..len], buf[0..len]);
                    alloc.free(buf);
                    buf = new_buf;
                    cap = new_cap;
                }
                const n = std.posix.read(s.fd, buf[len..cap]) catch break;
                if (n == 0) break;
                len += n;
            }
            return buf[0..len];
        },
        else => return "",
    }
}

pub fn stream_close(stream_val: i64) void {
    const t = rt.profile.begin();
    defer rt.profile.end(.close, t);

    const s = toStreamFromI64(stream_val) orelse return;
    if (s.closed) return;
    s.closed = true;
    switch (s.kind) {
        .tcp_client, .tcp_listener => {
            std.posix.close(s.fd);
        },
        .file_read, .file_write => std.posix.close(s.fd),
    }
}

/// Read up to `max_bytes` from a stream. Returns []const u8.
pub fn stream_read_bytes(stream_val: i64, max: i64) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.read, t);

    const s = toStreamFromI64(stream_val) orelse return "";
    if (s.closed) return "";
    const max_usize: usize = @intCast(@as(u64, @bitCast(max)));
    const buf = rt.arena_alloc(max_usize) orelse return "";
    var total: usize = 0;
    switch (s.kind) {
        .file_read, .tcp_client => {
            // Drain buffered data first
            while (s.read_pos < s.read_len and total < max_usize) {
                buf[total] = s.read_buf[s.read_pos];
                s.read_pos += 1;
                total += 1;
            }
            // Read from fd if we need more
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

// ── File operations ───────────────────────────────

pub fn fileOpen(path: []const u8, mode: []const u8) usize {
    const is_write = mode.len > 0 and mode[0] == 'w';

    if (is_write) {
        const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch return rt.makeTagged(1, 0);
        const s = std.heap.page_allocator.create(VerveStream) catch {
            file.close();
            return rt.makeTagged(1, 0);
        };
        s.* = .{
            .kind = .file_write,
            .fd = file.handle,
            .read_buf = undefined,
            .read_pos = 0,
            .read_len = 0,
            .closed = false,
        };
        return rt.makeTagged(0, @intCast(s.streamPtr()));
    } else {
        const file = std.fs.cwd().openFile(path, .{}) catch return rt.makeTagged(1, 0);
        const s = std.heap.page_allocator.create(VerveStream) catch {
            file.close();
            return rt.makeTagged(1, 0);
        };
        s.* = .{
            .kind = .file_read,
            .fd = file.handle,
            .read_buf = undefined,
            .read_pos = 0,
            .read_len = 0,
            .closed = false,
        };
        return rt.makeTagged(0, @intCast(s.streamPtr()));
    }
}

pub fn file_size(stream_val: i64) i64 {
    const s = toStreamFromI64(stream_val) orelse return -1;
    if (s.closed) return -1;
    const file = std.fs.File{ .handle = s.fd };
    const stat = file.stat() catch return -1;
    return @intCast(stat.size);
}

pub fn file_seek(stream_val: i64, pos: i64) void {
    const s = toStreamFromI64(stream_val) orelse return;
    if (s.closed) return;
    const file = std.fs.File{ .handle = s.fd };
    file.seekTo(@intCast(@as(u64, @bitCast(pos)))) catch return;
    // Invalidate read buffer after seek
    s.read_pos = 0;
    s.read_len = 0;
}

pub fn file_truncate(stream_val: i64, size: i64) void {
    const s = toStreamFromI64(stream_val) orelse return;
    if (s.closed) return;
    const len: u64 = @bitCast(size);
    std.posix.ftruncate(s.fd, len) catch return;
}

pub fn file_fsync(stream_val: i64) void {
    const s = toStreamFromI64(stream_val) orelse return;
    if (s.closed) return;
    std.posix.fsync(s.fd) catch return;
}
