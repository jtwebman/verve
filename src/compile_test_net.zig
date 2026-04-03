const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Lower = @import("lower.zig").Lower;
const ZigBackend = @import("zig_backend.zig").ZigBackend;
const testing = std.testing;
const alloc = std.heap.page_allocator;

fn getZigPath() []const u8 {
    return std.posix.getenv("VERVE_ZIG") orelse "/home/jt/.local/zig/zig";
}

fn getOptimizeMode() []const u8 {
    return std.posix.getenv("VERVE_OPTIMIZE") orelse "-OReleaseFast";
}

/// Compile Verve source to native binary, run it, return exit code.
fn compileAndRun(source: []const u8) !u8 {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_net";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 255,
    };
}

/// Compile, run, capture stdout.
fn compileAndCapture(source: []const u8) !struct { exit: u8, stdout: []const u8 } {
    var parser = Parser.init(source, alloc);
    const file = try parser.parseFile();
    var lower = Lower.init(alloc);
    const program = try lower.lowerFile(file);
    var backend = ZigBackend.init(alloc);
    backend.emit(program);
    backend.optimize_mode = getOptimizeMode();
    const path = "/tmp/verve_ct_net_cap";
    try backend.build(path, getZigPath());
    defer std.fs.cwd().deleteFile(path) catch {};
    var child = std.process.Child.init(&.{path}, alloc);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    var buf: [4096]u8 = undefined;
    const n = try child.stdout.?.readAll(&buf);
    const term = try child.wait();
    return .{
        .exit = switch (term) {
            .Exited => |code| code,
            else => 255,
        },
        .stdout = try alloc.dupe(u8, buf[0..n]),
    };
}

// ── TCP tests ──────────────────────────────────────

test "compile: tcp listen and connect loopback" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "hello from client");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                line: string = Stream.read_line(client);
        \\                                Stdio.println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("hello from client\n", r.stdout);
}

test "compile: tcp connect refused" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.open("127.0.0.1", 1) {
        \\            :ok{conn} => Stdio.println("unexpected success");
        \\            :error{e} => Stdio.println("refused");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("refused\n", r.stdout);
}

test "compile: tcp read eof on peer close" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "data");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                line: string = Stream.read_line(client);
        \\                                Stdio.println(line);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("data\n", r.stdout);
}

test "compile: tcp bidirectional echo" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.write_line(conn, "ping");
        \\                                req: string = Stream.read_line(client);
        \\                                Stdio.println(req);
        \\                                Stream.write_line(client, "pong");
        \\                                resp: string = Stream.read_line(conn);
        \\                                Stdio.println(resp);
        \\                                Stream.close(client);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ping\npong\n", r.stdout);
}

test "compile: tcp multiple sequential connections" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                i: int = 0;
        \\                while i < 3 {
        \\                    match Tcp.open("127.0.0.1", port) {
        \\                        :ok{conn} => {
        \\                            Stream.write_line(conn, "msg");
        \\                            Stream.close(conn);
        \\                            match Tcp.accept(listener) {
        \\                                :ok{client} => {
        \\                                    line: string = Stream.read_line(client);
        \\                                    Stdio.println(line);
        \\                                    Stream.close(client);
        \\                                }
        \\                                :error{e} => Stdio.println("accept failed");
        \\                            }
        \\                        }
        \\                        :error{e} => Stdio.println("connect failed");
        \\                    }
        \\                    i = i + 1;
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("msg\nmsg\nmsg\n", r.stdout);
}

test "compile: tcp listen port zero assigns port" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                if port > 0 {
        \\                    Stdio.println("ok");
        \\                } else {
        \\                    Stdio.println("bad port");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("ok\n", r.stdout);
}

test "compile: tcp double bind fails" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener1} => {
        \\                port: int = Tcp.port(listener1);
        \\                match Tcp.listen("127.0.0.1", port) {
        \\                    :ok{listener2} => {
        \\                        Stdio.println("unexpected success");
        \\                        Stream.close(listener2);
        \\                    }
        \\                    :error{e} => Stdio.println("address in use");
        \\                }
        \\                Stream.close(listener1);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("address in use\n", r.stdout);
}

