const std = @import("std");

// ── Constants ──────────────────────────────────────
pub const MAILBOX_CAPACITY = 64;
pub const MAX_PROCESSES = 256;
pub const MAX_STATE_FIELDS = 16;
pub const MAX_WATCHERS = 64;
pub const MAX_MSG_ARGS = 8;

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
    const stream = std.heap.page_allocator.alloc(i64, 3) catch return makeTagged(1, 0);
    stream[0] = @intCast(@intFromPtr(data.ptr));
    stream[1] = @intCast(data.len);
    stream[2] = 0;
    return makeTagged(0, @intCast(@intFromPtr(stream.ptr)));
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
            const buf = std.heap.page_allocator.alloc(u8, line_len + 1) catch return 0;
            @memcpy(buf[0..line_len], data[s.file_pos..end]);
            buf[line_len] = 0;
            s.file_pos = if (end < s.file_len) end + 1 else end;
            return @intCast(@intFromPtr(buf.ptr));
        },
        .tcp_client => {
            var line_buf = std.heap.page_allocator.alloc(u8, 4096) catch return 0;
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

    const s = std.heap.page_allocator.create(VerveStream) catch return makeTagged(1, 0);
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

    const s = std.heap.page_allocator.create(VerveStream) catch return makeTagged(1, 0);
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

    const s = std.heap.page_allocator.create(VerveStream) catch {
        std.posix.close(client_fd);
        return makeTagged(1, 0);
    };
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
    const result = std.heap.page_allocator.alloc(u8, s.len + 1) catch return 0;
    @memcpy(result[0..s.len], s);
    result[s.len] = 0;
    return @intCast(@intFromPtr(result.ptr));
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
    const result = std.heap.page_allocator.alloc(u8, s.len + 1) catch return 0;
    @memcpy(result[0..s.len], s);
    result[s.len] = 0;
    return @intCast(@intFromPtr(result.ptr));
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
        const mem = std.heap.page_allocator.alloc(i64, 256) catch return .{ .items = undefined, .len = 0, .cap = 0 };
        return .{ .items = @constCast(mem.ptr), .len = 0, .cap = 256 };
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
    const t = std.heap.page_allocator.create(Tagged) catch return 0;
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
    process_count += 1;
    const idx = pidx(process_count);
    process_table[idx] = .{
        .id = process_count,
        .alive = true,
        .process_type = process_type,
        .state = @splat(0),
        .mailbox = .{},
        .watcher_pids = @splat(0),
        .watcher_count = 0,
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
