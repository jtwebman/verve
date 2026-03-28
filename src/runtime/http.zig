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

pub fn http_parse_request(data: []const u8) i64 {
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
    return @intCast(@intFromPtr(req));
}

pub fn toHttpReq(ptr: i64) ?*HttpRequest {
    if (ptr == 0) return null;
    return @as(*HttpRequest, @ptrFromInt(@as(usize, @intCast(@as(u64, @bitCast(ptr))))));
}

pub fn http_req_method(req_ptr: i64) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    return req.src[req.method_start .. req.method_start + req.method_len];
}

pub fn http_req_path(req_ptr: i64) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    return req.src[req.path_start .. req.path_start + req.path_len];
}

pub fn http_req_body(req_ptr: i64) []const u8 {
    const req = toHttpReq(req_ptr) orelse return "";
    req.ensureHeadersParsed();
    if (req.body_len == 0) return "";
    return req.src[req.body_start .. req.body_start + req.body_len];
}

/// Find a header value by name (case-insensitive). Returns []const u8.
pub fn http_req_header(req_ptr: i64, name: []const u8) []const u8 {
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
pub fn http_read_request(stream_ptr: i64) []const u8 {
    const t = rt.profile.begin();
    defer rt.profile.end(.read, t);

    const s = io.toStream(stream_ptr) orelse return "";
    if (s.closed) return "";

    // Fast path: check if stream buffer already has data (pipelined request)
    const has_buffered = s.read_pos < s.read_len;

    // If no buffered data, wait for data via scheduler or poll
    if (!has_buffered) {
        if (rt.process.scheduler_running and rt.process.current_process_id > 0) {
            // Scheduler mode: yield until data arrives on this socket
            rt.process.verve_io_yield(@intCast(s.fd));
            // Resumed — data should be ready now
        } else {
            // Legacy mode: non-blocking check
            var pfd = [1]std.posix.pollfd{.{
                .fd = s.fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};
            const poll_n = std.posix.poll(&pfd, 0) catch return "";
            if (poll_n == 0) return ""; // no data ready
        }
    }

    // Data is available — allocate and read the request
    const max_request = max_header_size + max_body_size;
    const buf_mem = rt.arena_alloc(max_request) orelse return "";
    const buf = buf_mem[0..max_request];
    var total: usize = 0;

    // Drain buffered data first
    while (s.read_pos < s.read_len and total < max_request) {
        buf[total] = s.read_buf[s.read_pos];
        s.read_pos += 1;
        total += 1;
    }

    // Read until we find end of headers (\r\n\r\n)
    var header_end: ?usize = findHeaderEnd(buf[0..total]);
    while (header_end == null and total < max_header_size) {
        const n = std.posix.read(s.fd, buf[total..@min(total + 4096, max_request)]) catch return "";
        if (n == 0) {
            if (total > 0) return buf[0..total];
            return "";
        }
        total += n;
        header_end = findHeaderEnd(buf[0..total]);
    }

    const hdr_end = header_end orelse return buf[0..total];

    // Read body per Content-Length
    const content_len = parseContentLength(buf[0..hdr_end]);
    const needed = hdr_end + content_len;
    if (needed > max_request) return buf[0..total];

    while (total < needed) {
        const n = std.posix.read(s.fd, buf[total..@min(needed, max_request)]) catch break;
        if (n == 0) break;
        total += n;
    }

    // Stash leftover bytes back into stream buffer for next request
    if (total > needed) {
        const leftover = total - needed;
        const copy_len = @min(leftover, s.read_buf.len);
        @memcpy(s.read_buf[0..copy_len], buf[needed .. needed + copy_len]);
        s.read_pos = 0;
        s.read_len = copy_len;
        return buf[0..needed];
    }

    return buf[0..total];
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
