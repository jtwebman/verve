# Verve

Process-oriented language. Zig 0.15. See `LANGUAGE.md` for syntax and API reference.

## Build and test

```
/home/jt/.local/zig/zig build                # build
/home/jt/.local/zig/zig build test           # fast tests (parser, checker, IR)
/home/jt/.local/zig/zig build test-compile   # compile pipeline tests (~7 min)
/home/jt/.local/zig/zig build test-slow      # network tests (TCP/HTTP, ~2 min)
./zig-out/bin/verve run file.vv              # compile and run
```

## Before every commit

1. `/home/jt/.local/zig/zig fmt src/file.zig` on changed files
2. `/home/jt/.local/zig/zig build`
3. `/home/jt/.local/zig/zig build test` — fast tests pass
4. `/home/jt/.local/zig/zig build test-compile` — compile tests pass

Do NOT commit code that fails any of these steps.
