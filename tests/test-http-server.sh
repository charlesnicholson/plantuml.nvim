#!/bin/bash
set -euo pipefail



echo "Testing HTTP server..."

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..."
nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start()" &
NVIM_PID=$!

# Wait for server to be ready
echo "Waiting for server to be ready..."
for i in {1..10}; do
    if netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
        echo "HTTP server is listening"
        break
    fi
    echo "Waiting for HTTP server to start (attempt $i/10)..."
    sleep 1
done

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Test 1: HTTP server responds on correct port
echo "Test 1: HTTP server responds on port 8764"
if curl -f -s "http://127.0.0.1:8764" > /dev/null; then
    echo "✓ HTTP server responding"
else
    echo "✗ HTTP server not responding"
    exit 1
fi

# Test 2: Server returns HTML content
echo "Test 2: Server returns HTML content"
RESPONSE=$(curl -s "http://127.0.0.1:8764")
if echo "$RESPONSE" | grep -q "<!doctype html>"; then
    echo "✓ HTML content returned"
else
    echo "✗ No HTML content found"
    exit 1
fi

# Test 3: HTML contains required elements
echo "Test 3: HTML contains required elements"
REQUIRED_ELEMENTS="PlantUML.Viewer board img status-text"
for element in $REQUIRED_ELEMENTS; do
    if echo "$RESPONSE" | grep -q "$element"; then
        echo "✓ Element '$element' found"
    else
        echo "✗ Element '$element' not found"
        exit 1
    fi
done

# Test 4: CSS styles are embedded
echo "Test 4: CSS styles are embedded"
if echo "$RESPONSE" | grep -q "<style>" && echo "$RESPONSE" | grep -q "fit-to-page"; then
    echo "✓ CSS styles embedded"
else
    echo "✗ CSS styles not found"
    exit 1
fi

# Test 5: JavaScript is embedded
echo "Test 5: JavaScript is embedded"
if echo "$RESPONSE" | grep -q "<script>" && echo "$RESPONSE" | grep -q "WebSocket"; then
    echo "✓ JavaScript embedded"
else
    echo "✗ JavaScript not found"
    exit 1
fi

# Test 6: Content-Type header is correct
echo "Test 6: Content-Type header is correct"
HEADERS=$(curl -I -s "http://127.0.0.1:8764")
if echo "$HEADERS" | grep -q "Content-Type: text/html"; then
    echo "✓ Content-Type header correct"
else
    echo "✗ Content-Type header incorrect"
    exit 1
fi

# Test 7: Content-Length header is present
echo "Test 7: Content-Length header is present"
if echo "$HEADERS" | grep -q "Content-Length:"; then
    echo "✓ Content-Length header present"
else
    echo "✗ Content-Length header missing"
    exit 1
fi

echo "✓ All HTTP server tests passed"