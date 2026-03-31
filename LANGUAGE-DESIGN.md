# Verve Language Design

A process-oriented compiled language designed for AI to write and humans to audit.

## Philosophy

- **AI writes it, humans verify it** — the language is optimized for machine authorship and human auditability. Explicit types, no exceptions, no hidden behavior.
- **One way to do things** — no style debates, every problem has one idiomatic solution
- **Verbose is fine** — explicitness helps verification, AI doesn't care about boilerplate
- **Docs are code** — `@example` annotations are tests, doc comments are required on exports
- **Processes are the unit of concurrency** — no shared mutable state, message passing only

## Syntax

C/JavaScript style. Curly braces, semicolons. Chosen because AI training data contains more of this syntax than any other.

## Core Design Decisions

### Types are explicit, always

Every variable declaration must have a type annotation. No type inference on declarations.

```verve
x: int = 42;
name: string = "alice";
items: list<int> = list();
```

### Errors are values, not exceptions

Functions return `Result<T>` for fallible operations. No try/catch, no throw. Match forces exhaustive handling.

```verve
match File.open("config.json", "r") {
    :ok{stream} => { ... }
    :error{reason} => { ... }
}
```

### Processes own state

State lives inside processes, accessed via explicit struct parameters. No global mutable state. Processes communicate via `send` (synchronous, returns Result) and `tell` (fire-and-forget).

```verve
struct CounterState {
    count: int = 0;
}

process Counter<CounterState> {
    receive Increment(state: CounterState) -> int {
        state.count = state.count + 1;
        return state.count;
    }
}
```

### Arithmetic is overflow-safe

Integer overflow produces `:overflow` poison values that propagate through all operations. Division by zero produces `:div_zero`. No silent wrapping.

### No recursion

The compiler rejects call graph cycles. Use while loops with explicit stacks. This makes call depth predictable and stack overflow impossible.

### No implicit null

Optional types (`T?`) are explicit. `none` is a value keyword, not a type. A non-optional value is never absent.

### Strings are fat pointers

Strings carry both pointer and length. No null-terminated C strings. String concatenation with `+` works natively.

### Per-process memory

Each process has its own arena allocator. When a process exits, its entire arena is freed in one operation. No garbage collector needed for short-lived processes.

## Compilation

Verve source → AST → typed IR (SSA) → Zig source → native binary.

The compiler generates Zig code that links against `verve_runtime.zig` — a real Zig source file containing the process scheduler, mailbox, TCP/HTTP/JSON runtime, and arena allocator. The Zig compiler handles optimization and native code generation.

## Process Model

Based on Erlang/BEAM but simpler:

- **Spawn**: `handler: pid<ConnectionHandler> = spawn ConnectionHandler();` — creates a lightweight process
- **Send**: `match counter.Increment() { :ok{v} => ... }` — synchronous, returns Result
- **Tell**: `tell handler.Handle(fd, n);` — fire-and-forget, process executes asynchronously
- **Exit**: `Process.exit();` — handler self-terminates, slot recycled
- **Watch**: `watch worker;` — get `ProcessDied` notification when watched process dies
- **Bounded mailbox**: ring buffer with backpressure. `send` returns `:error` when full, `tell` drops silently

## What Verve Does NOT Have

- No exceptions (use Result and poison values)
- No implicit null (use optional T?)
- No recursion (use while loops)
- No inheritance (use structs and modules)
- No operator overloading
- No macros
- No implicit type conversions
- No global mutable state
- No garbage collector (per-process arenas)
