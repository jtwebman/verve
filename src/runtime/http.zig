const std = @import("std");
const rt = @import("runtime.zig");
const json = @import("json.zig");
const io = @import("io.zig");

// HTTP limits — configurable via Http.set_max_header_size, Http.set_max_body_size, Http.set_timeout
var max_header_size: usize = 8 * 1024; // 8KB per header section
var max_body_size: usize = 1024 * 1024; // 1MB request body
pub const HTTP_MAX_URI_SIZE = 8 * 1024; // 8KB URI length
pub const HTTP_MAX_METHOD_SIZE = 16; // longest standard method
var keepalive_timeout_ms: i32 = 5000; // default 5 seconds

pub fn http_set_timeout(ms: i64) i64 {
    const clamped = if (ms < 0) 0 else if (ms > std.math.maxInt(i32)) std.math.maxInt(i32) else ms;
    keepalive_timeout_ms = @intCast(clamped);
    return 0;
}

pub fn http_set_max_header_size(size: i64) i64 {
    max_header_size = if (size < 1024) 1024 else @intCast(@as(u64, @bitCast(size)));
    return 0;
}

pub fn http_set_max_body_size(size: i64) i64 {
    max_body_size = if (size < 0) 0 else @intCast(@as(u64, @bitCast(size)));
    return 0;
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
        if (self.headers_end - self.headers_start > max_header_size) {
            self.headers_end = self.headers_start + max_header_size;
        }
        self.body_start = pos;
        const remaining = if (pos < self.src.len) self.src.len - pos else 0;
        self.body_len = @min(remaining, max_body_size);
    }
};

pub fn http_parse_request(data: []const u8) usize {
    const t = rt.profile.begin();
    defer rt.profile.end(.parse_http, t);

    const src = data;
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

    const req_mem = rt.arena_alloc(@sizeOf(HttpRequest)) orelse return 0;
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
    return @intFromPtr(req);
}

pub fn toHttpReq(ptr: usize) ?*HttpRequest {
    if (ptr == 0) return null;
    return @as(*HttpRequest, @ptrFromInt(ptr));
}

pub fn http_req_method(req_ptr: usize) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    return req.src[req.method_start .. req.method_start + req.method_len];
}

pub fn http_req_path(req_ptr: usize) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    return req.src[req.path_start .. req.path_start + req.path_len];
}

pub fn http_req_body(req_ptr: usize) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    req.ensureHeadersParsed();
    if (req.body_len == 0) return "";
    return req.src[req.body_start .. req.body_start + req.body_len];
}

/// Find a header value by name (case-insensitive). Returns []const u8.
pub fn http_req_header(req_ptr: usize, name: []const u8) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    req.ensureHeadersParsed();
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
                return headers[val_start..val_end];
            }
        }
        while (pos < headers.len and headers[pos] != '\n') pos += 1;
        if (pos < headers.len) pos += 1;
    }
    return "";
}

// ── HTTP keep-alive request framing ───────────────

