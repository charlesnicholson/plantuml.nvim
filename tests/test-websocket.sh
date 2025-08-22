#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/websocket.log"
echo "Testing WebSocket server..." | tee "$LOG_FILE"

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..." | tee -a "$LOG_FILE"
nvim --headless -u ~/.config/nvim/init.lua -c "lua require('plantuml').start()" &
NVIM_PID=$!
echo "Neovim started with PID: $NVIM_PID" | tee -a "$LOG_FILE"

# Give server time to start
sleep 5

# Verify both servers are running before proceeding
echo "Verifying servers are ready..." | tee -a "$LOG_FILE"
for i in {1..10}; do
    if netstat -ln | grep ":8764" && netstat -ln | grep ":8765"; then
        echo "Both servers are listening" | tee -a "$LOG_FILE"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "Servers not ready after 10 seconds" | tee -a "$LOG_FILE"
        netstat -ln | grep ":876" | tee -a "$LOG_FILE" || true
        exit 1
    fi
    sleep 1
done

# Cleanup function
cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
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

# Test 3: WebSocket upgrade handshake validation with Node.js
echo "Test 3: WebSocket upgrade handshake validation" | tee -a "$LOG_FILE"

# Create a more robust WebSocket upgrade test using Node.js
cat > /tmp/websocket_upgrade_test.js << EOF
const net = require('net');
const crypto = require('crypto');

function testWebSocketUpgrade() {
    return new Promise((resolve, reject) => {
        const socket = new net.Socket();
        let responseData = '';
        
        socket.setTimeout(5000); // 5 second timeout
        
        socket.on('data', (data) => {
            responseData += data.toString();
            // Check if we have the complete HTTP response
            if (responseData.includes('\r\n\r\n')) {
                socket.end();
                resolve(responseData);
            }
        });
        
        socket.on('timeout', () => {
            socket.destroy();
            reject(new Error('Connection timeout'));
        });
        
        socket.on('error', (err) => {
            reject(err);
        });
        
        socket.on('close', () => {
            if (!responseData.includes('\r\n\r\n')) {
                reject(new Error('Connection closed before complete response'));
            }
        });
        
        socket.connect(8765, '127.0.0.1', () => {
            const key = 'dGhlIHNhbXBsZSBub25jZQ==';
            const request = [
                'GET / HTTP/1.1',
                'Host: 127.0.0.1:8765',
                'Upgrade: websocket',
                'Connection: Upgrade',
                'Sec-WebSocket-Key: ' + key,
                'Sec-WebSocket-Version: 13',
                '',
                ''
            ].join('\r\n');
            
            socket.write(request);
        });
    });
}

testWebSocketUpgrade().then(response => {
    console.log('WebSocket upgrade response received');
    
    // Check for 101 Switching Protocols
    if (response.includes('101 Switching Protocols')) {
        console.log('✓ Status: 101 Switching Protocols');
    } else {
        console.log('✗ Missing 101 Switching Protocols status');
        console.log('Response:', response.substring(0, 200));
        process.exit(1);
    }
    
    // Check for Sec-WebSocket-Accept header
    if (response.includes('Sec-WebSocket-Accept:')) {
        console.log('✓ Sec-WebSocket-Accept header present');
    } else {
        console.log('✗ Sec-WebSocket-Accept header missing');
        console.log('Response headers:', response.split('\r\n\r\n')[0]);
        process.exit(1);
    }
    
    process.exit(0);
}).catch(err => {
    console.error('WebSocket upgrade test failed:', err.message);
    process.exit(1);
});
EOF

if node /tmp/websocket_upgrade_test.js 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ WebSocket upgrade handshake validation successful" | tee -a "$LOG_FILE"
else
    echo "✗ WebSocket upgrade handshake validation failed" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All WebSocket tests passed" | tee -a "$LOG_FILE"