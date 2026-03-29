# Benchmark Results

Most recent results at top. Machine: 4-core x86-64, Linux (WSL2).

---

## 2026-03-29 — Keep-alive working, process-main server

**Config:** 10,000 requests, 50 concurrent

| Mode | Verve | Go 1.25.5 |
|------|-------|-----------|
| Keep-alive | 61,306 req/s | **69,464 req/s** |
| No keep-alive | **71,977 req/s** | 20,435 req/s |

Keep-alive: Go leads by 12%. No keep-alive: Verve leads 3.5x.
Verve keep-alive is functional (pipelined requests work).

**Changes:** Process-main entry point (runs accept loop inside scheduler), keep-alive handler loop with io_yield, drain_one reply_slot fix.

---

## 2026-03-29 — 1M sustained

**Config:** 1,000,000 requests, 100 concurrent, no keep-alive

| | Verve | Go | Node.js (cluster) |
|--|-------|-----|-------------------|
| Plaintext | **71,776** | 25,253 | 14,008 |
| JSON | **75,822** | 24,850 | 14,204 |

---

## 2026-03-29 — Baseline

7,100 req/s. 1MB HTTP buffer, 64KB mailbox, 64KB fiber stack.
