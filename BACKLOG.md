# Verve Backlog

## Phase 1 — Parser & Interpreter ✅

- [x] Set up Zig project structure
- [x] Hand-written recursive descent parser (no separate lexer, no parser generator)
  - [x] Types, structs, unions, enums
  - [x] Functions, guards, match, while
  - [x] Modules, imports (use)
  - [x] Processes, receive handlers, state, transitions
  - [x] spawn keyword
  - [x] Doc comments
  - [x] Compile-time generics (parser only, type params)
  - [x] Function type expressions: fn(T, T) -> T
  - [x] Tagged unions
  - [x] Optional types (T?)
- [x] Parser error messages with line/col and clear context (42 tests)
- [x] Reserved word detection
- [x] Double semicolon detection
- [x] Tree-walk interpreter — basic expressions, math, strings
- [x] Interpreter — match, while, guards, if/else with chaining
- [x] Interpreter — module functions, cross-module calls
- [x] Interpreter — process scheduler (single-threaded, synchronous)
- [x] Interpreter — send messaging (synchronous, returns Result<T>)
- [x] Interpreter — spawn processes with state initialization
- [x] Interpreter — state transitions (deprecated — now field assignment)
- [x] Interpreter — poison values (overflow, div_zero, out_of_bounds)
- [x] Interpreter — guard failure returns :error{:guard_failed}
- [x] CLI — `verve run file.vv`
- [x] CLI — `verve check file.vv`
- [x] Import system — `import "./file.vv";`
- [x] Export system — `export module`, `export process`, `export struct`, `export type`
- [x] Loader — recursive import resolution, circular import detection
- [x] Non-exported declarations hidden from importers
- [x] Multi-file example working (math.vv + multi.vv)
- [x] Entry point: fn main() in any module or process
- [x] tell statement execution (fire-and-forget)
- [x] watch statement (registers watcher for ProcessDied)
- [x] receive; statement (processes one message from mailbox)
- [x] append statement execution
- [x] list, map, set, stack, queue value types with operations
- [x] Pass command line args to main() as list<string>
- [x] @example and @property parsing and extraction
- [x] Struct literal creation and field access in interpreter
- [x] String operations — split, contains, starts_with, ends_with, trim, replace, slice, byte_at, char_at, chars, is_alpha, is_digit, is_whitespace, is_alnum
- [x] String interpolation — `${expr}` syntax
- [x] String indexing — `s[i]` returns single-byte string
- [x] String pattern matching in match arms
- [x] Stream-based IO — Stdio (out/err/in), File (open), Stream (write/write_line/read_line/read_all/close)
- [x] Module-level constants — frozen after initialization, collections deeply immutable
- [x] Collection initializers — `list(1, 2, 3)`, `set("a", "b")`, `map("k", v)`
- [x] `break` and `continue` in while loops
- [x] `&&` and `||` logical operators with correct precedence
- [x] Doc comment enforcement — required on exported modules, processes, and functions
- [x] Self-hosting tokenizer — parser.vv tokenizes and parses Verve source in Verve

## Phase 1.5 — Formatter ✅

- [x] AST pretty printer (canonical output from parsed AST)
- [x] Tabs for indentation, non-configurable
- [x] One space around binary operators, one space after commas
- [x] One blank line between functions/handlers
- [x] Opening brace on same line
- [x] CLI — `verve fmt file.vv` (format in place)
- [x] CLI — `verve fmt --check file.vv` (fail if not formatted, for CI)
- [x] Max 120 chars per line, wrap params one-per-line

## Phase 2 — Type Checker (122 tests)

### Done

- [x] Undefined variable detection
- [x] Unknown type detection (struct fields, params, return types, generics)
- [x] Guards/while/if/assert must be boolean expressions
- [x] receive; only in processes
- [x] Duplicate struct field detection
- [x] Empty match detection
- [x] Entry point validation (exactly one main(), skipped for library files with exports)
- [x] Multiple errors reported in one pass
- [x] Built-in types and functions recognized
- [x] Sibling functions and module constants in scope
- [x] Explicit types on all variable declarations
- [x] Type checking — function signatures, return types, assignments
- [x] Type checking — match exhaustiveness (booleans, enums, Result ok+error, wildcard required)
- [x] Type checking — send/tell only on process values
- [x] Type checking — tell handler arg count and types (skips injected state param)
- [x] Type checking — function references match signatures
- [x] Type inference — literals, binary/unary ops, calls, field access, index access, built-in modules
- [x] Type checking — built-in function return types (String, Map, Set, Stack, Queue, Stream, Stdio)
- [x] Type checking — struct field access types
- [x] Type checking — collection index types (list<T>[i] → T, map<K,V>[k] → V, string[i] → string)
- [x] Type checking — string concatenation via + operator
- [x] Type checking — type alias resolution in assignments
- [x] && and || require bool operands — no implicit truthiness
- [x] Generic types require type parameters (no bare list/map/set/stack/queue)
- [x] All struct fields require default values — no implicit zero-initialization
- [x] Process state is explicit struct with type parameter: `process Name<StateStruct>`
- [x] Handlers receive state as first param: `receive Handler(state: StateType, ...) -> T`
- [x] State mutation via field assignment: `state.field = expr;`
- [x] Frozen collection mutation gives clear "cannot mutate constant" error
- [x] Fail fast everywhere — no silent error swallowing, IO panics on write failure
- [x] Call graph cycle detection (no recursion — direct, mutual, cross-module)
- [x] Error messages include module.function context, variable names, parameter names

