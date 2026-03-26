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
- `src/verve_runtime.zig` — compiled runtime (processes, TCP, HTTP, JSON, arena allocator)

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
/home/jt/.local/zig/zig build test         # run all tests
./zig-out/bin/verve run file.vv            # compile and run
./zig-out/bin/verve build file.vv          # compile to native binary
./zig-out/bin/verve check file.vv          # type check
./zig-out/bin/verve test file.vv           # run @example and test blocks
./zig-out/bin/verve fmt file.vv            # format in place
```

## Key design decisions

- Strings are UTF-8 byte sequences stored as (ptr, len) fat pointers in compiled code
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
