#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/plugin-loading.log"
echo "Testing plugin loading..." | tee "$LOG_FILE"

# Test 1: Plugin loads without errors
echo "Test 1: Plugin loads without errors" | tee -a "$LOG_FILE"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua print('Plugin loaded successfully')" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ Plugin loaded successfully" | tee -a "$LOG_FILE"
else
    echo "✗ Plugin failed to load" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: Check if required dependencies are available  
echo "Test 2: Check LuaJIT bit library availability" | tee -a "$LOG_FILE"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua assert(pcall(require, 'bit'), 'bit library not found'); print('bit library available')" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ LuaJIT bit library available" | tee -a "$LOG_FILE"
else
    echo "✗ LuaJIT bit library not available" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: Plugin module exports expected functions
echo "Test 3: Plugin exports expected functions" | tee -a "$LOG_FILE"
EXPECTED_FUNCTIONS="start stop is_running open_browser update_diagram setup get_config"
for func in $EXPECTED_FUNCTIONS; do
    if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); assert(type(p.$func) == 'function', '$func not found'); print('Function $func found')" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
        echo "✓ Function $func exported" | tee -a "$LOG_FILE"
    else
        echo "✗ Function $func not exported" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 4: Plugin starts server successfully
echo "Test 4: Plugin starts server successfully" | tee -a "$LOG_FILE"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.start(); print('Server started'); vim.wait(1000); p.stop(); print('Server stopped')" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ Server starts and stops successfully" | tee -a "$LOG_FILE"
else
    echo "✗ Server failed to start/stop" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 5: Plugin configuration works
echo "Test 5: Plugin configuration works" | tee -a "$LOG_FILE"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); local config = p.get_config(); assert(config.http_port == 8764, 'Wrong port'); print('Configuration loaded correctly')" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ Configuration loaded correctly" | tee -a "$LOG_FILE"
else
    echo "✗ Configuration failed to load" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All plugin loading tests passed" | tee -a "$LOG_FILE"