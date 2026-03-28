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

pub fn tcp_accept(listener_ptr: i64) i64 {
    const t = rt.profile.begin();
    defer rt.profile.end(.accept, t);

    const listener = io.toStream(listener_ptr) orelse return rt.makeTagged(1, 0);
    if (listener.closed or listener.kind != .tcp_listener) return rt.makeTagged(1, 0);

    const client_fd = std.posix.accept(listener.fd, null, null, 0) catch return rt.makeTagged(1, 0);

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

/// Get the local port of a listener socket. Useful after listen with port 0.
pub fn tcp_port(stream_ptr: i64) i64 {
    const s = io.toStream(stream_ptr) orelse return 0;
    if (s.kind != .tcp_listener and s.kind != .tcp_client) return 0;
    var addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    std.posix.getsockname(s.fd, @ptrCast(&addr), &addr_len) catch return 0;
    return @intCast(std.mem.bigToNative(u16, addr.port));
}
