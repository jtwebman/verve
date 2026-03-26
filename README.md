# Verve

A process-oriented compiled language. No exceptions, no recursion, no implicit nulls. Built for AI to write, built for humans to trust.

- File extension: `.vv`
- License: MIT

## What is Verve?

Verve is an explicit programming language designed for AI-generated code that humans can audit. There is one way to do everything, no magic, no hidden behavior, and nothing for the AI to get tripped up on.

The language strips away the ambiguity that causes AI-generated code to fail — no exceptions, no implicit null, no implicit conversions, no operator overloading, no inheritance, no macros. What's left is a small, strict set of constructs where AI can produce correct code reliably because there are fewer ways to be wrong.

Compiles to native binaries via Zig backend. Process model for concurrency. Signed source-code packages for auditable dependencies.

## Key Design Decisions

- **One way to do things** — no style debates, every problem has one idiomatic solution
- **Modules and processes** — modules organize code, processes own state and communicate via typed messages
- **Process per connection** — Elixir-style lightweight processes, spawn millions, auto-cleanup on exit
- **Guards, not exceptions** — preconditions are boolean expressions, failures return structured errors
- **Match, not if/else chains** — exhaustive branching, compiler checks all cases
- **Poison values** — overflow, division by zero, and out-of-bounds propagate instead of crashing
- **No recursion** — call graph cycles are rejected at compile time, use while loops with explicit stacks
- **Typed JSON parsing** — `Json.parse(data, MyStruct)` compiles to specialized parser code
- **Explicit types everywhere** — all variable declarations must have type annotations

## Quick Start

Requires [Zig](https://ziglang.org) 0.15+.

```
zig build                                    # build the compiler
./zig-out/bin/verve build file.vv            # compile to native binary
./zig-out/bin/verve check file.vv            # type check
./zig-out/bin/verve test file.vv             # run @example and @property tests
./zig-out/bin/verve fmt file.vv              # format in place
```

## Example: HTTP Server

```verve
struct HandlerState {
    id: int = 0;
}

process ConnectionHandler<HandlerState> {
    receive Handle(state: HandlerState, client_fd: int, n: int) -> int {
        data: string = Stream.read_bytes(client_fd, 4096);
        if String.len(data) > 0 {
            req: int = Http.parse_request(data);
            path: string = Http.req_path(req);
            response: string = Http.respond(200, "text/plain", "Hello from Verve!");
            Stream.write(client_fd, response);
        }
        Stream.close(client_fd);
        Process.exit();
        return 0;
    }
}

module Main {
    fn main() -> int {
        match Tcp.listen("127.0.0.1", 8080) {
            :ok{listener} => {
                i: int = 0;
                while i < 100000 {
                    match Tcp.accept(listener) {
                        :ok{client_fd} => {
                            handler: int = spawn ConnectionHandler();
                            tell handler.Handle(client_fd, i);
                        }
                        :error{e} => { i = i; }
                    }
                    i = i + 1;
                }
            }
            :error{e} => println("Listen failed");
        }
        return 0;
    }
}
```

## Built-in Modules

| Module | Functions |
|--------|-----------|
| **Tcp** | open, listen, accept, port |
| **Http** | parse_request, req_method, req_path, req_body, req_header, respond |
| **Json** | parse (typed struct), get_string, get_int, get_bool, get_object, build_object, build_end |
| **Stream** | write, write_line, read_line, read_bytes, read_all, close |
| **Math** | abs, min, max, clamp, pow, sqrt, log2, floor, ceil, round, sin, cos, tan |
| **Convert** | to_string, to_int, to_float, float_to_string, string_to_float |
| **String** | len, contains, starts_with, ends_with, trim, replace, split, slice, byte_at, char_at |
| **Env** | get |
| **System** | exit, time_ms |
| **File** | open |
| **Stdio** | out, err, in |

## Project Structure

```
verve/
├── build.zig                # Zig build config
├── LANGUAGE.md              # Complete language reference
├── BACKLOG.md               # Development backlog
├── ROADMAP.md               # Full-stack vision
├── src/
│   ├── main.zig             # CLI: build, check, test, fmt
│   ├── ast.zig              # AST node types
│   ├── parser.zig           # Recursive descent parser
│   ├── checker.zig          # Type checker
│   ├── ir.zig               # Target-independent SSA IR
│   ├── lower.zig            # AST → IR lowering
│   ├── zig_backend.zig      # IR → Zig source code generation
│   ├── verve_runtime.zig    # Compiled runtime (processes, TCP, HTTP, JSON, arena allocator)
│   ├── formatter.zig        # Code formatter
│   └── verifier.zig         # @example and @property test runner
└── examples/
    ├── http_server.vv       # Process-per-connection HTTP server
    ├── tcp_echo.vv          # TCP echo server
    ├── counter.vv           # Process state + message passing
    ├── supervisor.vv        # Process supervision with watch
    └── bench_messages.vv    # Message throughput benchmark
```

## Status

Native compiler with TCP networking, HTTP server, JSON parsing (scanning + typed struct), per-process arena allocator, overflow-safe arithmetic with poison values. Process model supports spawn-per-connection with automatic cleanup. 482 tests.

See [BACKLOG.md](BACKLOG.md) for detailed progress. See [ROADMAP.md](ROADMAP.md) for the full-stack vision.

## License

MIT — see [LICENSE](LICENSE).
