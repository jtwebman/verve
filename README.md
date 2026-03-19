# Verve

An implementation language designed for AI to write and verify. Humans describe what they want and test the final product.

- Website: [vervelang.org](https://vervelang.org)
- File extension: `.vv`
- License: MIT

## What is Verve?

Verve is a programming language where AI writes the code and a verifier proves it correct. Humans stay at the product level — they describe what they want, test the result, and never review code.

The language is designed around a tight feedback loop: the AI generates code, the verifier says VALID or INVALID, the AI iterates. This is the same approach that makes [Leanstral](https://mistral.ai/news/leanstral) work for formal proofs, applied to systems programming.

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

### Run tests

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
├── build.zig               # Zig build config
├── LANGUAGE-DESIGN.md       # Complete language specification
├── BACKLOG.md               # Development roadmap and progress
├── examples/                # Example Verve programs
│   ├── hello.vv             # Basic: math, loops, match, functions
│   ├── counter.vv           # Processes: spawn, send, state, transitions
│   ├── multi.vv             # Multi-file imports
│   ├── math.vv              # Exported module library
│   └── supervisor.vv        # Process supervision with watch
└── src/
    ├── main.zig             # CLI entry point
    ├── ast.zig              # AST node types
    ├── parser.zig           # Hand-written recursive descent parser
    ├── value.zig            # Runtime value types
    ├── interpreter.zig      # Tree-walk interpreter
    ├── process.zig          # Process scheduler and mailbox
    ├── loader.zig           # Multi-file import resolver
    └── *_test.zig           # 131 tests
```

## Status

Early development. The interpreter runs Verve programs with modules, processes, message passing, and multi-file imports. Native compilation, type checking, and the verifier are planned.

See [BACKLOG.md](BACKLOG.md) for the full roadmap.

## License

MIT — see [LICENSE](LICENSE).