/// Read one complete HTTP request from a stream. Handles keep-alive by reading
/// exactly one request: headers up to \r\n\r\n, then body per Content-Length.
/// Returns the raw request bytes, or "" on connection close / error.
/// Non-blocking on subsequent calls: if no data is buffered or ready, returns ""
/// immediately so the handler can yield back to the scheduler.
pub fn http_read_request(stream_ptr: usize) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.read, t);

    const s = io.toStream(stream_ptr) orelse return "";
    if (s.closed) return "";

    // Fast path: check if stream buffer already has data (pipelined request)
    const has_buffered = s.read_pos < s.read_len;

    // If no buffered data, check if data is available without blocking
    if (!has_buffered) {
        // Fast path: non-blocking poll — avoids context switch if data already on socket
        var pfd = [1]std.posix.pollfd{.{
            .fd = s.fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const poll_n = std.posix.poll(&pfd, 0) catch return "";
        if (poll_n == 0) {
            // No data ready — yield to scheduler
            if (rt.process.current_process_id > 0) {
                rt.process.verve_io_yield(@intCast(s.fd));
            } else {
                return "";
            }
        }
        // Data is available (or we were woken from yield) — fall through to read
    }

    // Data is available — allocate a small initial buffer for headers
    const initial_size: usize = 8192; // 8KB for headers — grow if body needed
    var buf_ptr: [*]u8 = rt.arena_alloc(initial_size) orelse return "";
    var buf_cap: usize = initial_size;
    var total: usize = 0;

    // Drain buffered data first
    while (s.read_pos < s.read_len and total < buf_cap) {
        buf_ptr[total] = s.read_buf[s.read_pos];
        s.read_pos += 1;
        total += 1;
    }

    // Read until we find end of headers (\r\n\r\n)
    var header_end: ?usize = findHeaderEnd(buf_ptr[0..total]);
    while (header_end == null and total < max_header_size) {
        const n = std.posix.read(s.fd, buf_ptr[total..@min(total + 4096, buf_cap)]) catch return "";
        if (n == 0) {
            if (total > 0) return buf_ptr[0..total];
            return "";
        }
        total += n;
        header_end = findHeaderEnd(buf_ptr[0..total]);
    }

    const hdr_end = header_end orelse return buf_ptr[0..total];

    // Read body per Content-Length — grow buffer if needed
    const content_len = parseContentLength(buf_ptr[0..hdr_end]);
    const needed = hdr_end + content_len;
    const max_request = max_header_size + max_body_size;
    if (needed > max_request) return buf_ptr[0..total];

    // Grow buffer if body requires more space
    if (needed > buf_cap) {
        const new_buf = rt.arena_alloc(needed) orelse return buf_ptr[0..total];
        @memcpy(new_buf[0..total], buf_ptr[0..total]);
        buf_ptr = new_buf;
        buf_cap = needed;
    }

    while (total < needed) {
        const n = std.posix.read(s.fd, buf_ptr[total..@min(needed, buf_cap)]) catch break;
        if (n == 0) break;
        total += n;
    }

    // Stash leftover bytes back into stream buffer for next request
    if (total > needed) {
        const leftover = total - needed;
        const copy_len = @min(leftover, s.read_buf.len);
        @memcpy(s.read_buf[0..copy_len], buf_ptr[needed .. needed + copy_len]);
        s.read_pos = 0;
        s.read_len = copy_len;
        return buf_ptr[0..needed];
    }

    return buf_ptr[0..total];
}

fn findHeaderEnd(data: []const u8) ?usize {
    if (data.len < 4) return null;
    for (0..data.len - 3) |i| {
        if (data[i] == '\r' and data[i + 1] == '\n' and data[i + 2] == '\r' and data[i + 3] == '\n') {
            return i + 4;
        }
    }
    return null;
}

fn parseContentLength(headers: []const u8) usize {
    // Case-insensitive search for Content-Length header
    const needle = "content-length:";
    var i: usize = 0;
    while (i + needle.len < headers.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = headers[i + j];
            const lower = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            if (lower != nc) {
                match = false;
                break;
            }
        }
        if (match) {
            var start = i + needle.len;
            while (start < headers.len and headers[start] == ' ') start += 1;
            var end = start;
            while (end < headers.len and headers[end] >= '0' and headers[end] <= '9') end += 1;
            return std.fmt.parseInt(usize, headers[start..end], 10) catch 0;
        }
    }
    return 0;
}

/// Build an HTTP response. Returns the full response as []const u8.
pub fn http_build_response(status: i64, ct: []const u8, body: []const u8) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.build_response, t);

    var b = json.JsonBuilder.init();
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
    b.append("Content-Type: ");
    b.append(ct);
    b.append("\r\n");
    b.append("Content-Length: ");
    var len_buf: [20]u8 = undefined;
    const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch "0";
    b.append(len_str);
    b.append("\r\n");

    // HTTP/1.1 defaults to keep-alive
    b.append("Connection: keep-alive\r\n");

    // Date header (RFC 7231 MUST) — Unix timestamp for simplicity
    var date_buf: [48]u8 = undefined;
    const ts = std.time.timestamp();
    const date_str = std.fmt.bufPrint(&date_buf, "Date: {d}\r\n", .{ts}) catch "";
    b.append(date_str);
    b.append("\r\n");

    // Body
    b.append(body);

    const res = b.result();
    return rt.sliceFromPair(res.ptr, res.len);
}

/// Build an HTTP response with chunked transfer encoding.
pub fn http_build_response_chunked(status: i64, ct: []const u8, body: []const u8) []const u8 {
    var b = json.JsonBuilder.init();
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
    b.append("Content-Type: ");
    b.append(ct);
    b.append("\r\nTransfer-Encoding: chunked\r\n");
    b.append("Connection: keep-alive\r\n");
    var date_buf: [48]u8 = undefined;
    const ts = std.time.timestamp();
    const date_str = std.fmt.bufPrint(&date_buf, "Date: {d}\r\n", .{ts}) catch "";
    b.append(date_str);
    b.append("\r\n");
    // Single chunk: hex-size \r\n data \r\n, then terminator 0\r\n\r\n
    var hex_buf: [20]u8 = undefined;
    const hex_str = std.fmt.bufPrint(&hex_buf, "{x}", .{body.len}) catch "0";
    b.append(hex_str);
    b.append("\r\n");
    b.append(body);
    b.append("\r\n0\r\n\r\n");
    const res = b.result();
    return rt.sliceFromPair(res.ptr, res.len);
}

// ── HTTP Server (multi-threaded epoll connection manager) ──────

const process = @import("process.zig");

const SERVE_MAX_CONNS = 256;
const SERVE_SENTINEL: u64 = SERVE_MAX_CONNS; // epoll data sentinel for listener

/// Per-connection state managed by the epoll thread.
const ServeConn = struct {
    stream: io.VerveStream,
    active: bool,
};

