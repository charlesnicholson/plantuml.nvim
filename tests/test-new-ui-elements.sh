#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/test-new-ui-elements.log"

mkdir -p "$SCRIPT_DIR/logs"

echo "Testing new UI elements (timestamp and server URL)..." | tee "$LOG_FILE"

cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    if [ ! -z "$NVIM_PID" ]; then
        kill -TERM "$NVIM_PID" 2>/dev/null || true
        wait "$NVIM_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Start Neovim with plugin
echo "Starting Neovim with plugin..." | tee -a "$LOG_FILE"
timeout 15s nvim --headless -c "set runtimepath+=$(pwd)" -c "lua require('plantuml').setup(); require('plantuml').start()" -c "sleep 8" -c "qall!" > /dev/null 2>&1 &
NVIM_PID=$!

# Wait for server to start
sleep 5

# Verify servers are ready
echo "Verifying HTTP server is ready..." | tee -a "$LOG_FILE"
for i in {1..10}; do
    if netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
        echo "HTTP server is listening" | tee -a "$LOG_FILE"
        break
    fi
    echo "Waiting for HTTP server to start (attempt $i/10)..." | tee -a "$LOG_FILE"
    sleep 1
done

# Test 1: Check if HTTP server is responding
echo "Test 1: HTTP server responds on port 8764" | tee -a "$LOG_FILE"
if curl -s --max-time 5 "http://127.0.0.1:8764" > /dev/null; then
    echo "✓ HTTP server responding" | tee -a "$LOG_FILE"
else
    echo "✗ HTTP server not responding" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: Check if HTML contains new elements
echo "Test 2: HTML contains new timestamp element" | tee -a "$LOG_FILE"
RESPONSE=$(curl -s "http://127.0.0.1:8764")
if echo "$RESPONSE" | grep -q 'id="timestamp"'; then
    echo "✓ Timestamp element found in HTML" | tee -a "$LOG_FILE"
else
    echo "✗ Timestamp element not found in HTML" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: Check if HTML contains server URL element
echo "Test 3: HTML contains new server URL element" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q 'id="server-url"'; then
    echo "✓ Server URL element found in HTML" | tee -a "$LOG_FILE"
else
    echo "✗ Server URL element not found in HTML" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 4: Check if CSS contains info class
echo "Test 4: CSS contains info class styling" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q '\.info{'; then
    echo "✓ Info class styling found in CSS" | tee -a "$LOG_FILE"
else
    echo "✗ Info class styling not found in CSS" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 5: Check if JavaScript references new elements
echo "Test 5: JavaScript references new elements" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q 'getElementById("timestamp")' && echo "$RESPONSE" | grep -q 'getElementById("server-url")'; then
    echo "✓ JavaScript references new elements" | tee -a "$LOG_FILE"
else
    echo "✗ JavaScript does not reference new elements correctly" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 6: Check if JavaScript handles new data fields
echo "Test 6: JavaScript handles new data fields" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q 'data\.timestamp' && echo "$RESPONSE" | grep -q 'data\.server_url'; then
    echo "✓ JavaScript handles new data fields" | tee -a "$LOG_FILE"
else
    echo "✗ JavaScript does not handle new data fields" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All new UI elements tests passed" | tee -a "$LOG_FILE"