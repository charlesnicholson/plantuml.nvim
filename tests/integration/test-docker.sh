#!/bin/bash
# Integration test: Docker container lifecycle (requires Docker to be running).
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Docker Tests ==="

# Check if Docker is available
if ! command -v docker &>/dev/null; then
    echo "SKIP: Docker not installed"
    exit 0
fi

if ! docker info &>/dev/null 2>&1; then
    echo "SKIP: Docker daemon not running"
    exit 0
fi

FAILURES=0

# Test: is_docker_available returns true
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local docker = require("plantuml.docker")
        docker.is_docker_available(function(ok)
            if ok then io.write("OK") else io.write("FAIL") end
            vim.cmd("qall!")
        end)
    end' 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: is_docker_available returns true"
else
    echo "FAIL: is_docker_available: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test: is_docker_running returns true
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local docker = require("plantuml.docker")
        docker.is_docker_running(function(ok)
            if ok then io.write("OK") else io.write("FAIL") end
            vim.cmd("qall!")
        end)
    end' 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: is_docker_running returns true"
else
    echo "FAIL: is_docker_running: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test: get_container_status for non-existent container
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local docker = require("plantuml.docker")
        docker.get_container_status("plantuml-nvim-test-nonexistent-12345", function(status)
            io.write(status)
            vim.cmd("qall!")
        end)
    end' 2>&1)

if [ "$result" = "not_found" ]; then
    echo "PASS: Non-existent container returns not_found"
else
    echo "FAIL: Non-existent container status: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES Docker test(s) FAILED ==="
    exit 1
fi
echo "=== All Docker tests passed ==="
