#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing browser UI interactions..."

# Setup isolated test environment
setup_test_env

# Create screenshots directory
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping browser UI tests"
    exit 0
fi

# Start Neovim with plugin in background (clean mode, only local plugin)
echo "Starting Neovim with plugin..."
nvim --headless --clean \
    -c "lua vim.opt.runtimepath:prepend('$PLUGIN_DIR')" \
    -c "lua package.loaded.plantuml = nil; package.loaded['plantuml.docker'] = nil" \
    -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = $TEST_HTTP_PORT}); p.start()" &
NVIM_PID=$!
track_pid "$NVIM_PID"

# Wait for health endpoint to report ready
if ! wait_for_health 10; then
    echo "✗ Server failed to become ready"
    exit 1
fi

# Verify HTTP server is running
echo "Verifying HTTP server is running..."
if ! curl -f -s "http://127.0.0.1:$TEST_HTTP_PORT" > /dev/null; then
    echo "✗ HTTP server not responding, cannot run browser tests"
    exit 1
fi

# Create Playwright test script
cat > "$TEST_TMP_DIR/browser_test.js" << 'EOF'
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

    // Navigate to the plugin's web interface
    console.log(`Navigating to http://127.0.0.1:${TEST_PORT}`);
    await page.goto(`http://127.0.0.1:${TEST_PORT}`, { waitUntil: 'networkidle' });

    // Test 1: Page loads correctly
    const title = await page.title();
    console.log('Page title:', title);
    if (!title.includes('PlantUML Viewer')) {
      throw new Error('Page title incorrect');
    }
    console.log('✓ Page loads with correct title');

    // Test 2: Required elements are present
    const elements = ['#status', '#board', '#img', '#timestamp', '#server-url'];
    for (const selector of elements) {
      const element = await page.$(selector);
      if (!element) {
        throw new Error(`Element ${selector} not found`);
      }
    }
    console.log('✓ All required elements found');

    // Test 3: Check CSS classes
    const boardClasses = await page.getAttribute('#board', 'class');
    if (!boardClasses.includes('board')) {
      throw new Error('Board does not have board class');
    }
    console.log('✓ Board has correct CSS classes');

    // Test 4: Wait for WebSocket connection - use waitForFunction with proper predicate
    console.log('Waiting for WebSocket connection...');
    await page.waitForFunction(() => {
      const status = document.querySelector('#status-text');
      // Accept any status that indicates connection happened
      return status && (
        status.textContent === 'Live' ||
        status.textContent.includes('Starting') ||
        status.textContent.includes('Docker')
      );
    }, { timeout: 10000 });

    const statusText = await page.textContent('#status-text');
    console.log('WebSocket status:', statusText);
    console.log('✓ WebSocket connection established');

    // Test 5: Test filename truncation function exists and works
    console.log('Testing filename truncation...');
    const truncationTests = await page.evaluate(() => {
      if (typeof window.truncateFilename !== 'function') {
        throw new Error('window.truncateFilename function not found');
      }

      const tests = [];

      // Rule 1: Entire path fits
      const shortPath = 'test.puml';
      tests.push({
        name: 'Entire path fits',
        passed: window.truncateFilename(shortPath, 1000) === shortPath
      });

      // Rule 2: Truncate from left
      const longPath = 'very/long/path/to/deep/directory/filename.puml';
      const truncated = window.truncateFilename(longPath, 200);
      tests.push({
        name: 'Truncate preserves filename',
        passed: truncated.endsWith('filename.puml')
      });

      // Rule 3: Filename only when insufficient space
      const filenameOnly = window.truncateFilename(longPath, 50);
      tests.push({
        name: 'Filename only for narrow width',
        passed: filenameOnly === 'filename.puml'
      });

      return tests;
    });

    for (const test of truncationTests) {
      if (!test.passed) {
        throw new Error(`Truncation test "${test.name}" failed`);
      }
      console.log(`✓ Truncation: ${test.name}`);
    }

    // Test 6: Test that updateFilenameDisplay function works
    console.log('Testing updateFilenameDisplay function...');
    const testFilename = 'very/long/path/to/some/deep/directory/structure/filename.puml';

    // Test that updateFilenameDisplay sets the file element content
    await page.evaluate((filename) => {
      window.currentFilename = filename;
      window.updateFilenameDisplay();
    }, testFilename);

    // Wait for the display to update
    await page.waitForFunction(() => {
      const el = document.getElementById('file');
      return el && el.textContent && el.textContent.length > 0;
    }, { timeout: 5000 });

    const displayedFilename = await page.textContent('#file');
    console.log('Displayed filename:', displayedFilename);

    // The filename should be set (either truncated or full)
    if (!displayedFilename || displayedFilename.length === 0) {
      throw new Error('updateFilenameDisplay did not set file content');
    }

    // Title should always contain the full path
    const titleAttr = await page.getAttribute('#file', 'title');
    if (titleAttr !== testFilename) {
      throw new Error('File title attribute not set correctly');
    }
    console.log('✓ updateFilenameDisplay works correctly');

    // Test 7: Take screenshot
    await page.screenshot({ path: 'tests/screenshots/browser-ui-test.png' });
    console.log('✓ Screenshot saved');

    console.log('All browser UI tests passed!');

  } catch (error) {
    console.error('Browser test failed:', error);
    if (page) {
      try {
        await page.screenshot({ path: 'tests/screenshots/browser-ui-failure.png' });
      } catch (e) {}
    }
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

# Run Playwright tests
echo "Running Playwright browser tests..."
if TEST_HTTP_PORT="$TEST_HTTP_PORT" NODE_PATH="$PLUGIN_DIR/node_modules" DISPLAY=${DISPLAY:-:99} node "$TEST_TMP_DIR/browser_test.js" 2>&1; then
    echo "✓ All browser UI tests passed"
else
    echo "✗ Browser UI tests failed"
    exit 1
fi
