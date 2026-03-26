const std = @import("std");

// ── Constants ──────────────────────────────────────
pub const MAILBOX_CAPACITY = 64;
pub const MAX_PROCESSES = 256;
pub const MAX_STATE_FIELDS = 16;
pub const MAX_WATCHERS = 64;
pub const MAX_MSG_ARGS = 8;

// HTTP limits (sane defaults, engineers can recompile with different values)
pub const HTTP_MAX_HEADER_SIZE = 8 * 1024; // 8KB per header section
pub const HTTP_MAX_BODY_SIZE = 1024 * 1024; // 1MB request body
pub const HTTP_MAX_URI_SIZE = 8 * 1024; // 8KB URI length
pub const HTTP_MAX_METHOD_SIZE = 16; // longest standard method

// ── Initialization ─────────────────────────────────

/// Must be called at program startup. Ignores SIGPIPE so writing to a closed
/// socket returns an error instead of killing the process.
pub fn verve_runtime_init() void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
}

// ── IO helpers ─────────────────────────────────────

pub fn verve_write(fd: i64, ptr: [*]const u8, len: i64) void {
    const f = std.posix.STDOUT_FILENO;
    _ = fd;
    const actual_len: usize = if (len > 0) @intCast(@as(u64, @bitCast(len))) else blk: {
        var l: usize = 0;
        while (ptr[l] != 0) l += 1;
        break :blk l;
    };
    const slice = ptr[0..actual_len];
    _ = std.posix.write(f, slice) catch 0;
}

pub fn fileOpen(path_ptr: i64, path_len: i64) i64 {
    const ptr = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(path_ptr))))));
    const len: usize = if (path_len > 0) @intCast(@as(u64, @bitCast(path_len))) else blk: {
        var l: usize = 0;
        while (ptr[l] != 0) l += 1;
        break :blk l;
    };
    const path = ptr[0..len];
    const data = std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 10 * 1024 * 1024) catch return makeTagged(1, 0);
    const stream_mem = arena_alloc(3 * @sizeOf(i64)) orelse return makeTagged(1, 0);
    const stream = @as([*]i64, @ptrCast(@alignCast(stream_mem)));
    stream[0] = @intCast(@intFromPtr(data.ptr));
    stream[1] = @intCast(data.len);
    stream[2] = 0;
    return makeTagged(0, @intCast(@intFromPtr(stream)));
}

pub fn streamReadAll(stream_ptr: i64) i64 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    return s[0];
}

pub fn streamReadAllLen(stream_ptr: i64) i64 {
    const s = @as([*]i64, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(stream_ptr))))));
    return s[1];
}

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

