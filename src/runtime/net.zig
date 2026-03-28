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
    const s = toStream(stream_ptr) orelse return;
    if (s.closed) return;
    s.closed = true;
    switch (s.kind) {
        .tcp_client, .tcp_listener => std.posix.close(s.fd),
        .file_write => std.posix.close(s.fd),
        .file_read => {},
    }
}

/// Read up to `max_bytes` from a stream. Returns []const u8.
pub fn stream_read_bytes(stream_ptr: i64, max: i64) []const u8 {
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

// ── TCP ────────────────────────────────────────────

pub fn tcp_open(host: []const u8, port: i64) i64 {
    const port_u16: u16 = @intCast(@as(u64, @bitCast(port)));

    const addr = std.net.Address.resolveIp(host, port_u16) catch return rt.makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return rt.makeTagged(1, 0);
    std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };

    const s_mem = rt.arena_alloc(@sizeOf(VerveStream)) orelse return rt.makeTagged(1, 0);
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
    return rt.makeTagged(0, s.streamPtr());
}

pub fn tcp_listen(host: []const u8, port: i64) i64 {
    const port_u16: u16 = @intCast(@as(u64, @bitCast(port)));

    const addr = std.net.Address.resolveIp(host, port_u16) catch return rt.makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return rt.makeTagged(1, 0);

    // SO_REUSEADDR to avoid "address already in use"
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch {};

    std.posix.bind(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };
    std.posix.listen(fd, 128) catch {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };

    const s_mem = rt.arena_alloc(@sizeOf(VerveStream)) orelse return rt.makeTagged(1, 0);
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
    return rt.makeTagged(0, s.streamPtr());
}

pub fn tcp_accept(listener_ptr: i64) i64 {
    const listener = toStream(listener_ptr) orelse return rt.makeTagged(1, 0);
    if (listener.closed or listener.kind != .tcp_listener) return rt.makeTagged(1, 0);

    const client_fd = std.posix.accept(listener.fd, null, null, 0) catch return rt.makeTagged(1, 0);

    const s_mem = rt.arena_alloc(@sizeOf(VerveStream)) orelse {
        std.posix.close(client_fd);
        return rt.makeTagged(1, 0);
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
    return rt.makeTagged(0, s.streamPtr());
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
        if (self.headers_end - self.headers_start > rt.HTTP_MAX_HEADER_SIZE) {
            self.headers_end = self.headers_start + rt.HTTP_MAX_HEADER_SIZE;
        }
        self.body_start = pos;
        const remaining = if (pos < self.src.len) self.src.len - pos else 0;
        self.body_len = @min(remaining, rt.HTTP_MAX_BODY_SIZE);
    }
};

pub fn http_parse_request(data: []const u8) i64 {
    const src = data;
    if (src.len < 10) return 0;

    // Parse request line only (lazy: headers + body parsed on access)
    var pos: usize = 0;

    // Method — enforce limit
    const method_start = pos;
    while (pos < src.len and src[pos] != ' ' and pos - method_start < rt.HTTP_MAX_METHOD_SIZE) pos += 1;
    const method_len = pos - method_start;
    if (pos >= src.len or method_len == 0) return 0;
    pos += 1;

    // Path — enforce limit
    const path_start = pos;
    while (pos < src.len and src[pos] != ' ' and pos - path_start < rt.HTTP_MAX_URI_SIZE) pos += 1;
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

/// Build an HTTP response. Returns the full response as []const u8.
pub fn http_build_response(status: i64, ct: []const u8, body: []const u8) []const u8 {
    const json = @import("json.zig");
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
    return rt.sliceFromPair(res.ptr, res.len);
}
