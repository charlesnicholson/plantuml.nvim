#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing PlantUML processing..."

# Setup isolated test environment
setup_test_env

# Test 1: Load PlantUML file and trigger update
echo "Test 1: Load PlantUML file and trigger update"

# Create WebSocket listener script in temp directory
cat > "$TEST_TMP_DIR/websocket_listener.js" << EOF
const WebSocket = require('$(pwd)/node_modules/ws');

const timeout = setTimeout(() => {
    console.log('Timeout waiting for update');
    process.exit(1);
}, 30000);

function connect() {
    const ws = new WebSocket('ws://127.0.0.1:${TEST_WS_PORT}');

    ws.on('open', () => {
        console.log('WebSocket listener connected');
        ws.send(JSON.stringify({type: 'refresh'}));
    });

    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data.toString());
            console.log('Received:', JSON.stringify(message, null, 2));

            if (message.type === 'update') {
                clearTimeout(timeout);
                ws.close();
                process.exit(0);
            }
            // If we got a status message, keep waiting for update
        } catch (err) {
            console.error('Parse error:', err);
        }
    });

    ws.on('error', (err) => {
        console.log('Connection error, retrying...');
        setTimeout(connect, 500);
    });

    ws.on('close', () => {
        // Reconnect if we didn't get an update yet
        console.log('Connection closed, reconnecting...');
        setTimeout(connect, 500);
    });
}

connect();
EOF

# Start WebSocket listener in background
node "$TEST_TMP_DIR/websocket_listener.js" > "$TEST_TMP_DIR/ws_output.log" 2>&1 &
LISTENER_PID=$!
track_pid "$LISTENER_PID"

# Start Neovim with plugin and process file (clean mode, only local plugin)
echo "Starting Neovim and processing PlantUML file..."
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $TEST_HTTP_PORT}); p.start()" \
    -c "edit tests/fixtures/simple.puml" \
    -c "set filetype=plantuml" \
    -c "sleep 2" \
    -c "lua require('plantuml').update_diagram()" \
    -c "sleep 2" \
    -c "qall!" 2>&1 &
NVIM_PID=$!
track_pid "$NVIM_PID"

# Wait for listener to receive update (it will exit 0 on success)
if wait $LISTENER_PID 2>/dev/null; then
    echo "✓ WebSocket update message received"
else
    echo "✗ No WebSocket update message received"
    echo "WebSocket output:"
    cat "$TEST_TMP_DIR/ws_output.log" || true
    exit 1
fi

# Wait for nvim to finish
wait $NVIM_PID 2>/dev/null || true

# Test 2: Verify message contains URL
echo "Test 2: Verify message contains PlantUML URL"
if grep -q '"url"' "$TEST_TMP_DIR/ws_output.log" && grep -q 'plantuml' "$TEST_TMP_DIR/ws_output.log"; then
    echo "✓ Message contains PlantUML URL"
else
    echo "✗ Message does not contain PlantUML URL"
    exit 1
fi

# Test 3: Verify message contains filename
echo "Test 3: Verify message contains filename"
if grep -q '"filename"' "$TEST_TMP_DIR/ws_output.log"; then
    echo "✓ Message contains filename"
else
    echo "✗ Message does not contain filename"
    exit 1
fi

# Test 4: Verify message contains timestamp field
echo "Test 4: Verify message contains timestamp field"
if grep -q '"timestamp"' "$TEST_TMP_DIR/ws_output.log"; then
    echo "✓ Message contains timestamp field"
else
    echo "✗ Message does not contain timestamp field"
    exit 1
fi

# Test 5: Verify message contains server_url field
echo "Test 5: Verify message contains server_url field"
if grep -q '"server_url"' "$TEST_TMP_DIR/ws_output.log"; then
    echo "✓ Message contains server_url field"
else
    echo "✗ Message does not contain server_url field"
    exit 1
fi

# Test 6: Extract and verify PlantUML URL structure
echo "Test 6: Verify PlantUML URL structure"
PLANTUML_URL=$(grep -o 'http://www\.plantuml\.com/plantuml/png/~1[^"]*' "$TEST_TMP_DIR/ws_output.log" || true)
if [ -n "$PLANTUML_URL" ]; then
    echo "✓ PlantUML URL has correct structure"
else
    echo "✗ PlantUML URL has incorrect structure"
    exit 1
fi

# Test 7: Verify URL accessibility (basic check)
echo "Test 7: Verify PlantUML URL accessibility"
if curl -f -s --max-time 10 "$PLANTUML_URL" > /dev/null; then
    echo "✓ PlantUML URL is accessible"
else
    echo "⚠ PlantUML URL not accessible (may be network issue)"
    # Don't fail the test for network issues
fi

echo "✓ All PlantUML processing tests passed"