fn toStream(ptr: i64) ?*VerveStream {
    if (ptr == 0) return null;
    return @as(*VerveStream, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
}

fn sliceFromPtr(ptr: i64, len: i64) []const u8 {
    const p = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
    const l: usize = @intCast(@as(u64, @bitCast(len)));
    return p[0..l];
}

pub fn stream_write(stream_ptr: i64, data_ptr: i64, data_len: i64) void {
    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    const data = sliceFromPtr(data_ptr, data_len);
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

pub fn stream_write_line(stream_ptr: i64, data_ptr: i64, data_len: i64) void {
    stream_write(stream_ptr, data_ptr, data_len);
    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    switch (s.kind) {
        .tcp_client, .file_write => {
            _ = std.posix.write(s.fd, "\n") catch {};
        },
        else => {},
    }
}

/// Read one line from a stream. Returns a null-terminated string pointer as i64.
/// Returns 0 on EOF.
pub fn stream_read_line(stream_ptr: i64) i64 {
    const s = toStream(stream_ptr) orelse return 0;
    if (s.closed) return 0;
    switch (s.kind) {
        .file_read => {
            const data = s.file_data orelse return 0;
            if (s.file_pos >= s.file_len) return 0;
            var end = s.file_pos;
            while (end < s.file_len and data[end] != '\n') : (end += 1) {}
            const line_len = end - s.file_pos;
            // Copy to null-terminated buffer
            const buf_mem = arena_alloc(line_len + 1) orelse return 0;
            const buf = @as([*]u8, buf_mem);
            @memcpy(buf[0..line_len], data[s.file_pos..end]);
            buf[line_len] = 0;
            s.file_pos = if (end < s.file_len) end + 1 else end;
            return @intCast(@intFromPtr(buf));
        },
        .tcp_client => {
            const line_mem = arena_alloc(4096) orelse return 0;
            var line_buf = @as([*]u8, line_mem)[0..4096];
            var line_len: usize = 0;
            while (true) {
                while (s.read_pos < s.read_len) {
                    const byte = s.read_buf[s.read_pos];
                    s.read_pos += 1;
                    if (byte == '\n') {
                        // Null-terminate and return
                        if (line_len < line_buf.len) line_buf[line_len] = 0;
                        return @intCast(@intFromPtr(line_buf.ptr));
                    }
                    if (line_len < line_buf.len - 1) {
                        line_buf[line_len] = byte;
                        line_len += 1;
                    }
                }
                const n = std.posix.read(s.fd, &s.read_buf) catch return 0;
                if (n == 0) {
                    if (line_len > 0) {
                        if (line_len < line_buf.len) line_buf[line_len] = 0;
                        return @intCast(@intFromPtr(line_buf.ptr));
                    }
                    return 0;
                }
                s.read_pos = 0;
                s.read_len = n;
            }
        },
        else => return 0,
    }
}

/// Get the byte length of a stream_read_line result (null-terminated string).
pub fn stream_read_line_len(ptr: i64) i64 {
    if (ptr == 0) return 0;
    const p = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
    var l: usize = 0;
    while (p[l] != 0) l += 1;
    return @intCast(l);
}

/// Read all remaining data from a stream. Returns string pointer as i64.
pub fn stream_read_all_new(stream_ptr: i64) i64 {
    const s = toStream(stream_ptr) orelse return 0;
    if (s.closed) return 0;
    switch (s.kind) {
        .file_read => {
            // For file streams, return pointer to remaining data
            const data = s.file_data orelse return 0;
            const ptr = @intFromPtr(data + s.file_pos);
            s.file_pos = s.file_len;
            return @intCast(ptr);
        },
        .tcp_client => {
            var buf = std.ArrayList(u8).init(std.heap.page_allocator);
            // Drain read buffer first
            if (s.read_pos < s.read_len) {
                buf.appendSlice(s.read_buf[s.read_pos..s.read_len]) catch return 0;
                s.read_pos = s.read_len;
            }
            var tmp: [4096]u8 = undefined;
            while (true) {
                const n = std.posix.read(s.fd, &tmp) catch break;
                if (n == 0) break;
                buf.appendSlice(tmp[0..n]) catch break;
            }
            // Null-terminate
            buf.append(0) catch {};
            return @intCast(@intFromPtr(buf.items.ptr));
        },
        else => return 0,
    }
}

pub fn stream_close(stream_ptr: i64) void {
    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    s.closed = true;
    switch (s.kind) {
        .tcp_client, .tcp_listener => std.posix.close(s.fd),
        .file_write => std.posix.close(s.fd),
        .file_read => {},
    }
}

// ── TCP ────────────────────────────────────────────

pub fn tcp_open(host_ptr: i64, host_len: i64, port: i64) i64 {
    const host = sliceFromPtr(host_ptr, host_len);
    const port_u16: u16 = @intCast(@as(u64, @bitCast(port)));

    const addr = std.net.Address.resolveIp(host, port_u16) catch return makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return makeTagged(1, 0);
    std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return makeTagged(1, 0);
    };

    const s_mem = arena_alloc(@sizeOf(VerveStream)) orelse return makeTagged(1, 0);
    const s = @as(*VerveStream, @ptrCast(@alignCast(s_mem)));
    s.* = .{
        .kind = .tcp_client,
        .fd = fd,
        .read_buf = undefined,
        .read_pos = 0,
        .read_len = 0,
        .file_data = null,
        .file_len = 0,
        .file_pos = 0,
        .closed = false,
    };
    return makeTagged(0, s.streamPtr());
}

pub fn tcp_listen(host_ptr: i64, host_len: i64, port: i64) i64 {
    const host = sliceFromPtr(host_ptr, host_len);
    const port_u16: u16 = @intCast(@as(u64, @bitCast(port)));

    const addr = std.net.Address.resolveIp(host, port_u16) catch return makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return makeTagged(1, 0);

    // SO_REUSEADDR to avoid "address already in use"
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch {};

    std.posix.bind(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return makeTagged(1, 0);
    };
    std.posix.listen(fd, 128) catch {
        std.posix.close(fd);
        return makeTagged(1, 0);
    };

    const s_mem = arena_alloc(@sizeOf(VerveStream)) orelse return makeTagged(1, 0);
    const s = @as(*VerveStream, @ptrCast(@alignCast(s_mem)));
    s.* = .{
        .kind = .tcp_listener,
        .fd = fd,
        .read_buf = undefined,
        .read_pos = 0,
        .read_len = 0,
        .file_data = null,
        .file_len = 0,
        .file_pos = 0,
        .closed = false,
    };
    return makeTagged(0, s.streamPtr());
}

pub fn tcp_accept(listener_ptr: i64) i64 {
    const listener = toStream(listener_ptr) orelse return makeTagged(1, 0);
    if (listener.closed or listener.kind != .tcp_listener) return makeTagged(1, 0);

    const client_fd = std.posix.accept(listener.fd, null, null, 0) catch return makeTagged(1, 0);

    const s_mem = arena_alloc(@sizeOf(VerveStream)) orelse {
        std.posix.close(client_fd);
        return makeTagged(1, 0);
    };
    const s = @as(*VerveStream, @ptrCast(@alignCast(s_mem)));
    s.* = .{
        .kind = .tcp_client,
        .fd = client_fd,
        .read_buf = undefined,
        .read_pos = 0,
        .read_len = 0,
        .file_data = null,
        .file_len = 0,
        .file_pos = 0,
        .closed = false,
    };
    return makeTagged(0, s.streamPtr());
}

/// Get the local port of a listener socket. Useful after listen with port 0.
pub fn tcp_port(stream_ptr: i64) i64 {
    const s = toStream(stream_ptr) orelse return 0;
    if (s.kind != .tcp_listener and s.kind != .tcp_client) return 0;
    var addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    std.posix.getsockname(s.fd, @ptrCast(&addr), &addr_len) catch return 0;
    return @intCast(std.mem.bigToNative(u16, addr.port));
}

// ── Math ───────────────────────────────────────────

pub fn math_abs(x: i64) i64 {
    return if (x < 0) -x else x;
}

pub fn math_min(a: i64, b: i64) i64 {
    return if (a < b) a else b;
}

pub fn math_max(a: i64, b: i64) i64 {
    return if (a > b) a else b;
}

pub fn math_clamp(x: i64, lo: i64, hi: i64) i64 {
    return if (x < lo) lo else if (x > hi) hi else x;
}

pub fn math_pow(base: i64, exp: i64) i64 {
    if (exp < 0) return 0;
    var result: i64 = 1;
    var e: i64 = exp;
    var b: i64 = base;
    while (e > 0) {
        if (@mod(e, 2) == 1) result = result *% b;
        b = b *% b;
        e = @divTrunc(e, 2);
    }
    return result;
}

pub fn math_sqrt(x: i64) i64 {
    if (x <= 0) return 0;
    const f: f64 = @floatFromInt(x);
    return @intFromFloat(@sqrt(f));
}

pub fn math_log2(x: i64) i64 {
    if (x <= 0) return 0;
    var n: i64 = x;
    var result: i64 = 0;
    while (n > 1) {
        n = @divTrunc(n, 2);
        result += 1;
    }
    return result;
}

// ── Math (float) ──────────────────────────────────

fn f64_from_i64(v: i64) f64 {
    return @bitCast(v);
}

fn i64_from_f64(v: f64) i64 {
    return @bitCast(v);
}

pub fn math_abs_f(x: i64) i64 {
    return i64_from_f64(@abs(f64_from_i64(x)));
}

pub fn math_floor(x: i64) i64 {
    return @intFromFloat(@floor(f64_from_i64(x)));
}

pub fn math_ceil(x: i64) i64 {
    return @intFromFloat(@ceil(f64_from_i64(x)));
}

pub fn math_round(x: i64) i64 {
    return @intFromFloat(@round(f64_from_i64(x)));
}

pub fn math_sin(x: i64) i64 {
    return i64_from_f64(@sin(f64_from_i64(x)));
}

pub fn math_cos(x: i64) i64 {
    return i64_from_f64(@cos(f64_from_i64(x)));
}

pub fn math_tan(x: i64) i64 {
    return i64_from_f64(@tan(f64_from_i64(x)));
}

pub fn math_sqrt_f(x: i64) i64 {
    const v = f64_from_i64(x);
    if (v < 0) return i64_from_f64(0.0);
    return i64_from_f64(@sqrt(v));
}

pub fn math_pow_f(base: i64, exp: i64) i64 {
    const b = f64_from_i64(base);
    const e = f64_from_i64(exp);
    return i64_from_f64(std.math.pow(f64, b, e));
}

pub fn math_log(x: i64) i64 {
    const v = f64_from_i64(x);
    if (v <= 0) return i64_from_f64(0.0);
    return i64_from_f64(@log(v));
}

pub fn math_log10(x: i64) i64 {
    const v = f64_from_i64(x);
    if (v <= 0) return i64_from_f64(0.0);
    return i64_from_f64(@log10(v));
}

pub fn math_exp(x: i64) i64 {
    return i64_from_f64(@exp(f64_from_i64(x)));
}

pub fn math_min_f(a: i64, b: i64) i64 {
    const fa = f64_from_i64(a);
    const fb = f64_from_i64(b);
    return i64_from_f64(if (fa < fb) fa else fb);
}

pub fn math_max_f(a: i64, b: i64) i64 {
    const fa = f64_from_i64(a);
    const fb = f64_from_i64(b);
    return i64_from_f64(if (fa > fb) fa else fb);
}

// ── Convert (float) ───────────────────────────────

pub fn convert_to_float(x: i64) i64 {
    const f: f64 = @floatFromInt(x);
    return i64_from_f64(f);
}

pub fn convert_to_int_f(x: i64) i64 {
    const f = f64_from_i64(x);
    return @intFromFloat(f);
}

pub fn float_to_string(val: i64) i64 {
    const f = f64_from_i64(val);
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return 0;
    const result_mem = arena_alloc(s.len + 1) orelse return 0;
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    result[s.len] = 0;
    return @intCast(@intFromPtr(result));
}

pub fn string_to_float(ptr: i64, len: i64) i64 {
    const s = sliceFromPtr(ptr, len);
    const f = std.fmt.parseFloat(f64, s) catch return i64_from_f64(0.0);
    return i64_from_f64(f);
}

// ── Env ────────────────────────────────────────────

pub fn env_get(name_ptr: i64, name_len: i64) i64 {
    const name = sliceFromPtr(name_ptr, name_len);
    const val = std.posix.getenv(name) orelse return 0;
    return @intCast(@intFromPtr(val.ptr));
}

pub fn env_get_len(name_ptr: i64, name_len: i64) i64 {
    const name = sliceFromPtr(name_ptr, name_len);
    const val = std.posix.getenv(name) orelse return 0;
    return @intCast(val.len);
}

// ── System ─────────────────────────────────────────

pub fn system_exit(code: i64) noreturn {
    std.process.exit(@intCast(@as(u64, @bitCast(code))));
}

pub fn system_time_ms() i64 {
    return @intCast(@divFloor(std.time.milliTimestamp(), 1));
}

// ── Int/String conversion ──────────────────────────

pub fn int_to_string(val: i64) i64 {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return 0;
    const result_mem = arena_alloc(s.len + 1) orelse return 0;
    const result = @as([*]u8, result_mem);
    @memcpy(result[0..s.len], s);
    result[s.len] = 0;
    return @intCast(@intFromPtr(result));
}

pub fn int_to_string_len(val: i64) i64 {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return 0;
    return @intCast(s.len);
}

pub fn string_to_int(ptr: i64, len: i64) i64 {
    const s = sliceFromPtr(ptr, len);
    return std.fmt.parseInt(i64, s, 10) catch 0;
}

// ── Collections ────────────────────────────────────

pub const List = struct {
    items: [*]i64,
    len: i64,
    cap: i64,

    pub fn init() List {
        const raw = arena_alloc(256 * @sizeOf(i64)) orelse return .{ .items = undefined, .len = 0, .cap = 0 };
        const mem = @as([*]i64, @ptrCast(@alignCast(raw)));
        return .{ .items = mem, .len = 0, .cap = 256 };
    }

    pub fn append(self: *List, val: i64) void {
        const idx: usize = @intCast(@as(u64, @bitCast(self.len)));
        self.items[idx] = val;
        self.len += 1;
    }

    pub fn get(self: *const List, idx: i64) i64 {
        return self.items[@intCast(@as(u64, @bitCast(idx)))];
    }
};

// ── Tagged values (Result<T>) ──────────────────────

pub const Tagged = struct { tag: i64, value: i64 };

pub fn makeTagged(tag: i64, value: i64) i64 {
    const mem = arena_alloc(@sizeOf(Tagged)) orelse return 0;
    const t = @as(*Tagged, @ptrCast(@alignCast(mem)));
    t.* = .{ .tag = tag, .value = value };
    return @intCast(@intFromPtr(t));
}

pub fn getTag(ptr: i64) i64 {
    if (ptr == 0) return -1;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).tag;
}

