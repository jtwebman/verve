# Verve Backlog

## Completed ✅

Parser, formatter, type checker (121 tests), native compiler via Zig backend, per-process arena allocator, bounded mailbox, dynamic process table, spawn-per-connection, poison-safe arithmetic (overflow, div-zero, infinity/NaN), string builtins, float arithmetic, test blocks + @example, interpreter removed (4,549 lines), old state{}/transition syntax removed.

Stdlib: Tcp, Http (lazy parsing, size limits), Json (scanning + typed struct parse + builder), Stream, Math (int + float), String (all operations), Convert, Env, System, Process, Stdio (println/print).

356 tests across parser (49), parser errors (42), checker (121), compile pipeline (144).

---

## Priority 1 — Language Completeness (before benchmark apps)

These are things LANGUAGE-DESIGN.md and LANGUAGE.md claim that don't fully work in the compiler.

### Type System Gaps
- [ ] Result<T> type checking — `send` returns Result but checker doesn't verify the inner type
- [ ] Compile-time generics (monomorphization) — `list<int>` parses but types aren't specialized
- [ ] Enum types in compiler — parser supports, lowerer/backend don't
- [ ] Tagged union types in compiler — parser supports, lowerer/backend don't
- [ ] Optional types (T?) in compiler — parser supports, no runtime representation

### Checker Gaps
- [ ] Doc comment enforcement in compiler (checker validates, but compiled code doesn't require them)
- [ ] Guard type checking in compiler (checker validates, but guards may not compile correctly for all types)
- [ ] Match exhaustiveness for enums in compiler

### String Gaps
- [ ] Fully eliminate strlen — 2 fallback sites remain for unknown-source strings
- [ ] String interpolation in compiler — `"hello ${name}"` syntax parses but doesn't compile

### Compiler Correctness
- [ ] Struct allocations still use page_allocator (should use arena)
- [ ] `verve check` should use the compiler pipeline, not just the checker
- [ ] Import/export system in compiler (multi-file programs)

## Priority 2 — Runtime for Concurrency Story

The benchmark apps need real concurrency to show Verve's advantage.

### Multi-threaded Scheduler
- [ ] Thread pool (N scheduler threads, one per core)
- [ ] Per-thread run queue with process migration
- [ ] Process affinity — each process runs on one thread at a time
- [ ] Proper locking on mailbox push (multi-producer)

### Process Improvements
- [ ] Send timeout language syntax — `match counter.Inc() timeout 5000 { ... }`
- [ ] Process worker pool — `ProcessPool.create(Handler, size)`, fetch/release
- [ ] `tell` handlers with `-> void` return type (no meaningless return 0)
- [ ] Per-process memory budgets from `memory` declaration
- [ ] Idle-thread GC — compact dormant process arenas on idle threads

## Priority 3 — Stdlib for Benchmark Apps

What's needed to build the 20 benchmark apps.

### Needed
- [ ] Http — keep-alive connections (reuse TCP, skip handshake per request)
- [ ] Http — chunked transfer encoding
- [ ] Http client (for API-to-API calls, webhook sending)
- [ ] Json — typed struct stringify (`Json.stringify(my_struct)`)
- [ ] Database driver (SQLite — single file, no server)
- [ ] Timer process (setTimeout/setInterval equivalent)
- [ ] module Time (timestamps, durations, formatting)
- [ ] module Uuid (v4 generation)
- [ ] module Base64 (encode/decode)
- [ ] module Hash (sha256, for auth tokens)

### Nice to Have
- [ ] IO — Udp, Signal
- [ ] Tcp.shutdown (half-close)
- [ ] Http — form/multipart parsing
- [ ] module Bytes, Hex, Sort, Dns

## Priority 4 — Tooling for Adoption

### Non-Negotiable (research-backed)
- [ ] LSP — editor support (go-to-definition, autocomplete, errors)
- [ ] Package manager (Cargo model — build + packages + tests)
- [ ] Excellent error messages (show code, point to problem, suggest fix)
- [ ] WASM compilation target

### Important
- [ ] Project index (`verve index`) — AI-optimized codebase navigation
- [ ] `verve doc` — generate reference docs from doc comments
- [ ] vervelang.org website

## Priority 5 — Future

- [ ] C FFI with process isolation
- [ ] arm64 / macOS / cross-compilation
- [ ] Clustering (distributed processes, network message passing)
- [ ] Property-based testing as language feature
- [ ] GPU backend (SPIR-V)
- [ ] LLVM backend
- [ ] Self-hosting compiler
