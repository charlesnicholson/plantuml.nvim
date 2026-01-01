#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing plugin loading..."

# Test 1: Plugin loads without errors
echo "Test 1: Plugin loads without errors"
if run_nvim_clean "local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); print('Plugin loaded successfully')" 2>&1; then
    echo "✓ Plugin loaded successfully"
else
    echo "✗ Plugin failed to load"
    exit 1
fi

# Test 2: Check if required dependencies are available
echo "Test 2: Check LuaJIT bit library availability"
if run_nvim_clean "assert(pcall(require, 'bit'), 'bit library not found'); print('bit library available')" 2>&1; then
    echo "✓ LuaJIT bit library available"
else
    echo "✗ LuaJIT bit library not available"
    exit 1
fi

# Test 3: Plugin module exports expected functions
echo "Test 3: Plugin exports expected functions"
EXPECTED_FUNCTIONS="start stop is_running open_browser update_diagram setup get_config get_state"
for func in $EXPECTED_FUNCTIONS; do
    if run_nvim_clean "local p = require('plantuml'); p.setup({auto_start = false}); assert(type(p.$func) == 'function', '$func not found'); print('Function $func found')" 2>&1; then
        echo "✓ Function $func exported"
    else
        echo "✗ Function $func not exported"
        exit 1
    fi
done

# Test 4: Plugin starts server successfully
echo "Test 4: Plugin starts server successfully"
if run_nvim_clean "local p = require('plantuml'); p.setup({auto_start = false}); p.start(); print('Server started'); vim.wait(1000); p.stop(); print('Server stopped')" 2>&1; then
    echo "✓ Server starts and stops successfully"
else
    echo "✗ Server failed to start/stop"
    exit 1
fi

# Test 5: Plugin configuration works
echo "Test 5: Plugin configuration works"
if run_nvim_clean "local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); local config = p.get_config(); assert(config.http_port == 8764, 'Wrong port'); print('Configuration loaded correctly')" 2>&1; then
    echo "✓ Configuration loaded correctly"
else
    echo "✗ Configuration failed to load"
    exit 1
fi

echo "✓ All plugin loading tests passed"
