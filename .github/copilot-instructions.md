# Copilot Instructions for plantuml.nvim

## Project Overview

This is a pure Lua Neovim plugin that provides automatic PlantUML diagram rendering in a local web browser. The plugin runs HTTP and WebSocket servers to deliver real-time diagram updates when `.puml` files are saved in Neovim.

## Architecture & Design Principles

### Core Components
- **HTTP Server**: Serves the web interface on `127.0.0.1:8764`
- **WebSocket Server**: Handles real-time updates on port `8765`
- **PlantUML Integration**: Compresses and encodes diagram content for the PlantUML web service
- **Embedded Web UI**: HTML, CSS, and JavaScript are embedded directly in `lua/plantuml/init.lua`

### Key Design Decisions
- **Pure Lua**: No external dependencies except LuaJIT's `bit` library
- **Self-contained**: All web assets (HTML/CSS/JS) remain embedded in the main Lua file
- **Vendor preservation**: Third-party code in `vendor/` directories must not be modified
- **Single-file approach**: Keep the web interface embedded rather than split into separate files

## Development Guidelines

### File Structure
```
lua/plantuml/
├── init.lua              # Main plugin logic with embedded web UI
└── vendor/
    └── LibDeflate/       # DO NOT MODIFY - third-party compression library
plugin/
└── plantuml.lua         # Plugin entry point and autocmds
```

### Code Patterns

#### Error Handling
- Use `assert()` for critical failures (e.g., missing dependencies)
- Use `vim.notify()` for user-facing warnings/errors
- Use `vim.schedule()` for UI updates from async contexts

#### Neovim API Usage
- Prefer `vim.api.*` functions over vim.* when available
- Use `vim.loop` for async I/O operations (TCP servers, file operations)
- Use autocmds for file event handling (BufWritePost, BufReadPost, etc.)

#### Server Implementation
- HTTP responses must include proper headers (`Content-Type`, `Content-Length`)
- WebSocket handshake follows RFC 6455 specification
- Client management uses connection tracking table
- Graceful cleanup of closed connections

### Constraints & Requirements

#### NEVER Modify
- Files in `lua/plantuml/vendor/` - these are pristine third-party libraries
- Vendor LICENSE files or documentation

#### Keep Embedded
- HTML, CSS, and JavaScript must remain in `lua/plantuml/init.lua`
- Do not split web assets into separate files
- Maintain the single-file simplicity approach

#### WebSocket Protocol
- Implement proper WebSocket handshaking with Sec-WebSocket-Accept headers
- Use frame encoding for message transmission
- Handle client disconnections gracefully

### Testing & Validation

#### Manual Testing
- Start Neovim and verify the plugin loads without errors
- Check that HTTP server starts on `127.0.0.1:8764`
- Open browser to verify web interface loads
- Create/edit `.puml` files and verify real-time updates work
- Test WebSocket connectivity and message broadcast

#### Common Issues
- LuaJIT `bit` library availability
- Port conflicts (8764/8765)
- WebSocket handshake failures
- PlantUML URL length limits (warn at >8000 characters)

### Coding Style

#### Lua Conventions
- Use 2-space indentation (see `.editorconfig`)
- Local variables for module imports
- Consistent error messages with "[plantuml.nvim]" prefix
- Use `local M = {}` pattern for module exports

#### API Patterns
- Buffer operations default to current buffer (buf = 0)
- File paths use `:p` modifier for full paths
- Async operations use proper callback handling
- WebSocket frames follow binary encoding spec

### Performance Considerations

- Compression using LibDeflate for PlantUML encoding
- Connection pooling for WebSocket clients
- Efficient buffer content reading
- Minimal DOM manipulation in embedded JavaScript

### Security Notes

- Server binds to localhost only (127.0.0.1)
- No external network access required
- PlantUML service calls use HTTP (external dependency)
- WebSocket connections limited to local clients

### Common Modification Patterns

#### Adding Configuration Options
```lua
local config = {
  http_port = 8764,
  websocket_port = 8765,
  host = "127.0.0.1",
  -- new options here
}
```

#### Extending WebSocket Messages
```lua
server.broadcast({ 
  type = "update", 
  url = plantuml_url, 
  filename = filename,
  -- additional fields
})
```

#### Adding Autocmd Triggers
```lua
vim.api.nvim_create_autocmd({ "Event1", "Event2" }, {
  group = augroup,
  pattern = "*.puml",
  callback = plantuml.update_diagram,
  desc = "Description of the trigger",
})
```

## When Making Changes

1. **Preserve the embedded approach**: Keep HTML/CSS/JS in `lua/plantuml/init.lua`
2. **Test server functionality**: Verify both HTTP and WebSocket servers work
3. **Validate PlantUML integration**: Ensure diagram updates propagate correctly
4. **Check browser compatibility**: Test the embedded web interface
5. **Respect vendor boundaries**: Never modify files in `vendor/` directories
6. **Maintain simplicity**: This plugin values simplicity over feature complexity

## References

- [PlantUML Web Service](http://www.plantuml.com/plantuml/)
- [RFC 6455 - WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [Neovim Lua API Reference](https://neovim.io/doc/user/lua.html)
- [LuaJIT BitOp Library](http://bitop.luajit.org/)