/// Per-thread state for an epoll worker.
const ServeThread = struct {
    listener_fd: std.posix.fd_t,
    epoll_fd: i32,
    dispatch_fn: process.DispatchFn,
    handler_index: u8,
    handler_pids: []usize,
    pool_size: usize,
    next_handler: usize,
    conns: []ServeConn, // heap-allocated
    conn_count: usize,

    fn run(self: *ServeThread) void {
        var events: [256]std.os.linux.epoll_event = undefined;

        while (true) {
            const n = std.posix.epoll_wait(self.epoll_fd, &events, -1);
            if (n == 0) continue;

            for (events[0..n]) |ev| {
                if (ev.data.u64 == SERVE_SENTINEL) {
                    self.acceptAll();
                } else {
                    self.handleConn(@intCast(ev.data.u64));
                }
            }
        }
    }

    fn acceptAll(self: *ServeThread) void {
        while (true) {
            const cfd = std.posix.accept(self.listener_fd, null, null, std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK) catch break;

            // Find free slot
            var slot: ?usize = null;
            for (0..self.conn_count) |i| {
                if (!self.conns[i].active) {
                    slot = i;
                    break;
                }
            }
            if (slot == null and self.conn_count < SERVE_MAX_CONNS) {
                slot = self.conn_count;
                self.conn_count += 1;
            }

            if (slot) |si| {
                self.conns[si] = .{
                    .stream = .{
                        .kind = .tcp_client,
                        .fd = cfd,
                        .read_buf = undefined,
                        .read_pos = 0,
                        .read_len = 0,
                        .file_data = null,
                        .file_len = 0,
                        .file_pos = 0,
                        .closed = false,
                    },
                    .active = true,
                };

                var cev = std.os.linux.epoll_event{
                    .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ONESHOT,
                    .data = .{ .u64 = @intCast(si) },
                };
                std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, cfd, &cev) catch {
                    std.posix.close(cfd);
                    self.conns[si].active = false;
                };
            } else {
                std.posix.close(cfd);
            }
        }
    }

    fn handleConn(self: *ServeThread, idx: usize) void {
        const conn = &self.conns[idx];
        if (!conn.active) return;
        const s = &conn.stream;

        // Read one HTTP request (blocking read since epoll told us data is ready)
        const req_data = http_read_request_from_stream(s);
        if (req_data.len == 0) {
            // Connection closed
            std.posix.close(s.fd);
            conn.active = false;
            return;
        }

        const req_ptr = http_parse_request(req_data);

        // Build message: handler_index, 2 params (req_ptr, stream_ptr)
        var msg_buf: [20]u8 = undefined;
        msg_buf[0] = self.handler_index;
        msg_buf[1] = 2;
        msg_buf[2] = 0; // type int
        @memcpy(msg_buf[3..11], &@as([8]u8, @bitCast(@as(i64, @intCast(req_ptr)))));
        msg_buf[11] = 0; // type int
        @memcpy(msg_buf[12..20], &@as([8]u8, @bitCast(@as(i64, @intCast(s.streamPtr())))));

        // Dispatch to handler process (synchronous — handler writes response)
        const pid = self.handler_pids[self.next_handler % self.pool_size];
        self.next_handler +%= 1;
        _ = process.verve_send(pid, &msg_buf, 20);

        // Re-arm for keep-alive
        var cev = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ONESHOT,
            .data = .{ .u64 = @intCast(idx) },
        };
        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_MOD, s.fd, &cev) catch {
            std.posix.close(s.fd);
            conn.active = false;
        };
    }
};

/// Read one HTTP request from a stream that already has data ready (epoll signaled).
/// No poll/yield — data should be available. Returns "" on close/error.
fn http_read_request_from_stream(s: *io.VerveStream) []const u8 {
    if (s.closed) return "";

    const initial_size: usize = 8192;
    var buf_ptr: [*]u8 = rt.arena_alloc(initial_size) orelse return "";
    var buf_cap: usize = initial_size;
    var total: usize = 0;

    // Drain buffered data
    while (s.read_pos < s.read_len and total < buf_cap) {
        buf_ptr[total] = s.read_buf[s.read_pos];
        s.read_pos += 1;
        total += 1;
    }

    // Read until headers complete
    var header_end: ?usize = findHeaderEnd(buf_ptr[0..total]);
    while (header_end == null and total < max_header_size) {
        const n = std.posix.read(s.fd, buf_ptr[total..@min(total + 4096, buf_cap)]) catch return "";
        if (n == 0) return if (total > 0) buf_ptr[0..total] else "";
        total += n;
        header_end = findHeaderEnd(buf_ptr[0..total]);
    }

    const hdr_end = header_end orelse return buf_ptr[0..total];
    const content_len = parseContentLength(buf_ptr[0..hdr_end]);
    const needed = hdr_end + content_len;

    if (needed > buf_cap) {
        const new_buf = rt.arena_alloc(needed) orelse return buf_ptr[0..total];
        @memcpy(new_buf[0..total], buf_ptr[0..total]);
        buf_ptr = new_buf;
        buf_cap = needed;
    }

    while (total < needed) {
        const n = std.posix.read(s.fd, buf_ptr[total..@min(needed, buf_cap)]) catch break;
        if (n == 0) break;
        total += n;
    }

    if (total > needed) {
        const leftover = total - needed;
        const copy_len = @min(leftover, s.read_buf.len);
        @memcpy(s.read_buf[0..copy_len], buf_ptr[needed .. needed + copy_len]);
        s.read_pos = 0;
        s.read_len = copy_len;
        return buf_ptr[0..needed];
    }

    return buf_ptr[0..total];
}

