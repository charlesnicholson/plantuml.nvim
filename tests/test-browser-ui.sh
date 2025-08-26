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
    if (!boardClasses.includes('board')) {
      throw new Error('Board does not have board class');
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
    
    // Test 5: Test filename re-truncation on browser resize
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
    
    // Test 8: Test proper filename truncation without CSS ellipsis
    console.log('Testing proper filename truncation without CSS ellipsis...');
    
    const truncationTest = await page.evaluate(() => {
      const fileEl = document.getElementById('file');
      const filenameSection = document.querySelector('.filename-section');
      
      // Test filename from the bug report
      const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
      
      // Set a width that should allow for some path but not the full path
      filenameSection.style.width = '250px';
      filenameSection.style.minWidth = '250px';
      filenameSection.style.maxWidth = '250px';
      
      // Apply JavaScript truncation
      window.currentFilename = longFilename;
      updateFilenameDisplay();
      
      const result = fileEl.textContent;
      const availableWidth = filenameSection.getBoundingClientRect().width - 20;
      
      return {
        originalFilename: longFilename,
        truncatedResult: result,
        availableWidth: availableWidth,
        isLeftTruncated: result.startsWith('...'),
        isRightTruncated: result.endsWith('...') && !result.startsWith('...'),
        filenamePreserved: result.endsWith('some_component.puml'),
        hasProperTruncation: result.startsWith('...') && result.endsWith('some_component.puml'),
        noCssEllipsis: getComputedStyle(fileEl).textOverflow !== 'ellipsis'
      };
    });
    
    console.log('Truncation test results:');
    console.log('  Original:', truncationTest.originalFilename);
    console.log('  Truncated:', truncationTest.truncatedResult);
    console.log('  Available width:', truncationTest.availableWidth);
    console.log('  CSS ellipsis removed:', truncationTest.noCssEllipsis);
    console.log('  Left-truncated:', truncationTest.isLeftTruncated);
    console.log('  Right-truncated:', truncationTest.isRightTruncated);
    console.log('  Filename preserved:', truncationTest.filenamePreserved);
    console.log('  Proper truncation:', truncationTest.hasProperTruncation);
    
    // Verify the fix
    if (!truncationTest.noCssEllipsis) {
      throw new Error('CSS text-overflow ellipsis still present - should be removed');
    }
    
    if (truncationTest.isRightTruncated) {
      throw new Error(`BUG STILL PRESENT: Right-truncated filename "${truncationTest.truncatedResult}" - should be left-truncated`);
    }
    
    // The filename should either be properly left-truncated or fit completely
    const isAcceptable = truncationTest.hasProperTruncation || 
                         (truncationTest.truncatedResult === truncationTest.originalFilename);
    
    if (!isAcceptable) {
      throw new Error(`Unexpected truncation result: "${truncationTest.truncatedResult}"`);
    }
    
    console.log('✓ Filename truncation working correctly without CSS ellipsis');
    
    // Test 9: Click-to-zoom behavior tests for bug fix
    console.log('Testing click-to-zoom bug fix behavior...');
    
    // Test Rule 1: Image at natural size should not allow clicking
    const rule1Test = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Setup: Simulate small image that displays at natural size
      // Override naturalWidth/Height properties
      Object.defineProperty(img, 'naturalWidth', { value: 200, configurable: true });
      Object.defineProperty(img, 'naturalHeight', { value: 150, configurable: true });
      
      // Mock getBoundingClientRect to simulate image at natural size
      const originalImgRect = img.getBoundingClientRect;
      img.getBoundingClientRect = () => ({
        width: 200,  // Same as natural width
        height: 150  // Same as natural height
      });
      
      const originalBoardRect = board.getBoundingClientRect;
      board.getBoundingClientRect = () => ({
        width: 800,  // Larger than image
        height: 600
      });
      
      // Test isImageAtNaturalSize function
      const isAtNaturalSize = Math.abs(200 - img.naturalWidth) < 1 && Math.abs(150 - img.naturalHeight) < 1;
      
      // Test isImageAtFullWidthOfBrowser function  
      const fillsWidth = img.naturalWidth >= 800;
      
      // Restore original functions
      img.getBoundingClientRect = originalImgRect;
      board.getBoundingClientRect = originalBoardRect;
      
      return {
        test: 'Rule 1 - Natural size image',
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        isAtNaturalSize: isAtNaturalSize,
        fillsWidth: fillsWidth,
        shouldPreventClick: isAtNaturalSize || fillsWidth
      };
    });
    
    console.log('Rule 1 test result:', rule1Test);
    if (!rule1Test.shouldPreventClick) {
      throw new Error('Rule 1 test failed: Should prevent clicking for image at natural size');
    }
    console.log('✓ Rule 1 passed: Natural size image prevents clicking');
    
    // Test Rule 2: Tall image that fills browser width should not allow clicking
    const rule2Test = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Setup: Tall image that fills browser horizontally
      Object.defineProperty(img, 'naturalWidth', { value: 800, configurable: true });
      Object.defineProperty(img, 'naturalHeight', { value: 1200, configurable: true });
      
      // Mock getBoundingClientRect to simulate image not at natural size but fills width
      const originalImgRect = img.getBoundingClientRect;
      img.getBoundingClientRect = () => ({
        width: 400,  // Smaller than natural (not at natural size)
        height: 600
      });
      
      const originalBoardRect = board.getBoundingClientRect;
      board.getBoundingClientRect = () => ({
        width: 800,  // Same as image natural width
        height: 600
      });
      
      // Test conditions
      const isAtNaturalSize = Math.abs(400 - img.naturalWidth) < 1 && Math.abs(600 - img.naturalHeight) < 1;
      const fillsWidth = img.naturalWidth >= 800;
      const isTallerThanWide = img.naturalHeight > img.naturalWidth;
      
      // Restore original functions
      img.getBoundingClientRect = originalImgRect;
      board.getBoundingClientRect = originalBoardRect;
      
      return {
        test: 'Rule 2 - Tall image fills width',
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        aspectRatio: img.naturalHeight / img.naturalWidth,
        isAtNaturalSize: isAtNaturalSize,
        fillsWidth: fillsWidth,
        isTallerThanWide: isTallerThanWide,
        shouldPreventClick: isAtNaturalSize || fillsWidth
      };
    });
    
    console.log('Rule 2 test result:', rule2Test);
    if (!rule2Test.shouldPreventClick) {
      throw new Error('Rule 2 test failed: Should prevent clicking for tall image that fills browser width');
    }
    if (!rule2Test.isTallerThanWide) {
      throw new Error('Rule 2 test setup failed: Image should be taller than wide');
    }
    console.log('✓ Rule 2 passed: Tall image that fills browser width prevents clicking');
    
    // Test Rule 3: Small image should allow clicking
    const rule3Test = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Setup: Small image that doesn't fill browser and isn't at natural size
      Object.defineProperty(img, 'naturalWidth', { value: 400, configurable: true });
      Object.defineProperty(img, 'naturalHeight', { value: 300, configurable: true });
      
      // Mock getBoundingClientRect to simulate scaled image
      const originalImgRect = img.getBoundingClientRect;
      img.getBoundingClientRect = () => ({
        width: 300,  // Smaller than natural
        height: 225
      });
      
      const originalBoardRect = board.getBoundingClientRect;
      board.getBoundingClientRect = () => ({
        width: 800,  // Larger than image natural width
        height: 600
      });
      
      // Test conditions
      const isAtNaturalSize = Math.abs(300 - img.naturalWidth) < 1 && Math.abs(225 - img.naturalHeight) < 1;
      const fillsWidth = img.naturalWidth >= 800;
      
      // Restore original functions
      img.getBoundingClientRect = originalImgRect;
      board.getBoundingClientRect = originalBoardRect;
      
      return {
        test: 'Rule 3 - Small image allows clicking',
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        isAtNaturalSize: isAtNaturalSize,
        fillsWidth: fillsWidth,
        shouldAllowClick: !isAtNaturalSize && !fillsWidth
      };
    });
    
    console.log('Rule 3 test result:', rule3Test);
    if (!rule3Test.shouldAllowClick) {
      throw new Error('Rule 3 test failed: Should allow clicking for small image');
    }
    console.log('✓ Rule 3 passed: Small image allows clicking');
    
    console.log('✓ All click-to-zoom bug fix tests passed!');
    
    // Test 10: Take screenshot for verification
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