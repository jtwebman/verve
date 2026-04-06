# Verve Language Design

A process-oriented compiled language designed to make some classes of backend code more explicit and more auditable.

## Status Note

This document describes the intended design direction of Verve.

It is not a guarantee that every claim here is fully realized in the current compiler/runtime. When the implementation and the design document disagree, the implementation wins and the backlog should be updated.

## Philosophy

- **AI writes it, humans verify it**: optimize for explicit code that is easier to inspect
- **One clear way to do things**: reduce stylistic and semantic ambiguity
- **Explicitness over cleverness**: boilerplate is acceptable if it improves correctness
- **Processes are the concurrency unit**: avoid shared mutable state as the default model
- **Prove a narrow win before broadening**: target backend/concurrency workloads first

## Why This Project Exists

Most language projects fail because they try to replace everything at once.

Verve is trying to do less:

- constrain the language enough that AI-generated code is less likely to go wrong
- make concurrency/state ownership more obvious
- make human audit easier by removing hidden behavior

If it works, it should work first for backend services where concurrency and failure handling usually create the most mess.

## Core Design Decisions

### Types are explicit

Every variable declaration requires a type annotation. The language prefers visible structure over inference-heavy convenience.

### Errors are values

Verve does not use exceptions. Fallible work should return values that the program handles explicitly.

### Processes own state

The design bias is toward isolated state plus message passing rather than shared mutable state.

### Arithmetic should fail visibly

Overflow and other invalid numeric operations should not silently become unrelated values.

### No recursion

Verve rejects call graph cycles. This keeps control flow simpler and prevents stack growth surprises.

### No implicit null

Absence is explicit through optional types.

### Per-process memory

The runtime design centers around process-local allocation and cleanup.

## Intended Compilation Model

Verve source -> AST -> typed IR -> Zig source -> native binary

That is a pragmatic implementation strategy, not part of the user-facing language identity.

## Process Model

The process model is inspired by Erlang/BEAM ideas, but the project is not trying to recreate BEAM wholesale.

What matters in the near term:

- typed process identifiers
- explicit send/tell APIs
- bounded mailboxes
- predictable process ownership and cleanup

## What This Document Should Not Be Used For

This document should not be treated as a marketing checklist.

It exists to explain the intended shape of the language. Public claims about reliability, trust, or production readiness should only be made when the implementation and tests support them.
