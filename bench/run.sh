#!/bin/bash
set -e

HEY="${HEY:-$HOME/go/bin/hey}"
DURATION=10
CONCURRENCY=100
REQUESTS=100000
PORT=8080

if ! command -v "$HEY" &>/dev/null; then
  echo "hey not found. Install: go install github.com/rakyll/hey@latest"
  exit 1
fi

kill_port() {
  lsof -ti:$PORT 2>/dev/null | xargs kill 2>/dev/null || true
  sleep 1
}

bench_endpoint() {
  local name=$1
  local url=$2
  echo "  $name:"
  "$HEY" -n "$REQUESTS" -c "$CONCURRENCY" "$url" 2>&1 | grep -E "Requests/sec|Average|Fastest|Slowest"
  echo ""
}

bench_server() {
  local label=$1
  echo "═══════════════════════════════════════"
  echo " $label"
  echo "═══════════════════════════════════════"
  sleep 2  # let server warm up
  bench_endpoint "GET /" "http://127.0.0.1:$PORT/"
  bench_endpoint "GET /health" "http://127.0.0.1:$PORT/health"
  bench_endpoint "GET /json" "http://127.0.0.1:$PORT/json"
}

echo ""
echo "HTTP Benchmark — $REQUESTS requests, $CONCURRENCY concurrent"
echo "$(date)"
echo ""

# ── Verve ──
kill_port
echo "Building Verve server..."
cd "$(dirname "$0")/.."
./zig-out/bin/verve build bench/verve/server.vv 2>/dev/null || {
  /home/jt/.local/zig/zig build 2>/dev/null
  ./zig-out/bin/verve build bench/verve/server.vv
}
bench/verve/server &
SERVER_PID=$!
bench_server "Verve (process-per-connection, cooperative scheduler)"
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

# ── Node.js ──
kill_port
node bench/node/server.js &
SERVER_PID=$!
bench_server "Node.js $(node --version) (single-threaded event loop)"
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

# ── Go ──
kill_port
cd bench/go
go build -o ../go_server server.go
cd ../..
bench/go_server &
SERVER_PID=$!
bench_server "Go $(go version | awk '{print $3}') (goroutine-per-connection)"
kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null

kill_port
echo "Done."
