const std = @import("std");
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    const addr = try net.Address.resolveIp("127.0.0.1", 8080);
    const fd = try posix.socket(addr.any.family, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, 0);
    defer posix.close(fd);

    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch {};
    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEPORT, &std.mem.toBytes(@as(c_int, 1))) catch {};
    try posix.bind(fd, &addr.any, addr.getOsSockLen());
    try posix.listen(fd, 128);

    _ = posix.write(posix.STDOUT_FILENO, "Zig server on http://127.0.0.1:8080\n") catch {};

    // Simple blocking accept + handle loop (single-threaded, like our Verve server)
    while (true) {
        const client_fd = posix.accept(fd, null, null, posix.SOCK.CLOEXEC) catch |err| {
            if (err == error.WouldBlock) {
                var pfd = [1]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
                _ = posix.poll(&pfd, -1) catch continue;
                continue;
            }
            continue;
        };

        // Keep-alive loop
        while (true) {
            var buf: [8192]u8 = undefined;
            const n = posix.read(client_fd, &buf) catch break;
            if (n == 0) break;

            // Find end of headers
            const data = buf[0..n];
            const hdr_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse break;
            _ = hdr_end;

            // Check path
            var response: []const u8 = undefined;
            if (std.mem.startsWith(u8, data, "GET /json")) {
                response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: keep-alive\r\n\r\n{\"status\":\"ok\"}";
            } else if (std.mem.startsWith(u8, data, "GET /health")) {
                response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok";
            } else {
                response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\nConnection: keep-alive\r\n\r\nHello from Zig!";
            }

            _ = posix.write(client_fd, response) catch break;
        }
        posix.close(client_fd);
    }
}
