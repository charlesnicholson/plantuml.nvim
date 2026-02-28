#!/bin/bash
# Integration test: docker.start_container detects port mismatches and recreates.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Docker Port Check Tests ==="

if ! command -v docker &>/dev/null; then
    echo "SKIP: Docker not installed"
    exit 0
fi

if ! docker info &>/dev/null 2>&1; then
    echo "SKIP: Docker daemon not running"
    exit 0
fi

FAILURES=0
TEST_CONTAINER="plantuml-nvim-test-portcheck-$$"

cleanup_container() {
    docker rm -f "$TEST_CONTAINER" &>/dev/null || true
}
trap cleanup_container EXIT

# Test: start_container with correct port on a fresh container
cleanup_container
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua do
        local docker = require('plantuml.docker')
        docker.start_container('$TEST_CONTAINER', 'plantuml/plantuml-server:jetty', 7700, 8080, function(ok)
            if ok then io.write('OK') else io.write('FAIL') end
            vim.cmd('qall!')
        end)
    end" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: start_container creates fresh container"
else
    echo "FAIL: start_container fresh: $result"
    FAILURES=$((FAILURES + 1))
fi

# Verify the port mapping is correct
actual_port=$(docker inspect "$TEST_CONTAINER" --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' 2>/dev/null || echo "NONE")
if [ "$actual_port" = "7700" ]; then
    echo "PASS: Fresh container has correct port mapping (7700:8080)"
else
    echo "FAIL: Fresh container port: expected 7700, got $actual_port"
    FAILURES=$((FAILURES + 1))
fi

# Test: start_container detects port mismatch on running container and recreates
# Container is currently running with 7700:8080. Request 7701:8080.
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua do
        local docker = require('plantuml.docker')
        docker.start_container('$TEST_CONTAINER', 'plantuml/plantuml-server:jetty', 7701, 8080, function(ok)
            if ok then io.write('OK') else io.write('FAIL') end
            vim.cmd('qall!')
        end)
    end" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: start_container recreates running container with wrong port"
else
    echo "FAIL: start_container port mismatch (running): $result"
    FAILURES=$((FAILURES + 1))
fi

actual_port=$(docker inspect "$TEST_CONTAINER" --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' 2>/dev/null || echo "NONE")
if [ "$actual_port" = "7701" ]; then
    echo "PASS: Recreated container has corrected port mapping (7701:8080)"
else
    echo "FAIL: Recreated container port: expected 7701, got $actual_port"
    FAILURES=$((FAILURES + 1))
fi

# Test: start_container detects port mismatch on stopped container and recreates
docker stop "$TEST_CONTAINER" &>/dev/null || true
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua do
        local docker = require('plantuml.docker')
        docker.start_container('$TEST_CONTAINER', 'plantuml/plantuml-server:jetty', 7702, 8080, function(ok)
            if ok then io.write('OK') else io.write('FAIL') end
            vim.cmd('qall!')
        end)
    end" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: start_container recreates stopped container with wrong port"
else
    echo "FAIL: start_container port mismatch (stopped): $result"
    FAILURES=$((FAILURES + 1))
fi

actual_port=$(docker inspect "$TEST_CONTAINER" --format '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' 2>/dev/null || echo "NONE")
if [ "$actual_port" = "7702" ]; then
    echo "PASS: Recreated stopped container has corrected port mapping (7702:8080)"
else
    echo "FAIL: Recreated stopped container port: expected 7702, got $actual_port"
    FAILURES=$((FAILURES + 1))
fi

# Test: start_container reuses running container when port matches
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua do
        local docker = require('plantuml.docker')
        docker.start_container('$TEST_CONTAINER', 'plantuml/plantuml-server:jetty', 7702, 8080, function(ok)
            if ok then io.write('OK') else io.write('FAIL') end
            vim.cmd('qall!')
        end)
    end" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: start_container reuses container when port matches"
else
    echo "FAIL: start_container reuse: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES Docker port check test(s) FAILED ==="
    exit 1
fi
echo "=== All Docker port check tests passed ==="
