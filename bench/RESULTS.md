# Benchmark Results

Most recent results at top. 10,000 requests, 50 concurrent connections.

---

## 2026-03-29 — O(1) spawn, multi-threaded scheduler, ptr type fix

**Machine:** 4-core x86-64, Linux (WSL2)

| Endpoint | Verve | Node.js v24.12 | Go 1.25.5 |
|----------|-------|----------------|-----------|
| GET / (plaintext) | **70,837 req/s** | 44,666 req/s | 66,506 req/s |
| GET /json | 61,564 req/s | 61,390 req/s | **68,674 req/s** |

Verve beats Go on plaintext. Matches Node.js on JSON.

**Changes:** O(1) spawn via free list, skip 64KB mailbox memset on reuse, pid as int not pointer, multi-threaded scheduler (4 cores)

---

## 2026-03-29 — Baseline (first profiled run)

| Endpoint | Verve |
|----------|-------|
| GET / (plaintext) | 7,867 req/s |
| GET /json | 7,678 req/s |

With VERVE_PROFILE=1 enabled (adds overhead). Bottlenecks: accept 114µs, spawn 90µs.
