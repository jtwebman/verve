# Verve

A process-oriented language with no exceptions, no recursion, no nulls. Written in Zig. Built for AI to write, built for humans to trust.

- File extension: `.vv`
- License: MIT

## What is Verve?

Verve is an explicit programming language designed for AI-generated code. There is one way to do everything, no magic, no hidden behavior, and nothing for the AI to get tripped up on.

The language strips away the ambiguity that causes AI-generated code to fail — no exceptions, no null, no implicit conversions, no operator overloading, no inheritance, no macros. What's left is a small, strict set of constructs where AI can produce correct code reliably because there are fewer ways to be wrong.

## Key Design Decisions

- **One way to do things** — no style debates, every problem has one idiomatic solution
- **Modules and processes** — modules organize code, processes own state and communicate via typed messages
- **Guards, not exceptions** — preconditions are boolean expressions, failures return structured errors
- **Match, not if/else chains** — exhaustive branching, compiler checks all cases
- **While, not for** — one loop construct, explicit counter management
- **Poison values** — overflow, division by zero, and out-of-bounds propagate instead of crashing
- **No recursion** — call graph cycles are rejected at compile time, use while loops with explicit stacks
- **Explicit process boundaries** — `send` and `tell` keywords mark every cross-process call
- **Static type checking** — function signatures, return types, assignments, and built-in calls checked before runtime

## Direction

### Source-only libraries

Verve libraries ship as signed source code, not compiled binaries. This enables:

- **Tree shaking** — only compile what you actually call
- **Full auditability** — AI or humans can read and verify every line of library code
- **Modification** — patch or adapt library code for your project
- **Code signing** — ed25519 signatures prove provenance via `verve.trust`

### Native compilation

Verve compiles to native binaries via a Zig backend. The pipeline: AST to target-independent IR (SSA-style) to Zig source to native binary. Process runtime supports spawn, send, tell, state transitions, and watch/ProcessDied.

### AI-first tooling

The type checker produces error messages with enough context for AI to fix them automatically — module name, function name, variable name, expected vs actual types, and parameter names in call mismatches.

## Quick Start

Requires [Zig](https://ziglang.org) 0.15+.

```
zig build                                    # build
zig build test                               # run all tests
./zig-out/bin/verve run examples/hello.vv    # run a program
./zig-out/bin/verve check examples/hello.vv  # type check
./zig-out/bin/verve test examples/tested.vv  # run @example and @property tests
./zig-out/bin/verve fmt file.vv              # format in place
./zig-out/bin/verve build file.vv            # compile to native binary
```

## Example

```verve
struct CounterState {
    count: int = 0;
}

process Counter<CounterState> {
    receive Increment(state: CounterState) -> int {
        state.count = state.count + 1;
        return state.count;
    }

    receive GetCount(state: CounterState) -> int {
        return state.count;
    }
}

module Main {
    fn main() -> int {
        counter: int = spawn Counter();

        match counter.Increment() {
            :ok{val} => println("Count: ", val);
            :error{reason} => println("Error");
        }

        return 0;
    }
}
```

## Project Structure

```
verve/
├── build.zig                # Zig build config
├── LANGUAGE.md              # Complete language reference
├── BACKLOG.md               # Development roadmap and progress
├── editors/vscode/          # VS Code / Cursor syntax highlighting
├── examples/
│   ├── hello.vv             # Basic: math, loops, match, functions
│   ├── counter.vv           # Processes: spawn, send, state, transitions
│   ├── multi.vv             # Multi-file imports
│   ├── math.vv              # Exported module library
│   ├── lists.vv             # Lists: create, append, index, iterate
│   ├── supervisor.vv        # Process supervision with watch
│   ├── tested.vv            # @example and @property annotations
│   └── parser.vv            # Self-hosting tokenizer and parser
└── src/
    ├── main.zig             # CLI: run, build, check, test, fmt
    ├── ast.zig              # AST node types
    ├── parser.zig           # Hand-written recursive descent parser
    ├── value.zig            # Runtime value types with poison values
    ├── interpreter.zig      # Tree-walk interpreter
    ├── process.zig          # Process scheduler, mailbox, state
    ├── loader.zig           # Multi-file import/export resolver
    ├── checker.zig          # Type checker (118 tests)
    ├── formatter.zig        # Canonical code formatter
    ├── verifier.zig         # @example and @property test runner
    ├── ir.zig               # Target-independent SSA intermediate representation
    ├── lower.zig            # Lowers AST to IR
    └── zig_backend.zig      # Emits Zig source from IR, compiles via zig build-exe
```

## Status

The interpreter runs Verve programs with modules, processes, typed message passing, multi-file imports, and collections. The type checker validates function signatures, return types, assignments, built-in module calls, struct field access, collection indexing, match exhaustiveness, and recursion — with error messages that include full context (module, function, variable, parameter names). The verifier runs @example and @property tests. Native compilation works via a Zig backend.

See [BACKLOG.md](BACKLOG.md) for the full roadmap.

## License

MIT — see [LICENSE](LICENSE).