pub fn getTagValue(ptr: i64) i64 {
    if (ptr == 0) return 0;
    return @as(*const Tagged, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr)))))).value;
}

// ── String helpers ─────────────────────────────────

pub fn strEql(a: [*]const u8, a_len: i64, b: [*]const u8, b_len: i64) bool {
    if (a_len != b_len) return false;
    const len: usize = @intCast(@as(u64, @bitCast(a_len)));
    return std.mem.eql(u8, a[0..len], b[0..len]);
}

/// Concatenate two strings. Returns pointer to new buffer.
/// Caller tracks length as a_len + b_len.
pub fn verve_string_concat(a_ptr: i64, a_len: i64, b_ptr: i64, b_len: i64) i64 {
    const al: usize = @intCast(@as(u64, @bitCast(a_len)));
    const bl: usize = @intCast(@as(u64, @bitCast(b_len)));
    const total = al + bl;
    const buf_ptr = arena_alloc(total + 1) orelse return 0; // +1 for null terminator
    const buf = @as([*]u8, buf_ptr)[0 .. total + 1];
    if (a_ptr != 0 and al > 0) {
        const a = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(a_ptr))))));
        @memcpy(buf[0..al], a[0..al]);
    }
    if (b_ptr != 0 and bl > 0) {
        const b = @as([*]const u8, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(b_ptr))))));
        @memcpy(buf[al..total], b[0..bl]);
    }
    buf[total] = 0; // null-terminate for backward compat with strlen
    return @intCast(@intFromPtr(buf.ptr));
}

