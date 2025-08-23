#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/test-websocket-new-fields.log"

mkdir -p "$SCRIPT_DIR/logs"

echo "Testing WebSocket new fields (timestamp and server_url)..." | tee "$LOG_FILE"

cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    if [ ! -z "$NVIM_PID" ]; then
        kill -TERM "$NVIM_PID" 2>/dev/null || true
        wait "$NVIM_PID" 2>/dev/null || true
    fi
    if [ ! -z "$LISTENER_PID" ]; then
        kill -TERM "$LISTENER_PID" 2>/dev/null || true
        wait "$LISTENER_PID" 2>/dev/null || true
    fi
    rm -f /tmp/websocket_listener.js /tmp/ws_output.log /tmp/test.puml
}

trap cleanup EXIT

# Create WebSocket listener script
cat > /tmp/websocket_listener.js << 'EOF'
const WebSocket = require('ws');
const net = require('net');

function listenForUpdates() {
    return new Promise((resolve, reject) => {
        let ws;
        let updateReceived = false;
        let messageData = null;
        let connectionAttempts = 0;
        const maxAttempts = 15;
        
        function tryConnect() {
            connectionAttempts++;
            console.log(`Connection attempt ${connectionAttempts}/${maxAttempts}`);
            
            // First check if server is ready
            const socket = new net.Socket();
            socket.setTimeout(2000);
            
            socket.on('timeout', () => {
                socket.destroy();
                if (connectionAttempts < maxAttempts) {
                    console.log('Server not ready, retrying in 1 second...');
                    setTimeout(tryConnect, 1000);
                } else {
                    reject(new Error('Server not available after max attempts'));
                }
            });
            
            socket.on('error', () => {
                socket.destroy();
                if (connectionAttempts < maxAttempts) {
                    console.log('Server not ready, retrying in 1 second...');
                    setTimeout(tryConnect, 1000);
                } else {
                    reject(new Error('Server not available after max attempts'));
                }
            });
            
            socket.on('connect', () => {
                socket.destroy();
                
                // Server is ready, now try WebSocket connection
                ws = new WebSocket('ws://127.0.0.1:8765');
                
                ws.on('open', () => {
                    console.log('WebSocket listener connected');
                    // Send refresh to get any existing messages
                    ws.send(JSON.stringify({type: 'refresh'}));
                });
                
                ws.on('message', (data) => {
                    try {
                        const message = JSON.parse(data.toString());
                        console.log('Received message:', JSON.stringify(message, null, 2));
                        
                        if (message.type === 'update') {
                            updateReceived = true;
                            messageData = message;
                            ws.close();
                        }
                    } catch (err) {
                        console.error('Failed to parse message:', err);
                    }
                });
                
                ws.on('error', (err) => {
                    console.error('WebSocket error:', err.message);
                    if (connectionAttempts < maxAttempts) {
                        console.log('Retrying WebSocket connection in 1 second...');
                        setTimeout(tryConnect, 1000);
                    } else {
                        reject(err);
                    }
                });
                
                ws.on('close', () => {
                    if (updateReceived) {
                        resolve({ updateReceived, messageData });
                    } else if (connectionAttempts < maxAttempts) {
                        console.log('WebSocket connection closed, retrying...');
                        setTimeout(tryConnect, 1000);
                    } else {
                        resolve({ updateReceived: false, messageData: null });
                    }
                });
            });
            
            // Try to connect to check if server is ready
            socket.connect(8765, '127.0.0.1');
        }
        
        tryConnect();
        
        // Timeout after 20 seconds total
        setTimeout(() => {
            if (!updateReceived) {
                console.log('No update received within timeout');
            }
            if (ws) {
                ws.close();
            }
            resolve({ updateReceived, messageData });
        }, 20000);
    });
}

listenForUpdates().then(result => {
    console.log('Listener result:', JSON.stringify(result, null, 2));
    process.exit(0);
}).catch(err => {
    console.error('Listener failed:', err);
    process.exit(1);
});
EOF

# Test 1: Verify new fields are included in WebSocket message
echo "Test 1: Verify new fields are included in WebSocket message" | tee -a "$LOG_FILE"

# Start WebSocket listener first
node /tmp/websocket_listener.js > /tmp/ws_output.log 2>&1 &
LISTENER_PID=$!

# Give listener time to start
sleep 1

# Create test PlantUML file
cat > /tmp/test.puml << 'EOF'
@startuml
Alice -> Bob : Hello
@enduml
EOF

# Start Neovim with plugin and process file in the same session
timeout 15s nvim --headless -c "set runtimepath+=$(pwd)" -c "lua require('plantuml').setup(); require('plantuml').start()" -c "edit /tmp/test.puml" -c "lua require('plantuml').update_diagram()" -c "sleep 5" -c "qall!" > /dev/null 2>&1 &
NVIM_PID=$!

# Wait for processing
sleep 8

# Stop the listener
if [ ! -z "$LISTENER_PID" ]; then
    kill -TERM "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
fi

# Check the output
if [ -f /tmp/ws_output.log ]; then
    cat /tmp/ws_output.log | tee -a "$LOG_FILE"
    
    # Check for required fields
    if grep -q '"updateReceived":.*true' /tmp/ws_output.log; then
        echo "✓ WebSocket update message received" | tee -a "$LOG_FILE"
    else
        echo "✗ No WebSocket update message received" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Test 2: Check for timestamp field
    echo "Test 2: Check for timestamp field" | tee -a "$LOG_FILE"
    if grep -q '"timestamp"' /tmp/ws_output.log; then
        echo "✓ Message contains timestamp field" | tee -a "$LOG_FILE"
    else
        echo "✗ Message missing timestamp field" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Test 3: Check for server_url field
    echo "Test 3: Check for server_url field" | tee -a "$LOG_FILE"
    if grep -q '"server_url"' /tmp/ws_output.log; then
        echo "✓ Message contains server_url field" | tee -a "$LOG_FILE"
    else
        echo "✗ Message missing server_url field" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Test 4: Verify timestamp format
    echo "Test 4: Verify timestamp format" | tee -a "$LOG_FILE"
    if grep -q '"timestamp":.*"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]"' /tmp/ws_output.log; then
        echo "✓ Timestamp has correct format (YYYY-MM-DD HH:MM:SS)" | tee -a "$LOG_FILE"
    else
        echo "✗ Timestamp format incorrect" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # Test 5: Verify server_url content
    echo "Test 5: Verify server_url content" | tee -a "$LOG_FILE"
    if grep -q '"server_url":.*"http://www.plantuml.com/plantuml"' /tmp/ws_output.log; then
        echo "✓ Server URL has correct value" | tee -a "$LOG_FILE"
    else
        echo "✗ Server URL has incorrect value" | tee -a "$LOG_FILE"
        exit 1
    fi
    
else
    echo "✗ No WebSocket output captured" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All WebSocket new fields tests passed" | tee -a "$LOG_FILE"