# Verve

Process-oriented language with no exceptions, no recursion, no nulls. Written in Zig 0.15. Tree-walk interpreter, native compilation planned.

## Quick reference

See `LANGUAGE.md` for complete syntax, built-in modules, and API reference.

## Project structure

- `src/parser.zig` — hand-written recursive descent parser
- `src/ast.zig` — AST node definitions
- `src/interpreter.zig` — tree-walk interpreter with built-in modules (String, Map, Set, Stdio, File, Stream)
- `src/value.zig` — runtime value types (int, float, string, list, map, set, stream, struct, tag, poison)
- `src/process.zig` — process scheduler, mailbox, state management
- `src/checker.zig` — type checker (undefined vars, recursion detection, doc comment enforcement)
- `src/verifier.zig` — @example and @property test runner
- `src/formatter.zig` — canonical code formatter
- `src/loader.zig` — multi-file import resolver
- `src/main.zig` — CLI entry point (run, check, test, fmt)
- `examples/` — working example programs

## Build and test

```
/home/jt/.local/zig/zig build        # build
/home/jt/.local/zig/zig build test   # run all tests
./zig-out/bin/verve run file.vv      # run a program
./zig-out/bin/verve check file.vv    # type check
./zig-out/bin/verve test file.vv     # run @example tests
```

## Key design decisions

- Strings are UTF-8 byte sequences. `s[i]` is byte access, `String.char_at(s, i)` is code point access.
- IO uses opaque `stream` values. Stdio/File return streams, Stream module operates on them.
- Doc comments (`///`) are required on all exported modules, processes, and functions.
- No recursion — enforced by call graph cycle detection. Use while loops with explicit stacks.
- Poison values instead of exceptions for arithmetic errors.
- Processes communicate via send (returns Result) and tell (fire-and-forget).
