#!/bin/bash
set -euo pipefail

echo "Setting up test environment..."

# Create directories for test output
mkdir -p tests/screenshots
mkdir -p tests/fixtures

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
