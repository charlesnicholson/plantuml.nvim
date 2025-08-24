#!/bin/bash

set -e

echo "Testing HTML file loading functionality..."

# Create temporary directory and log file
TEMP_DIR=$(mktemp -d)
LOG_FILE="$TEMP_DIR/test-html-file-loading.log"
echo "Starting HTML file loading tests..." > "$LOG_FILE"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Test 1: Verify HTML file exists
echo "Test 1: Verify HTML file exists" | tee -a "$LOG_FILE"
HTML_FILE="lua/plantuml/assets/viewer.html"
if [ -f "$HTML_FILE" ]; then
    echo "✓ HTML file exists at $HTML_FILE" | tee -a "$LOG_FILE"
else
    echo "✗ HTML file not found at $HTML_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: Verify HTML file is valid HTML
echo "Test 2: Verify HTML file is valid HTML" | tee -a "$LOG_FILE"
if grep -q "<!doctype html>" "$HTML_FILE" && grep -q "</html>" "$HTML_FILE"; then
    echo "✓ HTML file has valid structure" | tee -a "$LOG_FILE"
else
    echo "✗ HTML file does not have valid structure" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: Verify HTML file contains required elements
echo "Test 3: Verify HTML file contains required elements" | tee -a "$LOG_FILE"
REQUIRED_ELEMENTS="PlantUML.Viewer board img status-text"
for element in $REQUIRED_ELEMENTS; do
    if grep -q "$element" "$HTML_FILE"; then
        echo "✓ Element '$element' found in HTML file" | tee -a "$LOG_FILE"
    else
        echo "✗ Element '$element' not found in HTML file" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 4: Verify HTML file contains CSS styles
echo "Test 4: Verify HTML file contains CSS styles" | tee -a "$LOG_FILE"
CSS_CLASSES="server-link timestamp filename-section status-section"
for css_class in $CSS_CLASSES; do
    if grep -q "\.$css_class{" "$HTML_FILE"; then
        echo "✓ CSS class '$css_class' found in HTML file" | tee -a "$LOG_FILE"
    else
        echo "✗ CSS class '$css_class' not found in HTML file" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 5: Verify HTML file contains JavaScript
echo "Test 5: Verify HTML file contains JavaScript" | tee -a "$LOG_FILE"
JS_FUNCTIONS="setStatus connect truncateFilename"
for js_function in $JS_FUNCTIONS; do
    if grep -q "function $js_function" "$HTML_FILE"; then
        echo "✓ JavaScript function '$js_function' found in HTML file" | tee -a "$LOG_FILE"
    else
        echo "✗ JavaScript function '$js_function' not found in HTML file" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 6: Test HTML file loading in Neovim
echo "Test 6: Test HTML file loading in Neovim" | tee -a "$LOG_FILE"

# Start Neovim with the plugin and test HTML loading
cat > test_html_loading.lua << 'EOF'
-- Test script to verify HTML file loading
local plantuml = require("plantuml")

-- Try to start server to trigger HTML loading
local success, error = pcall(function()
    plantuml.start()
    plantuml.stop()
end)

if success then
    print("HTML_LOADING_SUCCESS")
else
    print("HTML_LOADING_ERROR: " .. tostring(error))
end

vim.cmd("qall!")
EOF

NVIM_OUTPUT=$(nvim --headless --noplugin -u NONE -c "set rtp+=$PWD" -c "lua dofile('test_html_loading.lua')" 2>&1)
echo "Neovim output: $NVIM_OUTPUT" | tee -a "$LOG_FILE"

if echo "$NVIM_OUTPUT" | grep -q "HTML_LOADING_SUCCESS"; then
    echo "✓ HTML file loads successfully in Neovim" | tee -a "$LOG_FILE"
elif echo "$NVIM_OUTPUT" | grep -q "HTML_LOADING_ERROR"; then
    echo "✗ HTML file loading failed in Neovim" | tee -a "$LOG_FILE"
    echo "$NVIM_OUTPUT" | tee -a "$LOG_FILE"
    exit 1
else
    echo "✗ Unexpected output from Neovim test" | tee -a "$LOG_FILE"
    echo "$NVIM_OUTPUT" | tee -a "$LOG_FILE"
    exit 1
fi

# Cleanup
rm -f test_html_loading.lua

# Test 7: Compare file size reduction
echo "Test 7: Compare file size reduction" | tee -a "$LOG_FILE"
INIT_LUA_LINES=$(wc -l < lua/plantuml/init.lua)
HTML_FILE_LINES=$(wc -l < "$HTML_FILE")
echo "✓ init.lua reduced to $INIT_LUA_LINES lines" | tee -a "$LOG_FILE"
echo "✓ HTML extracted to $HTML_FILE_LINES lines in separate file" | tee -a "$LOG_FILE"

if [ $INIT_LUA_LINES -lt 400 ]; then
    echo "✓ Significant reduction in init.lua size" | tee -a "$LOG_FILE"
else
    echo "✗ init.lua size not significantly reduced" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ All HTML file loading tests passed" | tee -a "$LOG_FILE"