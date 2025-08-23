# Repository Instructions for GitHub Copilot

## Project Overview

**plantuml.nvim** is a pure Lua Neovim plugin that provides real-time PlantUML diagram rendering in a web browser. When users edit `.puml` files in Neovim, the plugin automatically updates diagrams in their browser via WebSocket connections.

**Key Features:**
- Real-time diagram updates as you type and save
- Local HTTP server (port 8764) with embedded web interface
- WebSocket server (port 8765) for live updates
- No external dependencies except LuaJIT's `bit` library
- Supports Neovim 0.11+

## Architecture & Code Organization

### File Structure
```
lua/plantuml/
├── init.lua              # Main plugin with embedded web UI (HTML/CSS/JS)
└── vendor/
    └── LibDeflate/       # Third-party compression library (DO NOT MODIFY)
plugin/
└── plantuml.lua         # Plugin entry point and autocmds
tests/                   # Test scripts for validation
```

### Core Components
- **HTTP Server**: Serves web interface on `127.0.0.1:8764`
- **WebSocket Server**: Handles real-time updates on port `8765`
- **PlantUML Integration**: Compresses and encodes diagrams for plantuml.com service
- **Embedded Web UI**: All HTML, CSS, and JavaScript embedded in `lua/plantuml/init.lua`

### Design Principles
- **Pure Lua**: No external dependencies except LuaJIT's `bit` library
- **Self-contained**: Web assets embedded in main Lua file (don't split into separate files)
- **No comments**: Code should be self-documenting
- **Vendor preservation**: Never modify files in `vendor/` directories

## Development Guidelines

### Code Style
- Use 2-space indentation (see `.editorconfig`)
- Use `local M = {}` pattern for module exports
- Error messages should include "[plantuml.nvim]" prefix
- Never add comments to code or embedded web assets
- Prefer `vim.api.*` functions over legacy vim.* when available

### Key APIs and Patterns
- Use `vim.loop` for async I/O operations (TCP servers, file operations)
- Use `vim.api.nvim_create_autocmd()` for file event handling
- WebSocket handshake follows RFC 6455 specification
- HTTP responses must include proper headers (`Content-Type`, `Content-Length`)
- PlantUML URL construction: `http://www.plantuml.com/plantuml/png/~1{encoded_data}`

### Configuration Options
```lua
require("plantuml").setup({
  auto_start = true,        -- Auto-start server when plugin loads
  auto_update = true,       -- Auto-update diagrams on file events
  http_port = 8764,        -- HTTP server port (WebSocket uses http_port + 1)
  plantuml_server_url = "http://www.plantuml.com/plantuml",
  auto_launch_browser = "never",  -- "never", "always", or "once"
})
```

## Testing & Validation

### Running Tests
The plugin includes comprehensive test scripts in the `tests/` directory:

```bash
./tests/setup-test-env.sh           # Setup test environment
./tests/test-plugin-loading.sh      # Test plugin loads correctly
./tests/test-http-server.sh         # Test HTTP server functionality
./tests/test-websocket.sh           # Test WebSocket server
./tests/test-plantuml-processing.sh # Test PlantUML diagram processing
./tests/test-browser-ui.sh          # Test browser UI (requires display)
```

**Always run tests locally before making changes** to ensure nothing breaks.

### Common Issues
- LuaJIT `bit` library availability (required dependency)
- Port conflicts (8764/8765) - check for other services
- WebSocket handshake failures - verify Sec-WebSocket-Key handling
- PlantUML URL length limits (warn at >8000 characters)

### User Commands
- `:PlantumlUpdate` - Manually trigger diagram update
- `:PlantumlLaunchBrowser` - Open web viewer in browser
- `:PlantumlServerStart` - Start server (when auto_start = false)
- `:PlantumlServerStop` - Stop server

## Important Constraints

### What NOT to Modify
- Files in `lua/plantuml/vendor/` - these are pristine third-party libraries
- Never split embedded HTML/CSS/JS into separate files
- Don't add comments to code or embedded web assets

### When Making Changes
1. Keep HTML/CSS/JS embedded in `lua/plantuml/init.lua`
2. Run tests locally to validate changes
3. Preserve the single-file simplicity approach
4. Maintain compatibility with Neovim 0.11+
5. Test both HTTP and WebSocket servers manually
6. Ensure PlantUML integration still works correctly
