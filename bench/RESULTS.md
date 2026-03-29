# Benchmark Results

Most recent results at top. All with `-disable-keepalive` for fair new-connection-per-request comparison.

---

## 2026-03-29 — 64k req/s: 2.7x faster than Go

**Machine:** 4-core x86-64, Linux (WSL2)
**Config:** 50,000 requests, 100 concurrent, warmup 2,000 requests

| Endpoint | Verve | Go 1.25.5 | Node.js v24.12 (cluster) |
|----------|-------|-----------|--------------------------|
| GET / (plaintext) | **64,006 req/s** | 23,869 req/s | 11,465 req/s |
| GET /json | **62,418 req/s** | 23,384 req/s | 12,826 req/s |

**Verve is 2.7x faster than Go and 5.6x faster than Node.js.**

**Changes from previous:**
- HTTP read buffer: 1MB → 8KB (only grow for body)
- Mailbox buffer: 64KB → 4KB per process
- Fiber stack: 64KB → 16KB per process
- HTTP response: always Connection: keep-alive
- Benchmark server: single request per connection (no keep-alive loop blocking)

---

## 2026-03-29 — Previous: 7.1k req/s baseline

| Endpoint | Verve | Go | Node |
|----------|-------|----|------|
| Plaintext | 7,100 | 19,595 | 45,247 |

With 1MB HTTP buffer, 64KB mailbox, 64KB fiber stack. All overhead from oversized allocations.