test "compile: tcp data before close all delivered" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        Stream.write_line(conn, "line1");
        \\                        Stream.write_line(conn, "line2");
        \\                        Stream.write_line(conn, "line3");
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                l1: string = Stream.read_line(client);
        \\                                l2: string = Stream.read_line(client);
        \\                                l3: string = Stream.read_line(client);
        \\                                Stdio.println(l1);
        \\                                Stdio.println(l2);
        \\                                Stdio.println(l3);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("line1\nline2\nline3\n", r.stdout);
}

test "compile: tcp large transfer" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        i: int = 0;
        \\                        while i < 100 {
        \\                            Stream.write_line(conn, "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz01");
        \\                            i = i + 1;
        \\                        }
        \\                        Stream.close(conn);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                count: int = 0;
        \\                                done: bool = false;
        \\                                while !done {
        \\                                    line: string = Stream.read_line(client);
        \\                                    if String.len(line) > 0 {
        \\                                        count = count + 1;
        \\                                    } else {
        \\                                        done = true;
        \\                                    }
        \\                                }
        \\                                Stdio.println(count);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("100\n", r.stdout);
}

test "compile: tcp write after peer close" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.close(client);
        \\                                Stream.write_line(conn, "should not crash");
        \\                                Stdio.println("survived");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // SIGPIPE is ignored, write to closed socket doesn't crash
    try testing.expectEqualStrings("survived\n", r.stdout);
}

test "compile: tcp operations on closed stream" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{conn} => {
        \\                        match Tcp.accept(listener) {
        \\                            :ok{client} => {
        \\                                Stream.close(client);
        \\                                Stream.close(client);
        \\                                Stream.write_line(client, "noop");
        \\                                Stdio.println("ok");
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Double close and write to closed stream should not crash
    try testing.expectEqualStrings("ok\n", r.stdout);
}

test "compile: tcp accept on closed listener" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                Stream.close(listener);
        \\                match Tcp.accept(listener) {
        \\                    :ok{client} => Stdio.println("unexpected");
        \\                    :error{e} => Stdio.println("rejected");
        \\                }
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("rejected\n", r.stdout);
}

// ── HTTP tests ─────────────────────────────────────

test "compile: http parse request method and path" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(method);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\n/hello\n", r.stdout);
}

test "compile: http parse request header" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Type: application/json\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        host: string = Http.req_header(req, "Host");
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(host);
        \\        Stdio.println(ct);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("example.com\napplication/json\n", r.stdout);
}

test "compile: http build response" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        response: string = Http.respond(200, "text/plain", "hello");
        \\        Stdio.println(response);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Response includes Date header, so check key parts
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 200 OK\r\n"));
    try testing.expect(std.mem.indexOf(u8, r.stdout, "Content-Length: 5") != null);
    try testing.expect(std.mem.indexOf(u8, r.stdout, "hello") != null);
}

test "compile: http server loopback" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n");
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                path: string = Http.req_path(req);
        \\                                response: string = Http.respond(200, "text/plain", "ok");
        \\                                Stream.write(conn, response);
        \\                                Stream.close(conn);
        \\                                reply: string = Stream.read_line(client);
        \\                                Stdio.println(reply);
        \\                                Stdio.println(path);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // read_line preserves \r from HTTP \r\n line endings
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\n/test\n", r.stdout);
}

test "compile: http 404 response" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        response: string = Http.respond(404, "text/plain", "not found");
        \\        Stdio.println(response);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 404 Not Found\r\n"));
    try testing.expect(std.mem.indexOf(u8, r.stdout, "Content-Length: 9") != null);
    try testing.expect(std.mem.indexOf(u8, r.stdout, "not found") != null);
}