// ── Checked arithmetic (poison values) ─────────────

/// Poison sentinel values — chosen to be in the extreme negative range
/// that normal arithmetic cannot produce (i64.MIN region).
pub const POISON_OVERFLOW: i64 = std.math.minInt(i64) + 1; // 0x8000000000000001
pub const POISON_DIV_ZERO: i64 = std.math.minInt(i64) + 2;
pub const POISON_OUT_OF_BOUNDS: i64 = std.math.minInt(i64) + 3;

fn isPoison(v: i64) bool {
    return v >= std.math.minInt(i64) and v <= std.math.minInt(i64) + 3 and v != std.math.minInt(i64);
}

pub fn verve_add_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_sub_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_mul_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

pub fn verve_div_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    if (b == 0) return POISON_DIV_ZERO;
    return @divTrunc(a, b);
}

pub fn verve_mod_checked(a: i64, b: i64) i64 {
    if (isPoison(a)) return a;
    if (isPoison(b)) return b;
    if (b == 0) return POISON_DIV_ZERO;
    return @mod(a, b);
}

pub fn verve_neg_checked(a: i64) i64 {
    if (isPoison(a)) return a;
    const result = @subWithOverflow(@as(i64, 0), a);
    if (result[1] != 0) return POISON_OVERFLOW;
    return result[0];
}

/// Check if a value is poison (for comparisons — poison is never equal to anything).
pub fn verve_is_poison(v: i64) i64 {
    return if (isPoison(v)) @as(i64, 1) else @as(i64, 0);
}

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
fn json_extract_string(src: []const u8, start: usize, end: usize) struct { ptr: i64, len: i64 } {
    if (start >= end or src[start] != '"') return .{ .ptr = 0, .len = 0 };
    // Simple case: no escapes
    const inner_start = start + 1;
    const inner_end = end - 1;
    if (inner_end <= inner_start) return .{ .ptr = 0, .len = 0 };
    const inner = src[inner_start..inner_end];
    // Check for escapes
    if (std.mem.indexOfScalar(u8, inner, '\\') == null) {
        return .{ .ptr = @intCast(@intFromPtr(inner.ptr)), .len = @intCast(inner.len) };
    }
    // Has escapes — need to copy and unescape
    const buf = arena_alloc(inner.len) orelse return .{ .ptr = 0, .len = 0 };
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
    return .{ .ptr = @intCast(@intFromPtr(buf)), .len = @intCast(out) };
}

// ── JSON public API ────────────────────────────────

/// Get a string value from a JSON object by key.
pub fn json_get_string(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    const result = json_extract_string(src, found.start, found.end);
    return result.ptr;
}

pub fn json_get_string_len(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    const result = json_extract_string(src, found.start, found.end);
    return result.len;
}

/// Get an int value from a JSON object by key.
pub fn json_get_int(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    const num_str = src[found.start..found.end];
    return std.fmt.parseInt(i64, num_str, 10) catch 0;
}

/// Get a float value from a JSON object by key (returned as bitcast i64).
pub fn json_get_float(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return i64_from_f64(0.0);
    const num_str = src[found.start..found.end];
    const f = std.fmt.parseFloat(f64, num_str) catch return i64_from_f64(0.0);
    return i64_from_f64(f);
}

/// Get a bool value from a JSON object by key.
pub fn json_get_bool(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    if (found.end - found.start >= 4 and std.mem.eql(u8, src[found.start .. found.start + 4], "true")) return 1;
    return 0;
}

/// Get a sub-object from a JSON object by key (returns JSON string).
pub fn json_get_object(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    return @intCast(@intFromPtr(src[found.start..found.end].ptr));
}

pub fn json_get_object_len(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    return @intCast(found.end - found.start);
}

/// Parse a single JSON value string as int.
pub fn json_to_int(json_ptr: i64, json_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const trimmed = std.mem.trim(u8, src, " \t\n\r");
    return std.fmt.parseInt(i64, trimmed, 10) catch 0;
}

/// Parse a single JSON value string as float (returned as bitcast i64).
pub fn json_to_float(json_ptr: i64, json_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const trimmed = std.mem.trim(u8, src, " \t\n\r");
    const f = std.fmt.parseFloat(f64, trimmed) catch return i64_from_f64(0.0);
    return i64_from_f64(f);
}

/// Parse a single JSON value string as bool.
pub fn json_to_bool(json_ptr: i64, json_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const trimmed = std.mem.trim(u8, src, " \t\n\r");
    if (trimmed.len >= 4 and std.mem.eql(u8, trimmed[0..4], "true")) return 1;
    return 0;
}

/// Unquote a JSON string value.
pub fn json_to_string(json_ptr: i64, json_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const trimmed = std.mem.trim(u8, src, " \t\n\r");
    const result = json_extract_string(trimmed, 0, trimmed.len);
    return result.ptr;
}

pub fn json_to_string_len(json_ptr: i64, json_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const trimmed = std.mem.trim(u8, src, " \t\n\r");
    const result = json_extract_string(trimmed, 0, trimmed.len);
    return result.len;
}

