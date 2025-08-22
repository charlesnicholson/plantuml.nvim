#!/bin/bash
set -euo pipefail

echo "Setting up test environment..."

# Create logs and screenshots directories
mkdir -p tests/logs tests/screenshots

# Create Neovim config directory for testing
mkdir -p ~/.config/nvim

# Create minimal init.lua for testing
cat > ~/.config/nvim/init.lua << 'EOF'
-- Minimal Neovim config for testing plantuml.nvim
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Load the plugin
require("plantuml").setup({
  auto_start = false,
  http_port = 8764,
  auto_launch_browser = "never"
})

-- Setup filetype detection
vim.filetype.add({
  extension = {
    puml = 'plantuml',
    plantuml = 'plantuml',
  },
})
EOF

# Create test PlantUML file
cat > tests/fixtures/test.puml << 'EOF'
@startuml
!theme plain
skinparam monochrome true

participant User
participant Browser
participant Plugin
participant PlantUML

User -> Browser: Opens .puml file
Browser -> Plugin: WebSocket connect
Plugin -> Browser: Sends diagram update
Browser -> PlantUML: Requests PNG
PlantUML -> Browser: Returns diagram
Browser -> User: Displays diagram
@enduml
EOF

# Create a simple PlantUML test case
cat > tests/fixtures/simple.puml << 'EOF'
@startuml
A -> B: test
B -> C: response
@enduml
EOF

echo "Test environment setup complete"