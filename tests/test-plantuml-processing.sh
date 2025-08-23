#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/plantuml-processing.log"
echo "Testing PlantUML processing..." | tee "$LOG_FILE"

# Create WebSocket listener to capture messages
cat > /tmp/websocket_listener.js << EOF
const WebSocket = require('$(pwd)/node_modules/ws');

function listenForUpdates() {
    return new Promise((resolve, reject) => {
        let ws;
        let updateReceived = false;
        let messageData = null;
        let connectionAttempts = 0;
        const maxAttempts = 5;
        
        function tryConnect() {
            connectionAttempts++;
            console.log('WebSocket connection attempt', connectionAttempts);
            
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
                    console.log('Retrying connection in 1 second...');
                    setTimeout(tryConnect, 1000);
                } else {
                    reject(err);
                }
            });
            
            ws.on('close', () => {
                if (updateReceived) {
                    resolve({ updateReceived, messageData });
                } else if (connectionAttempts < maxAttempts) {
                    console.log('Connection closed, retrying...');
                    setTimeout(tryConnect, 1000);
                } else {
                    resolve({ updateReceived: false, messageData: null });
                }
            });
        }
        
        tryConnect();
        
        // Timeout after 15 seconds total
        setTimeout(() => {
            if (!updateReceived) {
                console.log('No update received within timeout');
            }
            if (ws) {
                ws.close();
            }
        }, 15000);
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

# Test 1: Load PlantUML file and trigger update
echo "Test 1: Load PlantUML file and trigger update" | tee -a "$LOG_FILE"

# Start WebSocket listener in background
node /tmp/websocket_listener.js > /tmp/ws_output.log 2>&1 &
LISTENER_PID=$!

# Give listener time to connect
sleep 2

# Use a single Neovim instance that starts the server, connects to file, and updates
echo "Starting Neovim with plugin and processing file..." | tee -a "$LOG_FILE"
nvim --headless -u ~/.config/nvim/init.lua \
    -c "lua require('plantuml').start()" \
    -c "sleep 2" \
    -c "edit tests/fixtures/simple.puml" \
    -c "set filetype=plantuml" \
    -c "lua require('plantuml').update_diagram()" \
    -c "sleep 3" \
    -c "qall!" 2>&1 | tee -a "$LOG_FILE"

# Wait for listener to capture message
sleep 2
kill $LISTENER_PID 2>/dev/null || true

# Cleanup function for any remaining processes
cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    # Kill any remaining Neovim processes
    pkill -f "nvim.*headless" 2>/dev/null || true
}
trap cleanup EXIT

# Check if update was received
if grep -q '"type": "update"' /tmp/ws_output.log; then
    echo "✓ WebSocket update message received" | tee -a "$LOG_FILE"
else
    echo "✗ No WebSocket update message received" | tee -a "$LOG_FILE"
    echo "WebSocket output:" | tee -a "$LOG_FILE"
    cat /tmp/ws_output.log | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: Verify message contains URL
echo "Test 2: Verify message contains PlantUML URL" | tee -a "$LOG_FILE"
if grep -q '"url"' /tmp/ws_output.log && grep -q 'plantuml.com' /tmp/ws_output.log; then
    echo "✓ Message contains PlantUML URL" | tee -a "$LOG_FILE"
else
    echo "✗ Message does not contain PlantUML URL" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: Verify message contains filename
echo "Test 3: Verify message contains filename" | tee -a "$LOG_FILE"
if grep -q '"filename"' /tmp/ws_output.log; then
    echo "✓ Message contains filename" | tee -a "$LOG_FILE"
else
    echo "✗ Message does not contain filename" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 4: Extract and verify PlantUML URL structure
echo "Test 4: Verify PlantUML URL structure" | tee -a "$LOG_FILE"
PLANTUML_URL=$(grep -o 'http://www\.plantuml\.com/plantuml/png/~1[^"]*' /tmp/ws_output.log || true)
if [ -n "$PLANTUML_URL" ]; then
    echo "✓ PlantUML URL has correct structure: $PLANTUML_URL" | tee -a "$LOG_FILE"
else
    echo "✗ PlantUML URL has incorrect structure" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 5: Verify URL accessibility (basic check)
echo "Test 5: Verify PlantUML URL accessibility" | tee -a "$LOG_FILE"
if curl -f -s --max-time 10 "$PLANTUML_URL" > /dev/null; then
    echo "✓ PlantUML URL is accessible" | tee -a "$LOG_FILE"
else
    echo "⚠ PlantUML URL not accessible (may be network issue)" | tee -a "$LOG_FILE"
    # Don't fail the test for network issues
fi

# Test 6: Test with more complex PlantUML content
echo "Test 6: Test with complex PlantUML content" | tee -a "$LOG_FILE"

# Start another WebSocket listener
node /tmp/websocket_listener.js > /tmp/ws_output2.log 2>&1 &
LISTENER_PID=$!
sleep 2

# Use single Neovim instance for complex content test
nvim --headless -u ~/.config/nvim/init.lua \
    -c "lua require('plantuml').start()" \
    -c "sleep 2" \
    -c "edit tests/fixtures/test.puml" \
    -c "set filetype=plantuml" \
    -c "lua require('plantuml').update_diagram()" \
    -c "sleep 3" \
    -c "qall!" 2>&1 | tee -a "$LOG_FILE"

sleep 2
kill $LISTENER_PID 2>/dev/null || true

if grep -q '"type": "update"' /tmp/ws_output2.log; then
    echo "✓ Complex PlantUML content processed successfully" | tee -a "$LOG_FILE"
else
    echo "✗ Complex PlantUML content processing failed" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All PlantUML processing tests passed" | tee -a "$LOG_FILE"