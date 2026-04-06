# Verve

A process-oriented compiled language for explicit backend code.

Verve is an experimental language project aimed at one narrow claim:

**AI should be able to write certain backend and concurrency-heavy programs in Verve with fewer mistakes and less repair work than in mainstream languages, while leaving humans with code they can audit.**

- File extension: `.vv`
- License: MIT
- Status: experimental compiler/runtime, not production-ready

## Where The Project Actually Is

What exists today:

- A real compiler pipeline: parser, checker, IR lowering, Zig backend
- A runtime with processes, mailboxes, TCP, HTTP, JSON, fibers, and per-process arenas
- A formatter, examples, and a substantial test suite
- Early benchmarking and example apps

What is not true yet:

- The runtime safety story is not fully hardened
- The CLI and examples still have rough edges
- Tooling is minimal
- The project has not yet proved its core claim against Go, TypeScript, or Python in a disciplined benchmark

The immediate goal is not to become a general-purpose language. The immediate goal is to prove a narrow backend story honestly.

## What Verve Is Trying To Be Good At

- Explicit state and explicit types
- Process-style concurrency with message passing
- Code generation that avoids hidden behavior
- Backend services where failure handling and concurrency usually make code messy

## What Verve Is Not Trying To Prove Yet

- Broad production readiness
- General application development
- Desktop, mobile, or ecosystem maturity
- Superior performance in every category

## Current Priorities

1. Make the current compiler/runtime behavior match the public claims.
2. Fix user-facing workflow issues in `verve check`, `verve test`, examples, and docs.
3. Harden the runtime safety story enough that "humans can trust it" becomes defensible.
4. Build a small benchmark set that can honestly answer whether Verve helps on real backend tasks.

## Quick Start

Requires [Zig](https://ziglang.org) 0.15+.

```bash
zig build
./zig-out/bin/verve build file.vv
./zig-out/bin/verve check file.vv
./zig-out/bin/verve test file.vv
./zig-out/bin/verve fmt file.vv
```

Note: command behavior is still being tightened. Check the backlog before treating the CLI as stable.

## Example

```verve
module App {
    fn factorial(n: int) -> int {
        result: int = 1;
        i: int = 1;
        while i <= n {
            result = result * i;
            i = i + 1;
        }
        return result;
    }
}

process App {
    receive main(args: list<string>) -> int {
        Stdio.println("Hello from Verve!");
        Stdio.println("Factorial of 10 = ", factorial(10));
        return 0;
    }
}
```

## Project Structure

```text
verve/
├── build.zig
├── README.md
├── LANGUAGE.md
├── LANGUAGE-DESIGN.md
├── BACKLOG.md
├── ROADMAP.md
├── src/
│   ├── main.zig
│   ├── parser.zig
│   ├── checker.zig
│   ├── ir.zig
│   ├── ir_validate.zig
│   ├── lower/
│   ├── zig_backend.zig
│   ├── formatter.zig
│   └── runtime/
└── examples/
```

## Honest Status

This repo is past the "idea only" stage, but not yet at the "claims proven" stage.

If Verve succeeds, it will probably succeed first as a niche tool for AI-assisted backend and concurrency-heavy code, not as a universal new language.

See [BACKLOG.md](BACKLOG.md) for concrete next steps and [ROADMAP.md](ROADMAP.md) for the narrower plan.

## License

MIT — see [LICENSE](LICENSE).
