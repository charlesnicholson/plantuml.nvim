#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/http-server.log"
echo "Testing HTTP server..." | tee "$LOG_FILE"

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

# Test 1: HTTP server responds on correct port
echo "Test 1: HTTP server responds on port 8764" | tee -a "$LOG_FILE"
if curl -f -s "http://127.0.0.1:8764" > /dev/null; then
    echo "✓ HTTP server responding" | tee -a "$LOG_FILE"
else
    echo "✗ HTTP server not responding" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: Server returns HTML content
echo "Test 2: Server returns HTML content" | tee -a "$LOG_FILE"
RESPONSE=$(curl -s "http://127.0.0.1:8764")
if echo "$RESPONSE" | grep -q "<!doctype html>"; then
    echo "✓ HTML content returned" | tee -a "$LOG_FILE"
else
    echo "✗ No HTML content found" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: HTML contains required elements
echo "Test 3: HTML contains required elements" | tee -a "$LOG_FILE"
REQUIRED_ELEMENTS="PlantUML.Viewer board img status-text"
for element in $REQUIRED_ELEMENTS; do
    if echo "$RESPONSE" | grep -q "$element"; then
        echo "✓ Element '$element' found" | tee -a "$LOG_FILE"
    else
        echo "✗ Element '$element' not found" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 4: CSS styles are embedded
echo "Test 4: CSS styles are embedded" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q "<style>" && echo "$RESPONSE" | grep -q "fit-to-page"; then
    echo "✓ CSS styles embedded" | tee -a "$LOG_FILE"
else
    echo "✗ CSS styles not found" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 5: JavaScript is embedded
echo "Test 5: JavaScript is embedded" | tee -a "$LOG_FILE"
if echo "$RESPONSE" | grep -q "<script>" && echo "$RESPONSE" | grep -q "WebSocket"; then
    echo "✓ JavaScript embedded" | tee -a "$LOG_FILE"
else
    echo "✗ JavaScript not found" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 6: Content-Type header is correct
echo "Test 6: Content-Type header is correct" | tee -a "$LOG_FILE"
HEADERS=$(curl -I -s "http://127.0.0.1:8764")
if echo "$HEADERS" | grep -q "Content-Type: text/html"; then
    echo "✓ Content-Type header correct" | tee -a "$LOG_FILE"
else
    echo "✗ Content-Type header incorrect" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 7: Content-Length header is present
echo "Test 7: Content-Length header is present" | tee -a "$LOG_FILE"
if echo "$HEADERS" | grep -q "Content-Length:"; then
    echo "✓ Content-Length header present" | tee -a "$LOG_FILE"
else
    echo "✗ Content-Length header missing" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All HTTP server tests passed" | tee -a "$LOG_FILE"