# Benchmark Results

Most recent results at top. Machine: 4-core x86-64, Linux (WSL2). Results vary ±15% between runs.

---

## 2026-03-29 — Full comparison (lightweight 90-byte processes)

**Config:** 10,000 requests, 50 concurrent, warmup 2,000

| Mode | Verve | Go 1.25.5 | Node.js v24.12 (cluster) | Zig (raw, 1 thread) |
|------|-------|-----------|--------------------------|---------------------|
| Keep-alive | 39-68k req/s | 65-80k req/s | 45-64k req/s | 162 (single-threaded) |
| No keep-alive | **68k req/s** | 17-18k req/s | 10-11k req/s | 5.4k (single-threaded) |

**No keep-alive: Verve is 3.5-4x faster than Go, 6x faster than Node.js.**
**Keep-alive: competitive with Go and Node, varies by run.**

Process struct: ~90 bytes (lazy heap-alloc mailbox/arena/watchers).
Zig raw server is single-threaded blocking — not a fair concurrent comparison.

---

## 2026-03-29 — 1M sustained

**Config:** 1,000,000 requests, 100 concurrent, no keep-alive

| | Verve | Go | Node.js |
|--|-------|-----|---------|
| Plaintext | **71,776** | 25,253 | 14,008 |
| JSON | **75,822** | 24,850 | 14,204 |

---

## 2026-03-29 — Baseline: 7.1k req/s

Before optimizations.