fn serveThreadEntry(thread: *ServeThread) void {
    thread.run();
}

/// Run multi-threaded HTTP server with epoll connection management.
/// N threads each run their own epoll loop with SO_REUSEPORT.
/// Handler processes receive (req_ptr, stream_ptr) and write responses directly.
///
/// Args: listener_ptr, handler_process_type, handler_index
pub fn http_serve(listener_ptr: usize, handler_type_i: i64, handler_index_i: i64) i64 {
    const listener = io.toStream(listener_ptr) orelse return -1;
    if (listener.closed) return -1;

    const handler_type: usize = @intCast(@as(u64, @bitCast(handler_type_i)));
    const handler_index: u8 = @intCast(@as(u64, @bitCast(handler_index_i)));

    // Start with single thread to verify correctness, then scale up
    const num_threads: usize = 1;
    const dispatch_fn = if (handler_type < process.dispatch_table.len)
        process.dispatch_table[handler_type]
    else
        return -1;

    // Spawn handler process pool (2 per thread)
    const handlers_per_thread = 2;
    const total_handlers = num_threads * handlers_per_thread;
    var handler_pids_buf: [128]usize = undefined;
    for (0..total_handlers) |i| {
        handler_pids_buf[i] = process.verve_spawn(handler_type);
    }

    // Create per-thread state
    const alloc = std.heap.page_allocator;
    var threads: [64]ServeThread = undefined;
    var os_threads: [64]?std.Thread = .{null} ** 64;

    for (0..num_threads) |i| {
        // Each thread gets its own epoll
        const epoll_fd = std.posix.epoll_create1(std.os.linux.EPOLL.CLOEXEC) catch return -1;

        // Register listener with this thread's epoll
        var listen_ev = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN,
            .data = .{ .u64 = SERVE_SENTINEL },
        };
        std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, listener.fd, &listen_ev) catch return -1;

        const start = i * handlers_per_thread;
        threads[i] = .{
            .listener_fd = listener.fd,
            .epoll_fd = epoll_fd,
            .dispatch_fn = dispatch_fn,
            .handler_index = handler_index,
            .handler_pids = handler_pids_buf[start .. start + handlers_per_thread],
            .pool_size = handlers_per_thread,
            .next_handler = 0,
            .conns = blk: {
                const c = alloc.alloc(ServeConn, SERVE_MAX_CONNS) catch return -1;
                for (c) |*conn| conn.active = false;
                break :blk c;
            },
            .conn_count = 0,
        };
    }

    // Start N-1 worker threads
    for (1..num_threads) |i| {
        os_threads[i] = std.Thread.spawn(.{}, serveThreadEntry, .{&threads[i]}) catch null;
    }

    // Run thread 0 on main thread
    threads[0].run();

    // Join workers (unreachable in practice — server runs forever)
    for (1..num_threads) |i| {
        if (os_threads[i]) |t| t.join();
    }

    return 0;
}

// ── HTTP Client ─────────────────────────────────────

var client_timeout_ms: i64 = 30000; // default 30 seconds

pub fn http_set_client_timeout(ms: i64) i64 {
    client_timeout_ms = if (ms < 0) 0 else ms;
    return 0;
}

/// Parsed URL components.
const ParsedUrl = struct {
    host: []const u8,
    port: u16,
    path: []const u8, // includes query string
    is_tls: bool,
};

/// Parse "http://host:port/path?query" or "https://..." into components.
fn parseUrl(url: []const u8) ?ParsedUrl {
    var rest = url;
    var is_tls = false;
    if (std.mem.startsWith(u8, rest, "https://")) {
        rest = rest[8..];
        is_tls = true;
    } else if (std.mem.startsWith(u8, rest, "http://")) {
        rest = rest[7..];
    }
    const slash_pos = std.mem.indexOf(u8, rest, "/");
    const host_part = if (slash_pos) |sp| rest[0..sp] else rest;
    const path = if (slash_pos) |sp| rest[sp..] else "/";
    const default_port: u16 = if (is_tls) 443 else 80;
    if (std.mem.indexOf(u8, host_part, ":")) |colon| {
        const port = std.fmt.parseInt(u16, host_part[colon + 1 ..], 10) catch return null;
        return .{ .host = host_part[0..colon], .port = port, .path = path, .is_tls = is_tls };
    }
    return .{ .host = host_part, .port = default_port, .path = path, .is_tls = is_tls };
}

