# Benchmark Results

Most recent results at top. All with `-disable-keepalive`, warmup pass before measurement.

---

## 2026-03-29 — 1M sustained: 75k req/s JSON, 2.8x faster than Go

**Machine:** 4-core x86-64, Linux (WSL2)
**Config:** 1,000,000 requests, 100 concurrent connections

| Endpoint | Verve | Go 1.25.5 | Node.js v24.12 (cluster) |
|----------|-------|-----------|--------------------------|
| GET / (plaintext) | **71,776 req/s** | 25,253 req/s | 14,008 req/s |
| GET /json | **75,822 req/s** | 24,850 req/s | 14,204 req/s |

**Verve is 2.8x faster than Go and 5.1x faster than Node.js** sustained over 1 million requests.

| | Go p50 | Go p99 | Verve p50 | Verve p99 |
|--|--------|--------|-----------|-----------|
| Plaintext | 3.7ms | 10.5ms | <1ms | <2ms |

---

## 2026-03-29 — 50k run: 64k req/s

**Config:** 50,000 requests, 100 concurrent

| Endpoint | Verve | Go | Node |
|----------|-------|----|------|
| Plaintext | 64,006 | 23,869 | 11,465 |
| JSON | 62,418 | 23,384 | 12,826 |

---

## 2026-03-29 — Baseline: 7.1k req/s

Before optimizations. 1MB HTTP buffer, 64KB mailbox, 64KB fiber stack.
