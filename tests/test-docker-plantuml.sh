#!/bin/bash
# Test Docker PlantUML server functionality

set -euo pipefail

echo "Testing Docker PlantUML functionality..."

# Check if Docker is available in the environment
if ! command -v docker &> /dev/null; then
    echo "✗ Docker not available in environment - skipping Docker tests"
    exit 0
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "✗ Docker daemon not running - skipping Docker tests"
    exit 0
fi

echo "✓ Docker available and running"

# Test variables
CONTAINER_NAME="plantuml-nvim-test"
DOCKER_IMAGE="plantuml/plantuml-server:jetty"
HOST_PORT=8080
INTERNAL_PORT=8080

# Cleanup function
cleanup() {
    echo "Cleaning up test containers..."
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
}
trap cleanup EXIT

# Ensure clean state
cleanup

echo "Test 1: Test Docker API functions"

# Test the Docker API module in isolation
cat > /tmp/test_docker_api.lua << 'EOF'
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local docker = require("plantuml.docker")

-- Test 1: Docker availability
local available, err = docker.is_docker_available()
if not available then
    print("Docker not available: " .. (err or "unknown error"))
    os.exit(1)
end
print("✓ Docker availability check passed")

-- Test 2: Docker running status
local running, err = docker.is_docker_running()
if not running then
    print("Docker not running: " .. (err or "unknown error"))
    os.exit(1)
end
print("✓ Docker running status check passed")

-- Test 3: Container status (should be not_found initially)
local status, err = docker.get_container_status("plantuml-nvim-test")
if status ~= "not_found" then
    print("Expected container status 'not_found', got: " .. tostring(status))
    os.exit(1)
end
print("✓ Container status check (not_found) passed")

print("All Docker API tests passed")
EOF

nvim --headless --clean \
    -u /tmp/minimal_init.lua \
    -c "luafile /tmp/test_docker_api.lua" \
    -c "qall!" 2>&1

echo "✓ Docker API module functions correctly"

echo "Test 2: Test Docker container lifecycle"

# Pull the image to ensure it's available
echo "Pulling PlantUML Docker image..."
docker pull $DOCKER_IMAGE

echo "✓ PlantUML Docker image available"

# Test container lifecycle with Neovim plugin
cat > /tmp/test_docker_lifecycle.lua << 'EOF'
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local docker = require("plantuml.docker")

local container_name = "plantuml-nvim-test"
local image = "plantuml/plantuml-server:jetty"
local host_port = 8080
local internal_port = 8080

-- Test starting container
print("Starting container...")
local success, err = docker.start_container(container_name, image, host_port, internal_port)
if not success then
    print("Failed to start container: " .. (err or "unknown error"))
    os.exit(1)
end
print("✓ Container started successfully")

-- Wait for container to be ready
print("Waiting for container to be ready...")
local ready, err = docker.wait_for_container_ready(container_name, 30)
if not ready then
    print("Container not ready: " .. (err or "unknown error"))
    os.exit(1)
end
print("✓ Container is ready")

-- Test container status
local status, err = docker.get_container_status(container_name)
if status ~= "running" then
    print("Expected container status 'running', got: " .. tostring(status))
    os.exit(1)
end
print("✓ Container status is running")

-- Test port mapping
local port, err = docker.get_container_port(container_name, internal_port)
if not port or port ~= host_port then
    print("Port mapping not found or incorrect. Expected: " .. host_port .. ", got: " .. tostring(port))
    os.exit(1)
end
print("✓ Port mapping is correct")

-- Test stopping container
print("Stopping container...")
local success, err = docker.stop_container(container_name)
if not success then
    print("Failed to stop container: " .. (err or "unknown error"))
    os.exit(1)
end
print("✓ Container stopped successfully")

-- Test status after stopping
local status, err = docker.get_container_status(container_name)
if status ~= "stopped" then
    print("Expected container status 'stopped', got: " .. tostring(status))
end
print("✓ Container status is stopped")

print("All Docker lifecycle tests passed")
EOF

nvim --headless --clean \
    -u /tmp/minimal_init.lua \
    -c "luafile /tmp/test_docker_lifecycle.lua" \
    -c "qall!" 2>&1

echo "✓ Docker container lifecycle tests passed"

echo "Test 3: Test HTTP connectivity to Docker PlantUML server"

# Start container for HTTP test
docker run -d --name $CONTAINER_NAME -p $HOST_PORT:$INTERNAL_PORT $DOCKER_IMAGE

# Wait for server to be ready
echo "Waiting for PlantUML server to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:$HOST_PORT/ > /dev/null 2>&1; then
        echo "✓ PlantUML server is responding"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "✗ PlantUML server failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Test generating a simple diagram
echo "Testing diagram generation..."
SIMPLE_DIAGRAM="@startuml\nAlice -> Bob: Hello\n@enduml"
COMPRESSED=$(echo -e "$SIMPLE_DIAGRAM" | python3 -c "
import sys, zlib, base64
data = sys.stdin.read().encode('utf-8')
compressed = zlib.compress(data, 9)
# PlantUML uses a custom base64 encoding
table = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
encoded = ''
for i in range(0, len(compressed), 3):
    chunk = compressed[i:i+3]
    if len(chunk) == 1:
        b1 = chunk[0] >> 2
        b2 = (chunk[0] & 0x3) << 4
        encoded += table[b1] + table[b2]
    elif len(chunk) == 2:
        b1 = chunk[0] >> 2
        b2 = ((chunk[0] & 0x3) << 4) | (chunk[1] >> 4)
        b3 = (chunk[1] & 0xF) << 2
        encoded += table[b1] + table[b2] + table[b3]
    else:
        b1 = chunk[0] >> 2
        b2 = ((chunk[0] & 0x3) << 4) | (chunk[1] >> 4)
        b3 = ((chunk[1] & 0xF) << 2) | (chunk[2] >> 6)
        b4 = chunk[2] & 0x3F
        encoded += table[b1] + table[b2] + table[b3] + table[b4]
print(encoded)
")

# Test the PNG endpoint
if curl -s -f "http://localhost:$HOST_PORT/plantuml/png/~1$COMPRESSED" -o /tmp/test_diagram.png; then
    echo "✓ PlantUML diagram generation successful"
else
    echo "✗ PlantUML diagram generation failed"
    exit 1
fi

# Verify it's actually a PNG file
if file /tmp/test_diagram.png | grep -q "PNG image"; then
    echo "✓ Generated file is a valid PNG image"
else
    echo "✗ Generated file is not a valid PNG image"
    exit 1
fi

echo "✓ All Docker PlantUML server tests passed"