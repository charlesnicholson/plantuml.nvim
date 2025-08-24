#!/bin/bash
set -euo pipefail



echo "Testing plugin loading..."

# Test 1: Plugin loads without errors
echo "Test 1: Plugin loads without errors"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); print('Plugin loaded successfully')" -c "qall!" 2>&1; then
    echo "✓ Plugin loaded successfully"
else
    echo "✗ Plugin failed to load"
    exit 1
fi

# Test 2: Check if required dependencies are available  
echo "Test 2: Check LuaJIT bit library availability"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua assert(pcall(require, 'bit'), 'bit library not found'); print('bit library available')" -c "qall!" 2>&1; then
    echo "✓ LuaJIT bit library available"
else
    echo "✗ LuaJIT bit library not available"
    exit 1
fi

# Test 3: Plugin module exports expected functions
echo "Test 3: Plugin exports expected functions"
EXPECTED_FUNCTIONS="start stop is_running open_browser update_diagram setup get_config"
for func in $EXPECTED_FUNCTIONS; do
    if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false}); assert(type(p.$func) == 'function', '$func not found'); print('Function $func found')" -c "qall!" 2>&1; then
        echo "✓ Function $func exported"
    else
        echo "✗ Function $func not exported"
        exit 1
    fi
done

# Test 4: Plugin starts server successfully
echo "Test 4: Plugin starts server successfully"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false}); p.start(); print('Server started'); vim.wait(1000); p.stop(); print('Server stopped')" -c "qall!" 2>&1; then
    echo "✓ Server starts and stops successfully"
else
    echo "✗ Server failed to start/stop"
    exit 1
fi

# Test 5: Plugin configuration works
echo "Test 5: Plugin configuration works"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); local config = p.get_config(); assert(config.http_port == 8764, 'Wrong port'); print('Configuration loaded correctly')" -c "qall!" 2>&1; then
    echo "✓ Configuration loaded correctly"
else
    echo "✗ Configuration failed to load"
    exit 1
fi

echo "✓ All plugin loading tests passed"