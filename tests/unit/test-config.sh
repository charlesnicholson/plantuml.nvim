#!/bin/bash
# Unit tests for config merging and defaults.
set -euo pipefail
source "$(dirname "$0")/../test-utils.sh"

echo "=== Config Unit Tests ==="

FAILURES=0

# Test default config values
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local p = require("plantuml")
        p.setup()
        local c = p.get_config()
        local checks = {
            c.auto_start == true,
            c.auto_update == true,
            c.http_port == 8764,
            c.plantuml_server_url == "http://www.plantuml.com/plantuml",
            c.auto_launch_browser == "never",
            c.use_docker == false,
            c.docker_image == "plantuml/plantuml-server:jetty",
            c.docker_port == 8080,
            c.docker_remove_on_stop == false,
        }
        for i, v in ipairs(checks) do
            if not v then io.write("FAIL:" .. i); return end
        end
        io.write("OK")
    end' \
    -c "qall!" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: Default config values are correct"
else
    echo "FAIL: Default config values: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test config merging with user values
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local p = require("plantuml")
        p.setup({ http_port = 9000, auto_launch_browser = "always" })
        local c = p.get_config()
        if c.http_port == 9000 and c.auto_launch_browser == "always" and c.auto_start == true then
            io.write("OK")
        else
            io.write("FAIL:port=" .. c.http_port .. ",browser=" .. c.auto_launch_browser)
        end
    end' \
    -c "qall!" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: Config merging preserves defaults and applies overrides"
else
    echo "FAIL: Config merging: $result"
    FAILURES=$((FAILURES + 1))
fi

# Test get_config returns a copy (not a reference)
result=$(nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c 'lua do
        local p = require("plantuml")
        p.setup({ http_port = 5000 })
        local c1 = p.get_config()
        c1.http_port = 9999
        local c2 = p.get_config()
        if c2.http_port == 5000 then io.write("OK") else io.write("FAIL:" .. c2.http_port) end
    end' \
    -c "qall!" 2>&1)

if [ "$result" = "OK" ]; then
    echo "PASS: get_config() returns a defensive copy"
else
    echo "FAIL: get_config() copy: $result"
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "=== $FAILURES config test(s) FAILED ==="
    exit 1
fi
echo "=== All config tests passed ==="
