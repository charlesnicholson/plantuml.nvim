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
    plantuml_server_url = "http://www.plantuml.com/plantuml",
    auto_launch_browser = "never",
  }
}
```

### Manual setup
```lua
require("plantuml").setup({
  auto_start = false,  -- Don't start server automatically
  http_port = 9000,    -- Use different port
  plantuml_server_url = "http://my-plantuml-server.com/plantuml",
  auto_launch_browser = "always",  -- Always automatically launch browser
})
```

## Configuration

The plugin supports the following configuration options:

- `auto_start` (boolean, default: `true`) - Whether to automatically start the server when the plugin loads
- `http_port` (number, default: `8764`) - Port for the HTTP server (WebSocket server uses http_port + 1)
- `plantuml_server_url` (string, default: `"http://www.plantuml.com/plantuml"`) - Base URL for the PlantUML server (the `/png/~1` component is automatically appended)
- `auto_launch_browser` (string, default: `"never"`) - Controls automatic browser launching:
  - `"never"` - Never automatically launch a browser
  - `"always"` - Always launch a browser if no clients are connected when a PlantUML file is opened/saved/etc
  - `"once"` - Only launch a browser once per Neovim session when a PlantUML file is opened/saved/etc

By default, the plugin starts automatically and runs a server on http://127.0.0.1:8764/. Browse to that page, and it will refresh automatically any time you save, open, or enter a buffer with a filename ending in `.puml`.

## Commands

The plugin provides the following user commands:

- `:PlantumlUpdate` - Manually trigger a PlantUML diagram update for the current buffer
- `:PlantumlLaunchBrowser` - Open the PlantUML web viewer in your default browser
- `:PlantumlServerStart` - Start the PlantUML server (useful when `auto_start = false`)
- `:PlantumlServerStop` - Stop the PlantUML server

The plugin automatically updates diagrams when you save, open, or enter a buffer with a `.puml` file extension. The `:PlantumlUpdate` command is useful for manual refreshes, while `:PlantumlLaunchBrowser` provides an easy way to open the web viewer without manually navigating to the URL.

This was 100% vibe coded but the code doesn't look awful, so whatever. Lots of stuff to improve but the core of it is up and running.

Pull requests welcome.
