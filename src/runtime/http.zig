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
            // No data ready — yield to scheduler or return
            if (rt.process.scheduler_running.load(.acquire) and rt.process.current_process_id > 0) {
                rt.process.verve_io_yield(@intCast(s.fd));
            } else {
                return ""; // no data, no scheduler
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

/// Blocking HTTP read — for use in the connection manager (no scheduler/fiber).
/// Reads one complete HTTP request using poll() for blocking.
fn http_read_request_blocking(s: *io.VerveStream) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.read, t);

    if (s.closed) return "";

    // Check buffer first
    if (s.read_pos >= s.read_len) {
        // No buffered data — poll for readability
        var pfd = [1]std.posix.pollfd{.{
            .fd = s.fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const poll_n = std.posix.poll(&pfd, keepalive_timeout_ms) catch return "";
        if (poll_n == 0) return ""; // timeout — close connection
        if (pfd[0].revents & std.posix.POLL.HUP != 0) return ""; // client closed
    }

    // Read into buffer
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

    // Read body
    const content_len = parseContentLength(buf_ptr[0..hdr_end]);
    const needed = hdr_end + content_len;
    const max_request = max_header_size + max_body_size;
    if (needed > max_request) return buf_ptr[0..total];

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

    // Stash leftover
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
