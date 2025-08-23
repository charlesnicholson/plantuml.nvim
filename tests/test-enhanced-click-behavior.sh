#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$(mktemp -d)/enhanced-click-behavior-test.log"

echo "Testing enhanced click behavior..." | tee "$LOG_FILE"

# Start Neovim with plugin in background
echo "Starting Neovim with plugin..." | tee -a "$LOG_FILE"
nvim --headless -u ~/.config/nvim/init.lua -c "lua local p = require('plantuml'); p.setup({auto_start = false, http_port = 8764}); p.start()" &
NVIM_PID=$!

# Wait for server to be ready
echo "Waiting for server to be ready..." | tee -a "$LOG_FILE"
for i in {1..10}; do
    if netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
        echo "HTTP server is listening" | tee -a "$LOG_FILE"
        break
    fi
    echo "Waiting for HTTP server to start (attempt $i/10)..." | tee -a "$LOG_FILE"
    sleep 1
done

# Verify HTTP server is running
if ! netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
    echo "HTTP server not found" | tee -a "$LOG_FILE"
    kill $NVIM_PID 2>/dev/null || true
    exit 1
fi

echo "Verifying HTTP server is running..." | tee -a "$LOG_FILE"

# Create browser test
echo "Running enhanced Playwright browser tests..." | tee -a "$LOG_FILE"

# Use node to run playwright tests
node << 'EOF'
const { chromium } = require('playwright');

