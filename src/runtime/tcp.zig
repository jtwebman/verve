const std = @import("std");
const rt = @import("runtime.zig");
const io = @import("io.zig");

// ── TCP ────────────────────────────────────────────

pub fn tcp_open(host: []const u8, port: i64) i64 {
    const port_u16: u16 = @intCast(@as(u64, @bitCast(port)));

    const addr = std.net.Address.resolveIp(host, port_u16) catch return rt.makeTagged(1, 0);
    const fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return rt.makeTagged(1, 0);
    std.posix.connect(fd, &addr.any, addr.getOsSockLen()) catch {
        std.posix.close(fd);
        return rt.makeTagged(1, 0);
    };

    const s = std.heap.page_allocator.create(io.VerveStream) catch return rt.makeTagged(1, 0);
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

    // Set listener to non-blocking for batch accept
    setNonBlocking(fd);

    const s = std.heap.page_allocator.create(io.VerveStream) catch return rt.makeTagged(1, 0);
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

// ── Non-blocking accept with pre-accept buffer ────

const ACCEPT_BUF_SIZE = 64;

var accept_buf: [ACCEPT_BUF_SIZE]std.posix.fd_t = undefined;
var accept_head: usize = 0;
var accept_count: usize = 0;

/// Drain all pending connections from the listener into the accept buffer.
fn fillAcceptBuffer(listener_fd: std.posix.fd_t) void {
    while (accept_count < ACCEPT_BUF_SIZE) {
        const client_fd = std.posix.accept(listener_fd, null, null, std.posix.SOCK.CLOEXEC) catch |err| {
            switch (err) {
                error.WouldBlock => return, // no more queued connections
                else => return,
            }
        };
        const idx = (accept_head + accept_count) % ACCEPT_BUF_SIZE;
        accept_buf[idx] = client_fd;
        accept_count += 1;
    }
}

/// Pop one pre-accepted fd from the buffer. Returns null if empty.
fn popAcceptBuffer() ?std.posix.fd_t {
    if (accept_count == 0) return null;
    const fd = accept_buf[accept_head];
    accept_head = (accept_head + 1) % ACCEPT_BUF_SIZE;
    accept_count -= 1;
    return fd;
}

pub fn tcp_accept(listener_ptr: i64) i64 {
    const t = rt.profile.begin();
    defer rt.profile.end(.accept, t);

    const listener = io.toStream(listener_ptr) orelse return rt.makeTagged(1, 0);
    if (listener.closed or listener.kind != .tcp_listener) return rt.makeTagged(1, 0);

    // Try the pre-accept buffer first
    if (popAcceptBuffer()) |client_fd| {
        return wrapClientFd(client_fd);
    }

    // Buffer empty — try non-blocking accept batch
    fillAcceptBuffer(listener.fd);
    if (popAcceptBuffer()) |client_fd| {
        return wrapClientFd(client_fd);
    }

    // No connections queued — poll until one arrives, then batch accept
    var pfd = [1]std.posix.pollfd{.{
        .fd = listener.fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    _ = std.posix.poll(&pfd, -1) catch return rt.makeTagged(1, 0);

    fillAcceptBuffer(listener.fd);
    if (popAcceptBuffer()) |client_fd| {
        return wrapClientFd(client_fd);
    }

    return rt.makeTagged(1, 0);
}

fn wrapClientFd(client_fd: std.posix.fd_t) i64 {
    const s = std.heap.page_allocator.create(io.VerveStream) catch {
        std.posix.close(client_fd);
        return rt.makeTagged(1, 0);
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
    return rt.makeTagged(0, s.streamPtr());
}

fn setNonBlocking(fd: std.posix.fd_t) void {
    const flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch return;
    _ = std.posix.fcntl(fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }))) catch return;
}

/// Get the local port of a listener socket. Useful after listen with port 0.
pub fn tcp_port(stream_ptr: i64) i64 {
    const s = io.toStream(stream_ptr) orelse return 0;
    if (s.kind != .tcp_listener and s.kind != .tcp_client) return 0;
    var addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    std.posix.getsockname(s.fd, @ptrCast(&addr), &addr_len) catch return 0;
    return @intCast(std.mem.bigToNative(u16, addr.port));
}
