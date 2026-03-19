# Verve

A verbose, explicit programming language built for AI. One way to do everything. No magic.

- Website: [vervelang.org](https://vervelang.org)
- File extension: `.vv`
- License: MIT

## What is Verve?

Verve is a verbose, explicit programming language built for AI to write. There is one way to do everything, no magic, no hidden behavior, and nothing for the AI to get tripped up on.

The language strips away the ambiguity that causes AI-generated code to fail — no exceptions, no null, no implicit conversions, no operator overloading, no inheritance, no macros. What's left is a small, strict set of constructs where the AI can produce correct code reliably because there are fewer ways to be wrong.

## Key Design Decisions

- **One way to do things** — no style debates, every problem has one idiomatic solution
- **Modules and processes** — modules organize code, processes own state and communicate via typed messages
- **Guards, not exceptions** — preconditions are boolean expressions, failures return structured errors
- **Match, not if/else** — one branching construct, always exhaustive
- **While, not for** — one loop construct
- **Pre-allocated memory** — process state declares capacity upfront, no GC, no dynamic allocation
- **Poison values** — overflow, division by zero, and out-of-bounds propagate instead of crashing
- **Compile-time generics** — no runtime type parameters, compiler stamps out concrete versions
- **No recursion** — call graph cycles are rejected, use while loops
- **Explicit process boundaries** — `send` and `tell` keywords mark every cross-process call
- **Native binaries** — compiles to x86_64/arm64, deploys in a container

## Quick Start

### Build

Requires [Zig](https://ziglang.org) 0.15+.

```
zig build
```

### Run a program

```
zig build run -- run examples/hello.vv
```

### Check a program (parse only)

```
zig build run -- check examples/hello.vv
```

### Check a program (type check)

```
zig build run -- check examples/hello.vv
```

### Run @example and @property tests

```
zig build run -- test examples/tested.vv
```

### Format a file

```
zig build run -- fmt file.vv
zig build run -- fmt file.vv --check   # CI mode — fail if not formatted
```

### Run compiler tests

```
zig build test
```

## Example

```verve
process Counter {
    state {
        count: int [capacity: 1];
    }

    receive Increment() -> int {
        guard count >= 0;
        transition count { count + 1; }
        return count;
    }

    receive GetCount() -> int {
        return count;
    }
}

module Main {
    fn main() -> int {
        counter = spawn Counter();

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
├── LANGUAGE-DESIGN.md        # Complete language specification
├── BACKLOG.md                # Development roadmap and progress
├── editors/vscode/           # VS Code / Cursor syntax highlighting
├── examples/
│   ├── hello.vv              # Basic: math, loops, match, functions
│   ├── counter.vv            # Processes: spawn, send, state, transitions
│   ├── multi.vv              # Multi-file imports
│   ├── math.vv               # Exported module library
│   ├── lists.vv              # Lists: create, append, index, iterate
│   ├── supervisor.vv         # Process supervision with watch
│   └── tested.vv             # @example and @property annotations
└── src/
    ├── main.zig              # CLI: run, check, test, fmt
    ├── ast.zig               # AST node types
    ├── parser.zig            # Hand-written recursive descent parser
    ├── value.zig             # Runtime value types with poison values
    ├── interpreter.zig       # Tree-walk interpreter
    ├── process.zig           # Process scheduler, mailbox, state
    ├── loader.zig            # Multi-file import/export resolver
    ├── checker.zig           # Type checker, recursion detection
    ├── formatter.zig         # Canonical code formatter
    ├── verifier.zig          # @example and @property test runner
    └── *_test.zig            # 191 tests across 6 suites
```

## Status

The interpreter runs Verve programs with modules, processes, typed message passing, multi-file imports, and lists. The type checker catches undefined variables, unknown types, recursion, and non-boolean guards. The verifier runs @example and @property tests with VALID/INVALID/INCOMPLETE signals. Native compilation is planned.

See [BACKLOG.md](BACKLOG.md) for the full roadmap.

See [BACKLOG.md](BACKLOG.md) for the full roadmap.

## License

MIT — see [LICENSE](LICENSE).
