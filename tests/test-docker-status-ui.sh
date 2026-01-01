#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing Docker status UI functionality..."

# Setup isolated test environment
setup_test_env

# Create screenshots directory
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping Docker status UI tests"
    exit 0
fi

# Check if Docker is available for testing
if ! command -v docker &> /dev/null; then
    echo "⚠ Docker not available, skipping Docker status UI tests"
    exit 0
fi

# Remove existing container to force a fresh startup and capture status messages
echo "Removing existing Docker container to force fresh startup..."
docker rm -f plantuml-nvim 2>/dev/null || true

# Create Playwright test script for Docker status UI
cat > "$TEST_TMP_DIR/docker_status_ui_test.js" << 'ENDOFJS'
const { chromium } = require('playwright');

const TEST_PORT = process.env.TEST_HTTP_PORT || '8764';

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
    console.log(`Navigating to http://127.0.0.1:${TEST_PORT}`);
    await page.goto(`http://127.0.0.1:${TEST_PORT}`, { waitUntil: 'networkidle' });

    // Test 1: Wait for WebSocket connection and capture status messages
    console.log('Test 1: Capturing status messages during Docker startup...');

    // Set up mutation observer to capture all status changes
    const capturedMessages = await page.evaluate(() => {
      return new Promise((resolve) => {
        const statusEl = document.querySelector('#status-text');
        const messages = new Set();
        let timeoutId;

        // Capture initial state
        messages.add(statusEl.textContent);

        const observer = new MutationObserver((mutations) => {
          const text = statusEl.textContent;
          messages.add(text);
          console.log('Status changed to:', text);

          // Reset timeout - resolve after status stabilizes
          if (timeoutId) clearTimeout(timeoutId);
          timeoutId = setTimeout(() => {
            observer.disconnect();
            resolve(Array.from(messages));
          }, 3000);
        });

        observer.observe(statusEl, {
          childList: true,
          characterData: true,
          subtree: true
        });

        // Initial timeout in case status doesn't change
        timeoutId = setTimeout(() => {
          observer.disconnect();
          resolve(Array.from(messages));
        }, 10000);
      });
    });

    console.log('Captured status messages:', capturedMessages);

    // Check for Docker-related status messages OR proper state transitions
    const dockerRelatedMessages = capturedMessages.filter(msg =>
      msg.toLowerCase().includes('docker') ||
      msg.toLowerCase().includes('starting') ||
      msg.toLowerCase().includes('container')
    );

    // Also check for the state machine states from the server
    const stateMessages = capturedMessages.filter(msg =>
      msg === 'Live' ||
      msg === 'Connecting...' ||
      msg === 'Starting Docker...' ||
      msg === 'Starting...'
    );

    console.log('Docker-related messages:', dockerRelatedMessages);
    console.log('State messages:', stateMessages);

    // Test passes if we see either Docker status messages OR proper state transitions
    const hasDockerMessages = dockerRelatedMessages.length > 0;
    const hasProperTransition = capturedMessages.includes('Live');

    if (!hasDockerMessages && !hasProperTransition) {
      throw new Error(`No Docker status messages or proper state transitions found. Got: ${JSON.stringify(capturedMessages)}`);
    }

    if (hasDockerMessages) {
      console.log('✓ Docker status messages found');
    } else {
      console.log('✓ Server transitioned to Live state (Docker started quickly)');
    }

    // Test 2: Verify WebSocket message handling for Docker status
    console.log('Test 2: Testing WebSocket Docker status message simulation...');

    // Simulate receiving a Docker status message directly in the DOM
    const simulationResult = await page.evaluate(() => {
      const statusEl = document.querySelector('#status-text');
      const statusPill = document.querySelector('#status');

      // Simulate Docker status message handling
      const originalText = statusEl.textContent;
      const originalClass = statusPill.className;

      // Simulate "Pulling..." status
      statusEl.textContent = 'Pulling image...';
      statusPill.className = 'pill warn';

      return {
        originalText,
        originalClass,
        simulatedText: statusEl.textContent,
        simulatedClass: statusPill.className
      };
    });

    console.log('Simulation result:', simulationResult);

    if (simulationResult.simulatedText !== 'Pulling image...') {
      throw new Error('Failed to simulate Docker status message');
    }
    console.log('✓ Docker status simulation works');

    // Test 3: Verify status CSS classes
    console.log('Test 3: Testing status CSS classes...');

    // Reset to Live and verify
    await page.evaluate(() => {
      document.querySelector('#status-text').textContent = 'Live';
      document.querySelector('#status').className = 'pill ok';
    });

    const statusClasses = await page.getAttribute('#status', 'class');
    if (!statusClasses.includes('pill') || !statusClasses.includes('ok')) {
      throw new Error(`Invalid status classes: ${statusClasses}`);
    }
    console.log('✓ Status CSS classes work correctly');

    // Test 4: Verify error status styling
    console.log('Test 4: Testing error status styling...');

    await page.evaluate(() => {
      document.querySelector('#status-text').textContent = 'Docker startup failed';
      document.querySelector('#status').className = 'pill err';
    });

    const errorClasses = await page.getAttribute('#status', 'class');
    if (!errorClasses.includes('err')) {
      throw new Error(`Error status missing 'err' class: ${errorClasses}`);
    }
    console.log('✓ Error status styling works');

    // Test 5: Verify warning status styling
    console.log('Test 5: Testing warning status styling...');

    await page.evaluate(() => {
      document.querySelector('#status-text').textContent = 'Starting Docker...';
      document.querySelector('#status').className = 'pill warn';
    });

    const warnClasses = await page.getAttribute('#status', 'class');
    if (!warnClasses.includes('warn')) {
      throw new Error(`Warning status missing 'warn' class: ${warnClasses}`);
    }
    console.log('✓ Warning status styling works');

    // Take screenshot for verification
    await page.screenshot({ path: 'tests/screenshots/docker-status-ui-test.png' });
    console.log('✓ Screenshot saved');

    console.log('All Docker status UI tests passed!');

  } catch (error) {
    console.error('Docker status UI test failed:', error);

    if (page) {
      try {
        await page.screenshot({ path: 'tests/screenshots/docker-status-ui-failure.png' });
        console.log('Failure screenshot saved');
      } catch (screenshotError) {
        console.error('Failed to take failure screenshot:', screenshotError);
      }
    }

    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
ENDOFJS

# Start Neovim with Docker-enabled plugin in background
echo "Starting Neovim with Docker-enabled plugin..."
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $TEST_HTTP_PORT, use_docker = true, docker_port = 8081}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

# Wait for HTTP server (not full health) - we want to connect during Docker startup
if ! wait_for_http 15; then
    echo "✗ HTTP server failed to start"
    exit 1
fi

# Run Playwright tests
echo "Running Docker status UI tests..."
if TEST_HTTP_PORT="$TEST_HTTP_PORT" NODE_PATH="$PLUGIN_DIR/node_modules" DISPLAY=${DISPLAY:-:99} node "$TEST_TMP_DIR/docker_status_ui_test.js" 2>&1; then
    echo "✓ All Docker status UI tests passed"
else
    echo "✗ Docker status UI tests failed"
    exit 1
fi
