#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing HTTP server..."

# Setup isolated test environment
setup_test_env

# Start Neovim with plugin in background (clean mode, only local plugin)
echo "Starting Neovim with plugin..."
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $TEST_HTTP_PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

# Wait for health endpoint to report ready
if ! wait_for_health 10; then
    echo "✗ Server failed to become ready"
    exit 1
fi

# Test 1: HTTP server responds on correct port
echo "Test 1: HTTP server responds on port $TEST_HTTP_PORT"
if curl -f -s "http://127.0.0.1:$TEST_HTTP_PORT" > /dev/null; then
    echo "✓ HTTP server responding"
else
    echo "✗ HTTP server not responding"
    exit 1
fi

# Test 2: Server returns HTML content
echo "Test 2: Server returns HTML content"
RESPONSE=$(curl -s "http://127.0.0.1:$TEST_HTTP_PORT")
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
if echo "$RESPONSE" | grep -q "<style>" && echo "$RESPONSE" | grep -q "board"; then
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
HEADERS=$(curl -I -s "http://127.0.0.1:$TEST_HTTP_PORT")
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

# Test 8: Health endpoint works
echo "Test 8: Health endpoint returns JSON"
HEALTH=$(curl -s "http://127.0.0.1:$TEST_HTTP_PORT/health")
if echo "$HEALTH" | grep -q '"state"'; then
    echo "✓ Health endpoint returns state"
else
    echo "✗ Health endpoint invalid"
    exit 1
fi

echo "✓ All HTTP server tests passed"
