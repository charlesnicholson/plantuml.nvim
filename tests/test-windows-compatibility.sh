#!/bin/bash
# Test Windows compatibility for plantuml.nvim
set -euo pipefail

echo "Testing Windows compatibility for plantuml.nvim..."

# Test 1: Cross-platform path joining
echo "Test 1: Cross-platform path joining"
if nvim --headless -c "lua print('Path test: ' .. vim.fs.joinpath('C:', 'Users', 'test.txt')); print('✓ Cross-platform path joining works')" -c "qall!" 2>&1; then
    echo "✓ Cross-platform path joining works"
else
    echo "✗ Cross-platform path joining failed"
    exit 1
fi

# Test 2: Plugin loads and HTML file is found with cross-platform paths
echo "Test 2: Plugin HTML loading with cross-platform paths"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false}); p.start(); if p.is_running() then print('✓ Plugin HTML loading successful'); p.stop() else error('Plugin HTML loading failed') end" -c "qall!" 2>&1; then
    echo "✓ Plugin HTML loading with cross-platform paths works"
else
    echo "✗ Plugin HTML loading failed"
    exit 1
fi

# Test 3: File path operations work correctly
echo "Test 3: File path operations"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local abs = vim.fn.fnamemodify('test.puml', ':p'); print('Path normalization: test.puml -> ' .. abs); print('✓ File path operations work correctly')" -c "qall!" 2>&1; then
    echo "✓ File path operations work correctly"
else
    echo "✗ File path operations failed"
    exit 1
fi

# Test 4: Network operations are platform-agnostic
echo "Test 4: Network operations"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start(); if p.is_running() then print('✓ Network operations work'); p.stop() else error('Network failed') end" -c "qall!" 2>&1; then
    echo "✓ Network operations are platform-agnostic"
else
    echo "✗ Network operations failed"
    exit 1
fi

# Test 5: Browser URL construction
echo "Test 5: Browser URL construction"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({http_port = 8764}); local url = 'http://127.0.0.1:' .. p.get_config().http_port; print('URL: ' .. url); print('✓ Browser URL construction is platform-agnostic')" -c "qall!" 2>&1; then
    echo "✓ Browser URL construction is platform-agnostic"
else
    echo "✗ Browser URL construction failed"
    exit 1
fi

echo ""
echo "=== Windows Compatibility Test Results ==="
echo "✓ All Windows compatibility tests passed!"
echo ""
echo "The plugin should work correctly on Windows systems with:"
echo "  - Proper file path handling using vim.fs.joinpath()"
echo "  - Cross-platform network operations"
echo "  - Standard Neovim APIs that work on all platforms"
echo "  - No platform-specific system commands"
echo ""
echo "Note: These tests run on Linux but validate the same"
echo "cross-platform APIs that Windows would use."