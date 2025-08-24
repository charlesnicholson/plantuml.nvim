#!/bin/bash
set -euo pipefail



echo "Testing WebSocket server..."

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..."
nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start()" &
NVIM_PID=$!
echo "Neovim started with PID: $NVIM_PID"

# Verify both servers are running before proceeding
echo "Verifying servers are ready..."
for i in {1..10}; do
    if netstat -ln | grep ":8764" && netstat -ln | grep ":8765"; then
        echo "Both servers are listening"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "Servers not ready after 10 seconds"
        netstat -ln | grep ":876" || true
        exit 1
    fi
    # Shorter sleep interval for faster detection
    sleep 0.5
done

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    # Skip graceful shutdown for speed - just force kill
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Create WebSocket test script  
cat > /tmp/websocket_test.js << EOF
const WebSocket = require('$(pwd)/node_modules/ws');

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
        
        // Close after 500ms - enough time for handshake and message exchange
        setTimeout(() => {
            ws.close();
            // Force exit after a short delay if close event doesn't fire
            setTimeout(() => {
                resolve(results);
            }, 100);
        }, 500);
    });
}

testWebSocket().then(results => {
    console.log('Test results:', JSON.stringify(results, null, 2));
    // Force immediate exit to prevent event loop hanging
    const exitCode = results.connected && results.handshake ? 0 : 1;
    setTimeout(() => process.exit(exitCode), 50);
}).catch(err => {
    console.error('Test failed:', err);
    setTimeout(() => process.exit(1), 50);
});
EOF

# Test 1: WebSocket server is listening on port 8765
echo "Test 1: WebSocket server is listening on port 8765"
if netstat -ln | grep ":8765"; then
    echo "✓ WebSocket server listening on port 8765"
else
    echo "✗ WebSocket server not listening on port 8765"
    # Try to get more info
    netstat -ln | grep ":876" || true
    exit 1
fi

# Test 2: WebSocket connection and handshake
echo "Test 2: WebSocket connection and handshake"
if node /tmp/websocket_test.js 2>&1; then
    echo "✓ WebSocket connection and handshake successful"
else
    echo "✗ WebSocket connection or handshake failed"
    exit 1
fi

echo "✓ All WebSocket tests passed"