// ── Read/write abstraction (plain TCP or TLS) ───────

const IoReader = std.Io.Reader;
const IoWriter = std.Io.Writer;

fn clientRead(fd: std.posix.fd_t, tls_reader: ?*IoReader, buf: []u8) ?usize {
    if (tls_reader) |r| {
        return r.readSliceShort(buf) catch return null;
    }
    const n = std.posix.read(fd, buf) catch return null;
    if (n == 0) return null;
    return n;
}

fn clientWriteAll(fd: std.posix.fd_t, tls_writer: ?*IoWriter, data: []const u8) bool {
    if (tls_writer) |w| {
        w.writeAll(data) catch return false;
        w.flush() catch return false;
        return true;
    }
    _ = std.posix.write(fd, data) catch return false;
    return true;
}

/// HTTP response — stores full raw data with parsed offsets.
pub const HttpResponse = struct {
    status: i64,
    raw: [*]const u8, // full response bytes
    raw_len: usize,
    header_end: usize, // byte offset where body starts (after \r\n\r\n)
};

/// Build an HTTP request string.
fn clientBuildRequest(method: []const u8, host: []const u8, path: []const u8, body: []const u8) []const u8 {
    var b = json.JsonBuilder.init();
    b.append(method);
    b.appendByte(' ');
    b.append(path);
    b.append(" HTTP/1.1\r\nHost: ");
    b.append(host);
    b.append("\r\nConnection: close\r\nUser-Agent: Verve/1.0\r\n");
    if (body.len > 0) {
        b.append("Content-Length: ");
        var len_buf: [20]u8 = undefined;
        const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{body.len}) catch "0";
        b.append(len_str);
        b.append("\r\nContent-Type: application/json\r\n");
    }
    b.append("\r\n");
    if (body.len > 0) b.append(body);
    const res = b.result();
    return rt.sliceFromPair(res.ptr, res.len);
}

/// Parse status code from HTTP response first line: "HTTP/1.1 200 OK\r\n"
fn parseStatusCode(data: []const u8) i64 {
    // Find first space after HTTP/1.x
    const sp1 = std.mem.indexOf(u8, data, " ") orelse return 0;
    const rest = data[sp1 + 1 ..];
    // Read 3-digit status code
    if (rest.len < 3) return 0;
    return std.fmt.parseInt(i64, rest[0..3], 10) catch 0;
}

/// Check if transfer-encoding is chunked (case-insensitive).
fn isChunkedTransfer(headers: []const u8) bool {
    const needle = "transfer-encoding:";
    var i: usize = 0;
    while (i + needle.len < headers.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            const hc = headers[i + j];
            const lower = if (hc >= 'A' and hc <= 'Z') hc + 32 else hc;
            if (lower != nc) {
                match = false;
                break;
            }
        }
        if (match) {
            var start = i + needle.len;
            while (start < headers.len and headers[start] == ' ') start += 1;
            // Check if value contains "chunked"
            const line_end = std.mem.indexOf(u8, headers[start..], "\r\n") orelse headers.len - start;
            const val = headers[start .. start + line_end];
            // Case-insensitive check for "chunked"
            if (val.len >= 7) {
                var buf: [7]u8 = undefined;
                for (val[0..@min(val.len, 7)], 0..) |c, k| {
                    buf[k] = if (c >= 'A' and c <= 'Z') c + 32 else c;
                }
                if (std.mem.eql(u8, buf[0..7], "chunked")) return true;
            }
            return false;
        }
    }
    return false;
}

/// Growable buffer for response reading.
const GrowBuf = struct {
    ptr: [*]u8,
    len: usize,
    cap: usize,

    fn init(initial: usize) ?GrowBuf {
        const mem = rt.arena_alloc(initial) orelse return null;
        return .{ .ptr = mem, .len = 0, .cap = initial };
    }

    fn grow(self: *GrowBuf, needed: usize) bool {
        if (needed <= self.cap) return true;
        var new_cap = self.cap;
        while (new_cap < needed) new_cap *= 2;
        const new_mem = rt.arena_alloc(new_cap) orelse return false;
        if (self.len > 0) @memcpy(new_mem[0..self.len], self.ptr[0..self.len]);
        self.ptr = new_mem;
        self.cap = new_cap;
        return true;
    }

    fn appendSlice(self: *GrowBuf, data: []const u8) bool {
        if (!self.grow(self.len + data.len)) return false;
        @memcpy(self.ptr[self.len .. self.len + data.len], data);
        self.len += data.len;
        return true;
    }

    fn slice(self: *const GrowBuf) []const u8 {
        if (self.len == 0) return "";
        return self.ptr[0..self.len];
    }
};

