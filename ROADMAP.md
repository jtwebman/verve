# Verve Roadmap

## Current Focus: Prove the Backend Story

Before expanding to desktop/mobile/ecosystem, prove one thing: **AI writes more correct backend services in Verve with fewer tokens and fewer errors than in Go, TypeScript, Java, or Python.**

### Step 1 — Harden the Runtime
- Finish concurrency correctness (multi-threaded scheduler, proper process lifecycle)
- Verifier validates the process model (supervision, mailbox overflow, dead process handling)
- Database driver (SQLite or PostgreSQL)
- HTTP client (for API-to-API calls)

### Step 2 — Build 3 Serious Example Apps
Real apps, not toys. Each has a test suite.
1. HTTP API with JSON, auth, validation
2. Job queue with retries, dead-letter, supervision
3. TCP chat server with per-client processes

### Step 3 — The 20-App Benchmark
Build each app from a spec in Verve, TypeScript, Go, Java, and Python. Compare:
- **Tokens used** by AI to complete the app
- **Errors/retries** needed to pass the test suite
- **Lines of code** from spec to working API
- **Test suite pass rate** on first attempt
- **Performance** (req/s, latency)

#### Benchmark Mix (20 apps)

**Familiar (4)** — prove Verve isn't worse at the basics:
1. CRUD API with database
2. CRUD + auth + input validation
3. Admin API with file upload
4. Multi-tenant config service

**Workflow / Concurrency (8)** — where Verve's process model should shine:
5. Job queue with retries
6. Dead-letter queue processor
7. Rate-limited email sender
8. Multi-step order workflow (saga pattern)
9. Payment authorization + compensation flow
10. Webhook ingestion pipeline
11. Cron-like scheduler process
12. Leader/worker task dispatcher

**Network / Stateful (4)** — TCP, sessions, real-time:
13. TCP chat server with per-client process
14. Chat session state manager
15. HTTP worker pool with bounded mailbox
16. Request fan-out / result aggregation

**Reliability (4)** — where "always stays up" matters:
17. Supervisor tree with worker restart
18. Outbox pattern (DB + background sender)
19. API poller with timeout/retry/backoff
20. AI agent task orchestrator with tool-call stages

#### Benchmark Theme: "20 Ways Concurrency and Failure Make Normal Backend Code Ugly"

Every app stresses the same claims:
- **Explicit state ownership** — process state vs shared mutable state
- **Process isolation** — one crash doesn't take down the system
- **Timeout/retry behavior** — built into the language, not bolted on
- **Supervision** — automatic restart, not manual error handling
- **Typed messages** — send/tell with Result, not unchecked async
- **AI generation quality** — fewer retries to pass the test suite

Each app has:
- A written spec (what it does, API endpoints, expected behavior)
- A test suite (30-50 tests covering happy path, errors, edge cases)
- Built in Verve, TypeScript, and Go from the same spec by the same AI
- Measured on:
  - **Lines of code** from spec to working app
  - **Number of async/concurrency concepts** the developer must juggle
  - **AI repair loops** to get to green (retries, errors, fixes)
  - **Timeout/retry/restart bugs** in the final code
  - **Performance** (req/s, latency under load)

### After the Benchmark
If Verve wins (fewer tokens, fewer errors, comparable performance):
- Publish results
- LSP for editor support
- Package manager
- Website + docs
- Community building

If Verve doesn't win, fix what's losing and re-run.