/// Split a JSON array into a List of (ptr, len) pairs for each element.
/// Returns pointer to a List where even indices are ptrs and odd are lens.
pub fn json_get_array(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    return json_split_array(src, found.start, found.end);
}

pub fn json_get_array_len(json_ptr: i64, json_len: i64, key_ptr: i64, key_len: i64) i64 {
    const src = sliceFromPtr(json_ptr, json_len);
    const key = sliceFromPtr(key_ptr, key_len);
    const found = json_find_key(src, key) orelse return 0;
    return json_count_array(src, found.start, found.end);
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
    const list_mem = arena_alloc(@sizeOf(List)) orelse return 0;
    const list = @as(*List, @ptrCast(@alignCast(list_mem)));
    list.* = List.init();
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
const JsonBuilder = struct {
    buf: [*]u8,
    len: usize,
    cap: usize,

    fn init() JsonBuilder {
        const initial_cap: usize = 256;
        const mem = arena_alloc(initial_cap) orelse return .{ .buf = undefined, .len = 0, .cap = 0 };
        return .{ .buf = mem, .len = 0, .cap = initial_cap };
    }

    fn append(self: *JsonBuilder, data: []const u8) void {
        if (self.cap == 0) return;
        // Simple: if it fits, copy. Otherwise truncate (arena can't realloc easily).
        const remaining = self.cap - self.len;
        const to_copy = @min(data.len, remaining);
        @memcpy(self.buf[self.len .. self.len + to_copy], data[0..to_copy]);
        self.len += to_copy;
    }

    fn appendByte(self: *JsonBuilder, b: u8) void {
        if (self.len < self.cap) {
            self.buf[self.len] = b;
            self.len += 1;
        }
    }

    fn appendInt(self: *JsonBuilder, val: i64) void {
        var tmp: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
        self.append(s);
    }

    fn appendFloat(self: *JsonBuilder, val: f64) void {
        var tmp: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
        self.append(s);
    }

    fn appendQuotedString(self: *JsonBuilder, str: []const u8) void {
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

    fn result(self: *JsonBuilder) struct { ptr: i64, len: i64 } {
        return .{ .ptr = @intCast(@intFromPtr(self.buf)), .len = @intCast(self.len) };
    }
};

/// Start building a JSON object. Returns a builder handle (pointer to JsonBuilder in arena).
pub fn json_build_object() i64 {
    const mem = arena_alloc(@sizeOf(JsonBuilder)) orelse return 0;
    const b = @as(*JsonBuilder, @ptrCast(@alignCast(mem)));
    b.* = JsonBuilder.init();
    b.appendByte('{');
    return @intCast(@intFromPtr(b));
}

/// Add a string field to a JSON builder.
pub fn json_build_add_string(builder_ptr: i64, key_ptr: i64, key_len: i64, val_ptr: i64, val_len: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(','); // comma between fields
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.appendQuotedString(sliceFromPtr(val_ptr, val_len));
}

/// Add an int field to a JSON builder.
pub fn json_build_add_int(builder_ptr: i64, key_ptr: i64, key_len: i64, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.appendInt(val);
}

/// Add a float field to a JSON builder.
pub fn json_build_add_float(builder_ptr: i64, key_ptr: i64, key_len: i64, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.appendFloat(f64_from_i64(val));
}

/// Add a bool field to a JSON builder.
pub fn json_build_add_bool(builder_ptr: i64, key_ptr: i64, key_len: i64, val: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.append(if (val != 0) "true" else "false");
}

/// Add a null field to a JSON builder.
pub fn json_build_add_null(builder_ptr: i64, key_ptr: i64, key_len: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.append("null");
}

/// Add a raw JSON value (sub-object, sub-array) to a JSON builder.
pub fn json_build_add_raw(builder_ptr: i64, key_ptr: i64, key_len: i64, val_ptr: i64, val_len: i64) void {
    if (builder_ptr == 0) return;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    if (b.len > 1) b.appendByte(',');
    b.appendQuotedString(sliceFromPtr(key_ptr, key_len));
    b.appendByte(':');
    b.append(sliceFromPtr(val_ptr, val_len));
}

/// Finish building a JSON object. Returns the JSON string pointer.
pub fn json_build_end(builder_ptr: i64) i64 {
    if (builder_ptr == 0) return 0;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    b.appendByte('}');
    return b.result().ptr;
}

/// Get the length of a finished JSON builder result.
pub fn json_build_end_len(builder_ptr: i64) i64 {
    if (builder_ptr == 0) return 0;
    const b = @as(*JsonBuilder, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(builder_ptr))))));
    return b.result().len;
}

/// Read up to `max_bytes` from a stream. Returns (ptr, len) stored in a 2-slot arena array.
/// The returned pointer points to the data, and the companion _len function returns the length.
var last_read_bytes_len: i64 = 0;

pub fn stream_read_bytes(stream_ptr: i64, max: i64) i64 {
    const s = toStream(stream_ptr) orelse {
        last_read_bytes_len = 0;
        return 0;
    };
    if (s.closed) {
        last_read_bytes_len = 0;
        return 0;
    }
    const max_usize: usize = @intCast(@as(u64, @bitCast(max)));
    const buf = arena_alloc(max_usize + 1) orelse {
        last_read_bytes_len = 0;
        return 0;
    };
    var total: usize = 0;
    switch (s.kind) {
        .tcp_client => {
            // Drain read buffer first
            while (s.read_pos < s.read_len and total < max_usize) {
                buf[total] = s.read_buf[s.read_pos];
                s.read_pos += 1;
                total += 1;
            }
            // Read from socket
            if (total < max_usize) {
                const n = std.posix.read(s.fd, buf[total..max_usize]) catch 0;
                total += n;
            }
        },
        else => {},
    }
    buf[total] = 0; // null terminate
    last_read_bytes_len = @intCast(total);
    return @intCast(@intFromPtr(buf));
}

pub fn stream_read_bytes_len() i64 {
    return last_read_bytes_len;
}

// ── HTTP/1.1 ───────────────────────────────────────