/// Decode chunked transfer encoding, appending decoded bytes to buf.
fn readChunkedBody(fd: std.posix.fd_t, tls_reader: ?*IoReader, buf: *GrowBuf, leftover: []const u8) void {
    var pending = leftover;

    while (true) {
        const chunk_header_end = findInData(pending, "\r\n");
        if (chunk_header_end == null) {
            var read_buf: [4096]u8 = undefined;
            const n = clientRead(fd, tls_reader, &read_buf) orelse return;
            const old_len = buf.len;
            if (!buf.appendSlice(pending)) return;
            if (!buf.appendSlice(read_buf[0..n])) return;
            pending = buf.ptr[old_len..buf.len];
            buf.len = old_len;
            continue;
        }

        const size_str = pending[0..chunk_header_end.?];
        const clean = if (std.mem.indexOf(u8, size_str, ";")) |semi| size_str[0..semi] else size_str;
        const chunk_size = std.fmt.parseInt(usize, std.mem.trim(u8, clean, " \t"), 16) catch return;

        if (chunk_size == 0) return;

        const data_start = chunk_header_end.? + 2;
        const data_end = data_start + chunk_size;
        const chunk_end = data_end + 2;

        if (pending.len >= chunk_end) {
            if (!buf.appendSlice(pending[data_start..data_end])) return;
            pending = pending[chunk_end..];
        } else if (pending.len >= data_start) {
            const available = pending.len - data_start;
            const in_pending = @min(available, chunk_size);
            if (!buf.appendSlice(pending[data_start .. data_start + in_pending])) return;

            var remaining = chunk_size - in_pending;
            while (remaining > 0) {
                var read_buf2: [4096]u8 = undefined;
                const to_read = @min(remaining, read_buf2.len);
                const n2 = clientRead(fd, tls_reader, read_buf2[0..to_read]) orelse return;
                if (!buf.appendSlice(read_buf2[0..n2])) return;
                remaining -= n2;
            }
            var trail: [2]u8 = undefined;
            _ = clientRead(fd, tls_reader, &trail);
            pending = &.{};
        } else {
            var read_buf3: [4096]u8 = undefined;
            const n3 = clientRead(fd, tls_reader, &read_buf3) orelse return;
            const old_len = buf.len;
            if (!buf.appendSlice(pending)) return;
            if (!buf.appendSlice(read_buf3[0..n3])) return;
            pending = buf.ptr[old_len..buf.len];
            buf.len = old_len;
            continue;
        }
    }
}

fn findInData(data: []const u8, needle: []const u8) ?usize {
    if (data.len < needle.len) return null;
    for (0..data.len - needle.len + 1) |i| {
        if (std.mem.eql(u8, data[i .. i + needle.len], needle)) return i;
    }
    return null;
}

/// Read full HTTP response. Returns HttpResponse or null on failure.
fn clientReadResponse(fd: std.posix.fd_t, tls_reader: ?*IoReader) ?*HttpResponse {
    var buf = GrowBuf.init(8192) orelse return null;

    // Read until end of headers
    var header_end: ?usize = null;
    while (header_end == null and buf.len < max_header_size) {
        const space = @min(buf.cap - buf.len, 4096);
        if (space == 0) {
            if (!buf.grow(buf.cap * 2)) break;
            continue;
        }
        const n = clientRead(fd, tls_reader, buf.ptr[buf.len .. buf.len + space]) orelse break;
        buf.len += n;
        header_end = findHeaderEnd(buf.ptr[0..buf.len]);
    }

    const hdr_end = header_end orelse return null;

    const status = parseStatusCode(buf.ptr[0..@min(buf.len, 32)]);

    const headers = buf.ptr[0..hdr_end];
    if (isChunkedTransfer(headers)) {
        const leftover = if (buf.len > hdr_end) buf.ptr[hdr_end..buf.len] else "";
        var body_buf = GrowBuf.init(8192) orelse return null;
        readChunkedBody(fd, tls_reader, &body_buf, leftover);

        var final = GrowBuf.init(hdr_end + body_buf.len) orelse return null;
        if (!final.appendSlice(headers)) return null;
        if (!final.appendSlice(body_buf.slice())) return null;

        const resp_mem = rt.arena_alloc(@sizeOf(HttpResponse)) orelse return null;
        const resp: *HttpResponse = @ptrCast(@alignCast(resp_mem));
        resp.* = .{ .status = status, .raw = final.ptr, .raw_len = final.len, .header_end = hdr_end };
        return resp;
    }

    // Content-Length body reading
    const content_len = parseContentLength(headers);
    if (content_len > 0) {
        const needed = hdr_end + content_len;
        if (buf.grow(needed)) {
            while (buf.len < needed) {
                const n = clientRead(fd, tls_reader, buf.ptr[buf.len..@min(needed, buf.cap)]) orelse break;
                buf.len += n;
            }
        }
    } else {
        // No Content-Length, not chunked: read until connection close
        const max_total = hdr_end + max_body_size;
        while (buf.len < max_total) {
            if (!buf.grow(buf.len + 4096)) break;
            const space = @min(buf.cap - buf.len, 4096);
            const n = clientRead(fd, tls_reader, buf.ptr[buf.len .. buf.len + space]) orelse break;
            buf.len += n;
        }
    }

    const resp_mem = rt.arena_alloc(@sizeOf(HttpResponse)) orelse return null;
    const resp: *HttpResponse = @ptrCast(@alignCast(resp_mem));
    resp.* = .{
        .status = status,
        .raw = buf.ptr,
        .raw_len = buf.len,
        .header_end = hdr_end,
    };
    return resp;
}