### Remaining

- [ ] Type checking — compile-time generics (monomorphization)
- [ ] Type checking — constrained types (range, precision, min/max) — parser support needed
- [ ] Type checking — Result<T> and send wrapping
- [ ] Remove old `state {}` block and `transition` keyword from parser (deprecated, still parses for compiler backward compat)

## Phase 3 — Verifier

### Done

- [x] @example — parse from doc comments, run as tests, compare results
- [x] Verifier signals — VALID, INVALID(reason), INCOMPLETE
- [x] CLI — `verve test file.vv`
- [x] @property — fuzz testing with 100 random inputs per property, deterministic seed
- [x] Poison value warnings (literal division by zero detected at compile time)
- [x] Guard consistency checks (always-false, self-comparison)
- [x] DIVERGENT signal (while true with no return detected)

### Remaining

- [ ] Invariant checking after receive handlers
- [ ] Real test blocks — `test "name" { ... }` in addition to @example

## Phase 4 — Native Compilation (Zig backend)

### Done

- [x] Design Verve IR (target-agnostic, SSA-style)
- [x] Lower typed AST to Verve IR
- [x] Zig backend — emits Zig source from IR, compiles via zig build-exe
- [x] CLI — `verve build file.vv`
- [x] Process runtime — spawn/watch/ProcessDied (cooperative single-threaded)
- [x] Process runtime — pre-allocated state memory

### Remaining

- [x] Compiler support for new process<StateStruct> syntax (lowerer + backend)
- [x] Compiler support for field_assign (state.field = expr)
- [ ] Process runtime — multi-threaded scheduler
- [x] Process runtime — bounded mailbox (ring buffer, capacity 64, backpressure via Result)
- [x] Process runtime — send/tell split (tell drops silently on full, send returns :error)
- [x] Process runtime — ProcessDied notification via mailbox (verve_kill)
- [x] Process runtime — send_timeout IR instruction + runtime plumbing (no syntax yet)
- [ ] Process runtime — send timeout language syntax
- [ ] Process runtime — multi-threaded scheduler
- [x] Benchmark: message passing throughput (examples/bench_messages.vv)

## Phase 4.5 — Foundation Refactor (runtime correctness)

### Fat Strings
- [ ] String representation: fat pointers (ptr, len) everywhere, eliminate strlen
- [ ] String concatenation with `+` in compiled code
- [ ] stream_read_line returns (ptr, len) not null-terminated
- [ ] int_to_string / float_to_string return (ptr, len)
- [ ] String.len uses tracked length, never scans
- [ ] Remove `-1 marker` pattern in println — track types properly

### Per-Process Arena Allocator
- [ ] ProcessArena: bump allocator with page-based growth
- [ ] Route all runtime allocations through process-local arena
- [ ] Global arena for non-process (module main) code
- [ ] Process death frees entire arena (verve_kill → arena.freeAll)
- [ ] Fix List stack-escape bug (list_new stores pointer to stack local)

### Overflow → Poison Values (spec compliance)
- [ ] Checked arithmetic: add, sub, mul detect overflow → `:overflow`
- [ ] Division by zero → `:div_zero`
- [ ] Poison propagation: any op on poison returns poison
- [ ] Poison in comparisons: poison is not equal to anything

### Future (needs multi-threaded scheduler)
- [ ] Idle-thread GC: scan dormant processes, compact arenas
- [ ] Per-process memory limits (from memory budget in process declaration)
- [ ] NaN-boxing or tagged value representation (revisit when adding REPL/debugger)

## Phase 5 — Standard Library & IO

### Done

- [x] IO — File (open, read, write via streams)
- [x] IO — Stdio (out, err, in via streams)
- [x] module String (len, contains, starts_with, ends_with, trim, replace, split, slice, byte_at, char_at, char_len, chars, is_alpha, is_digit, is_whitespace, is_alnum)
- [x] IO — Tcp (open, listen, accept, port — returns Result<stream>, 12 compile tests)
- [x] IO — Stream (write, write_line, read_line, read_all, close — works for both file and tcp)
- [x] SIGPIPE handling in runtime (write to closed socket returns error, not process death)

### Remaining — IO

- [ ] IO — Udp
- [ ] IO — Timer
- [ ] IO — Signal

### Remaining — Tcp hardening (needs multi-threaded runtime or shutdown support)

