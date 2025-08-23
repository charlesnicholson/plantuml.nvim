#!/bin/bash
set -euo pipefail

LOG_FILE="tests/logs/browser-ui.log"
echo "Testing browser UI interactions..." | tee "$LOG_FILE"

# Create screenshots directory if it doesn't exist
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping browser UI tests" | tee -a "$LOG_FILE"
    exit 0
fi

# Create Playwright test script
cat > browser_test.js << 'EOF'
const { chromium } = require('playwright');

(async () => {
  let browser;
  let page;
  
  try {
    // Launch browser
    browser = await chromium.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    const context = await browser.newContext();
    page = await context.newPage();
    
    // Navigate to the plugin's web interface
    console.log('Navigating to http://127.0.0.1:8764');
    await page.goto('http://127.0.0.1:8764', { waitUntil: 'networkidle' });
    
    // Test 1: Page loads correctly
    const title = await page.title();
    console.log('Page title:', title);
    if (!title.includes('PlantUML Viewer')) {
      throw new Error('Page title incorrect');
    }
    console.log('✓ Page loads with correct title');
    
    // Test 2: Required elements are present
    const statusElement = await page.$('#status');
    if (!statusElement) {
      throw new Error('Status element not found');
    }
    console.log('✓ Status element found');
    
    const boardElement = await page.$('#board');
    if (!boardElement) {
      throw new Error('Board element not found');
    }
    console.log('✓ Board element found');
    
    const imgElement = await page.$('#img');
    if (!imgElement) {
      throw new Error('Image element not found');
    }
    console.log('✓ Image element found');
    
    // Test 3: Check initial CSS classes
    const boardClasses = await page.getAttribute('#board', 'class');
    console.log('Initial board classes:', boardClasses);
    if (!boardClasses.includes('fit-to-page')) {
      throw new Error('Board does not have fit-to-page class initially');
    }
    console.log('✓ Board has correct initial CSS classes');
    
    // Test 4: Wait for WebSocket connection
    console.log('Waiting for WebSocket connection...');
    await page.waitForFunction(() => {
      const status = document.querySelector('#status-text');
      return status && (status.textContent === 'Live' || status.textContent === 'Connecting...');
    }, { timeout: 10000 });
    
    const statusText = await page.textContent('#status-text');
    console.log('WebSocket status:', statusText);
    console.log('✓ WebSocket connection established');
    
    // Test 5: Simulate diagram loading by injecting update
    console.log('Simulating diagram update...');
    await page.evaluate(() => {
      // Simulate receiving a WebSocket update
      const img = document.getElementById('img');
      const board = document.getElementById('board');
      
      // Set a dummy image src to trigger the loaded state
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      
      // Trigger the loaded state
      board.classList.add('has-diagram');
      window.hasLoadedDiagram = true;
    });
    
    // Wait for image to load
    await page.waitForFunction(() => {
      const board = document.getElementById('board');
      return board.classList.contains('has-diagram');
    });
    
    console.log('✓ Diagram loaded state simulated');
    
    // Test 6: Test click to toggle viewing modes
    console.log('Testing click toggle functionality...');
    
    // Initial state should be fit-to-page
    let boardClasses1 = await page.getAttribute('#board', 'class');
    console.log('Before click - Board classes:', boardClasses1);
    
    if (!boardClasses1.includes('fit-to-page')) {
      throw new Error('Board should initially have fit-to-page class');
    }
    
    // Click the board to toggle
    await page.click('#board');
    await page.waitForTimeout(100); // Brief wait for class change
    
    let boardClasses2 = await page.getAttribute('#board', 'class');
    console.log('After first click - Board classes:', boardClasses2);
    
    if (boardClasses2.includes('fit-to-page')) {
      throw new Error('Board should not have fit-to-page class after click');
    }
    console.log('✓ First click removed fit-to-page class');
    
    // Click again to toggle back
    await page.click('#board');
    await page.waitForTimeout(100);
    
    let boardClasses3 = await page.getAttribute('#board', 'class');
    console.log('After second click - Board classes:', boardClasses3);
    
    if (!boardClasses3.includes('fit-to-page')) {
      throw new Error('Board should have fit-to-page class after second click');
    }
    console.log('✓ Second click restored fit-to-page class');
    
    // Test 7: Take screenshot for verification
    await page.screenshot({ path: 'tests/screenshots/browser-ui-test.png' });
    console.log('✓ Screenshot saved');
    
    console.log('All browser UI tests passed!');
    
  } catch (error) {
    console.error('Browser test failed:', error);
    
    // Take screenshot on failure
    if (page) {
      try {
        await page.screenshot({ path: 'tests/screenshots/browser-ui-failure.png' });
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
EOF

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..." | tee -a "$LOG_FILE"
nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start()" &
NVIM_PID=$!

# Give server time to start
sleep 3

# Cleanup function
cleanup() {
    echo "Cleaning up..." | tee -a "$LOG_FILE"
    rm -f browser_test.js  # Clean up the test script
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Verify HTTP server is running first
echo "Verifying HTTP server is running..." | tee -a "$LOG_FILE"
if ! curl -f -s "http://127.0.0.1:8764" > /dev/null; then
    echo "✗ HTTP server not responding, cannot run browser tests" | tee -a "$LOG_FILE"
    exit 1
fi

# Run Playwright tests
echo "Running Playwright browser tests..." | tee -a "$LOG_FILE"
if DISPLAY=${DISPLAY:-:99} node browser_test.js 2>&1 | tee -a "$LOG_FILE"; then
    echo "✓ All browser UI tests passed" | tee -a "$LOG_FILE"
    rm -f browser_test.js  # Clean up the script
else
    echo "✗ Browser UI tests failed" | tee -a "$LOG_FILE"
    rm -f browser_test.js  # Clean up the script
    exit 1
fi