# Verve Backlog

This backlog is intentionally biased toward proving the project instead of expanding it.

The current goal is not "add everything a language might eventually need." The current goal is:

**Make the existing compiler/runtime honest, reliable enough to evaluate, and strong enough to test the backend thesis.**

## Current Phase

Verve is in the "tighten the core and prove the narrow claim" phase.

That means:

- Fix workflows that break trust
- Fix docs that overstate reality
- Harden the runtime where the safety story is weak
- Build a small, disciplined benchmark suite before broadening scope

## Priority 0 — Trust The Basics

These are the highest-leverage tasks because they affect whether users can trust the repo at all.

### CLI correctness
- [x] `verve check` exits non-zero on errors
- [x] `verve check --json file.vv` and `verve check file.vv --json` both work
- [x] JSON mode emits JSON only, with no human text after it
- [x] `verve run`, `build`, `test`, and `fmt` have consistent argument parsing and exit codes

### Example correctness
- [x] Every example in `examples/` passes the workflow it is meant to demonstrate
- [x] README example matches current language syntax and current compiler behavior
- [ ] Remove or fix any example that needs caveats to compile or run

### Test workflow correctness
- [x] Fix `verve test` on bundled examples
- [ ] Add regression tests for test-runner code generation
- [ ] Add regression tests for CLI exit-code behavior

## Priority 1 — Runtime Safety Story

These are the tasks required before "humans can trust it" is a fair claim.

### Memory and boundary hardening
- [x] Validate `sliceFromPair` inputs beyond a length cap
- [x] Validate tagged string metadata before reconstructing slices
- [ ] Stop panicking on ordinary runtime allocation failure where poison/error propagation is possible
- [ ] Define clear behavior for arena exhaustion

### Collection/runtime correctness
- [x] Replace silent `List.append` capacity failure with growth or explicit failure semantics
- [ ] Audit similar silent-failure behavior in other runtime data structures
- [x] Add tests for collection boundary behavior under load

### Mailbox/process hardening
- [ ] Review mailbox corruption handling and length-prefix validation
- [ ] Add more tests around mailbox full, process death, and cross-thread wake behavior
- [ ] Define and implement user-visible watcher/death notification semantics for `watch`
- [ ] Audit process lifecycle cleanup paths for stale state reuse

### Validation discipline
- [ ] Run compile tests in ReleaseSafe regularly, not just as an optional path
- [ ] Add targeted runtime safety regression tests
- [ ] Add fuzz/property-style testing for compiler/runtime invariants where practical

## Priority 2 — Checker And Compiler Credibility

The compiler should reject bad code, accept valid code, and avoid surprising users.

### Control-flow analysis
- [x] Fix false positives around `while true` loops with reachable `break` paths
- [ ] Improve return-path analysis for realistic handler patterns
- [x] Add regression tests for accepted first-party examples

### Diagnostics
- [ ] Improve top error messages that currently read as internal/compiler-centric
- [ ] Keep error locations accurate across loader/checker/lowering stages
- [ ] Separate "hard error" from "warning-like heuristic" where appropriate

### Generated code correctness
- [x] Fix type mismatches in generated test-runner dispatch
- [ ] Audit generated dispatch and process wrapper signatures for consistency
- [x] Add focused tests for process entry-point and handler codegen

## Priority 3 — Prove The Narrow Backend Thesis

Do this before broadening the language mission.

### Pick the first serious benchmark set
- [ ] Choose 3 benchmark apps, not 20
- [ ] Write exact specs before implementation
- [ ] Write exact test suites before comparison

Recommended first 3:
- [ ] JSON HTTP API with validation and env config
- [ ] Job queue with retries and dead-letter behavior
- [ ] TCP/stateful service with per-client process ownership

### Measurement discipline
- [ ] Measure first-pass correctness, not just final working output
- [ ] Record AI repair loops and retries to green
- [ ] Record code size, performance, and failure-handling complexity
- [ ] Compare against a small honest baseline set: Go, TypeScript, Python

### Exit criteria for this phase
- [ ] Verve must clearly win on at least one meaningful workflow
- [ ] If it loses, identify why and fix the product before expanding scope

## Priority 4 — Stdlib Needed For The Benchmark Apps

Only build what the first benchmark set actually needs.

- [ ] Database driver (likely SQLite first)
- [ ] HTTP client custom headers
- [ ] HTTP client keep-alive pooling
- [ ] Response body streaming where benchmark apps need it
- [ ] Time utilities needed by retries, deadlines, and logs
- [ ] Hash/UUID/Base64 only if required by chosen apps

## Priority 5 — Tooling After The Thesis Is Proven

These matter, but they should follow a demonstrated product win.

- [ ] LSP/editor support
- [ ] Package manager
- [ ] Better documentation generation
- [ ] Website
- [ ] Project indexing / AI navigation tooling

## Future / Optional

These stay explicitly out of the near-term critical path.

- [ ] WASM target
- [ ] Clustering
- [ ] C FFI
- [ ] Portable fiber fallback
- [ ] arm64/macOS polish
- [ ] LLVM backend
- [ ] Self-hosting

## What Not To Do Right Now

- [ ] Do not broaden the language surface area unless it directly helps the first benchmark apps
- [ ] Do not market broad production readiness
- [ ] Do not treat docs, examples, and CLI behavior as secondary polish

## Next Up

1. Fix CLI/test/example trust issues.
2. Harden the runtime safety story.
3. Fix checker/codegen correctness issues that break first-party examples.
4. Lock the first 3 benchmark apps and measure them honestly.