test "compile: http json response end to end" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        b: int = Json.build_object();
        \\        Json.build_add_string(b, "msg", "hello");
        \\        body: string = Json.build_end(b);
        \\        response: string = Http.respond(200, "application/json", body);
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET / HTTP/1.1\r\n\r\n");
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                Stream.write(conn, response);
        \\                                Stream.close(conn);
        \\                                reply: string = Stream.read_line(client);
        \\                                Stdio.println(reply);
        \\                                Stream.close(client);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("connect failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\n", r.stdout);
}

test "compile: http parse POST with body" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "POST /api HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"key\":\"val\"}";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(method);
        \\        Stdio.println(body);
        \\        name: string = Json.get_string(body, "key");
        \\        Stdio.println(name);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("POST\n{\"key\":\"val\"}\nval\n", r.stdout);
}

test "compile: http parse different methods" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        get: int = Http.parse_request("GET / HTTP/1.1\r\n\r\n");
        \\        m1: string = Http.req_method(get);
        \\        Stdio.println(m1);
        \\        post: int = Http.parse_request("POST /data HTTP/1.1\r\n\r\n");
        \\        m2: string = Http.req_method(post);
        \\        Stdio.println(m2);
        \\        put: int = Http.parse_request("PUT /item HTTP/1.1\r\n\r\n");
        \\        m3: string = Http.req_method(put);
        \\        Stdio.println(m3);
        \\        del: int = Http.parse_request("DELETE /item HTTP/1.1\r\n\r\n");
        \\        m4: string = Http.req_method(del);
        \\        Stdio.println(m4);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\nPOST\nPUT\nDELETE\n", r.stdout);
}

test "compile: http response status codes" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        r200: string = Http.respond(200, "text/plain", "ok");
        \\        r201: string = Http.respond(201, "text/plain", "created");
        \\        r400: string = Http.respond(400, "text/plain", "bad");
        \\        r500: string = Http.respond(500, "text/plain", "error");
        \\        // Check first line of each
        \\        Stdio.println(r200);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    // Just verify it doesn't crash and produces output
    try testing.expect(r.stdout.len > 0);
    try testing.expect(std.mem.startsWith(u8, r.stdout, "HTTP/1.1 200 OK"));
}

test "compile: http server with json request and response" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "POST /api HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"name\":\"test\"}");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                body: string = Http.req_body(req);
        \\                                name: string = Json.get_string(body, "name");
        \\                                b: int = Json.build_object();
        \\                                Json.build_add_string(b, "hello", name);
        \\                                resp_body: string = Json.build_end(b);
        \\                                Stdio.println(resp_body);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"hello\":\"test\"}\n", r.stdout);
}

test "compile: http missing header returns empty" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(String.len(ct));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: http case insensitive headers" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nContent-Type: text/html\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        ct1: string = Http.req_header(req, "content-type");
        \\        ct2: string = Http.req_header(req, "CONTENT-TYPE");
        \\        ct3: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(ct1);
        \\        Stdio.println(ct2);
        \\        Stdio.println(ct3);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("text/html\ntext/html\ntext/html\n", r.stdout);
}

test "compile: http path with query string" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET /search?q=verve&page=1 HTTP/1.1\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/search?q=verve&page=1\n", r.stdout);
}

test "compile: http multiple requests on same listener" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                i: int = 0;
        \\                while i < 3 {
        \\                    match Tcp.open("127.0.0.1", port) {
        \\                        :ok{client} => {
        \\                            n: string = Convert.to_string(i);
        \\                            Stream.write(client, "GET /req" + n + " HTTP/1.1\r\n\r\n");
        \\                            Stream.close(client);
        \\                            match Tcp.accept(listener) {
        \\                                :ok{conn} => {
        \\                                    data: string = Stream.read_bytes(conn, 4096);
        \\                                    req: int = Http.parse_request(data);
        \\                                    path: string = Http.req_path(req);
        \\                                    Stdio.println(path);
        \\                                    Stream.close(conn);
        \\                                }
        \\                                :error{e} => Stdio.println("accept failed");
        \\                            }
        \\                        }
        \\                        :error{e} => Stdio.println("open failed");
        \\                    }
        \\                    i = i + 1;
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/req0\n/req1\n/req2\n", r.stdout);
}

