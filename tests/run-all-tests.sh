#!/bin/bash
# Run all plantuml.nvim tests.
# Usage: ./tests/run-all-tests.sh [--unit] [--integration] [--browser] [--docker]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_FAILURES=0
TOTAL_SKIPS=0
TOTAL_PASSES=0

run_test() {
    local script="$1"
    local name=$(basename "$script" .sh)
    echo ""
    echo "=========================================="
    echo "Running: $name"
    echo "=========================================="

    if bash "$script"; then
        TOTAL_PASSES=$((TOTAL_PASSES + 1))
    else
        local exit_code=$?
        if [ "$exit_code" -eq 0 ]; then
            TOTAL_PASSES=$((TOTAL_PASSES + 1))
        else
            # Check if it was a skip (exit 0 with SKIP message handled by the test)
            TOTAL_FAILURES=$((TOTAL_FAILURES + 1))
        fi
    fi
}

# Parse args
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_BROWSER=false
RUN_DOCKER=false
RUN_ALL=true

for arg in "$@"; do
    case "$arg" in
        --unit) RUN_UNIT=true; RUN_ALL=false ;;
        --integration) RUN_INTEGRATION=true; RUN_ALL=false ;;
        --browser) RUN_BROWSER=true; RUN_ALL=false ;;
        --docker) RUN_DOCKER=true; RUN_ALL=false ;;
    esac
done

# Unit tests
if $RUN_ALL || $RUN_UNIT; then
    echo ""
    echo "##########################################"
    echo "# Unit Tests                             #"
    echo "##########################################"
    for test in "$SCRIPT_DIR"/unit/test-*.sh; do
        [ -f "$test" ] && run_test "$test"
    done
fi

# Integration tests (excluding docker)
if $RUN_ALL || $RUN_INTEGRATION; then
    echo ""
    echo "##########################################"
    echo "# Integration Tests                      #"
    echo "##########################################"
    for test in "$SCRIPT_DIR"/integration/test-*.sh; do
        [ -f "$test" ] || continue
        name=$(basename "$test")
        if [ "$name" = "test-docker.sh" ] && ! $RUN_DOCKER && ! $RUN_ALL; then
            continue
        fi
        run_test "$test"
    done
fi

# Docker tests (separate because they require Docker)
if $RUN_ALL || $RUN_DOCKER; then
    echo ""
    echo "##########################################"
    echo "# Docker Tests                           #"
    echo "##########################################"
    if [ -f "$SCRIPT_DIR/integration/test-docker.sh" ]; then
        run_test "$SCRIPT_DIR/integration/test-docker.sh"
    fi
fi

# Browser tests
if $RUN_ALL || $RUN_BROWSER; then
    echo ""
    echo "##########################################"
    echo "# Browser Tests                          #"
    echo "##########################################"
    if [ -f "$SCRIPT_DIR/browser/run-browser-tests.sh" ]; then
        run_test "$SCRIPT_DIR/browser/run-browser-tests.sh"
    fi
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Passed:  $TOTAL_PASSES"
echo "Failed:  $TOTAL_FAILURES"

if [ "$TOTAL_FAILURES" -gt 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi

echo "RESULT: PASS"
