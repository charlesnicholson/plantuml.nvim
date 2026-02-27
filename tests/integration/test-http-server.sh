#!/bin/bash
# Integration test: HTTP server serves viewer.html and /health endpoint.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== HTTP Server Tests ==="

setup_test_env

FAILURES=0
PORT="$TEST_HTTP_PORT"

# Start nvim server in background
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

# Wait for server to be ready
if ! wait_for_health 10 "$PORT"; then
    echo "FAIL: Server did not start"
    exit 1
fi

# Test: GET / returns HTML
html=$(curl -sf "http://127.0.0.1:${PORT}/")
if [[ "$html" == *"PlantUML Viewer"* ]]; then
    echo "PASS: GET / returns viewer.html"
else
    echo "FAIL: GET / did not return expected HTML"
    FAILURES=$((FAILURES + 1))
fi

# Test: HTML contains expected elements
if [[ "$html" == *"id=\"status\""* ]] && [[ "$html" == *"id=\"img\""* ]]; then
    echo "PASS: HTML contains status and image elements"
else
    echo "FAIL: HTML missing expected elements"
    FAILURES=$((FAILURES + 1))
fi

# Test: GET /health returns JSON
health=$(curl -sf "http://127.0.0.1:${PORT}/health")
if [[ "$health" == *'"state"'* ]]; then
    echo "PASS: GET /health returns JSON with state"
else
    echo "FAIL: GET /health response: $health"
    FAILURES=$((FAILURES + 1))
fi

# Test: health state is "ready"
state=$(echo "$health" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
if [ "$state" = "ready" ]; then
    echo "PASS: Health state is ready"
else
    echo "FAIL: Health state is '$state', expected 'ready'"
    FAILURES=$((FAILURES + 1))
fi

# Test: health includes connected_clients field
if [[ "$health" == *'"connected_clients"'* ]]; then
    echo "PASS: Health includes connected_clients"
else
    echo "FAIL: Health missing connected_clients"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES HTTP server test(s) FAILED ==="
    exit 1
fi
echo "=== All HTTP server tests passed ==="
