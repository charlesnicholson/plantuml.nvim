#!/bin/bash
# Run Playwright browser tests. Requires node, playwright, and a running plantuml server.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Browser Tests ==="

# Check prerequisites
if ! command -v node &>/dev/null; then
    echo "SKIP: Node.js not available"
    exit 0
fi

if ! node -e "require('playwright')" 2>/dev/null; then
    echo "SKIP: Playwright not available"
    exit 0
fi

setup_test_env

PORT="$TEST_HTTP_PORT"
FAILURES=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Start nvim server
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

if ! wait_for_health 10 "$PORT"; then
    echo "FAIL: Server did not start"
    exit 1
fi

# Run each browser test
for test_file in "$SCRIPT_DIR"/test-*.js; do
    test_name=$(basename "$test_file" .js)
    echo "--- Running $test_name ---"
    if DISPLAY=${DISPLAY:-:99} node "$test_file" "$PORT" 2>&1; then
        echo "PASS: $test_name"
    else
        echo "FAIL: $test_name"
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES browser test(s) FAILED ==="
    exit 1
fi
echo "=== All browser tests passed ==="
