#!/bin/bash
# Integration test: save file → WS update message with encoded URL.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Update Cycle Tests ==="

setup_test_env

FAILURES=0
PORT="$TEST_HTTP_PORT"
WS_PORT="$((PORT + 1))"
FIXTURE="$PLUGIN_DIR/tests/fixtures/simple.puml"

# Start nvim with a puml buffer, setup, and start server
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "edit $FIXTURE" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, auto_update = false, http_port = $PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

if ! wait_for_health 10 "$PORT"; then
    echo "FAIL: Server did not start"
    exit 1
fi

# Check for node + ws
if ! command -v node &>/dev/null || ! node -e "require('ws')" 2>/dev/null; then
    echo "SKIP: Node.js or ws module not available"
    exit 0
fi

# Test: Trigger update_diagram via RPC and check that WS client receives an update message
# We'll connect a WS client, then send a refresh + wait for update
cat > "$TEST_TMP_DIR/update-test.js" << 'EOF'
const WebSocket = require('ws');
const port = process.argv[2];
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const timeout = setTimeout(() => { console.log('TIMEOUT'); process.exit(1); }, 10000);

ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'refresh' }));
});

ws.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'update' && msg.url) {
        // Verify the URL contains the PlantUML encoding prefix
        if (msg.url.includes('/png/~1')) {
            console.log('OK:url=' + msg.url.substring(0, 60) + '...');
        } else {
            console.log('FAIL:bad_url=' + msg.url);
        }
        clearTimeout(timeout);
        ws.close();
        process.exit(0);
    }
    // Status messages are expected, keep waiting for update
});

ws.on('error', (e) => { console.log('ERROR:' + e.message); process.exit(1); });
EOF

# Give the WS client a moment to connect, then trigger update via separate nvim command
# We need to trigger update in the running nvim instance
# Since we can't easily RPC, we'll test that stored messages are replayed on connect

# First, trigger update by writing to the buffer via a second nvim invocation
# that connects to the same server... Actually, the running nvim should already
# have the fixture loaded. We need to trigger update_diagram() in it.

# Simpler approach: start another nvim that triggers an update, then connect WS
# to see if the update was stored and replayed.

# Kill the running nvim and start fresh with auto_update
kill "$NVIM_PID" 2>/dev/null || true
wait "$NVIM_PID" 2>/dev/null || true
sleep 0.5

# Start nvim that loads a file and immediately triggers update
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "set filetype=plantuml" \
    -c "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'@startuml', 'Bob -> Alice : hello', '@enduml'})" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, auto_update = false, http_port = $PORT}); p.start(); p.update_diagram()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

if ! wait_for_health 10 "$PORT"; then
    echo "FAIL: Server did not restart"
    exit 1
fi

# Now connect WS client — it should receive the stored update on refresh
result=$(node "$TEST_TMP_DIR/update-test.js" "$WS_PORT" 2>&1)
if [[ "$result" == OK:* ]]; then
    echo "PASS: Update cycle produces encoded URL via WebSocket"
else
    echo "FAIL: Update cycle: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES update cycle test(s) FAILED ==="
    exit 1
fi
echo "=== All update cycle tests passed ==="
