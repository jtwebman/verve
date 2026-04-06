# Verve HTTP Benchmark

This benchmark is an early performance probe, not proof of the full Verve thesis.

It compares a minimal HTTP server across Verve, Node.js, and Go.

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

Use it to spot rough performance direction, not to make broad production or language-quality claims on its own.

## Servers

| Language | File | Notes |
|----------|------|-------|
| Verve | `verve/server.vv` | Process-per-connection, cooperative scheduler |
| Node.js | `node/server.js` | Single-threaded event loop (default) |
| Go | `go/server.go` | net/http with goroutine-per-connection |
