#!/bin/bash
# Integration test: plugin loads and exports the expected API.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Plugin Loading Tests ==="

FAILURES=0

# Test that the module loads and has required functions
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local ok, p = pcall(require, "plantuml")
        if not ok then io.write("FAIL:load:" .. tostring(p)); return end
        local funcs = {"setup", "get_config", "start", "stop", "update_diagram", "open_browser"}
        for _, name in ipairs(funcs) do
            if type(p[name]) ~= "function" then
                io.write("FAIL:missing:" .. name)
                return
            end
        end
        io.write("OK")
    end' \
    -c "qall!" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: Module loads and exports all required functions"
else
    echo "FAIL: Module API: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test that submodules load independently
for mod in sha1 encoder browser server websocket docker; do
    result=$(nvim --headless --clean \
        -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
        -c "lua do
            local ok, m = pcall(require, 'plantuml.$mod')
            if ok then io.write('OK') else io.write('FAIL:' .. tostring(m)) end
        end" \
        -c "qall!" 2>&1)

    if [ "$result" = "OK" ]; then
        echo "PASS: plantuml.$mod loads"
    else
        echo "FAIL: plantuml.$mod: $result"
        FAILURES=$((FAILURES + 1))
    fi
done

# Test user commands are registered after plugin load
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "runtime plugin/plantuml.lua" \
    -c 'lua do
        local cmds = {"PlantumlUpdate", "PlantumlLaunchBrowser", "PlantumlServerStart", "PlantumlServerStop"}
        for _, cmd in ipairs(cmds) do
            local exists = vim.fn.exists(":" .. cmd) == 2
            if not exists then io.write("FAIL:cmd:" .. cmd); return end
        end
        io.write("OK")
    end' \
    -c "qall!" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: All user commands are registered"
else
    echo "FAIL: User commands: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES plugin loading test(s) FAILED ==="
    exit 1
fi
echo "=== All plugin loading tests passed ==="
