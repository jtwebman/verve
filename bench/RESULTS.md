# Benchmark Results

Most recent results at top. Each run: 100,000 requests, 100 concurrent connections.

---

## 2026-03-29 — Baseline (multi-threaded scheduler, free list spawn)

**Machine:** 4-core x86-64, Linux (WSL2)

| Endpoint | Verve | Node.js | Go |
|----------|-------|---------|-----|
| GET / (plaintext) | 7,867 req/s | TBD | TBD |
| GET /json | 7,678 req/s | TBD | TBD |

**Profile (Verve, 20k requests):**
```
phase            total_ms      calls     avg_us
accept            2291.45ms      20000      114us
spawn             1819.28ms      20001       90us
drain              461.92ms      20000       23us
read               113.38ms      34711        3us
write               55.40ms      14711        3us
close              208.51ms      20000       10us
parse_http          68.04ms      14711        4us
build_resp           2.71ms      14711        0us
```

**Bottlenecks:** accept (114µs/call — fiber context switch overhead), spawn (90µs/call — table lock + arena free)

**Changes:** Multi-threaded scheduler (4 threads), O(1) spawn via free list, ptr IR type for streams
