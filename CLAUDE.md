# Verve

Process-oriented language with no exceptions, no recursion, no implicit nulls. Written in Zig 0.15. Native compiler via Zig backend.

## Before every commit

1. Run `zig fmt` on all changed files: `/home/jt/.local/zig/zig fmt src/file.zig`
2. Build: `/home/jt/.local/zig/zig build`
3. All tests pass: `/home/jt/.local/zig/zig build test`

Do NOT commit code that fails any of these steps.

## Quick reference

See `LANGUAGE.md` for complete syntax, built-in modules, and API reference.

## Project structure

### Frontend (shared)
- `src/parser.zig` — hand-written recursive descent parser
- `src/ast.zig` — AST node definitions
- `src/checker.zig` — type checker (types, signatures, returns, assignments, built-ins, exhaustiveness, recursion)
- `src/verifier.zig` — @example, @property, and test block runner
- `src/formatter.zig` — canonical code formatter
- `src/loader.zig` — multi-file import resolver

### Compiler (verve build)
- `src/ir.zig` — target-independent SSA intermediate representation
- `src/lower.zig` — lowers AST to IR
- `src/zig_backend.zig` — emits Zig source from IR, compiles via zig build-exe

### Runtime (`src/runtime/`) — compiled into every Verve binary
- `runtime.zig` — core: Arena allocator, List, Tagged values, init, env, system
- `math.zig` — pure math: abs, sin, pow, floor, sqrt, etc.
- `checked.zig` — compiler internals: poison values, checked arithmetic, comparisons
- `convert.zig` — type conversions: int↔string, float↔string, int↔float
- `string.zig` — string ops: trim, replace, split, contains, concat
- `json.zig` — JSON scanning + builder
- `io.zig` — streams, files, stdio output
- `tcp.zig` — TCP: open, listen, accept
- `http.zig` — HTTP: parse requests, build responses
- `process.zig` — process table, mailbox, send/tell/drain

### CLI
- `src/main.zig` — CLI entry point (build, check, test, fmt, run)

### Examples
- `examples/http_server.vv` — process-per-connection HTTP server
- `examples/tcp_echo.vv` — TCP echo server
- `examples/counter.vv` — process state + message passing
- `examples/bench_messages.vv` — message throughput benchmark

## Build and test

```
/home/jt/.local/zig/zig build              # build
/home/jt/.local/zig/zig build test         # run fast tests (~14s)
/home/jt/.local/zig/zig build test-slow    # run slow tests (TCP/HTTP, ~2 min)
./zig-out/bin/verve run file.vv            # compile and run
./zig-out/bin/verve build file.vv          # compile to native binary
./zig-out/bin/verve check file.vv          # type check
./zig-out/bin/verve test file.vv           # run @example and test blocks
./zig-out/bin/verve fmt file.vv            # format in place
```

## Key design decisions

- Strings are `[]const u8` (Zig slices) in generated code — true fat pointers, no strlen
- Floats are native `f64` registers; bools are native `bool` registers
- Registers are fully typed: the backend tracks `RegType = { int, float, boolean, string }` per register
- Struct fields stored as `[N]i64` with boundary conversion (f64 via @bitCast, string via ptr+len pairs, bool via 0/1)
- Process messages use a binary protocol: `[handler_id:u8][param_count:u8][type:u8][value...]...` — self-describing, clustering-ready
- Process mailbox is a 64KB byte ring buffer (variable-size messages)
- IO uses opaque `stream` values. Stdio/File return streams, Stream module operates on them
- Doc comments (`///`) required on all exported modules, processes, and functions
- No recursion — enforced by call graph cycle detection. Use while loops with explicit stacks
- Poison values instead of exceptions for arithmetic errors — propagate through operations
- Processes communicate via send (returns Result) and tell (fire-and-forget)
- Process state is an explicit struct with type parameter: `process Counter<CounterState>`
- Handlers receive state as first param: `receive Increment(state: CounterState) -> int`
- State mutation via field assignment: `state.count = state.count + 1;` (no transition keyword)
- All struct fields require default values — no implicit zero-initialization
- Compiler pipeline: AST → IR (target-independent) → Zig backend → native binary
