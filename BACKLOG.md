# Verve Backlog

## Phase 1 — Parser & Interpreter (get the language running)

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
- [x] Parser error messages with line/col and clear context (40 tests)
- [x] Reserved word detection
- [x] Double semicolon detection
- [x] Tree-walk interpreter — basic expressions, math, strings
- [x] Interpreter — match, while, guards
- [x] Interpreter — module functions, cross-module calls
- [x] Interpreter — process scheduler (single-threaded, synchronous)
- [x] Interpreter — send messaging (synchronous, returns Result<T>)
- [x] Interpreter — spawn processes with state initialization
- [x] Interpreter — state transitions
- [x] Interpreter — poison values (overflow, div_zero, out_of_bounds)
- [x] Interpreter — guard failure returns :error{:guard_failed}
- [x] CLI — `verve run file.vv`
- [x] CLI — `verve check file.vv`
- [x] First program: hello world
- [x] Second program: process with state (counter)
- [x] Import system — `import "./file.vv";`
- [x] Export system — `export module`, `export process`, `export struct`, `export type`
- [x] Loader — recursive import resolution, circular import detection
- [x] Non-exported declarations hidden from importers
- [x] Multi-file example working (math.vv + multi.vv)
- [x] Entry point: fn main() in any module or process
- [x] tell statement execution (fire-and-forget — handler runs, result ignored)
- [x] watch statement (registers watcher for ProcessDied)
- [x] receive; statement (processes one message from mailbox)
- [x] spawn keyword in parser
- [x] append statement execution
- [x] list and map value types in interpreter (mutable, with .len, index, append)
- [x] Pass command line args to main() as list<string>
- [ ] @example parsing and extraction
- [ ] @property parsing and extraction
- [x] Struct literal creation and field access in interpreter

## Phase 1.5 — Formatter

- [ ] AST pretty printer (canonical output from parsed AST)
- [ ] Tabs for indentation, non-configurable
- [ ] One space around binary operators
- [ ] One space after commas
- [ ] No trailing whitespace
- [ ] One blank line between functions/handlers
- [ ] No double blank lines
- [ ] Opening brace on same line
- [ ] Max 120 chars per line, wrap params/args
- [ ] CLI — `verve fmt file.vv` (format in place)
- [ ] CLI — `verve fmt --check file.vv` (fail if not formatted)

## Phase 2 — Type Checker

- [ ] Type inference for local variables
- [ ] Type checking — structs, unions, enums
- [ ] Type checking — function signatures, return types, void
- [ ] Type checking — compile-time generics (monomorphization)
- [ ] Type checking — guards are boolean expressions only
- [ ] Type checking — match exhaustiveness
- [ ] Type checking — send/tell only on processes, not modules
- [ ] Type checking — transitions only in receive handlers
- [ ] Type checking — process state capacity declarations
- [ ] Type checking — constrained types (range, precision, min/max)
- [ ] Type checking — built-in types (email, uri, uuid, etc.)
- [ ] Type checking — Result<T> and send wrapping
- [ ] Type checking — function references match signatures
- [ ] Call graph cycle detection (no recursion)

## Phase 3 — Verifier

- [ ] @example — compile and run as tests
- [ ] @property — fuzz testing with random inputs
- [ ] Invariant checking after receive handlers
- [ ] Poison value coverage warnings
- [ ] Guard consistency checks
- [ ] Verifier signals — VALID, INVALID(reason), INCOMPLETE, DIVERGENT
- [ ] CLI — `verve check file.vv` (enhanced with verifier)

## Phase 4 — Native Compilation (x86_64)

- [ ] Design Verve IR (target-agnostic, SSA-style)
- [ ] Lower typed AST to Verve IR
- [ ] x86_64 instruction selection
- [ ] Register allocator
- [ ] ELF binary emission (Linux)
- [ ] Process runtime — multi-threaded scheduler
- [ ] Process runtime — message queues with fixed capacity
- [ ] Process runtime — spawn/watch/ProcessDied
- [ ] Process runtime — send with actual timeout
- [ ] Process runtime — pre-allocated state memory
- [ ] CLI — `verve build file.vv`
- [ ] Benchmark: message passing throughput

## Phase 5 — arm64 & Cross-compilation

- [ ] arm64 instruction selection
- [ ] Mach-O binary emission (macOS)
- [ ] Cross-compilation support (build arm64 on x86_64 and vice versa)

## Phase 6 — Standard Library & IO

- [ ] IO process — Tcp
- [ ] IO process — Udp
- [ ] IO process — File
- [ ] IO process — Timer
- [ ] IO process — Stdio
- [ ] IO process — Signal
- [ ] module String
- [ ] module Bytes
- [ ] module Math
- [ ] module Time
- [ ] module Uuid
- [ ] module Json (with struct mapping)
- [ ] module Base64
- [ ] module Hex
- [ ] module Hash
- [ ] module Sort
- [ ] module TextParser
- [ ] module BinaryParser
- [ ] module Env
- [ ] module Args
- [ ] module System
- [ ] module Dns

## Phase 7 — Package Management

- [ ] `verve.pkg` parser
- [ ] `verve.trust` parser
- [ ] Package download (HTTP GET static files)
- [ ] Signature verification (ed25519)
- [ ] Hash verification (sha256)
- [ ] Multiple version coexistence
- [ ] CLI — `verve publish`
- [ ] CLI — `verve cache sync`

## Phase 8 — FFI & Clustering

- [ ] FFI — `ffi` block parsing
- [ ] FFI — process isolation for foreign calls
- [ ] FFI — C library linking
- [ ] Clustering — `connect` with TLS
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
