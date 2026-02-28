#!/bin/bash
# Integration test: WS client receives stored diagram even when file mapping
# doesn't match (tests find_replay_message fallback).
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Replay Fallback Tests ==="

if ! command -v node &>/dev/null || ! node -e "require('ws')" 2>/dev/null; then
    echo "SKIP: Node.js or ws module not available"
    exit 0
fi

setup_test_env

FAILURES=0
PORT="$TEST_HTTP_PORT"
WS_PORT="$((PORT + 1))"

# Start nvim with a buffer that has plantuml content but a NON-plantuml filename.
# This means update_diagram() stores last_messages under an unusual path.
# When a WS client connects, pending_file is nil, so on_ws_connect falls back
# to current_filepath(). The fallback find_replay_message should still deliver
# the stored diagram.
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "set filetype=plantuml" \
    -c "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'@startuml', 'Alice -> Bob : hello', '@enduml'})" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, auto_update = false, http_port = $PORT}); p.start(); p.update_diagram()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

if ! wait_for_health 10 "$PORT"; then
    echo "FAIL: Server did not start"
    exit 1
fi

# Verify health shows has_diagram: true
health=$(curl -sf "http://127.0.0.1:$PORT/health" 2>/dev/null || echo "{}")
if echo "$health" | grep -q '"has_diagram":true'; then
    echo "PASS: Server has stored diagram"
else
    echo "FAIL: Server has no stored diagram: $health"
    FAILURES=$((FAILURES + 1))
fi

# Test 1: A fresh WS client receives the stored update via refresh
cat > "$TEST_TMP_DIR/replay-test.js" << 'JSEOF'
const WebSocket = require('ws');
const port = process.argv[2];
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const timeout = setTimeout(() => { console.log('TIMEOUT:no_update_received'); process.exit(1); }, 8000);

ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'refresh' }));
});

ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'update' && msg.url) {
        if (msg.url.includes('/png/~1')) {
            console.log('OK');
        } else {
            console.log('FAIL:bad_url=' + msg.url);
        }
        clearTimeout(timeout);
        ws.close();
        process.exit(0);
    }
});

ws.on('error', (e) => { console.log('ERROR:' + e.message); process.exit(1); });
JSEOF

result=$(node "$TEST_TMP_DIR/replay-test.js" "$WS_PORT" 2>&1)
if [ "$result" = "OK" ]; then
    echo "PASS: Fresh WS client receives stored diagram via replay"
else
    echo "FAIL: Replay to fresh client: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test 2: Second WS client also receives the diagram (after first consumed pending_file)
# This specifically tests the fallback path since pending_file is nil for the second client.
result=$(node "$TEST_TMP_DIR/replay-test.js" "$WS_PORT" 2>&1)
if [ "$result" = "OK" ]; then
    echo "PASS: Second WS client receives diagram (fallback replay)"
else
    echo "FAIL: Fallback replay to second client: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES replay fallback test(s) FAILED ==="
    exit 1
fi
echo "=== All replay fallback tests passed ==="
