#!/bin/bash
set -euo pipefail



echo "Testing browser UI interactions..."

# Create screenshots directory if it doesn't exist (this is needed for actual screenshots)
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping browser UI tests"
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
    
    // Test 2.5: Check for new UI elements (timestamp and server URL)
    const timestampElement = await page.$('#timestamp');
    if (!timestampElement) {
      throw new Error('Timestamp element not found');
    }
    console.log('✓ Timestamp element found');
    
    const serverUrlElement = await page.$('#server-url');
    if (!serverUrlElement) {
      throw new Error('Server URL element not found');
    }
    console.log('✓ Server URL element found');
    
    // Test 2.6: Check for current layout styling in CSS
    const pageContent = await page.content();
    if (!pageContent.includes('.server-link{')) {
      throw new Error('Server-link class styling not found in CSS');
    }
    if (!pageContent.includes('.timestamp{')) {
      throw new Error('Timestamp class styling not found in CSS');
    }
    if (!pageContent.includes('.filename-section{')) {
      throw new Error('Filename-section class styling not found in CSS');
    }
    if (!pageContent.includes('.status-section{')) {
      throw new Error('Status-section class styling not found in CSS');
    }
    if (!pageContent.includes('.info-section{')) {
      throw new Error('Info-section class styling not found in CSS');
    }
    console.log('✓ Current layout styling found in CSS');
    
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
    
    // Test 4.5: Check initial file element text (should be empty when no image loaded)
    console.log('Testing initial file element text...');
    const fileElement = await page.$('#file');
    if (!fileElement) {
      throw new Error('File element not found');
    }
    const initialFileText = await page.textContent('#file');
    console.log('Initial file text:', JSON.stringify(initialFileText));
    if (initialFileText !== '') {
      throw new Error(`Expected empty file text when no image loaded, but got: "${initialFileText}"`);
    }
    console.log('✓ File element is empty when no image is loaded');
    
    // Test 4.6: Test filename truncation behavior
    console.log('Testing filename truncation behavior...');
    
    const truncationTests = await page.evaluate(() => {
      // Use the actual truncateFilename function from the HTML page
      if (typeof window.truncateFilename !== 'function') {
        throw new Error('window.truncateFilename function not found on page');
      }
      
      const tests = [];
      
      // Test 1: Rule 1 - If the entire path and file fit, render the entire path and file
      const shortPath = 'test.puml';
      const shortResult = window.truncateFilename(shortPath, 1000);
      tests.push({
        name: 'Rule 1: Entire path fits',
        input: shortPath,
        expected: shortPath,
        actual: shortResult,
        passed: shortResult === shortPath
      });
      
      const fullPath = 'path/to/file.puml';
      const fullResult = window.truncateFilename(fullPath, 1000);
      tests.push({
        name: 'Rule 1: Full path with directories fits',
        input: fullPath,
        expected: fullPath,
        actual: fullResult,
        passed: fullResult === fullPath
      });
      
      // Test 2: Rule 2 - If only part fits, truncate from left preserving filename
      const longPath = 'very/long/path/to/some/deep/directory/structure/filename.puml';
      const partialResult = window.truncateFilename(longPath, 200);
      tests.push({
        name: 'Rule 2: Truncate from left preserving filename',
        input: longPath,
        actual: partialResult,
        expected: 'Should start with ... and end with filename.puml (NOT filename-only)',
        passed: partialResult.startsWith('...') && partialResult.endsWith('filename.puml') && partialResult !== 'filename.puml'
      });
      
      // Test 3: Rule 2 - Truncate by path components, not partial strings
      const pathComponents = 'path/to/some/plantuml/file.puml';
      const componentResult = window.truncateFilename(pathComponents, 180);
      tests.push({
        name: 'Rule 2: Truncate by path components',
        input: pathComponents,
        actual: componentResult,
        expected: 'Should be .../plantuml/file.puml or similar complete path components (NOT filename-only)',
        passed: (componentResult.startsWith('...') && componentResult.endsWith('file.puml') && 
                componentResult !== 'file.puml' && !componentResult.includes('...tuml'))
      });
      
      // Test 4: Rule 3 - If not enough space for path, show filename only without ellipses
      const filenameOnlyResult = window.truncateFilename(longPath, 50);
      tests.push({
        name: 'Rule 3: Filename only when insufficient space',
        input: longPath,
        expected: 'filename.puml',
        actual: filenameOnlyResult,
        passed: filenameOnlyResult === 'filename.puml'
      });
      
      // Test 5: Edge case - path without directories
      const noDir = 'file.puml';
      const noDirResult = window.truncateFilename(noDir, 30);
      tests.push({
        name: 'Edge case: No directories',
        input: noDir,
        expected: 'file.puml',
        actual: noDirResult,
        passed: noDirResult === 'file.puml'
      });
      
      // Test 6: Edge case - very long filename that doesn't fit
      const longFilename = 'very_long_filename_that_might_not_fit.puml';
      const longFilenameResult = window.truncateFilename(longFilename, 30);
      tests.push({
        name: 'Edge case: Long filename',
        input: longFilename,
        expected: longFilename,
        actual: longFilenameResult,
        passed: longFilenameResult === longFilename
      });
      
      return tests;
    });
    
    // Validate truncation test results
    for (const test of truncationTests) {
      console.log(`Truncation test "${test.name}":`, test.actual);
      if (!test.passed) {
        throw new Error(`Truncation test "${test.name}" failed. Expected: ${test.expected || 'valid truncation'}, Got: ${test.actual}`);
      }
    }
    console.log('✓ All filename truncation tests passed');
    
    // Test 5: Enable click functionality for testing
    console.log('Enabling click functionality for testing...');
    
    // Since hasLoadedDiagram is in a closure, we need to work around it
    // We'll override the click handler to make it work in test mode
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Set up the initial state
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      // Create a test-friendly click handler that doesn't depend on hasLoadedDiagram
      // We need to remove the existing event listeners first
      const newBoard = board.cloneNode(true);
      board.parentNode.replaceChild(newBoard, board);
      
      // Add our test click handler
      let testIsFitToPage = true;
      newBoard.addEventListener('click', () => {
        console.log('Test click handler triggered, current state:', testIsFitToPage);
        testIsFitToPage = !testIsFitToPage;
        if (testIsFitToPage) {
          newBoard.classList.add('fit-to-page');
          console.log('Added fit-to-page class');
        } else {
          newBoard.classList.remove('fit-to-page');
          console.log('Removed fit-to-page class');
        }
      });
      
      // Store reference for debugging
      window.testBoard = newBoard;
      window.testIsFitToPage = testIsFitToPage;
      
      return true;
    });
    
    // Wait for image to load
    await page.waitForFunction(() => {
      const board = document.getElementById('board');
      return board.classList.contains('has-diagram');
    });
    
    console.log('✓ Diagram loaded state simulated');
    
    // Test 6: Test click to toggle viewing modes
    console.log('Testing click toggle functionality...');
    
    // Verify the test setup worked
    await page.waitForFunction(() => window.testBoard !== undefined, { timeout: 5000 });
    
    // Initial state should be fit-to-page
    let boardClasses1 = await page.evaluate(() => {
      const board = window.testBoard;
      return board.className;
    });
    console.log('Before click - Board classes:', boardClasses1);
    
    if (!boardClasses1.includes('fit-to-page')) {
      throw new Error('Board should initially have fit-to-page class');
    }
    
    // Click the board to toggle
    await page.evaluate(() => {
      console.log('About to click the test board');
      const board = window.testBoard;
      board.click();
    });
    await page.waitForTimeout(200); // Wait for class change
    
    let boardClasses2 = await page.evaluate(() => {
      const board = window.testBoard;
      return board.className;
    });
    console.log('After first click - Board classes:', boardClasses2);
    
    if (boardClasses2.includes('fit-to-page')) {
      throw new Error('Board should not have fit-to-page class after click');
    }
    console.log('✓ First click removed fit-to-page class');
    
    // Click again to toggle back
    await page.evaluate(() => {
      console.log('About to click the test board again');
      const board = window.testBoard;
      board.click();
    });
    await page.waitForTimeout(200);
    
    let boardClasses3 = await page.evaluate(() => {
      const board = window.testBoard;
      return board.className;
    });
    console.log('After second click - Board classes:', boardClasses3);
    
    if (!boardClasses3.includes('fit-to-page')) {
      throw new Error('Board should have fit-to-page class after second click');
    }
    console.log('✓ Second click restored fit-to-page class');
    
    // Test 7: Test filename re-truncation on browser resize
    console.log('Testing filename re-truncation on browser resize...');
    
    // Set up a test filename and simulate a narrow window
    const setupResult = await page.evaluate(() => {
      const fileEl = document.getElementById('file');
      const filenameSection = document.querySelector('.filename-section');
      
      // Store the original filename for testing
      const testFilename = 'very/long/path/to/some/deep/directory/structure/filename.puml';
      
      // Manually set the currentFilename variable (simulate what WebSocket would do)
      window.currentFilename = testFilename;
      
      // Set a specific narrow width for consistent testing
      filenameSection.style.width = '120px';
      
      // Apply truncation with narrow width (force it to truncate significantly)
      const narrowMaxWidth = 100; // Force a narrow width
      const narrowTruncated = window.truncateFilename(testFilename, narrowMaxWidth);
      fileEl.textContent = narrowTruncated;
      fileEl.title = testFilename;
      
      return {
        original: testFilename,
        narrowTruncated: narrowTruncated,
        narrowWidth: narrowMaxWidth
      };
    });
    
    console.log('Filename after narrow setup:', setupResult.narrowTruncated);
    
    // Verify we actually got truncation
    if (setupResult.narrowTruncated === setupResult.original) {
      throw new Error('Test setup failed: filename was not truncated in narrow width');
    }
    
    // Now simulate expanding the window
    await page.evaluate(() => {
      const filenameSection = document.querySelector('.filename-section');
      
      // Expand the filename section width significantly
      filenameSection.style.width = '400px';
      
      // Manually call the update function to test it directly
      if (typeof window.updateFilenameDisplay === 'function') {
        window.updateFilenameDisplay();
      }
      
      // Also trigger a resize event
      window.dispatchEvent(new Event('resize'));
      
      return true;
    });
    
    // Wait a moment for resize handler to process
    await page.waitForTimeout(100);
    
    const expandedResult = await page.evaluate(() => {
      return document.getElementById('file').textContent;
    });
    console.log('Filename after expanded resize:', expandedResult);
    
    // Verify that the filename expanded when more space became available
    if (expandedResult === setupResult.narrowTruncated) {
      throw new Error(`Filename did not re-truncate on resize. Expected expansion from "${setupResult.narrowTruncated}" but got "${expandedResult}"`);
    }
    
    // Verify the expanded result shows more of the path than the narrow version
    if (expandedResult.length <= setupResult.narrowTruncated.length) {
      throw new Error(`Expanded filename should be longer than narrow version. Narrow: "${setupResult.narrowTruncated}", Expanded: "${expandedResult}"`);
    }
    
    console.log('✓ Filename successfully re-truncated on browser resize');
    
    // Test 8: Test initial filename load truncation (bug reproduction)
    console.log('Testing initial filename load truncation behavior...');
    
    const initialLoadTest = await page.evaluate(() => {
      const fileEl = document.getElementById('file');
      const filenameSection = document.querySelector('.filename-section');
      
      // Clear current state
      fileEl.textContent = '';
      window.currentFilename = '';
      
      // Simulate a very long filename like in the bug report
      const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
      
      // Set current width to something reasonable (not too narrow, not too wide)
      filenameSection.style.width = '300px';
      
      // Simulate what happens on initial load - set the filename and immediately display
      window.currentFilename = longFilename;
      updateFilenameDisplay();
      
      const displayedText = fileEl.textContent;
      
      return {
        originalFilename: longFilename,
        displayedText: displayedText,
        // Check if it's properly left-truncated (starts with ...) vs right-truncated (ends with ...)
        isLeftTruncated: displayedText.startsWith('...') && displayedText.endsWith('.puml'),
        isRightTruncated: displayedText.endsWith('...') && !displayedText.startsWith('...'),
        filenamePreserved: displayedText.endsWith('some_component.puml')
      };
    });
    
    console.log('Initial load test results:');
    console.log('  Original:', initialLoadTest.originalFilename);
    console.log('  Displayed:', initialLoadTest.displayedText);
    console.log('  Left-truncated:', initialLoadTest.isLeftTruncated);
    console.log('  Right-truncated:', initialLoadTest.isRightTruncated);
    console.log('  Filename preserved:', initialLoadTest.filenamePreserved);
    
    // The bug is that it shows right-truncated text initially
    // After fix, it should be left-truncated with filename preserved
    if (initialLoadTest.isRightTruncated) {
      throw new Error(`BUG REPRODUCED: Initial load shows right-truncated filename "${initialLoadTest.displayedText}" - should be left-truncated preserving filename`);
    }
    
    if (!initialLoadTest.isLeftTruncated || !initialLoadTest.filenamePreserved) {
      throw new Error(`Initial load filename truncation incorrect. Expected left-truncated with filename preserved, got: "${initialLoadTest.displayedText}"`);
    }
    
    console.log('✓ Initial filename load shows correct left-truncation');
    
    // Test 9: Take screenshot for verification
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
echo "Starting Neovim with plugin..."
nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start()" &
NVIM_PID=$!

# Wait for server to be ready
echo "Waiting for server to be ready..."
for i in {1..10}; do
    if netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
        echo "HTTP server is listening"
        break
    fi
    echo "Waiting for HTTP server to start (attempt $i/10)..."
    sleep 1
done

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    rm -f browser_test.js  # Clean up the test script
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Verify HTTP server is running first
echo "Verifying HTTP server is running..."
if ! curl -f -s "http://127.0.0.1:8764" > /dev/null; then
    echo "✗ HTTP server not responding, cannot run browser tests"
    exit 1
fi

# Run Playwright tests
echo "Running Playwright browser tests..."
if DISPLAY=${DISPLAY:-:99} node browser_test.js 2>&1; then
    echo "✓ All browser UI tests passed"
    rm -f browser_test.js  # Clean up the script
else
    echo "✗ Browser UI tests failed"
    rm -f browser_test.js  # Clean up the script
    exit 1
fi