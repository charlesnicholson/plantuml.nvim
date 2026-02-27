#!/bin/bash
# Integration test: WebSocket server connects, sends/receives messages.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== WebSocket Tests ==="

setup_test_env

FAILURES=0
PORT="$TEST_HTTP_PORT"
WS_PORT="$((PORT + 1))"

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

# Check if we have node and ws module available
if ! command -v node &>/dev/null; then
    echo "SKIP: Node.js not available for WebSocket tests"
    exit 0
fi

# Check for ws module
if ! node -e "require('ws')" 2>/dev/null; then
    echo "SKIP: 'ws' npm module not available"
    exit 0
fi

# Test: WebSocket connects and receives status message
cat > "$TEST_TMP_DIR/ws-test.js" << 'WSEOF'
const WebSocket = require('ws');
const port = process.argv[2];
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const timeout = setTimeout(() => { console.log('TIMEOUT'); process.exit(1); }, 5000);

ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'refresh' }));
});

let messages = [];
ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    messages.push(msg);
    // Expect at least a status message
    if (messages.length >= 1) {
        const hasStatus = messages.some(m => m.type === 'status');
        if (hasStatus) {
            console.log('OK:' + JSON.stringify(messages.map(m => m.type)));
            clearTimeout(timeout);
            ws.close();
            process.exit(0);
        }
    }
});

ws.on('error', (e) => { console.log('ERROR:' + e.message); process.exit(1); });
WSEOF

result=$(node "$TEST_TMP_DIR/ws-test.js" "$WS_PORT" 2>&1)
if [[ "$result" == OK:* ]]; then
    echo "PASS: WebSocket connects and receives status"
else
    echo "FAIL: WebSocket connection: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test: Multiple WebSocket clients can connect
cat > "$TEST_TMP_DIR/ws-multi.js" << 'MULTIEOF'
const WebSocket = require('ws');
const port = process.argv[2];
const timeout = setTimeout(() => { console.log('TIMEOUT'); process.exit(1); }, 5000);
let connected = 0;
const target = 3;

for (let i = 0; i < target; i++) {
    const ws = new WebSocket(`ws://127.0.0.1:${port}`);
    ws.on('message', () => {
        connected++;
        if (connected >= target) {
            console.log('OK:' + connected);
            clearTimeout(timeout);
            process.exit(0);
        }
    });
    ws.on('error', (e) => { console.log('ERROR:' + e.message); process.exit(1); });
}
MULTIEOF

result=$(node "$TEST_TMP_DIR/ws-multi.js" "$WS_PORT" 2>&1)
if [[ "$result" == OK:* ]]; then
    echo "PASS: Multiple WebSocket clients connect"
else
    echo "FAIL: Multiple WS clients: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES WebSocket test(s) FAILED ==="
    exit 1
fi
echo "=== All WebSocket tests passed ==="