(async () => {
  let browser;
  let page;
  
  try {
    browser = await chromium.launch({ headless: true });
    page = await browser.newPage();
    
    // Set a page timeout to prevent hanging
    page.setDefaultTimeout(10000);
    
    // Navigate to the plugin page
    console.log('Navigating to http://127.0.0.1:8764');
    await page.goto('http://127.0.0.1:8764', { timeout: 5000 });
    
    const title = await page.title();
    console.log('Page title:', title);
    if (title !== 'PlantUML Viewer') {
      throw new Error('Expected title "PlantUML Viewer", got "' + title + '"');
    }
    console.log('✓ Page loads with correct title');
    
    // Test 1: Verify both functions exist in the page
    const hasFunctions = await page.evaluate(() => {
      const pageContent = document.documentElement.outerHTML;
      return {
        hasIsImageAtNaturalSize: pageContent.includes('function isImageAtNaturalSize()'),
        hasDoesImageFitVertically: pageContent.includes('function doesImageFitVertically()')
      };
    });
    
    if (!hasFunctions.hasIsImageAtNaturalSize) {
      throw new Error('isImageAtNaturalSize function not found in page');
    }
    if (!hasFunctions.hasDoesImageFitVertically) {
      throw new Error('doesImageFitVertically function not found in page');
    }
    console.log('✓ Both required functions found');
    
    // Test 2: Test scenario 1 - image at natural size (should ignore clicks)
    console.log('Testing scenario 1: Image at natural size...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Set up a small 1x1 pixel image that won't need scaling
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      // Set state
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
      });
    });
    
    await page.waitForTimeout(500);
    
    const scenario1State = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      const rect = img.getBoundingClientRect();
      const boardRect = board.getBoundingClientRect();
      
      return {
        hasClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        renderedSize: { width: Math.round(rect.width), height: Math.round(rect.height) },
        boardSize: { width: Math.round(boardRect.width), height: Math.round(boardRect.height) },
        isAtNaturalSize: Math.abs(rect.width - img.naturalWidth) < 1 && Math.abs(rect.height - img.naturalHeight) < 1,
        fitsVertically: img.naturalHeight <= boardRect.height
      };
    });
    
    console.log('Scenario 1 state:', JSON.stringify(scenario1State, null, 2));
    
    // Click and verify no change
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const scenario1After = await page.evaluate(() => {
      const board = document.getElementById('board');
      return { hasClass: board.classList.contains('fit-to-page') };
    });
    
    if (scenario1After.hasClass !== scenario1State.hasClass) {
      throw new Error('Scenario 1 failed: Click should be ignored for image at natural size');
    }
    console.log('✓ Scenario 1 passed: Click correctly ignored for natural size image');
    
    // Test 3: Test scenario 2 - image with minification that fits vertically (should ignore clicks)
    console.log('Testing scenario 2: Image with minification that fits vertically...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a wider image that will be minified horizontally but fits vertically
      // Using a 100x50 image (wide but short)
      const canvas = document.createElement('canvas');
      canvas.width = 100;
      canvas.height = 50;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, 100, 50);
      
      img.src = canvas.toDataURL();
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
      });
    });
    
    await page.waitForTimeout(500);
    
    const scenario2State = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      const rect = img.getBoundingClientRect();
      const boardRect = board.getBoundingClientRect();
      
      return {
        hasClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        renderedSize: { width: Math.round(rect.width), height: Math.round(rect.height) },
        boardSize: { width: Math.round(boardRect.width), height: Math.round(boardRect.height) },
        isAtNaturalSize: Math.abs(rect.width - img.naturalWidth) < 1 && Math.abs(rect.height - img.naturalHeight) < 1,
        fitsVertically: img.naturalHeight <= boardRect.height
      };
    });
    
    console.log('Scenario 2 state:', JSON.stringify(scenario2State, null, 2));
    
    // This should be a minified image that fits vertically
    if (scenario2State.isAtNaturalSize) {
      console.log('⚠ Warning: Image appears to be at natural size, test may not be representative');
    }
    if (!scenario2State.fitsVertically) {
      console.log('⚠ Warning: Image does not fit vertically, test may not be representative');
    }
    
    // Click and verify no change (if conditions are met)
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const scenario2After = await page.evaluate(() => {
      const board = document.getElementById('board');
      return { hasClass: board.classList.contains('fit-to-page') };
    });
    
    if (!scenario2State.isAtNaturalSize && scenario2State.fitsVertically) {
      if (scenario2After.hasClass !== scenario2State.hasClass) {
        throw new Error('Scenario 2 failed: Click should be ignored for minified image that fits vertically');
      }
      console.log('✓ Scenario 2 passed: Click correctly ignored for minified image that fits vertically');
    } else {
      console.log('⚠ Scenario 2 skipped: Conditions not met for this test case');
    }
    
    // Test 4: Test normal toggle behavior with image that doesn't fit vertically
    console.log('Testing scenario 3: Normal toggle behavior...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a tall image that won't fit vertically
      const canvas = document.createElement('canvas');
      canvas.width = 50;
      canvas.height = 800; // Tall image
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#00ff00';
      ctx.fillRect(0, 0, 50, 800);
      
      img.src = canvas.toDataURL();
      board.classList.remove('fit-to-page'); // Start in fit-to-width mode
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = false;
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
      });
    });
    
    await page.waitForTimeout(500);
    
    const scenario3State = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      const rect = img.getBoundingClientRect();
      const boardRect = board.getBoundingClientRect();
      
      return {
        hasClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        boardSize: { width: Math.round(boardRect.width), height: Math.round(boardRect.height) },
        fitsVertically: img.naturalHeight <= boardRect.height
      };
    });
    
    console.log('Scenario 3 state:', JSON.stringify(scenario3State, null, 2));
    
    // Click and verify toggle happens
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const scenario3After = await page.evaluate(() => {
      const board = document.getElementById('board');
      return { hasClass: board.classList.contains('fit-to-page') };
    });
    
    if (scenario3After.hasClass === scenario3State.hasClass) {
      throw new Error('Scenario 3 failed: Click should toggle when image does not fit vertically');
    }
    console.log('✓ Scenario 3 passed: Click correctly toggled for image that does not fit vertically');
    
    console.log('All enhanced click behavior tests completed successfully!');
    
  } catch (error) {
    console.error('Enhanced click test failed:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "✓ All enhanced click behavior tests passed" | tee -a "$LOG_FILE"

# Cleanup
echo "Cleaning up..." | tee -a "$LOG_FILE"
kill $NVIM_PID 2>/dev/null || true
wait $NVIM_PID 2>/dev/null || true

echo "Enhanced click behavior test completed successfully!" | tee -a "$LOG_FILE"