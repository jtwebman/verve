# Verve Roadmap

## The Narrow Goal

Verve does not need to prove that it is a better language for everything.

It needs to prove one narrower claim first:

**For some backend and concurrency-heavy tasks, AI can get to correct, auditable code in Verve with fewer mistakes and fewer repair loops than in Go, TypeScript, or Python.**

If that claim is not true, the rest of the roadmap does not matter.

## Immediate Roadmap

### Phase 1 — Make The Current Story Honest

- Fix broken or misleading CLI behavior
- Make first-party examples compile and run cleanly
- Bring docs in line with reality
- Remove or soften claims that are not yet defensible

### Phase 2 — Make The Runtime Trustworthy Enough To Evaluate

- Harden runtime boundaries and failure behavior
- Reduce panic-based behavior in ordinary runtime paths
- Add stronger ReleaseSafe and regression coverage
- Fix checker/codegen bugs that break realistic examples

### Phase 3 — Prove The Backend Thesis With 3 Serious Apps

Build three real examples from written specs and test suites:

1. HTTP JSON API with validation and env config
2. Job queue with retries and dead-letter behavior
3. TCP/stateful service with explicit ownership per connection

For each comparison language, measure:

- AI repair loops to green
- Test pass rate
- Code size
- Complexity of failure handling
- Performance

## What Comes After That

Only after the narrow claim is proven:

- Expand the benchmark set
- Improve editor tooling
- Add packaging/docs infrastructure
- Broaden the stdlib carefully
- Revisit bigger ambitions like WASM, clustering, or broader adoption

## Success Criteria

This phase is a success if Verve can honestly show:

- a smaller correctness gap from spec to working backend code
- cleaner failure/concurrency structure
- competitive-enough performance for the target class of services

This phase is not a success if the result is only:

- "interesting language design"
- "promising benchmark anecdotes"
- "works after lots of manual cleanup"

## Current Position

Verve is already beyond the concept stage, but still before the proof stage.

The right move now is not to widen scope. The right move is to tighten the core and force the project to earn its thesis.