test "compile: json and http integration - parse json body and respond" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "POST /echo HTTP/1.1\r\n\r\n{\"input\":\"hello\"}");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                body: string = Http.req_body(req);
        \\                                input: string = Json.get_string(body, "input");
        \\                                b: int = Json.build_object();
        \\                                Json.build_add_string(b, "output", input);
        \\                                resp: string = Json.build_end(b);
        \\                                Stdio.println(resp);
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("{\"output\":\"hello\"}\n", r.stdout);
}

test "compile: http GET without body" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET /api HTTP/1.1\r\nHost: localhost\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(String.len(body));
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("0\n", r.stdout);
}

test "compile: http POST with form encoded body" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "POST /login HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 21\r\n\r\nuser=alice&pass=s3cret";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        body: string = Http.req_body(req);
        \\        ct: string = Http.req_header(req, "Content-Type");
        \\        Stdio.println(method);
        \\        Stdio.println(body);
        \\        Stdio.println(ct);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("POST\nuser=alice&pass=s3cret\napplication/x-www-form-urlencoded\n", r.stdout);
}

test "compile: http request line only no headers" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        path: string = Http.req_path(req);
        \\        Stdio.println(path);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("/\n", r.stdout);
}

test "compile: http lazy parsing - path only never touches headers" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Tcp.listen("127.0.0.1", 0) {
        \\            :ok{listener} => {
        \\                port: int = Tcp.port(listener);
        \\                match Tcp.open("127.0.0.1", port) {
        \\                    :ok{client} => {
        \\                        Stream.write(client, "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n");
        \\                        Stream.close(client);
        \\                        match Tcp.accept(listener) {
        \\                            :ok{conn} => {
        \\                                data: string = Stream.read_bytes(conn, 4096);
        \\                                req: int = Http.parse_request(data);
        \\                                path: string = Http.req_path(req);
        \\                                if path == "/health" {
        \\                                    Stdio.println("healthy");
        \\                                } else {
        \\                                    Stdio.println("unknown");
        \\                                }
        \\                                Stream.close(conn);
        \\                            }
        \\                            :error{e} => Stdio.println("accept failed");
        \\                        }
        \\                    }
        \\                    :error{e} => Stdio.println("open failed");
        \\                }
        \\                Stream.close(listener);
        \\            }
        \\            :error{e} => Stdio.println("listen failed");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("healthy\n", r.stdout);
}

test "compile: http GET with body (elasticsearch style)" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET /search HTTP/1.1\r\nContent-Length: 16\r\n\r\n{\"query\":\"test\"}";
        \\        req: int = Http.parse_request(data);
        \\        method: string = Http.req_method(req);
        \\        path: string = Http.req_path(req);
        \\        body: string = Http.req_body(req);
        \\        Stdio.println(method);
        \\        Stdio.println(path);
        \\        q: string = Json.get_string(body, "query");
        \\        Stdio.println(q);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("GET\n/search\ntest\n", r.stdout);
}

test "compile: http multiple headers" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        data: string = "GET / HTTP/1.1\r\nHost: localhost\r\nAccept: text/html\r\nUser-Agent: Verve/1.0\r\nX-Custom: hello\r\n\r\n";
        \\        req: int = Http.parse_request(data);
        \\        host: string = Http.req_header(req, "Host");
        \\        accept: string = Http.req_header(req, "Accept");
        \\        ua: string = Http.req_header(req, "User-Agent");
        \\        custom: string = Http.req_header(req, "X-Custom");
        \\        Stdio.println(host);
        \\        Stdio.println(accept);
        \\        Stdio.println(ua);
        \\        Stdio.println(custom);
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("localhost\ntext/html\nVerve/1.0\nhello\n", r.stdout);
}

// ── HTTP Client tests ─────────────────────────────────

