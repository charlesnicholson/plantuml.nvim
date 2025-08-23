#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/vim-help-system.log"
echo "Testing vim help system integration..." | tee "$LOG_FILE"

# Ensure log directory exists
mkdir -p tests/logs

# Test 1: Help tags file was generated
echo "Test 1: Help tags file was generated" | tee -a "$LOG_FILE"
if [ -f "doc/tags" ]; then
    echo "✓ Help tags file exists" | tee -a "$LOG_FILE"
else
    echo "✗ Help tags file not found" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 2: General plantuml help works
echo "Test 2: General plantuml help works" | tee -a "$LOG_FILE"
if nvim --headless -c "help plantuml" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ General plantuml help accessible" | tee -a "$LOG_FILE"
else
    echo "✗ General plantuml help failed" | tee -a "$LOG_FILE"
    exit 1
fi

# Test 3: Individual command help works
echo "Test 3: Individual command help works" | tee -a "$LOG_FILE"
COMMANDS="PlantumlUpdate PlantumlLaunchBrowser PlantumlServerStart PlantumlServerStop"
for cmd in $COMMANDS; do
    if nvim --headless -c "help :$cmd" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
        echo "✓ Command help for :$cmd works" | tee -a "$LOG_FILE"
    else
        echo "✗ Command help for :$cmd failed" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 4: Configuration options help works
echo "Test 4: Configuration options help works" | tee -a "$LOG_FILE"
CONFIG_OPTIONS="plantuml-configuration plantuml-commands plantuml-usage"
for option in $CONFIG_OPTIONS; do
    if nvim --headless -c "help $option" -c "qall!" 2>&1 | tee -a "$LOG_FILE"; then
        echo "✓ Help for $option works" | tee -a "$LOG_FILE"
    else
        echo "✗ Help for $option failed" | tee -a "$LOG_FILE"
        exit 1
    fi
done

# Test 5: Help tags contain expected entries
echo "Test 5: Help tags contain expected entries" | tee -a "$LOG_FILE"
EXPECTED_TAGS="plantuml.txt PlantumlUpdate PlantumlLaunchBrowser PlantumlServerStart PlantumlServerStop plantuml-commands plantuml-configuration"
for tag in $EXPECTED_TAGS; do
    if grep -q "$tag" doc/tags; then
        echo "✓ Tag $tag found in help tags" | tee -a "$LOG_FILE"
    else
        echo "✗ Tag $tag missing from help tags" | tee -a "$LOG_FILE"
        exit 1
    fi
done

echo "✓ All vim help system tests passed" | tee -a "$LOG_FILE"