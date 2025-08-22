# PlantUML.nvim
A pure Lua Neovim plugin for automatically rendering PlantUML diagrams in a local web browser.

<img width="646" height="515" alt="Screenshot 2025-08-22 at 10 33 37 AM" src="https://github.com/user-attachments/assets/25205bb6-267a-485d-8558-a53a7f5d7a39" />

## Installation

Lazy:
```
  { "charlesnicholson/plantuml.nvim" }
```

It starts automatically and runs a server on http://127.0.0.1:8764/. Browse to that page, and it will refresh automatically any time you save, open, or enter a buffer with a filename ending in `.puml`.

## Commands

The plugin provides the following user commands:

- `:PlantumlUpdate` - Manually trigger a PlantUML diagram update for the current buffer
- `:PlantumlLaunchBrowser` - Open the PlantUML web viewer in your default browser (http://127.0.0.1:8764)

The plugin automatically updates diagrams when you save, open, or enter a buffer with a `.puml` file extension. The `:PlantumlUpdate` command is useful for manual refreshes, while `:PlantumlLaunchBrowser` provides an easy way to open the web viewer without manually navigating to the URL.

This was 100% vibe coded but the code doesn't look awful, so whatever. Lots of stuff to improve but the core of it is up and running.

Pull requests welcome.
