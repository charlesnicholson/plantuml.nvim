# PlantUML.nvim
A pure Lua Neovim plugin for automatically rendering PlantUML diagrams in a local web browser.

<img width="646" height="515" alt="Screenshot 2025-08-22 at 10 33 37 AM" src="https://github.com/user-attachments/assets/25205bb6-267a-485d-8558-a53a7f5d7a39" />

## Installation

### Lazy (minimal setup)
```lua
{ "charlesnicholson/plantuml.nvim" }
```

### Lazy (with configuration)
```lua
{
  "charlesnicholson/plantuml.nvim",
  opts = {
    auto_start = true,
    http_port = 8764,
    websocket_port = 8765,
    host = "127.0.0.1",
    plantuml_server_url = "http://www.plantuml.com/plantuml/png",
  }
}
```

### Manual setup
```lua
require("plantuml").setup({
  auto_start = false,  -- Don't start server automatically
  http_port = 9000,    -- Use different port
  plantuml_server_url = "http://my-plantuml-server.com/plantuml/png",
})
```

## Configuration

The plugin supports the following configuration options:

- `auto_start` (boolean, default: `true`) - Whether to automatically start the server when the plugin loads
- `http_port` (number, default: `8764`) - Port for the HTTP server
- `websocket_port` (number, default: `8765`) - Port for the WebSocket server  
- `host` (string, default: `"127.0.0.1"`) - Host address to bind the servers to
- `plantuml_server_url` (string, default: `"http://www.plantuml.com/plantuml/png"`) - Base URL for the PlantUML server (the `~1` component is automatically appended)

By default, the plugin starts automatically and runs a server on http://127.0.0.1:8764/. Browse to that page, and it will refresh automatically any time you save, open, or enter a buffer with a filename ending in `.puml`.

## Commands

The plugin provides the following user commands:

- `:PlantumlUpdate` - Manually trigger a PlantUML diagram update for the current buffer
- `:PlantumlLaunchBrowser` - Open the PlantUML web viewer in your default browser
- `:PlantumlStart` - Start the PlantUML server (useful when `auto_start = false`)
- `:PlantumlStop` - Stop the PlantUML server

The plugin automatically updates diagrams when you save, open, or enter a buffer with a `.puml` file extension. The `:PlantumlUpdate` command is useful for manual refreshes, while `:PlantumlLaunchBrowser` provides an easy way to open the web viewer without manually navigating to the URL.

This was 100% vibe coded but the code doesn't look awful, so whatever. Lots of stuff to improve but the core of it is up and running.

Pull requests welcome.