/// HTTP request — lazy parsed. Only request line is parsed eagerly.
/// Headers and body are located on first access.
pub const HttpRequest = struct {
    method_start: usize,
    method_len: usize,
    path_start: usize,
    path_len: usize,
    // Lazy: computed on first header/body access
    headers_start: usize,
    headers_end: usize,
    body_start: usize,
    body_len: usize,
    headers_parsed: bool,
    src: []const u8,

    fn ensureHeadersParsed(self: *HttpRequest) void {
        if (self.headers_parsed) return;
        self.headers_parsed = true;
        // Find end of request line
        var pos = self.method_start;
        while (pos < self.src.len and self.src[pos] != '\n') pos += 1;
        if (pos < self.src.len) pos += 1;
        self.headers_start = pos;
        // Find blank line (end of headers)
        self.headers_end = pos;
        while (pos + 1 < self.src.len) {
            if (self.src[pos] == '\r' and pos + 1 < self.src.len and self.src[pos + 1] == '\n') {
                self.headers_end = pos;
                pos += 2;
                break;
            }
            if (self.src[pos] == '\n' and (pos + 1 >= self.src.len or self.src[pos + 1] == '\n' or self.src[pos + 1] == '\r')) {
                self.headers_end = pos;
                pos += 1;
                if (pos < self.src.len and self.src[pos] == '\n') pos += 1;
                break;
            }
            while (pos < self.src.len and self.src[pos] != '\n') pos += 1;
            if (pos < self.src.len) pos += 1;
        }
        // Enforce header size limit
        if (self.headers_end - self.headers_start > HTTP_MAX_HEADER_SIZE) {
            self.headers_end = self.headers_start + HTTP_MAX_HEADER_SIZE;
        }
        self.body_start = pos;
        const remaining = if (pos < self.src.len) self.src.len - pos else 0;
        self.body_len = @min(remaining, HTTP_MAX_BODY_SIZE);
    }
};

pub fn http_parse_request(data_ptr: i64, data_len: i64) i64 {
    const src = sliceFromPtr(data_ptr, data_len);
    if (src.len < 10) return 0;

    // Parse request line only (lazy: headers + body parsed on access)
    var pos: usize = 0;

    // Method — enforce limit
    const method_start = pos;
    while (pos < src.len and src[pos] != ' ' and pos - method_start < HTTP_MAX_METHOD_SIZE) pos += 1;
    const method_len = pos - method_start;
    if (pos >= src.len or method_len == 0) return 0;
    pos += 1;

    // Path — enforce limit
    const path_start = pos;
    while (pos < src.len and src[pos] != ' ' and pos - path_start < HTTP_MAX_URI_SIZE) pos += 1;
    const path_len = pos - path_start;
    if (pos >= src.len or path_len == 0) return 0;

    const req_mem = arena_alloc(@sizeOf(HttpRequest)) orelse return 0;
    const req = @as(*HttpRequest, @ptrCast(@alignCast(req_mem)));
    req.* = .{
        .method_start = method_start,
        .method_len = method_len,
        .path_start = path_start,
        .path_len = path_len,
        .headers_start = 0,
        .headers_end = 0,
        .body_start = 0,
        .body_len = 0,
        .headers_parsed = false,
        .src = src,
    };
    return @intCast(@intFromPtr(req));
}