test "compile: http client GET to local server" {
    // Use a Zig-level HTTP server to avoid Verve process timing issues
    const port = try startTestHttpServer("200 OK", "text/plain", "hello from server");
    defer stopTestHttpServer(port);

    var url_buf: [64]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/test", .{port}) catch unreachable;

    const src_fmt =
        \\process App {{
        \\    receive main(args: list<string>) -> int {{
        \\        match Http.get("{s}") {{
        \\            :ok{{resp}} => {{
        \\                Stdio.println(Http.resp_status(resp));
        \\                Stdio.println(Http.resp_body(resp));
        \\            }}
        \\            :error{{e}} => Stdio.println("error");
        \\        }}
        \\        return 0;
        \\    }}
        \\}}
    ;
    var src_buf: [2048]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf, src_fmt, .{url}) catch unreachable;
    const r = try compileAndCapture(src);
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("200\nhello from server\n", r.stdout);
}

test "compile: http client POST to local server" {
    const port = try startTestHttpServerEcho();
    defer stopTestHttpServer(port);

    var url_buf: [64]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/api", .{port}) catch unreachable;

    const src_fmt =
        \\process App {{
        \\    receive main(args: list<string>) -> int {{
        \\        match Http.post("{s}", "{{\"name\":\"alice\"}}") {{
        \\            :ok{{resp}} => {{
        \\                Stdio.println(Http.resp_status(resp));
        \\                Stdio.println(Http.resp_body(resp));
        \\            }}
        \\            :error{{e}} => Stdio.println("error");
        \\        }}
        \\        return 0;
        \\    }}
        \\}}
    ;
    var src_buf: [2048]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf, src_fmt, .{url}) catch unreachable;
    const r = try compileAndCapture(src);
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("200\n{\"name\":\"alice\"}\n", r.stdout);
}

test "compile: http client resp_header" {
    const port = try startTestHttpServer("200 OK", "application/json", "{}");
    defer stopTestHttpServer(port);

    var url_buf: [64]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/", .{port}) catch unreachable;

    const src_fmt =
        \\process App {{
        \\    receive main(args: list<string>) -> int {{
        \\        match Http.get("{s}") {{
        \\            :ok{{resp}} => {{
        \\                ct: string = Http.resp_header(resp, "Content-Type");
        \\                Stdio.println(ct);
        \\            }}
        \\            :error{{e}} => Stdio.println("error");
        \\        }}
        \\        return 0;
        \\    }}
        \\}}
    ;
    var src_buf: [2048]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf, src_fmt, .{url}) catch unreachable;
    const r = try compileAndCapture(src);
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("application/json\n", r.stdout);
}

test "compile: http client 404 is ok not error" {
    const port = try startTestHttpServer("404 Not Found", "text/plain", "not found");
    defer stopTestHttpServer(port);

    var url_buf: [64]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "http://127.0.0.1:{d}/missing", .{port}) catch unreachable;

    const src_fmt =
        \\process App {{
        \\    receive main(args: list<string>) -> int {{
        \\        match Http.get("{s}") {{
        \\            :ok{{resp}} => {{
        \\                Stdio.println(Http.resp_status(resp));
        \\                Stdio.println(Http.resp_body(resp));
        \\            }}
        \\            :error{{e}} => Stdio.println("should not be error");
        \\        }}
        \\        return 0;
        \\    }}
        \\}}
    ;
    var src_buf: [2048]u8 = undefined;
    const src = std.fmt.bufPrint(&src_buf, src_fmt, .{url}) catch unreachable;
    const r = try compileAndCapture(src);
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("404\nnot found\n", r.stdout);
}

test "compile: http client connection refused is error" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Http.get("http://127.0.0.1:19999/nope") {
        \\            :ok{resp} => Stdio.println("should not succeed");
        \\            :error{e} => Stdio.println("connection error");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("connection error\n", r.stdout);
}

test "compile: http client invalid url is error" {
    const r = try compileAndCapture(
        \\process App {
        \\    receive main(args: list<string>) -> int {
        \\        match Http.get("not-a-url") {
        \\            :ok{resp} => Stdio.println("should not succeed");
        \\            :error{e} => Stdio.println("invalid url");
        \\        }
        \\        return 0;
        \\    }
        \\}
    );
    try testing.expectEqual(@as(u8, 0), r.exit);
    try testing.expectEqualStrings("invalid url\n", r.stdout);
}

