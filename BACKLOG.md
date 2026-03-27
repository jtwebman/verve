# Verve Backlog

## Phase 1 — Parser & Language Foundation ✅

- [x] Recursive descent parser (types, structs, functions, modules, processes, guards, match, while, imports, exports)
- [x] Parser error messages with line/col
- [x] String operations, interpolation, indexing, pattern matching
- [x] Stream-based IO (Stdio, File, Stream)
- [x] Collection types (list, map, set, stack, queue)
- [x] Doc comments, `@example`/`@property` parsing
- [x] Self-hosting tokenizer (parser.vv)

## Phase 1.5 — Formatter ✅

- [x] `verve fmt` — canonical formatting, tabs, 120 char lines

## Phase 2 — Type Checker (121 tests)

### Done
- [x] Full type checking: signatures, returns, assignments, built-ins, exhaustiveness, recursion detection
- [x] Process state: `process<StateStruct>`, handlers receive state as first param, `state.field = expr`
- [x] Error messages with module/function/variable context

### Remaining
- [ ] Compile-time generics (monomorphization)
- [ ] Constrained types (range, precision, min/max)
- [ ] Result<T> type checking on send wrapping

## Phase 3 — Testing

### Done
- [x] `test "name" { assert expr; }` blocks — compile to native, run via `verve test`
- [x] `@example` doc comment tests — compile to assert, run alongside test blocks
- [x] Poison value warnings (literal division by zero at compile time)
- [x] Guard consistency checks

### Remaining
- [ ] Invariant checking after receive handlers
- [x] Cross-module calls in test blocks (user modules take priority over built-ins)
- [ ] Property-based testing as a language feature (not doc comments)

## Phase 4 — Native Compilation (Zig backend)

### Done
- [x] IR (SSA-style) → Zig backend → native binary
- [x] Process runtime: bounded mailbox, send/tell split, ProcessDied, Process.exit()
- [x] Dynamic process table (grows by doubling, no fixed limit, slot recycling)
- [x] Spawn-per-connection (Elixir-style)
- [x] send_timeout IR plumbing (no syntax yet)
- [x] Runtime extracted to `verve_runtime.zig` (real Zig, not string emission)
- [x] Float IR instructions (add_f64, sub_f64, etc.) for future backends
- [x] `verve run` = compile + execute (no interpreter)

### Remaining
- [ ] Multi-threaded scheduler
- [ ] Send timeout language syntax

### Process improvements (planned)
- [ ] Process worker pool — `ProcessPool.create(Handler, size)`, `pool.fetch()`, `pool.release()`
- [ ] `tell` handlers with `-> void` return type
- [ ] Per-process memory budgets from `memory` declaration
- [ ] Idle-thread GC on dormant processes

## Phase 4.5 — Foundation (runtime correctness)

### Done
- [x] String `+` concatenation in compiled code
- [x] String escape processing in parser
- [x] Per-process arena allocator (64KB pages, frees on process death)
- [x] Checked arithmetic: overflow → `:overflow`, div-zero → `:div_zero`, poison propagation

### Remaining
- [ ] Fully eliminate strlen — 2 fallback sites remain for unknown-source strings

### Done (this session)
- [x] Poison-safe comparisons: all int comparisons return false if either operand is poison
- [x] Float infinity/NaN → poison (float_check after division)
- [x] Fix List stack-escape bug (list_new allocates in arena, not stack)
- [x] String builtins: contains, starts_with, ends_with, trim, replace, split, char_at, char_len, chars
- [x] Cross-module calls in test blocks
- [x] println/print → Stdio.println/Stdio.print (module function, not magic global)
- [x] @example doc comment tests compile to native

## Phase 5 — Standard Library & IO

### Done
- [x] Tcp (open, listen, accept, port) — 12 tests
- [x] Http (parse_request, req_method/path/body/header, respond) — lazy parsing, size limits, Date header
- [x] Json — scanning API + typed struct parsing (`Json.parse(data, MyStruct)`) + builder
- [x] Stream (write, write_line, read_line, read_bytes, read_all, close — file + tcp)
- [x] Math — int (abs, min, max, clamp, pow, sqrt, log2) + float (floor, ceil, round, sin, cos, tan, sqrt_f, pow_f, log, log10, exp)
- [x] Convert (to_string, to_int, to_float, to_int_f, float_to_string, string_to_float)
- [x] Env (get), System (exit, time_ms), Process (exit)
- [x] SIGPIPE handling

### Remaining
- [ ] IO — Udp, Timer, Signal
- [ ] Tcp.shutdown (half-close)
- [ ] Http — keep-alive, chunked encoding, form/multipart parsing
- [ ] Json — typed struct stringify (`Json.stringify(my_struct)`)
- [ ] module Bytes, Time, Uuid, Base64, Hex, Hash, Sort, Dns

## Phase 6 — Project Index (`verve index`)

AI-optimized codebase navigation. Binary index with O(1) symbol lookup.
- [ ] Symbol table, cross-references, call graph
- [ ] CLI: `verve index .`, `--query`, `--format text`

## Phase 7 — Package Management

Signed source-code packages for AI-auditable dependencies.
- [ ] `verve.pkg`, `verve.trust`, download, verify, publish

## Phase 8 — FFI, Cross-compilation & Clustering

- [ ] C FFI with process isolation
- [ ] arm64 / macOS / cross-compilation (depends on FFI)
- [ ] Clustering: message serialization, distributed ProcessDied

## Adoption Prerequisites

Research-backed (Meyerovich-Rabkin OOPSLA 2013):
- [ ] LSP — editor support (non-negotiable for adoption)
- [ ] Package manager (Cargo model)
- [ ] Excellent error messages (Rust-quality)
- [ ] WASM compilation target
- [ ] Killer demo: HTTP API framework, AI agent orchestrator, or chat server
- [ ] vervelang.org website

## Future

- [ ] GPU backend (SPIR-V)
- [ ] LLVM backend
- [ ] Self-hosting compiler
