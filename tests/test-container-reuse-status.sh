#!/bin/bash
set -euo pipefail

echo "Testing Docker container reuse status UI behavior..."

# Create screenshots directory if it doesn't exist
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping container reuse status tests"
    exit 0
fi

# Check if Docker is available for testing
if ! command -v docker &> /dev/null; then
    echo "⚠ Docker not available, skipping container reuse status tests"
    exit 0
fi

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    # Kill any running Neovim instances
    pkill -f "nvim.*plantuml" || true
    # Clean up Docker containers
    docker stop plantuml-nvim 2>/dev/null || true
    docker rm plantuml-nvim 2>/dev/null || true
    # Clean up temp files
    rm -f container_reuse_test.js
    sleep 2
}

# Set up cleanup trap
trap cleanup EXIT

# First start a Docker container manually to simulate existing container
echo "Setting up existing Docker container..."
docker run -d --name plantuml-nvim -p 8080:8080 plantuml/plantuml-server:jetty

# Wait for container to be ready
echo "Waiting for PlantUML server to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "✓ PlantUML server is responding"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "✗ PlantUML server failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Create a test config that uses Docker
echo "Starting Neovim with Docker-enabled plugin..."
cat > /tmp/test_config.lua << 'EOF'
vim.opt.runtimepath:append(".")

require("plantuml").setup({
  auto_start = true,
  use_docker = true
})
EOF

# Start Neovim in background
timeout 30s nvim --headless --clean -u /tmp/test_config.lua > /tmp/nvim.log 2>&1 &
NVIM_PID=$!

# Wait for HTTP server to be ready
echo "Waiting for server to be ready..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8764/ > /dev/null 2>&1; then
        echo "HTTP server is listening"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "HTTP server failed to start"
        cat /tmp/nvim.log
        exit 1
    fi
    sleep 1
done

echo "Verifying HTTP server is running..."
if ! curl -s http://127.0.0.1:8764/ > /dev/null; then
    echo "HTTP server is not responding"
    exit 1
fi

# Create Playwright test to verify container reuse shows Live status
cat > container_reuse_test.js << 'EOF'
const { chromium } = require('playwright');

(async () => {
  let browser;
  let page;
  
  try {
    browser = await chromium.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    const context = await browser.newContext();
    page = await context.newPage();
    
    // Enable console logging
    page.on('console', msg => console.log('Browser console:', msg.text()));
    
    // Navigate to the plugin's web interface
    console.log('Navigating to http://127.0.0.1:8764');
    await page.goto('http://127.0.0.1:8764', { waitUntil: 'networkidle' });
    
    // Test: Verify that container reuse results in "Live" status
    console.log('Test: Checking container reuse status...');
    
    // Wait for initial WebSocket connection
    await page.waitForFunction(() => {
      const status = document.querySelector('#status-text');
      return status && status.textContent !== 'Connecting...';
    }, { timeout: 15000 });
    
    // Monitor status changes and capture all status messages
    let statusMessages = [];
    let finalStatus = '';
    
    // Wait up to 10 seconds and collect all status messages
    const startTime = Date.now();
    while (Date.now() - startTime < 10000) {
      const currentStatus = await page.textContent('#status-text');
      if (currentStatus && currentStatus !== finalStatus) {
        finalStatus = currentStatus;
        statusMessages.push(currentStatus);
        console.log('Status update:', currentStatus);
      }
      await page.waitForTimeout(500);
    }
    
    console.log('All captured status messages:', statusMessages);
    console.log('Final status:', finalStatus);
    
    // Check if we see the container reuse message
    const hasContainerReuseMessage = statusMessages.some(msg => 
      msg.toLowerCase().includes('existing') && msg.toLowerCase().includes('container')
    );
    
    if (hasContainerReuseMessage) {
      console.log('✓ Container reuse message detected');
      
      // The key test: After container reuse, status should eventually be "Live"
      if (finalStatus === 'Live') {
        console.log('✓ Status correctly transitioned to "Live" after container reuse');
        
        // Verify status color is green (ok)
        const statusClasses = await page.getAttribute('#status', 'class');
        if (statusClasses && statusClasses.includes('ok')) {
          console.log('✓ Status has correct "ok" CSS class (green)');
        } else {
          throw new Error('Status does not have "ok" CSS class. Classes: ' + statusClasses);
        }
        
      } else {
        throw new Error('Expected final status to be "Live" after container reuse, but got: ' + finalStatus);
      }
    } else {
      throw new Error('Expected to see container reuse message, but got: ' + statusMessages.join(', '));
    }
    
    // Take screenshot for verification
    await page.screenshot({ path: 'tests/screenshots/container-reuse-status.png' });
    console.log('✓ Screenshot saved');
    
    console.log('All container reuse status tests passed!');
    
  } catch (error) {
    console.error('Test failed:', error.message);
    if (page) {
      await page.screenshot({ path: 'tests/screenshots/container-reuse-status-failed.png' });
    }
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "Running container reuse status tests..."
npx playwright install chromium >/dev/null 2>&1 || true
if ! node container_reuse_test.js; then
    echo "✗ Container reuse status tests failed"
    echo "Neovim log:"
    cat /tmp/nvim.log || true
    exit 1
fi

echo "✓ All container reuse status tests passed"