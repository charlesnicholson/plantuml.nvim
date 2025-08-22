#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/websocket.log"
echo "Testing WebSocket server..." | tee "$LOG_FILE"

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..." | tee -a "$LOG_FILE"
nvim --headless -u ~/.config/nvim/init.lua -c "lua require('plantuml').start()" &
NVIM_PID=$!

# Give server time to start
sleep 3

# Cleanup function
cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Create WebSocket test script  
cat > /tmp/websocket_test.js << 'EOF'
const WebSocket = require('/home/runner/work/plantuml.nvim/plantuml.nvim/node_modules/ws');

function testWebSocket() {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket('ws://127.0.0.1:8765');
        let results = {
            connected: false,
            handshake: false,
            canSendMessage: false,
            receivedResponse: false
        };
        
        ws.on('open', () => {
            console.log('WebSocket connected');
            results.connected = true;
            results.handshake = true;
            
            // Test sending a refresh message
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
                if (message.type) {
                    results.receivedResponse = true;
                }
            } catch (err) {
                console.log('Message parsing failed, but message received');
                results.receivedResponse = true;
            }
        });
        
        ws.on('error', (err) => {
            console.error('WebSocket error:', err);
            reject(err);
        });
        
        ws.on('close', () => {
            console.log('WebSocket closed');
            resolve(results);
        });
        
        // Close after 3 seconds instead of 5
        setTimeout(() => {
            ws.close();
        }, 3000);
    });
}

testWebSocket().then(results => {
    console.log('Test results:', JSON.stringify(results, null, 2));
    process.exit(results.connected && results.handshake ? 0 : 1);
}).catch(err => {
    console.error('Test failed:', err);
    process.exit(1);
});
EOF

# Test 1: WebSocket server is listening on port 8765
echo "Test 1: WebSocket server is listening on port 8765" | tee -a "$LOG_FILE"
if netstat -ln | grep ":8765"; then
    echo "✓ WebSocket server listening on port 8765" | tee -a "$LOG_FILE"
else
    echo "✗ WebSocket server not listening on port 8765" | tee -a "$LOG_FILE"
    # Try to get more info
    netstat -ln | grep ":876" | tee -a "$LOG_FILE" || true
    exit 1
fi

# Test 2: WebSocket connection and handshake
echo "Test 2: WebSocket connection and handshake" | tee -a "$LOG_FILE"
if node /tmp/websocket_test.js 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ WebSocket connection and handshake successful" | tee -a "$LOG_FILE"
else
    echo "✗ WebSocket connection or handshake failed" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: WebSocket accepts proper upgrade headers
echo "Test 3: WebSocket upgrade headers" | tee -a "$LOG_FILE"
UPGRADE_RESPONSE=$(curl -i -s \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
    -H "Sec-WebSocket-Version: 13" \
    "http://127.0.0.1:8765" || true)

if echo "$UPGRADE_RESPONSE" | grep -q "101 Switching Protocols"; then
    echo "✓ WebSocket upgrade response correct" | tee -a "$LOG_FILE"
else
    echo "✗ WebSocket upgrade response incorrect" | tee -a "$LOG_FILE"
    echo "Response: $UPGRADE_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 4: WebSocket includes proper Sec-WebSocket-Accept header
echo "Test 4: Sec-WebSocket-Accept header" | tee -a "$LOG_FILE"
if echo "$UPGRADE_RESPONSE" | grep -q "Sec-WebSocket-Accept:"; then
    echo "✓ Sec-WebSocket-Accept header present" | tee -a "$LOG_FILE"
else
    echo "✗ Sec-WebSocket-Accept header missing" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All WebSocket tests passed" | tee -a "$LOG_FILE"