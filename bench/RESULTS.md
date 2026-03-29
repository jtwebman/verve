# Benchmark Results

Most recent results at top. Machine: 4-core x86-64, Linux (WSL2).

---

## 2026-03-29 — Beats Go on keepalive: 68.5k req/s

**Config:** 10,000 requests, 50 concurrent, warmup 2,000

| Mode | Verve | Go 1.25.5 |
|------|-------|-----------|
| Keep-alive | **68,519 req/s** | 65,106 req/s |
| No keep-alive | **68,171 req/s** | 17,258 req/s |

Verve beats Go on BOTH modes. Keep-alive and no-keepalive are now equal speed in Verve.

**Key change:** Lightweight processes — lazy heap-allocation of mailbox (4KB), arena (2KB), watchers (512B). Process struct reduced from ~6.8KB to ~90 bytes. Spawn cost dramatically reduced.

---

## 2026-03-29 — 1M sustained: 75k req/s

**Config:** 1,000,000 requests, 100 concurrent, no keep-alive

| | Verve | Go | Node.js (cluster) |
|--|-------|-----|-------------------|
| Plaintext | **71,776** | 25,253 | 14,008 |
| JSON | **75,822** | 24,850 | 14,204 |

---

## 2026-03-29 — Baseline: 7.1k req/s

Before optimizations. 1MB HTTP buffer, 64KB mailbox, 64KB fiber stack, inline process structs.
