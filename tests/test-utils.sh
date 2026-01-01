#!/bin/bash
# Test utilities for plantuml.nvim tests
# Source this file in test scripts: source "$(dirname "$0")/test-utils.sh"

set -euo pipefail

# Global state
TEST_TMP_DIR=""
TRACKED_PIDS=()
TEST_HTTP_PORT="${TEST_HTTP_PORT:-8764}"
TEST_WS_PORT="$((TEST_HTTP_PORT + 1))"

# Get plugin directory (for running nvim with local plugin only)
# Use BASH_SOURCE if available, otherwise fall back to script location detection
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    # Fallback: assume we're in the tests directory or repo root
    if [ -d "lua/plantuml" ]; then
        PLUGIN_DIR="$(pwd)"
    elif [ -d "../lua/plantuml" ]; then
        PLUGIN_DIR="$(cd .. && pwd)"
    else
        echo "Error: Cannot determine plugin directory" >&2
        exit 1
    fi
fi

# Helper to run nvim with only the local plugin (no user config)
# Usage: run_nvim_clean "lua code here"
run_nvim_clean() {
    local lua_code="$1"
    nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
        -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
        -c "lua $lua_code" \
        -c "qall!"
}

# Create isolated temp directory for this test
setup_test_env() {
    TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plantuml-test.XXXXXX")
    trap cleanup_test_env EXIT
}

# Clean up temp directory and all tracked processes
cleanup_test_env() {
    echo "Cleaning up test environment..."
    cleanup_pids
    if [ -n "$TEST_TMP_DIR" ] && [ -d "$TEST_TMP_DIR" ]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# Track a PID for cleanup
track_pid() {
    local pid="$1"
    TRACKED_PIDS+=("$pid")
}

# Kill all tracked PIDs
cleanup_pids() {
    for pid in "${TRACKED_PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    TRACKED_PIDS=()
    # Also kill any stray nvim processes from this test
    pkill -f "nvim.*headless.*plantuml" 2>/dev/null || true
}

# Wait for health endpoint to return ready state
# Usage: wait_for_health [timeout_seconds] [port]
wait_for_health() {
    local timeout="${1:-10}"
    local port="${2:-$TEST_HTTP_PORT}"
    local url="http://127.0.0.1:${port}/health"
    local start_time=$(date +%s)
    local delay=0.1

    echo "Waiting for health endpoint at $url..."
    while true; do
        local now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout waiting for health endpoint after ${timeout}s"
            return 1
        fi

        # Check health endpoint
        local response
        if response=$(curl -sf "$url" 2>/dev/null); then
            # Parse state from JSON response
            local state
            state=$(echo "$response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 || echo "")
            if [ "$state" = "ready" ]; then
                echo "Health endpoint ready (state=$state)"
                return 0
            elif [ -n "$state" ]; then
                echo "Health endpoint responding (state=$state), waiting for ready..."
            fi
        fi

        sleep "$delay"
        # Exponential backoff, cap at 1 second
        delay=$(echo "$delay * 1.5" | bc 2>/dev/null || echo "0.5")
        if [ "$(echo "$delay > 1" | bc 2>/dev/null || echo 0)" = "1" ]; then
            delay=1
        fi
    done
}

# Wait for HTTP server to respond (basic check, no health endpoint)
# Usage: wait_for_http [timeout_seconds] [port]
wait_for_http() {
    local timeout="${1:-10}"
    local port="${2:-$TEST_HTTP_PORT}"
    local url="http://127.0.0.1:${port}/"
    local start_time=$(date +%s)
    local delay=0.1

    echo "Waiting for HTTP server at $url..."
    while true; do
        local now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout waiting for HTTP server after ${timeout}s"
            return 1
        fi

        if curl -sf "$url" > /dev/null 2>&1; then
            echo "HTTP server ready"
            return 0
        fi

        sleep "$delay"
        delay=$(echo "$delay * 1.5" | bc 2>/dev/null || echo "0.5")
        if [ "$(echo "$delay > 1" | bc 2>/dev/null || echo 0)" = "1" ]; then
            delay=1
        fi
    done
}

# Wait for WebSocket to connect and receive a message
# Usage: wait_for_websocket [timeout_seconds] [port]
wait_for_websocket() {
    local timeout="${1:-10}"
    local port="${2:-$TEST_WS_PORT}"

    echo "Waiting for WebSocket server on port $port..."

    local script_file="$TEST_TMP_DIR/ws_wait.js"
    cat > "$script_file" << EOF
const WebSocket = require('$(pwd)/node_modules/ws');
const ws = new WebSocket('ws://127.0.0.1:${port}');
const timeout = setTimeout(() => { process.exit(1); }, ${timeout}000);

ws.on('open', () => {
    ws.send(JSON.stringify({type: 'refresh'}));
});

ws.on('message', () => {
    clearTimeout(timeout);
    ws.close();
    process.exit(0);
});

ws.on('error', () => { process.exit(1); });
EOF

    if node "$script_file" 2>/dev/null; then
        echo "WebSocket server ready and responding"
        return 0
    else
        echo "WebSocket server not ready"
        return 1
    fi
}

# Start Neovim with ONLY the local plugin (no user config)
# Usage: start_nvim_server [port]
start_nvim_server() {
    local port="${1:-$TEST_HTTP_PORT}"
    local plugin_dir
    plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    echo "Starting Neovim with local plugin from $plugin_dir on port $port..."
    nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$plugin_dir')" \
        -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
        -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $port}); p.start()" &
    local nvim_pid=$!
    track_pid "$nvim_pid"

    # Wait for health endpoint
    if wait_for_health 10 "$port"; then
        echo "Neovim server ready (PID: $nvim_pid)"
        echo "$nvim_pid"
        return 0
    else
        echo "Failed to start Neovim server"
        return 1
    fi
}

# Create a Playwright test wrapper that handles common setup
# Usage: run_playwright_test <test_script_content>
run_playwright_test() {
    local test_content="$1"
    local test_file="$TEST_TMP_DIR/playwright_test.js"

    cat > "$test_file" << EOF
const { chromium } = require('playwright');

(async () => {
    let browser;
    let page;

    try {
        browser = await chromium.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });

        const context = await browser.newContext();
        page = await context.newPage();

        // Navigate and wait for WebSocket connection
        await page.goto('http://127.0.0.1:${TEST_HTTP_PORT}', { waitUntil: 'networkidle' });

        // Wait for connection to be established
        await page.waitForFunction(() => {
            const status = document.querySelector('#status-text');
            return status && status.textContent !== 'Connecting...';
        }, { timeout: 10000 });

        // Run the test
        ${test_content}

        console.log('Test passed');

    } catch (error) {
        console.error('Test failed:', error);
        if (page) {
            try {
                await page.screenshot({ path: '$TEST_TMP_DIR/failure.png' });
            } catch (e) {}
        }
        process.exit(1);
    } finally {
        if (browser) {
            await browser.close();
        }
    }
})();
EOF

    DISPLAY=${DISPLAY:-:99} node "$test_file"
}

# Assert helper for tests
assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    if [ "$expected" != "$actual" ]; then
        echo "✗ $message: expected '$expected', got '$actual'"
        return 1
    fi
    echo "✓ $message"
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "✗ $message: '$haystack' does not contain '$needle'"
        return 1
    fi
    echo "✓ $message"
    return 0
}

# Export functions for subshells
export -f track_pid cleanup_pids wait_for_health wait_for_http wait_for_websocket
export TEST_HTTP_PORT TEST_WS_PORT PLUGIN_DIR
