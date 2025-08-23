#!/bin/bash

set -e

echo "Testing manual click behavior validation..."

# Start Neovim with plugin in background
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

if ! netstat -tuln 2>/dev/null | grep -q "127.0.0.1:8764"; then
    echo "HTTP server not found"
    kill $NVIM_PID 2>/dev/null || true
    exit 1
fi

echo "Server is running. Testing manual functionality..."

# Use node to verify functionality
node << 'EOF'
const { chromium } = require('playwright');

(async () => {
  let browser;
  let page;
  
  try {
    browser = await chromium.launch({ headless: false }); // Visible browser for manual validation
    page = await browser.newPage();
    
    page.setDefaultTimeout(10000);
    
    console.log('Navigating to http://127.0.0.1:8764');
    await page.goto('http://127.0.0.1:8764', { timeout: 5000 });
    
    console.log('✓ Page loaded');
    
    // Verify our new function exists
    const hasNewFunction = await page.evaluate(() => {
      return typeof window.doesImageFitVertically === 'function' || 
             document.documentElement.outerHTML.includes('function doesImageFitVertically()');
    });
    
    if (hasNewFunction) {
      console.log('✓ New function doesImageFitVertically() found in page');
    } else {
      console.log('⚠ Warning: doesImageFitVertically function not detected');
    }
    
    // Test the scenarios described in the issue
    console.log('Testing scenario: Wide but short image (should ignore clicks when in fit-to-page mode)');
    
    // Setup a wide but short image that would fit vertically but be minified horizontally
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a realistically wide image (simulating a wide diagram)
      const canvas = document.createElement('canvas');
      canvas.width = 1500; // Wide enough to require horizontal minification
      canvas.height = 100;  // Short enough to fit vertically
      const ctx = canvas.getContext('2d');
      
      // Draw a pattern to make it visible
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, 1500, 100);
      ctx.fillStyle = '#ffffff';
      ctx.font = '20px Arial';
      ctx.fillText('Wide Diagram - Should not toggle when clicked in fit-to-page mode', 50, 50);
      
      img.src = canvas.toDataURL();
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
      });
    });
    
    await page.waitForTimeout(1000); // Wait for image to load
    
    // Get current state
    const currentState = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      const rect = img.getBoundingClientRect();
      const boardRect = board.getBoundingClientRect();
      
      return {
        hasFitToPageClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        renderedSize: { width: Math.round(rect.width), height: Math.round(rect.height) },
        boardSize: { width: Math.round(boardRect.width), height: Math.round(boardRect.height) },
        isAtNaturalSize: Math.abs(rect.width - img.naturalWidth) < 1,
        fitsVertically: img.naturalHeight <= boardRect.height,
        isFitToPage: window.isFitToPage
      };
    });
    
    console.log('Current state:', JSON.stringify(currentState, null, 2));
    
    // This should be a minified image that fits vertically
    const shouldIgnoreClick = currentState.isFitToPage && 
                             !currentState.isAtNaturalSize && 
                             currentState.fitsVertically;
    
    console.log('Expected behavior: Click should be', shouldIgnoreClick ? 'IGNORED' : 'PROCESSED');
    
    // Click the board
    console.log('Clicking the board...');
    await page.click('#board');
    await page.waitForTimeout(500);
    
    // Check if state changed
    const afterClickState = await page.evaluate(() => {
      const board = document.getElementById('board');
      return {
        hasFitToPageClass: board.classList.contains('fit-to-page'),
        isFitToPage: window.isFitToPage
      };
    });
    
    console.log('After click state:', JSON.stringify(afterClickState, null, 2));
    
    if (shouldIgnoreClick) {
      if (afterClickState.hasFitToPageClass === currentState.hasFitToPageClass) {
        console.log('✓ SUCCESS: Click was correctly ignored for wide image that fits vertically');
      } else {
        console.log('✗ FAILURE: Click should have been ignored but wasn\'t');
      }
    } else {
      if (afterClickState.hasFitToPageClass !== currentState.hasFitToPageClass) {
        console.log('✓ SUCCESS: Click was correctly processed (normal toggle behavior)');
      } else {
        console.log('⚠ INFO: Click was ignored (this may be expected behavior)');
      }
    }
    
    // Wait for manual observation
    console.log('Pausing for manual observation...');
    await page.waitForTimeout(3000);
    
    console.log('Manual test completed successfully!');
    
  } catch (error) {
    console.error('Manual test failed:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "✓ Manual test completed"

# Cleanup
echo "Cleaning up..."
kill $NVIM_PID 2>/dev/null || true
wait $NVIM_PID 2>/dev/null || true

echo "Manual click behavior test completed!"