fn toHttpReq(ptr: i64) ?*HttpRequest {
    if (ptr == 0) return null;
    return @as(*HttpRequest, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
}

pub fn http_req_method(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    return @intCast(@intFromPtr(req.src[req.method_start .. req.method_start + req.method_len].ptr));
}

pub fn http_req_method_len(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    return @intCast(req.method_len);
}

pub fn http_req_path(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    return @intCast(@intFromPtr(req.src[req.path_start .. req.path_start + req.path_len].ptr));
}

pub fn http_req_path_len(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    return @intCast(req.path_len);
}

pub fn http_req_body(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    req.ensureHeadersParsed();
    if (req.body_len == 0) return 0;
    return @intCast(@intFromPtr(req.src[req.body_start .. req.body_start + req.body_len].ptr));
}

pub fn http_req_body_len(req_ptr: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    req.ensureHeadersParsed();
    return @intCast(req.body_len);
}

/// Find a header value by name (case-insensitive). Returns pointer to value string.
pub fn http_req_header(req_ptr: i64, name_ptr: i64, name_len: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    req.ensureHeadersParsed();
    const name = sliceFromPtr(name_ptr, name_len);
    const headers = req.src[req.headers_start..req.headers_end];

    var pos: usize = 0;
    while (pos < headers.len) {
        // Find colon
        const line_start = pos;
        var colon: usize = pos;
        while (colon < headers.len and headers[colon] != ':') colon += 1;
        if (colon >= headers.len) break;

        const header_name = headers[line_start..colon];
        // Case-insensitive compare
        if (header_name.len == name.len) {
            var match = true;
            for (header_name, 0..) |c, i| {
                const a = if (c >= 'A' and c <= 'Z') c + 32 else c;
                const b = if (name[i] >= 'A' and name[i] <= 'Z') name[i] + 32 else name[i];
                if (a != b) {
                    match = false;
                    break;
                }
            }
            if (match) {
                // Skip colon and optional space
                var val_start = colon + 1;
                while (val_start < headers.len and headers[val_start] == ' ') val_start += 1;
                // Find end of line
                var val_end = val_start;
                while (val_end < headers.len and headers[val_end] != '\r' and headers[val_end] != '\n') val_end += 1;
                return @intCast(@intFromPtr(headers[val_start..val_end].ptr));
            }
        }

        // Skip to next line
        while (pos < headers.len and headers[pos] != '\n') pos += 1;
        if (pos < headers.len) pos += 1;
    }
    return 0;
}

pub fn http_req_header_len(req_ptr: i64, name_ptr: i64, name_len: i64) i64 {
    const req = toHttpReq(req_ptr) orelse return 0;
    req.ensureHeadersParsed();
    const name = sliceFromPtr(name_ptr, name_len);
    const headers = req.src[req.headers_start..req.headers_end];

    var pos: usize = 0;
    while (pos < headers.len) {
        const line_start = pos;
        var colon: usize = pos;
        while (colon < headers.len and headers[colon] != ':') colon += 1;
        if (colon >= headers.len) break;

        const header_name = headers[line_start..colon];
        if (header_name.len == name.len) {
            var match = true;
            for (header_name, 0..) |c, i| {
                const a = if (c >= 'A' and c <= 'Z') c + 32 else c;
                const b = if (name[i] >= 'A' and name[i] <= 'Z') name[i] + 32 else name[i];
                if (a != b) {
                    match = false;
                    break;
                }
            }
            if (match) {
                var val_start = colon + 1;
                while (val_start < headers.len and headers[val_start] == ' ') val_start += 1;
                var val_end = val_start;
                while (val_end < headers.len and headers[val_end] != '\r' and headers[val_end] != '\n') val_end += 1;
                return @intCast(val_end - val_start);
            }
        }
        while (pos < headers.len and headers[pos] != '\n') pos += 1;
        if (pos < headers.len) pos += 1;
    }
    return 0;
}

/// Build an HTTP response. Returns the full response as a string.
pub fn http_build_response(status: i64, content_type_ptr: i64, content_type_len: i64, body_ptr: i64, body_len: i64) i64 {
    const ct = sliceFromPtr(content_type_ptr, content_type_len);
    const body = sliceFromPtr(body_ptr, body_len);

    var b = JsonBuilder.init(); // reuse the builder for any string building
    // Status line
    b.append("HTTP/1.1 ");
    var status_buf: [4]u8 = undefined;
    const status_str = std.fmt.bufPrint(&status_buf, "{d}", .{status}) catch "500";
    b.append(status_str);
    b.appendByte(' ');
    const reason: []const u8 = switch (status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "OK",
    };
    b.append(reason);
    b.append("\r\n");

    // Headers
    b.append("Content-Type: ");
    b.append(ct);
    b.append("\r\n");

    b.append("Content-Length: ");
    var len_buf: [20]u8 = undefined;
    const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch "0";
    b.append(len_str);
    b.append("\r\n");

    b.append("Connection: close\r\n");

    // Date header (RFC 7231 MUST) — Unix timestamp for simplicity
    var date_buf: [48]u8 = undefined;
    const ts = std.time.timestamp();
    const date_str = std.fmt.bufPrint(&date_buf, "Date: {d}\r\n", .{ts}) catch "";
    b.append(date_str);
    b.append("\r\n");

    // Body
    b.append(body);

    const res = b.result();
    last_response_len = res.len;
    return res.ptr;
}

/// Last response length — set by http_build_response.
var last_response_len: i64 = 0;

pub fn http_build_response_len(status: i64, content_type_ptr: i64, content_type_len: i64, body_ptr: i64, body_len: i64) i64 {
    // Build the response to get the exact length
    _ = http_build_response(status, content_type_ptr, content_type_len, body_ptr, body_len);
    return last_response_len;
}

// ── Arena allocator ────────────────────────────────

const ARENA_PAGE_SIZE = 64 * 1024; // 64KB per page
const ARENA_MAX_PAGES = 256; // 16MB max per arena

pub const Arena = struct {
    pages: [ARENA_MAX_PAGES]?[*]align(8) u8 = .{null} ** ARENA_MAX_PAGES,
    page_count: usize = 0,
    offset: usize = 0,
    total_allocated: usize = 0,

    /// Allocate `size` bytes from this arena. Returns null on failure.
    pub fn alloc(self: *Arena, size: usize) ?[*]u8 {
        // Align to 8 bytes
        const aligned = (size + 7) & ~@as(usize, 7);

        // Try current page
        if (self.page_count > 0 and self.offset + aligned <= ARENA_PAGE_SIZE) {
            const page = self.pages[self.page_count - 1] orelse return null;
            const ptr = page + self.offset;
            self.offset += aligned;
            self.total_allocated += aligned;
            return ptr;
        }

        // Need a new page
        if (self.page_count >= ARENA_MAX_PAGES) return null;
        const new_page = std.heap.page_allocator.alignedAlloc(u8, .@"8", ARENA_PAGE_SIZE) catch return null;
        self.pages[self.page_count] = new_page.ptr;
        self.page_count += 1;
        self.offset = aligned;
        self.total_allocated += aligned;
        return new_page.ptr;
    }

    /// Free all pages. After this, the arena is empty and reusable.
    pub fn freeAll(self: *Arena) void {
        for (0..self.page_count) |i| {
            if (self.pages[i]) |page| {
                std.heap.page_allocator.free(@as([*]u8, @ptrCast(page))[0..ARENA_PAGE_SIZE]);
                self.pages[i] = null;
            }
        }
        self.page_count = 0;
        self.offset = 0;
        self.total_allocated = 0;
    }
};

/// Global arena for non-process code (module main).
var global_arena: Arena = .{};

/// Get the current arena: process-local if in a process, global otherwise.
pub fn currentArena() *Arena {
    if (current_process_id > 0) {
        const idx = pidx(current_process_id);
        return &process_table[idx].arena;
    }
    return &global_arena;
}

/// Allocate from the current arena. Drop-in replacement for page_allocator.alloc.
pub fn arena_alloc(size: usize) ?[*]u8 {
    return currentArena().alloc(size);
}

// ── Process runtime ────────────────────────────────

pub const Message = struct {
    handler_id: i64,
    args: [MAX_MSG_ARGS]i64,
    arg_count: i64,
    reply_slot: ?*i64,
};

pub const Mailbox = struct {
    buf: [MAILBOX_CAPACITY]Message = undefined,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,

    pub fn push(self: *Mailbox, msg: Message) bool {
        if (self.count >= MAILBOX_CAPACITY) return false;
        self.buf[self.tail] = msg;
        self.tail = (self.tail + 1) % MAILBOX_CAPACITY;
        self.count += 1;
        return true;
    }

    pub fn pop(self: *Mailbox) ?Message {
        if (self.count == 0) return null;
        const msg = self.buf[self.head];
        self.head = (self.head + 1) % MAILBOX_CAPACITY;
        self.count -= 1;
        return msg;
    }
};

pub const VerveProcess = struct {
    id: i64,
    alive: bool,
    process_type: i64,
    state: [MAX_STATE_FIELDS]i64,
    mailbox: Mailbox,
    watcher_pids: [MAX_WATCHERS]i64,
    watcher_count: usize,
    arena: Arena,
};

pub const DispatchFn = *const fn (i64, [*]const i64, i64) i64;

pub var process_table: [MAX_PROCESSES]VerveProcess = blk: {
    var t: [MAX_PROCESSES]VerveProcess = undefined;
    for (&t) |*p| {
        p.* = .{
            .id = 0,
            .alive = false,
            .process_type = 0,
            .state = @splat(0),
            .mailbox = .{},
            .watcher_pids = @splat(0),
            .watcher_count = 0,
            .arena = .{},
        };
    }
    break :blk t;
};
pub var process_count: i64 = 0;
pub var current_process_id: i64 = 0;
pub var dispatch_table: [MAX_PROCESSES]DispatchFn = @splat(&dispatch_noop);

fn dispatch_noop(_: i64, _: [*]const i64, _: i64) i64 {
    return makeTagged(1, 0);
}

fn pidx(pid: i64) usize {
    return @intCast(@as(u64, @bitCast(pid - 1)));
}

// ── Process operations ─────────────────────────────

pub fn verve_spawn(process_type: i64) i64 {
    // Find a slot: prefer recycling dead processes, then use new slot
    var idx: usize = MAX_PROCESSES; // sentinel: not found
    // Scan for dead process to recycle
    for (&process_table, 0..) |*p, i| {
        if (!p.alive and p.id != 0) {
            p.arena.freeAll(); // free old arena before reuse
            idx = i;
            break;
        }
    }
    // No dead slot — try new slot
    if (idx == MAX_PROCESSES) {
        const next: usize = @intCast(@as(u64, @bitCast(process_count)));
        if (next >= MAX_PROCESSES) return 0;
        idx = next;
        process_count += 1;
    }
    process_table[idx] = .{
        .id = @intCast(idx + 1),
        .alive = true,
        .process_type = process_type,
        .state = @splat(0),
        .mailbox = .{},
        .watcher_pids = @splat(0),
        .watcher_count = 0,
        .arena = .{},
    };
    return process_count;
}

pub fn verve_state_get(field_index: i64) i64 {
    const idx = pidx(current_process_id);
    return process_table[idx].state[@intCast(@as(u64, @bitCast(field_index)))];
}

pub fn verve_state_set(field_index: i64, value: i64) void {
    const idx = pidx(current_process_id);
    process_table[idx].state[@intCast(@as(u64, @bitCast(field_index)))] = value;
}

pub fn verve_watch(target_pid: i64) void {
    const idx = pidx(target_pid);
    const wc = process_table[idx].watcher_count;
    process_table[idx].watcher_pids[wc] = current_process_id;
    process_table[idx].watcher_count = wc + 1;
}

pub fn verve_kill(target_pid: i64) void {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    proc.alive = false;
    // Notify watchers before freeing arena
    for (0..proc.watcher_count) |i| {
        const watcher_pid = proc.watcher_pids[i];
        const widx = pidx(watcher_pid);
        const watcher = &process_table[widx];
        if (!watcher.alive) continue;
        var msg: Message = .{ .handler_id = -1, .args = @splat(0), .arg_count = 2, .reply_slot = null };
        msg.args[0] = target_pid;
        msg.args[1] = 0;
        _ = watcher.mailbox.push(msg);
    }
    // Free all memory owned by this process
    proc.arena.freeAll();
}

// ── Message passing ────────────────────────────────

pub fn verve_drain(target_pid: i64) void {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    while (proc.mailbox.pop()) |msg| {
        if (!proc.alive) break;
        if (msg.handler_id == -1) continue;
        const saved = current_process_id;
        current_process_id = target_pid;
        const pt: usize = @intCast(@as(u64, @bitCast(proc.process_type)));
        const result = dispatch_table[pt](msg.handler_id, &msg.args, msg.arg_count);
        current_process_id = saved;
        if (msg.reply_slot) |slot| {
            slot.* = result;
        }
    }
}

fn build_msg(handler_id: i64, args: [*]const i64, arg_count: i64) Message {
    var msg: Message = .{ .handler_id = handler_id, .args = @splat(0), .arg_count = arg_count, .reply_slot = null };
    const ac: usize = @intCast(@as(u64, @bitCast(arg_count)));
    for (0..ac) |i| {
        msg.args[i] = args[i];
    }
    return msg;
}

pub fn verve_send(target_pid: i64, handler_id: i64, args: [*]const i64, arg_count: i64) i64 {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return makeTagged(1, 0);
    var msg = build_msg(handler_id, args, arg_count);
    var result: i64 = 0;
    msg.reply_slot = &result;
    if (!proc.mailbox.push(msg)) return makeTagged(1, 0);
    verve_drain(target_pid);
    if (result > 0x10000 and getTag(result) == 1) return result;
    return makeTagged(0, result);
}

pub fn verve_tell(target_pid: i64, handler_id: i64, args: [*]const i64, arg_count: i64) void {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return;
    const msg = build_msg(handler_id, args, arg_count);
    if (!proc.mailbox.push(msg)) return;
    verve_drain(target_pid);
}

pub fn verve_send_timeout(target_pid: i64, handler_id: i64, args: [*]const i64, arg_count: i64, timeout_ms: i64) i64 {
    const idx = pidx(target_pid);
    const proc = &process_table[idx];
    if (!proc.alive) return makeTagged(1, 0);
    var msg = build_msg(handler_id, args, arg_count);
    var result: i64 = 0;
    msg.reply_slot = &result;
    if (!proc.mailbox.push(msg)) return makeTagged(1, 0);
    _ = timeout_ms; // enforced in future multi-threaded runtime
    verve_drain(target_pid);
    if (result > 0x10000 and getTag(result) == 1) return result;
    return makeTagged(0, result);
}
