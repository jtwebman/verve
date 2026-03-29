# Verve HTTP Benchmark

Compares a minimal HTTP server across Verve, Node.js, and Go.

Each server implements the same three endpoints:
- `GET /` — returns `Hello from {language}!` (text/plain)
- `GET /health` — returns `ok` (text/plain)
- `GET /json` — returns `{"status":"ok"}` (application/json)

## Prerequisites

- [hey](https://github.com/rakyll/hey) — `go install github.com/rakyll/hey@latest`
- Node.js 20+
- Go 1.21+
- Verve (build from repo root: `zig build`)

## Running

```bash
# From repo root
./bench/run.sh
```

This starts each server, runs `hey` against all three endpoints, kills the server, and prints results.

## Servers

| Language | File | Notes |
|----------|------|-------|
| Verve | `verve/server.vv` | Process-per-connection, cooperative scheduler |
| Node.js | `node/server.js` | Single-threaded event loop (default) |
| Go | `go/server.go` | net/http with goroutine-per-connection |
