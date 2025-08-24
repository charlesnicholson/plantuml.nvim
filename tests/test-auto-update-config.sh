#!/bin/bash
set -euo pipefail

# Create temporary directory
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Testing auto_update configuration option..."

# Test 1: Default configuration has auto_update = true
echo "Test 1: Default configuration has auto_update = true"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({}); local config = p.get_config(); assert(config.auto_update == true, 'auto_update should default to true'); print('Default auto_update is true')" -c "qall!" 2>&1; then
    echo "✓ Default auto_update configuration is correct"
else
    echo "✗ Default auto_update configuration failed"
    exit 1
fi

# Test 2: Can configure auto_update = false
echo "Test 2: Can configure auto_update = false"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_update = false}); local config = p.get_config(); assert(config.auto_update == false, 'auto_update should be false'); print('auto_update set to false')" -c "qall!" 2>&1; then
    echo "✓ auto_update can be configured to false"
else
    echo "✗ auto_update configuration to false failed"
    exit 1
fi

# Test 3: Manual update_diagram still works when auto_update = false
echo "Test 3: Manual update_diagram still works when auto_update = false"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, auto_update = false}); p.start(); p.update_diagram(); print('Manual update_diagram works'); p.stop()" -c "qall!" 2>&1; then
    echo "✓ Manual update_diagram works when auto_update = false"
else
    echo "✗ Manual update_diagram failed when auto_update = false"
    exit 1
fi

# Test 4: Configuration preserves other options when auto_update is set
echo "Test 4: Configuration preserves other options when auto_update is set"
if nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_update = false, http_port = 9999}); local config = p.get_config(); assert(config.auto_update == false and config.http_port == 9999, 'Configuration should preserve all options'); print('Configuration preserves all options')" -c "qall!" 2>&1; then
    echo "✓ Configuration preserves other options correctly"
else
    echo "✗ Configuration failed to preserve other options"
    exit 1
fi

echo "✓ All auto_update configuration tests passed"