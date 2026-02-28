#!/bin/bash
# Unit tests for sha1.lua — verify against known SHA-1 test vectors.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== SHA-1 Unit Tests ==="

FAILURES=0

run_sha1_test() {
    local input="$1"
    local expected_hex="$2"
    local description="$3"

    local result
    result=$(nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
        -c "lua do
            local sha1 = require('plantuml.sha1')
            local raw = sha1('$input')
            local hex = {}
            for i = 1, #raw do hex[i] = string.format('%02x', raw:byte(i)) end
            io.write(table.concat(hex))
        end" \
        -c "qall!" 2>&1)

    if [ "$result" = "$expected_hex" ]; then
        echo "PASS: $description"
    else
        echo "FAIL: $description: expected $expected_hex, got $result"
        FAILURES=$((FAILURES + 1))
    fi
}

# NIST test vectors
run_sha1_test "abc" "a9993e364706816aba3e25717850c26c9cd0d89d" "SHA-1('abc')"
run_sha1_test "" "da39a3ee5e6b4b0d3255bfef95601890afd80709" "SHA-1('')"
run_sha1_test "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" \
    "84983e441c3bd26ebaae4aa1f95129e5e54670f1" "SHA-1(448-bit message)"

# WebSocket handshake test: SHA-1("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
# Expected: b37a4f2cc0624f1690f64606cf385945b2bec4ea
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua do
        local sha1 = require('plantuml.sha1')
        local raw = sha1('dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
        local hex = {}
        for i = 1, #raw do hex[i] = string.format('%02x', raw:byte(i)) end
        io.write(table.concat(hex))
    end" \
    -c "qall!" 2>&1)

if [ "$result" = "b37a4f2cc0624f1690f64606cf385945b2bec4ea" ]; then
    echo "PASS: SHA-1 WebSocket handshake vector"
else
    echo "FAIL: SHA-1 WebSocket handshake vector: expected b37a4f2cc0624f1690f64606cf385945b2bec4ea, got $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES SHA-1 test(s) FAILED ==="
    exit 1
fi
echo "=== All SHA-1 tests passed ==="
