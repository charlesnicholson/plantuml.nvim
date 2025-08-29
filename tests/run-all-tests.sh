#!/bin/bash

set -e

echo "Running all plantuml.nvim tests..."
echo "=================================="

# List of tests in the order they appear in functional-tests.yml
TESTS=(
    "setup-test-env.sh"
    "test-plugin-loading.sh"
    "test-vim-help-system.sh"
    "test-http-server.sh"
    "test-html-file-loading.sh"
    "test-websocket.sh"
    "test-plantuml-processing.sh"
    "test-browser-ui.sh"
    "test-pan-zoom.sh"
    "test-docker-plantuml.sh"
    "test-docker-status-ui.sh"
    "test-auto-update-config.sh"
)

FAILED_TESTS=()
PASSED_TESTS=()

for test in "${TESTS[@]}"; do
    echo ""
    echo "Running: $test"
    echo "----------------------------------------"
    
    if ./tests/"$test"; then
        echo "✓ $test PASSED"
        PASSED_TESTS+=("$test")
    else
        echo "✗ $test FAILED"
        FAILED_TESTS+=("$test")
    fi
done

echo ""
echo "=================================="
echo "Test Results Summary:"
echo "=================================="
echo "Total tests: ${#TESTS[@]}"
echo "Passed: ${#PASSED_TESTS[@]}"
echo "Failed: ${#FAILED_TESTS[@]}"

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo ""
    echo "🎉 All tests passed!"
    exit 0
else
    echo ""
    echo "❌ Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    exit 1
fi