/// Find a header value in response headers (case-insensitive).
fn clientFindHeader(resp: *const HttpResponse, name: []const u8) []const u8 {
    if (resp.header_end == 0) return "";
    const headers = resp.raw[0..resp.header_end];
    // Scan line by line
    var pos: usize = 0;
    // Skip status line
    if (findInData(headers, "\r\n")) |first_nl| {
        pos = first_nl + 2;
    }
    while (pos < headers.len) {
        const line_end = findInData(headers[pos..], "\r\n") orelse break;
        const line = headers[pos .. pos + line_end];
        pos += line_end + 2;
        const colon = std.mem.indexOf(u8, line, ":") orelse continue;
        const key = line[0..colon];
        if (key.len != name.len) continue;
        // Case-insensitive compare
        var match = true;
        for (key, 0..) |c, i| {
            const a = if (c >= 'A' and c <= 'Z') c + 32 else c;
            const b = if (name[i] >= 'A' and name[i] <= 'Z') name[i] + 32 else name[i];
            if (a != b) {
                match = false;
                break;
            }
        }
        if (match) {
            var val_start = colon + 1;
            while (val_start < line.len and line[val_start] == ' ') val_start += 1;
            return line[val_start..];
        }
    }
    return "";
}

// ── Client public API ───────────────────────────────

pub fn http_client_get(url: []const u8) usize {
    return httpClientRequest("GET", url, "");
}

pub fn http_client_post(url: []const u8, body: []const u8) usize {
    return httpClientRequest("POST", url, body);
}

pub fn http_client_request(method: []const u8, url: []const u8, body: []const u8) usize {
    return httpClientRequest(method, url, body);
}

fn httpClientRequest(method: []const u8, url: []const u8, body: []const u8) usize {
    return httpClientRequestInner(method, url, body, 0);
}

fn httpClientRequestInner(method: []const u8, url: []const u8, body: []const u8, redirect_count: u8) usize {
    if (redirect_count > 10) return rt.makeTagged(1, 0);

    const parsed = parseUrl(url) orelse return rt.makeTagged(1, 0);

    // HTTPS: delegate to std.http.Client (handles TLS, compression, etc.)
    if (parsed.is_tls) return httpClientRequestTls(method, url, body, redirect_count);

    // HTTP: raw socket path (fast, no allocator needed)
    const addr = std.net.Address.resolveIp(parsed.host, parsed.port) catch return rt.makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return rt.makeTagged(1, 0);

    if (client_timeout_ms > 0) {
        const tv_sec: i64 = @divFloor(client_timeout_ms, 1000);
        const tv_usec: i64 = @mod(client_timeout_ms, 1000) * 1000;
        const timeout = std.posix.timeval{ .sec = @intCast(tv_sec), .usec = @intCast(tv_usec) };
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&timeout)) catch {};
        std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&timeout)) catch {};
    }

    std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };

    const req = clientBuildRequest(method, parsed.host, parsed.path, body);
    if (!clientWriteAll(fd, null, req)) {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    }

    const resp = clientReadResponse(fd, null) orelse {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };
    std.posix.close(fd);

    // Handle redirects: 301, 302, 303, 307, 308
    if (resp.status >= 301 and resp.status <= 308 and resp.status != 304 and resp.status != 305 and resp.status != 306) {
        const location = clientFindHeader(resp, "location");
        if (location.len > 0) {
            var redirect_url: []const u8 = location;
            if (!std.mem.startsWith(u8, location, "http://") and !std.mem.startsWith(u8, location, "https://")) {
                var b = json.JsonBuilder.init();
                b.append("http://");
                b.append(parsed.host);
                if (parsed.port != 80) {
                    b.appendByte(':');
                    b.appendInt(@intCast(parsed.port));
                }
                if (location[0] != '/') b.appendByte('/');
                b.append(location);
                const res = b.result();
                redirect_url = rt.sliceFromPair(res.ptr, res.len);
            }
            const new_method = if (resp.status == 303) "GET" else method;
            const new_body = if (resp.status == 303) "" else body;
            return httpClientRequestInner(new_method, redirect_url, new_body, redirect_count + 1);
        }
    }

    return rt.makeTagged(0, @intCast(@intFromPtr(resp)));
}