// ── Test HTTP server helpers ─────────────────────────

const TestServer = struct {
    thread: ?std.Thread,
    fd: std.posix.fd_t,
};

var test_servers: [16]?TestServer = .{null} ** 16;

fn startTestHttpServer(status: []const u8, ct: []const u8, body: []const u8) !u16 {
    return startTestHttpServerImpl(status, ct, body, false);
}

fn startTestHttpServerEcho() !u16 {
    return startTestHttpServerImpl("200 OK", "application/json", "", true);
}

fn startTestHttpServerImpl(status: []const u8, ct: []const u8, body: []const u8, echo: bool) !u16 {
    const addr = try std.net.Address.resolveIp("127.0.0.1", 0);
    const fd = try std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0);
    const one: [4]u8 = .{ 1, 0, 0, 0 };
    std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &one) catch {};
    try std.posix.bind(fd, &addr.any, addr.getOsSockLen());
    try std.posix.listen(fd, 8);

    // Get assigned port
    var bound_addr: std.posix.sockaddr.in = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    try std.posix.getsockname(fd, @ptrCast(&bound_addr), &addr_len);
    const port = std.mem.bigToNative(u16, bound_addr.port);

    const ctx = alloc.create(ServerCtx) catch return error.OutOfMemory;
    ctx.* = .{ .fd = fd, .status = status, .ct = ct, .body = body, .echo = echo };

    const thread = try std.Thread.spawn(.{}, testServerThread, .{ctx});

    // Store for cleanup
    for (&test_servers) |*slot| {
        if (slot.* == null) {
            slot.* = .{ .thread = thread, .fd = fd };
            break;
        }
    }

    return port;
}

const ServerCtx = struct {
    fd: std.posix.fd_t,
    status: []const u8,
    ct: []const u8,
    body: []const u8,
    echo: bool,
};

fn testServerThread(ctx: *ServerCtx) void {
    // Accept one connection
    const client_fd = std.posix.accept(ctx.fd, null, null, 0) catch return;
    defer std.posix.close(client_fd);

    // Read request
    var req_buf: [8192]u8 = undefined;
    var total: usize = 0;
    while (total < req_buf.len) {
        const n = std.posix.read(client_fd, req_buf[total..]) catch break;
        if (n == 0) break;
        total += n;
        // Check for end of headers
        if (std.mem.indexOf(u8, req_buf[0..total], "\r\n\r\n")) |hdr_end| {
            // Check for Content-Length body
            const cl = parseTestContentLength(req_buf[0..hdr_end]);
            if (total >= hdr_end + 4 + cl) break;
        }
    }

    // Build response
    var resp_body: []const u8 = ctx.body;
    if (ctx.echo and total > 0) {
        // Echo back the request body
        if (std.mem.indexOf(u8, req_buf[0..total], "\r\n\r\n")) |hdr_end| {
            resp_body = req_buf[hdr_end + 4 .. total];
        }
    }

    var resp_buf: [8192]u8 = undefined;
    const resp = std.fmt.bufPrint(&resp_buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ ctx.status, ctx.ct, resp_body.len, resp_body }) catch return;
    _ = std.posix.write(client_fd, resp) catch {};
}

fn parseTestContentLength(headers: []const u8) usize {
    const needle = "Content-Length: ";
    if (std.mem.indexOf(u8, headers, needle)) |pos| {
        const start = pos + needle.len;
        var end = start;
        while (end < headers.len and headers[end] >= '0' and headers[end] <= '9') end += 1;
        return std.fmt.parseInt(usize, headers[start..end], 10) catch 0;
    }
    return 0;
}

fn stopTestHttpServer(port: u16) void {
    _ = port;
    for (&test_servers) |*slot| {
        if (slot.*) |*srv| {
            std.posix.close(srv.fd);
            if (srv.thread) |t| t.join();
            slot.* = null;
            return;
        }
    }
}
