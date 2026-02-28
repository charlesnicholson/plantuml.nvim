#!/bin/bash
# Unit tests for encoder.lua — verify PlantUML URL encoding.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Encoder Unit Tests ==="

FAILURES=0

# Test basic encoding: "@startuml\nBob -> Alice : hello\n@enduml"
# The encoded URL should start with the server URL + /png/~1
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local enc = require("plantuml.encoder")
        local text = "@startuml\nBob -> Alice : hello\n@enduml"
        local url = enc.encode(text, "http://www.plantuml.com/plantuml")
        io.write(url)
    end' \
    -c "qall!" 2>&1)

if [[ "$result" == http://www.plantuml.com/plantuml/png/~1* ]]; then
    echo "PASS: Encoder produces correct URL prefix"
else
    echo "FAIL: Encoder URL prefix: got $result"
    FAILURES=$((FAILURES + 1))
fi

# Verify encoded URL is non-empty after the prefix
encoded_part="${result#http://www.plantuml.com/plantuml/png/~1}"
if [ -n "$encoded_part" ]; then
    echo "PASS: Encoded data is non-empty"
else
    echo "FAIL: Encoded data is empty"
    FAILURES=$((FAILURES + 1))
fi

# Verify URL only contains valid PlantUML base64 characters
if [[ "$encoded_part" =~ ^[0-9A-Za-z_-]+$ ]]; then
    echo "PASS: Encoded data uses valid PlantUML base64 alphabet"
else
    echo "FAIL: Encoded data contains invalid characters: $encoded_part"
    FAILURES=$((FAILURES + 1))
fi

# Test with different server URL
result2=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local enc = require("plantuml.encoder")
        local url = enc.encode("@startuml\nA -> B\n@enduml", "http://localhost:8080")
        io.write(url)
    end' \
    -c "qall!" 2>&1)

if [[ "$result2" == http://localhost:8080/png/~1* ]]; then
    echo "PASS: Encoder respects custom server URL"
else
    echo "FAIL: Custom server URL: got $result2"
    FAILURES=$((FAILURES + 1))
fi

# Test determinism: same input → same output
result3a=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local enc = require("plantuml.encoder")
        io.write(enc.encode("@startuml\ntest\n@enduml", "http://x"))
    end' \
    -c "qall!" 2>&1)

result3b=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local enc = require("plantuml.encoder")
        io.write(enc.encode("@startuml\ntest\n@enduml", "http://x"))
    end' \
    -c "qall!" 2>&1)

if [ "$result3a" = "$result3b" ]; then
    echo "PASS: Encoding is deterministic"
else
    echo "FAIL: Encoding not deterministic: '$result3a' != '$result3b'"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES encoder test(s) FAILED ==="
    exit 1
fi
echo "=== All encoder tests passed ==="
