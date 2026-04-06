# Verve

Process-oriented language. Zig 0.15. See `LANGUAGE.md` for syntax and API reference.

## Build and test

```
/home/jt/.local/zig/zig build              # build
/home/jt/.local/zig/zig build test         # fast tests (parser, checker, IR)
/home/jt/.local/zig/zig test src/compile_test_basic.zig   # single compile test file
/home/jt/.local/zig/zig build test-compile # ALL compile tests (~7 min) — CI only
```

**Run compile tests individually** — never run `test-compile` during development.
Isolate failures to a single file, fix, verify that file passes, then move to the next.
Compile test files: `src/compile_test_*.zig` (basic, type, file, string, process, scheduler, env, math, json, net).

## Before every commit

1. `/home/jt/.local/zig/zig fmt src/file.zig` on changed files (also `src/test_*.zig` and `src/compile_test_*.zig`)
2. `/home/jt/.local/zig/zig build`
3. `/home/jt/.local/zig/zig build test` — fast tests pass
4. Each `src/compile_test_*.zig` passes individually

Do NOT commit code that fails any of these steps.
