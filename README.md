# PlantUML.nvim
A pure Lua Neovim plugin that provides **real-time PlantUML diagram rendering** in your web browser. Edit your `.puml` files in Neovim and watch your diagrams update instantly in the browser whenever you save - no manual refresh needed!

<img width="646" height="515" alt="Screenshot 2025-08-22 at 10 33 37 AM" src="https://github.com/user-attachments/assets/25205bb6-267a-485d-8558-a53a7f5d7a39" />

## How it works

The plugin runs a local HTTP server on `http://127.0.0.1:8764/` with a WebSocket connection for real-time updates. Simply:

1. Open a `plantuml` filetype file in Neovim (`.puml` by default, you can add more)
2. Browse to the local server URL.
3. Watch your diagrams update instantly as you save, edit, or switch between PlantUML files.

The browser page shows a live status indicator and automatically refreshes diagrams that are opened, saved, or entered in Neovim.

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

### Lazy (with Docker PlantUML server)
```lua
{
  "charlesnicholson/plantuml.nvim",
  opts = {
    use_docker = true,
    docker_port = 8080,
    docker_remove_on_stop = true,
  }
}
```

### Manual setup
```lua
require("plantuml").setup({
  auto_start = false,  -- Don't start server automatically
  auto_update = false, -- Disable automatic updates on file events
  http_port = 9000,    -- Use different port
  plantuml_server_url = "http://my-plantuml-server.com/plantuml",
  auto_launch_browser = "always",  -- Always automatically launch browser
})
```

### Docker PlantUML server setup
```lua
require("plantuml").setup({
  use_docker = true,                    -- Enable Docker PlantUML server
  docker_image = "plantuml/plantuml-server:jetty",  -- Docker image
  docker_port = 8080,                   -- Host port for container
  docker_remove_on_stop = false,        -- Keep container after stopping
})
```

## Configuration

The plugin supports the following configuration options:

- `auto_start` (boolean, default: `true`) - Whether to automatically start the server when the plugin loads
- `auto_update` (boolean, default: `true`) - Whether to automatically update diagrams when files are saved/opened/entered
- `http_port` (number, default: `8764`) - Port for the HTTP server (WebSocket server uses http_port + 1)
- `plantuml_server_url` (string, default: `"http://www.plantuml.com/plantuml"`) - Base URL for the PlantUML server
- `auto_launch_browser` (string, default: `"never"`) - Controls automatic browser launching:
  - `"never"` - Never automatically launch a browser
  - `"always"` - Always launch a browser if no clients are connected when a file is opened/saved/etc
  - `"once"` - Only launch a browser once per Neovim session when a file is opened/saved/etc

### Docker PlantUML Server

The plugin can run a local PlantUML server in Docker instead of using the external plantuml.com service:

- `use_docker` (boolean, default: `false`) - Enable Docker PlantUML server (mutually exclusive with `plantuml_server_url`)
- `docker_image` (string, default: `"plantuml/plantuml-server:jetty"`) - Docker image to use for PlantUML server
- `docker_port` (number, default: `8080`) - Host port to bind the Docker container
- `docker_remove_on_stop` (boolean, default: `false`) - Whether to remove the container when stopping the server

You must have docker installed and the engine running; this plugin just pulls and run the PlantUML image.

Docker mode provides:
- Local PlantUML rendering without external dependencies
- Automatic container lifecycle management (start, stop, reattach)
- No external network requests for diagram generation

## Commands

The plugin provides the following user commands:

- `:PlantumlUpdate` - Manually trigger a PlantUML diagram update for the current buffer
- `:PlantumlLaunchBrowser` - Open the PlantUML web viewer in your default browser
- `:PlantumlServerStart` - Start the PlantUML server (useful when `auto_start = false`)

## Notes

This plugin is my foray into "vibe coding" with GitHub Copilot. The only thing I've touched is this README.md file.
- `:PlantumlServerStop` - Stop the PlantUML server

When `auto_update = true` (default), diagrams update automatically when you save, open, or enter a buffer with a `plantuml` filetype extension. Use `:PlantumlUpdate` for manual refreshes or when automatic updates are disabled.
