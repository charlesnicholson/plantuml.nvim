#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing WebSocket server..."

# Setup isolated test environment
setup_test_env

# Start Neovim with plugin (clean mode, only local plugin)
echo "Starting Neovim with plugin..."
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $TEST_HTTP_PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"
echo "Neovim started with PID: $NVIM_PID"

# Wait for health endpoint to report ready
if ! wait_for_health 10; then
    echo "✗ Server failed to become ready"
    exit 1
fi
echo "✓ Server is ready"

# Test 1: Health endpoint returns valid JSON
echo "Test 1: Health endpoint returns valid state"
HEALTH_RESPONSE=$(curl -sf "http://127.0.0.1:${TEST_HTTP_PORT}/health")
if echo "$HEALTH_RESPONSE" | grep -q '"state":"ready"'; then
    echo "✓ Health endpoint returns ready state"
else
    echo "✗ Health endpoint response invalid: $HEALTH_RESPONSE"
    exit 1
fi

# Test 2: WebSocket connection and handshake
echo "Test 2: WebSocket connection and handshake"
cat > "$TEST_TMP_DIR/websocket_test.js" << EOF
const WebSocket = require('$(pwd)/node_modules/ws');

function testWebSocket() {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket('ws://127.0.0.1:${TEST_WS_PORT}');
        const results = {
            connected: false,
            handshake: false,
            canSendMessage: false,
            receivedResponse: false,
            responseType: null
        };

        const timeout = setTimeout(() => {
            ws.close();
            resolve(results);
        }, 5000);

        ws.on('open', () => {
            console.log('WebSocket connected');
            results.connected = true;
            results.handshake = true;

            try {
                ws.send(JSON.stringify({type: 'refresh'}));
                results.canSendMessage = true;
                console.log('Sent refresh message');
            } catch (err) {
                console.error('Failed to send message:', err);
            }
        });

        ws.on('message', (data) => {
            console.log('Received message:', data.toString());
            try {
                const message = JSON.parse(data.toString());
                results.receivedResponse = true;
                results.responseType = message.type;
                // Got response, we can close now
                clearTimeout(timeout);
                ws.close();
            } catch (err) {
                console.log('Message parsing failed');
            }
        });

        ws.on('error', (err) => {
            console.error('WebSocket error:', err.message);
            clearTimeout(timeout);
            reject(err);
        });

        ws.on('close', () => {
            clearTimeout(timeout);
            resolve(results);
        });
    });
}

testWebSocket().then(results => {
    console.log('Test results:', JSON.stringify(results, null, 2));
    const success = results.connected && results.handshake && results.receivedResponse;
    process.exit(success ? 0 : 1);
}).catch(err => {
    console.error('Test failed:', err);
    process.exit(1);
});
EOF

if node "$TEST_TMP_DIR/websocket_test.js" 2>&1; then
    echo "✓ WebSocket connection and handshake successful"
else
    echo "✗ WebSocket connection or handshake failed"
    exit 1
fi

# Test 3: Server always responds to refresh (even without diagram)
echo "Test 3: Server responds to refresh with status"
cat > "$TEST_TMP_DIR/refresh_test.js" << EOF
const WebSocket = require('$(pwd)/node_modules/ws');

const ws = new WebSocket('ws://127.0.0.1:${TEST_WS_PORT}');
const timeout = setTimeout(() => {
    console.error('Timeout waiting for response');
    process.exit(1);
}, 5000);

ws.on('open', () => {
    ws.send(JSON.stringify({type: 'refresh'}));
});

ws.on('message', (data) => {
    clearTimeout(timeout);
    const msg = JSON.parse(data.toString());
    // Should receive either a status or update message
    if (msg.type === 'status' || msg.type === 'update') {
        console.log('Received valid response:', msg.type);
        ws.close();
        process.exit(0);
    } else {
        console.error('Unexpected message type:', msg.type);
        ws.close();
        process.exit(1);
    }
});

ws.on('error', (err) => {
    clearTimeout(timeout);
    console.error('Error:', err.message);
    process.exit(1);
});
EOF

if node "$TEST_TMP_DIR/refresh_test.js" 2>&1; then
    echo "✓ Server responds to refresh request"
else
    echo "✗ Server did not respond to refresh"
    exit 1
fi

echo "✓ All WebSocket tests passed"
