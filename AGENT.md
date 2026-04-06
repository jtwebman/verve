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

## Language design guardrails

Verve is pre-adoption. Favor one canonical way to represent a feature, type, syntax form, or internal lowering shape.

Do not preserve or add parallel representations just for compatibility unless the user explicitly asks for a migration path.

When you find two ways of expressing the same concept:

1. Pick the clearer long-term form.
2. Convert the compiler/runtime/docs/tests toward that form.
3. Remove the alternate path instead of teaching the system both.

This applies to:

- surface syntax
- type name encodings
- IR conventions
- backend/runtime data representations
- docs and examples