/// HTTPS request via std.http.Client (handles TLS, certificate validation, compression).
fn httpClientRequestTls(method_str: []const u8, url: []const u8, body: []const u8, redirect_count: u8) usize {
    const http_mod = std.http;
    var client: http_mod.Client = .{ .allocator = std.heap.page_allocator };
    defer client.deinit();

    const uri = std.Uri.parse(url) catch return rt.makeTagged(1, 0);

    // Map method string to enum
    const method: http_mod.Method = if (std.mem.eql(u8, method_str, "GET"))
        .GET
    else if (std.mem.eql(u8, method_str, "POST"))
        .POST
    else if (std.mem.eql(u8, method_str, "PUT"))
        .PUT
    else if (std.mem.eql(u8, method_str, "DELETE"))
        .DELETE
    else if (std.mem.eql(u8, method_str, "PATCH"))
        .PATCH
    else if (std.mem.eql(u8, method_str, "HEAD"))
        .HEAD
    else
        .GET;

    // Configure redirect behavior
    const max_redirects: u16 = if (redirect_count >= 10) 0 else 10 - @as(u16, redirect_count);

    var req = client.request(method, uri, .{
        .headers = .{ .accept_encoding = .{ .override = "identity" } },
        .redirect_behavior = @enumFromInt(max_redirects),
    }) catch return rt.makeTagged(1, 0);
    defer req.deinit();

    // Send body or bodiless
    if (body.len > 0) {
        req.transfer_encoding = .{ .content_length = body.len };
        var req_body = req.sendBodyUnflushed(&.{}) catch return rt.makeTagged(1, 0);
        req_body.writer.writeAll(body) catch return rt.makeTagged(1, 0);
        req_body.end() catch return rt.makeTagged(1, 0);
        if (req.connection) |conn| conn.flush() catch return rt.makeTagged(1, 0);
    } else {
        req.sendBodiless() catch return rt.makeTagged(1, 0);
    }

    // Receive headers (arena-allocate to avoid stack overflow in Verve processes)
    const head_buf = rt.arena_alloc(16384) orelse return rt.makeTagged(1, 0);
    var response = req.receiveHead(head_buf[0..16384]) catch return rt.makeTagged(1, 0);
    const status: i64 = @intFromEnum(response.head.status);

    // Read body (arena-allocate decompression buffer to avoid stack overflow)
    const decomp_buf = rt.arena_alloc(65536) orelse return rt.makeTagged(1, 0);
    const reader = response.reader(decomp_buf[0..65536]);
    var body_buf = GrowBuf.init(8192) orelse return rt.makeTagged(1, 0);
    while (true) {
        if (!body_buf.grow(body_buf.len + 4096)) break;
        const space = @min(body_buf.cap - body_buf.len, 4096);
        const n = reader.readSliceShort(body_buf.ptr[body_buf.len .. body_buf.len + space]) catch break;
        if (n == 0) break;
        body_buf.len += n;
    }

    // Build HttpResponse struct compatible with our accessor functions
    // Reconstruct a minimal header section so resp_header still works
    var resp_buf = GrowBuf.init(256 + body_buf.len) orelse return rt.makeTagged(1, 0);
    // Minimal status line + content-type header
    var status_line_buf: [64]u8 = undefined;
    const status_line = std.fmt.bufPrint(&status_line_buf, "HTTP/1.1 {d} OK\r\n", .{status}) catch "HTTP/1.1 200 OK\r\n";
    if (!resp_buf.appendSlice(status_line)) return rt.makeTagged(1, 0);
    if (response.head.content_type) |ct| {
        if (!resp_buf.appendSlice("Content-Type: ")) return rt.makeTagged(1, 0);
        if (!resp_buf.appendSlice(ct)) return rt.makeTagged(1, 0);
        if (!resp_buf.appendSlice("\r\n")) return rt.makeTagged(1, 0);
    }
    if (!resp_buf.appendSlice("\r\n")) return rt.makeTagged(1, 0);
    const hdr_end = resp_buf.len;
    if (!resp_buf.appendSlice(body_buf.slice())) return rt.makeTagged(1, 0);

    const resp_mem = rt.arena_alloc(@sizeOf(HttpResponse)) orelse return rt.makeTagged(1, 0);
    const resp: *HttpResponse = @ptrCast(@alignCast(resp_mem));
    resp.* = .{ .status = status, .raw = resp_buf.ptr, .raw_len = resp_buf.len, .header_end = hdr_end };
    return rt.makeTagged(0, @intCast(@intFromPtr(resp)));
}

/// Http.resp_status(resp) → int
pub fn http_resp_status(resp_ptr: usize) i64 {
    if (resp_ptr == 0) return 0;
    const resp: *const HttpResponse = @ptrFromInt(resp_ptr);
    return resp.status;
}

/// Http.resp_body(resp) → string
pub fn http_resp_body(resp_ptr: usize) []const u8 {
    if (resp_ptr == 0) return "";
    const resp: *const HttpResponse = @ptrFromInt(resp_ptr);
    if (resp.raw_len <= resp.header_end) return "";
    return resp.raw[resp.header_end..resp.raw_len];
}

/// Http.resp_header(resp, name) → string (case-insensitive)
pub fn http_resp_header(resp_ptr: usize, name: []const u8) []const u8 {
    if (resp_ptr == 0) return "";
    const resp: *const HttpResponse = @ptrFromInt(resp_ptr);
    return clientFindHeader(resp, name);
}
