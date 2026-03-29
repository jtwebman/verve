# Verve Backlog

## Completed ✅

Parser, formatter, type checker (181 tests), native compiler via Zig backend, per-process arena allocator, bounded mailbox, dynamic process table, spawn-per-connection, poison-safe arithmetic (overflow, div-zero, infinity/NaN), string builtins, float arithmetic, test blocks + @example, interpreter removed (4,549 lines), old state{}/transition syntax removed.

Stdlib: Tcp, Http (lazy parsing, size limits), Json (scanning + typed struct parse + builder), Stream, Math (int + float), String (all operations), Convert, Env, System, Process, Stdio (println/print).

470+ tests across parser (49), parser errors (42), checker (181), IR (10), compile pipeline (156).

Typed IR + Zig slices: strings are []const u8, floats are f64, bools are native bool in generated Zig. Binary message protocol for process communication — self-describing byte sequences, ready for clustering.

Compiler correctness: error locations (line/col from AST spans), control flow return analysis, scope isolation (if/else/while/match), structured JSON error output (`--json`), IR-level tests.

---

## Priority 1 — Language Completeness (before benchmark apps)

These are things LANGUAGE-DESIGN.md and LANGUAGE.md claim that don't fully work in the compiler.

### Type System Gaps
- [x] Result<T> type checking — process sends infer Result<T>, pattern bindings typed, File/Tcp/Http return types
- [x] Compile-time generics (monomorphization) — struct Pair<T> monomorphized to Pair_int, Pair_string etc.
- [x] Enum types in compiler — real Zig enums, struct field boundaries, match support
- [x] Tagged union types in compiler — :tag{expr} construction, makeTagged runtime, string-aware extraction
- [x] Optional types (T?) in compiler — tagged values (some=0, none=1), match with :some{val}/none

### Checker Gaps
- [x] Doc comment enforcement in compiler — checker runs in build/run, errors are hard failures
- [x] Guard type checking in compiler — checker validates guards, now enforced in build/run
- [x] Match exhaustiveness for enums in compiler — checker runs in build/run, non-exhaustive is a compile error

### String Gaps
- [x] ~~Fully eliminate strlen~~ — strings are []const u8 slices everywhere, no strlen
- [x] String interpolation in compiler — lowerer converts parts via int/float/bool_to_string + string_concat

### Compiler Correctness
- [x] Struct allocations use arena — switched from page_allocator to rt.arena_alloc
- [x] `verve check` uses compiler pipeline — checker runs in build/run commands
- [x] Import/export system in compiler — Loader used by all commands (run/test/build/check)
- [x] Error locations — thread line/col from AST nodes through checker so every TypeError has a real source position
- [x] Control flow return analysis — verify all code paths in a function return a value (catch fall-off-end bugs in Verve, not downstream in Zig)
- [x] Scope isolation — variables declared in if/else/while/match bodies don't leak into outer scope
- [x] Structured error output — JSON error format (file/line/col/message) via `verve check --json`
- [x] IR-level tests — test lowering output directly so IR bugs surface as "invalid IR" not "Zig compilation failed"

## Priority 2 — Runtime for Concurrency Story

The benchmark apps need real concurrency to show Verve's advantage.

### Multi-threaded Scheduler
- [x] Thread pool (N scheduler threads, configurable via verve_scheduler_run_threaded)
- [x] Per-thread run queue (SchedulerThread with local_pids)
- [x] Process affinity — each process pinned to spawning thread, round-robin assignment
- [x] Proper locking on mailbox push (mutex per mailbox)
- [x] LIFO slot for message-passing cache locality (Tokio pattern)
- [x] Compile-time reduction counting (yield_check at loop back-edges, Lunatic/BEAM pattern)
- [x] Thread-safe process table (RwLock), atomic scheduler_running, threadlocal current_process_id

### Generics
- [x] Multi-type-parameter generics — `struct Pair<K, V>`, `struct Either<A, B>` (already works: parser, checker, lowerer all handle N params)

### Process Improvements
- [x] Mailbox overflow policy — configurable [mailbox: N] per process, error on full, tell returns Result<void>
- [x] Send timeout language syntax — `Process.send_timeout(counter.Inc, 5, 5000)`, explicit Process.send/tell/send_timeout API
- [ ] Process worker pool — `ProcessPool.create(Handler, size)`, fetch/release
- [x] `tell` handlers with `-> void` return type (no meaningless return 0)
- [ ] Per-process memory budgets from `memory` declaration
- [ ] Idle-thread GC — compact dormant process arenas on idle threads

## Priority 3 — Stdlib for Benchmark Apps

What's needed to build the 20 benchmark apps.

### Needed
- [x] Http — keep-alive connections (reuse TCP, skip handshake per request)
- [ ] Http — chunked transfer encoding
- [ ] Http client (for API-to-API calls, webhook sending)
- [ ] Json — typed struct stringify (`Json.stringify(my_struct)`)
- [ ] Database driver (SQLite — single file, no server)
- [ ] Timer process (setTimeout/setInterval equivalent)
- [ ] module Time (timestamps, durations, formatting)
- [ ] module Uuid (v4 generation)
- [ ] module Base64 (encode/decode)
- [ ] module Hash (sha256, for auth tokens)
- [ ] StringBuilder / Buffer type — avoid O(n²) string concat in loops, growable byte buffer

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

## Priority 5 — Future / Optimization

- [ ] Json — high-performance parser (SIMD/vectorized scanning, replace arena string-concat builder)
- [ ] C FFI with process isolation
- [ ] Portable fiber fallback — non-x86-64-linux platforms need a working scheduler (even if slower)
- [ ] arm64 / macOS / cross-compilation
- [ ] Clustering (distributed processes, network message passing)
- [ ] Property-based testing as language feature
- [ ] GPU backend (SPIR-V)
- [ ] LLVM backend
- [ ] Self-hosting compiler

## NEXT

Priority 1 complete. Pick from Priority 2 (concurrency), Priority 3 (stdlib for benchmarks), or Priority 4 (tooling).
