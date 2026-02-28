#!/bin/bash
# Test utilities for plantuml.nvim tests
# Source this file in test scripts: source "$(dirname "$0")/../test-utils.sh"

set -euo pipefail

# Global state
TEST_TMP_DIR=""
TRACKED_PIDS=()

# Get plugin directory (repo root).
# test-utils.sh lives in tests/, so repo root is one level up.
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    PLUGIN_DIR="$(pwd)"
fi

# Dynamic port allocation: find a free port
find_free_port() {
    python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null \
        || ruby -e "require 'socket'; s=TCPServer.new('127.0.0.1',0); puts s.addr[1]; s.close" 2>/dev/null \
        || echo $((8000 + RANDOM % 1000))
}

TEST_HTTP_PORT="${TEST_HTTP_PORT:-$(find_free_port)}"
TEST_WS_PORT="$((TEST_HTTP_PORT + 1))"

# Create isolated temp directory
setup_test_env() {
    TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plantuml-test.XXXXXX")
    trap cleanup_test_env EXIT
}

# Clean up
cleanup_test_env() {
    cleanup_pids
    if [ -n "$TEST_TMP_DIR" ] && [ -d "$TEST_TMP_DIR" ]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

track_pid() { TRACKED_PIDS+=("$1"); }

cleanup_pids() {
    for pid in "${TRACKED_PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    TRACKED_PIDS=()
    pkill -f "nvim.*headless.*plantuml" 2>/dev/null || true
}

# Run nvim headless with only the local plugin
run_nvim_clean() {
    local lua_code="$1"
    nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
        -c "lua $lua_code" \
        -c "qall!"
}

# Wait for health endpoint with exponential backoff
wait_for_health() {
    local timeout="${1:-10}"
    local port="${2:-$TEST_HTTP_PORT}"
    local url="http://127.0.0.1:${port}/health"
    local start_time=$(date +%s)
    local delay=0.1

    while true; do
        local elapsed=$(( $(date +%s) - start_time ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "FAIL: Timeout waiting for health endpoint after ${timeout}s"
            return 1
        fi
        local response
        if response=$(curl -sf "$url" 2>/dev/null); then
            local state
            state=$(echo "$response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
            if [ "$state" = "ready" ]; then
                return 0
            fi
        fi
        sleep "$delay"
        delay=$(echo "$delay * 1.5" | bc 2>/dev/null || echo "0.5")
        if [ "$(echo "$delay > 1" | bc 2>/dev/null || echo 0)" = "1" ]; then delay=1; fi
    done
}

# Wait for HTTP server to respond
wait_for_http() {
    local timeout="${1:-10}"
    local port="${2:-$TEST_HTTP_PORT}"
    local start_time=$(date +%s)
    local delay=0.1

    while true; do
        local elapsed=$(( $(date +%s) - start_time ))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "FAIL: Timeout waiting for HTTP server after ${timeout}s"
            return 1
        fi
        if curl -sf "http://127.0.0.1:${port}/" > /dev/null 2>&1; then
            return 0
        fi
        sleep "$delay"
        delay=$(echo "$delay * 1.5" | bc 2>/dev/null || echo "0.5")
        if [ "$(echo "$delay > 1" | bc 2>/dev/null || echo 0)" = "1" ]; then delay=1; fi
    done
}

# Start nvim server in background
start_nvim_server() {
    local port="${1:-$TEST_HTTP_PORT}"

    nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
        -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $port}); p.start()" &
    local nvim_pid=$!
    track_pid "$nvim_pid"

    if wait_for_health 10 "$port"; then
        echo "$nvim_pid"
        return 0
    else
        echo "FAIL: Could not start Neovim server"
        return 1
    fi
}

# Assertion helpers
assert_eq() {
    local expected="$1" actual="$2" message="${3:-Assertion failed}"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $message: expected '$expected', got '$actual'"
        return 1
    fi
    echo "PASS: $message"
}

assert_contains() {
    local haystack="$1" needle="$2" message="${3:-Assertion failed}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $message: output does not contain '$needle'"
        return 1
    fi
    echo "PASS: $message"
}

assert_not_empty() {
    local value="$1" message="${2:-Assertion failed}"
    if [ -z "$value" ]; then
        echo "FAIL: $message: value is empty"
        return 1
    fi
    echo "PASS: $message"
}

# Ensure node can find modules from the plugin dir (for ws, playwright, etc.)
if [ -d "$PLUGIN_DIR/node_modules" ]; then
    export NODE_PATH="$PLUGIN_DIR/node_modules${NODE_PATH:+:$NODE_PATH}"
fi

export TEST_HTTP_PORT TEST_WS_PORT PLUGIN_DIR
