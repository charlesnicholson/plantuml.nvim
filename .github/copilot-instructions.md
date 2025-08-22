# Copilot Instructions for plantuml.nvim

## Project Overview

This is a pure Lua Neovim plugin that provides automatic PlantUML diagram rendering in a local web browser. The plugin runs HTTP and WebSocket servers to deliver real-time diagram updates when `.puml` files are saved in Neovim.

**Requirements**: Neovim 0.11+ (uses modern APIs and features)

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
- **Comment-free**: Code should be self-documenting without comments
- **Modern Neovim**: Targets Neovim 0.11+ with modern APIs

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

#### Web UI Patterns
- Status indicators use CSS classes: `.pill.ok`, `.pill.err`, `.pill.warn`
- Diagram viewing modes: `fit-to-page` (default) and full-size (click to toggle)
- CSS custom properties (variables) for theming: `--bg`, `--fg`, `--muted`, etc.
- Responsive design with flexbox layout
- WebSocket reconnection with exponential backoff (1.5s delay)

### Constraints & Requirements

#### No Testing Infrastructure
- **Do not write tests** - this project has no test infrastructure by design
- **Do not attempt to run tests** - there are none and none should be added
- All validation is done through manual testing only

#### NEVER Modify
- Files in `lua/plantuml/vendor/` - these are pristine third-party libraries
- Vendor LICENSE files or documentation

#### Keep Embedded
- HTML, CSS, and JavaScript must remain in `lua/plantuml/init.lua`
- Do not split web assets into separate files
- Maintain the single-file simplicity approach
- **Never add comments** to embedded HTML, CSS, or JavaScript

#### WebSocket Protocol
- Implement proper WebSocket handshaking with Sec-WebSocket-Accept headers
- Use frame encoding for message transmission
- Handle client disconnections gracefully

### Testing & Validation

**Important**: This project has no test infrastructure and no tests should be written. Testing is done manually only.

#### Manual Testing Only
- Start Neovim and verify the plugin loads without errors
- Check that HTTP server starts on `127.0.0.1:8764`
- Open browser to verify web interface loads
- Create/edit `.puml` files and verify real-time updates work
- Test WebSocket connectivity and message broadcast
- Verify diagram click toggles between fit-to-page and full-size modes

#### Common Issues
- LuaJIT `bit` library availability (required dependency)
- Port conflicts (8764/8765) - check for other services
- WebSocket handshake failures - verify Sec-WebSocket-Key handling
- PlantUML URL length limits (warn at >8000 characters)
- Network connectivity to plantuml.com service

#### File Patterns to Validate
- `*.puml` files trigger autocmds
- Empty/whitespace-only buffers are skipped
- Untitled buffers default to "untitled.puml"
- File path handling with special characters

### Coding Style

#### Lua Conventions
- Use 2-space indentation (see `.editorconfig`)
- Local variables for module imports
- Consistent error messages with "[plantuml.nvim]" prefix
- Use `local M = {}` pattern for module exports
- **Never add comments** - keep code clean and uncommented

#### API Patterns
- Buffer operations default to current buffer (buf = 0)
- File paths use `:p` modifier for full paths
- Async operations use proper callback handling
- WebSocket frames follow binary encoding spec

### Performance Considerations

- Compression using LibDeflate for PlantUML encoding
- Connection pooling for WebSocket clients
- Efficient buffer content reading with `vim.api.nvim_buf_get_lines()`
- Minimal DOM manipulation in embedded JavaScript
- PlantUML URL construction: `http://www.plantuml.com/plantuml/png/~1{encoded_data}`

#### PlantUML Encoding Process
1. Extract buffer content as string
2. Compress using LibDeflate (zlib compression)
3. Encode with custom Base64-like encoding (`encode64_plantuml`)
4. Construct URL with encoded data
5. Broadcast via WebSocket to connected clients

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

#### Adding User Commands
```lua
vim.api.nvim_create_user_command("CommandName", function(opts)
  -- command implementation
  plantuml.update_diagram()
end, { 
  desc = "Command description",
  nargs = 0,  -- or 1, '?', '*', etc.
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
2. **No comments**: Never add comments to Lua code or embedded web assets
3. **Manual testing only**: Verify both HTTP and WebSocket servers work through browser testing
4. **Validate PlantUML integration**: Ensure diagram updates propagate correctly
5. **Check browser compatibility**: Test the embedded web interface
6. **Respect vendor boundaries**: Never modify files in `vendor/` directories
7. **Maintain simplicity**: This plugin values simplicity over feature complexity
8. **Neovim 0.11+ only**: Use modern APIs without fallback paths

## References

- [PlantUML Web Service](http://www.plantuml.com/plantuml/)
- [RFC 6455 - WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [Neovim Lua API Reference](https://neovim.io/doc/user/lua.html)
- [LuaJIT BitOp Library](http://bitop.luajit.org/)
- [GitHub Copilot Best Practices](https://gh.io/copilot-coding-agent-tips)