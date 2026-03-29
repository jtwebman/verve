# Benchmark Results

Most recent results at top. hey benchmark tool, `-disable-keepalive` for fair comparison.

---

## 2026-03-29 — Multi-threaded scheduler, O(1) spawn, SO_REUSEPORT

**Machine:** 4-core x86-64, Linux (WSL2)
**Config:** 10,000 requests, 50 concurrent, `-disable-keepalive`

| Endpoint | Verve | Node.js v24.12 | Go 1.25.5 |
|----------|-------|----------------|-----------|
| GET / (plaintext) | 7,100 req/s | 45,247 req/s | 83,048 req/s |
| GET /json | 6,989 req/s | 60,323 req/s | 64,127 req/s |

**Gap analysis:** Verve is ~6x slower than Node, ~11x slower than Go.

**Root cause (profiled):**
- Spawn per connection: 84µs per spawn (Go goroutine: 0.3µs — 280x faster)
- Scheduler context switch overhead: 4+ fiber switches per request
- Accept: 114µs per accept with scheduler io_yield

**Next steps:** Process pool (avoid spawn per connection), direct dispatch without fiber (for simple handlers), netpoller-style I/O integration
