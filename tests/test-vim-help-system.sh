#!/bin/bash
set -euo pipefail



echo "Testing vim help system integration..."

# Test 1: Help tags file was generated
echo "Test 1: Help tags file was generated"
if [ -f "doc/tags" ]; then
    echo "✓ Help tags file exists"
else
    echo "✗ Help tags file not found"
    exit 1
fi

# Test 2: General plantuml help works
echo "Test 2: General plantuml help works"
if nvim --headless -c "help plantuml" -c "qall!" 2>&1; then
    echo "✓ General plantuml help accessible"
else
    echo "✗ General plantuml help failed"
    exit 1
fi

# Test 3: Individual command help works
echo "Test 3: Individual command help works"
COMMANDS="PlantumlUpdate PlantumlLaunchBrowser PlantumlServerStart PlantumlServerStop"
for cmd in $COMMANDS; do
    if nvim --headless -c "help :$cmd" -c "qall!" 2>&1; then
        echo "✓ Command help for :$cmd works"
    else
        echo "✗ Command help for :$cmd failed"
        exit 1
    fi
done

# Test 4: Configuration options help works
echo "Test 4: Configuration options help works"
CONFIG_OPTIONS="plantuml-configuration plantuml-commands plantuml-usage"
for option in $CONFIG_OPTIONS; do
    if nvim --headless -c "help $option" -c "qall!" 2>&1; then
        echo "✓ Help for $option works"
    else
        echo "✗ Help for $option failed"
        exit 1
    fi
done

# Test 5: Help tags contain expected entries
echo "Test 5: Help tags contain expected entries"
EXPECTED_TAGS="plantuml.txt PlantumlUpdate PlantumlLaunchBrowser PlantumlServerStart PlantumlServerStop plantuml-commands plantuml-configuration"
for tag in $EXPECTED_TAGS; do
    if grep -q "$tag" doc/tags; then
        echo "✓ Tag $tag found in help tags"
    else
        echo "✗ Tag $tag missing from help tags"
        exit 1
    fi
done

echo "✓ All vim help system tests passed"