- [ ] Tcp test: half-close (shutdown write, peer still reads)
- [ ] Tcp test: shutdown pending (large data + shutdown flushes all bytes)
- [ ] Tcp test: concurrent accept (multiple acceptors on same listener)
- [ ] Tcp.shutdown(stream, :write) — half-close support

### Done — Standard modules

- [x] module Math (abs, min, max, clamp, pow, sqrt, log2)
- [x] module Env (get)
- [x] module System (exit, time_ms)
- [x] module Convert (to_string, to_int)

### Remaining — Standard modules

- [ ] module Bytes
- [ ] module Time
- [ ] module Uuid
- [ ] module Json (with struct mapping)
- [ ] module Base64
- [ ] module Hex
- [ ] module Hash
- [ ] module Sort
- [ ] module TextParser
- [ ] module BinaryParser
- [ ] module Dns

### Remaining — Utilities

- [ ] Collection copy — `List.copy`, `Map.copy`, etc. (shallow copy, returns mutable)
- [ ] `verve doc` CLI — generate reference docs from doc comments

## Phase 6 — Project Index (`verve index`)

Binary index format designed for AI assistants to navigate Verve codebases without reading source files. One tool call to understand an entire project. Replaces file-grepping with O(1) symbol lookup.

### Index format (`.verve/index.vvx`)

Binary file with four sections, each with offset tables for direct seeking:

1. **Header** — version, file count, symbol count, checksum
2. **String table** — deduplicated pool of all names, paths, doc comments, type signatures
3. **Symbol table** — fixed-size records, one per declaration:
   - Kind: struct | module | process | function | type | constant | handler
   - Name (string table offset)
   - File path + line number
   - Doc comment (string table offset)
   - Type signature (string table offset, e.g. `(int, int) -> int`)
   - Parent symbol (for handlers inside processes, functions inside modules)
   - Visibility: exported | internal
4. **Cross-reference table** — variable-length adjacency lists:
   - Call graph: function → functions it calls
   - Import graph: file → files it imports
   - Type usage: type → symbols that reference it
   - Handler map: process → its receive handlers

### CLI

- [ ] `verve index .` — build index from all `.vv` files in directory tree
- [ ] `verve index --format text` — emit human/AI-readable text instead of binary
- [ ] `verve index --query symbols` — list all symbols with signatures
- [ ] `verve index --query <name>` — lookup one symbol: signature, doc, location, callers/callees
- [ ] `verve index --query callgraph` — full call graph
- [ ] `verve index --query imports` — import graph
- [ ] `verve index --query types` — all type definitions and who uses them
- [ ] `verve index --diff` — incremental update, only re-index changed files (by mtime)

### Text format (for `--format text` and small projects)

```
[struct] CounterState counter.vv:1
  count: int = 0

[process] Counter<CounterState> counter.vv:7
  /// A counter that tracks a running total.
  receive Increment(amount: int) -> int
  receive Reset() -> void

[module] Math math.vv:1 (export)
  /// Math utilities.
  fn add(a: int, b: int) -> int
  fn multiply(a: int, b: int) -> int

[calls] main -> Math.add, Counter.Increment
[imports] main.vv -> math.vv, counter.vv
```

### Implementation

- [ ] Walk typed AST after checker pass, collect all declarations
- [ ] Build string table with deduplication
- [ ] Build symbol table with parent references
- [ ] Build cross-reference table from call graph (already computed for recursion detection)
- [ ] Binary serializer with offset tables
- [ ] Text serializer (line-oriented, grep-friendly)
- [ ] File watcher / mtime-based incremental rebuild
- [ ] Integration: `verve build` and `verve check` auto-rebuild stale index

## Phase 7 — Package Management

Libraries ship as signed source code (not binaries) — enables tree shaking, AI audit, and modification.

- [ ] `verve.pkg` parser
- [ ] `verve.trust` parser (trusted signers)
- [ ] Package download (HTTP GET static files)
- [ ] Signature verification (ed25519)
- [ ] Hash verification (sha256)
- [ ] Multiple version coexistence
- [ ] CLI — `verve publish`
- [ ] CLI — `verve cache sync`

## Phase 8 — FFI, Cross-compilation & Clustering

### FFI

- [ ] FFI — `ffi` block parsing
- [ ] FFI — process isolation for foreign calls
- [ ] FFI — C library linking

### Cross-compilation (depends on FFI for foreign library linking)

- [ ] arm64 instruction selection
- [ ] Mach-O binary emission (macOS)
- [ ] Cross-compilation support (build arm64 on x86_64 and vice versa)

### Clustering
- [ ] Clustering — message serialization across network
- [ ] Clustering — ProcessDied across network boundaries

## Future

- [ ] WASM backend
- [ ] GPU backend (SPIR-V)
- [ ] LLVM backend (optional, for maximum optimization)
- [ ] Self-hosting — rewrite compiler in Verve
- [ ] vervelang.org website
- [ ] Package discovery site
- [ ] Language server protocol (LSP) for editor support
- [ ] Memory-mapped file support
