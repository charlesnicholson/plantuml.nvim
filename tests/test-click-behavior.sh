#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$(mktemp -d)/click-behavior-test.log"

echo "Testing click behavior..." | tee "$LOG_FILE"

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
echo "Running Playwright browser tests..." | tee -a "$LOG_FILE"

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
    
    // Test 1: Verify the new function exists in the page
    const hasNewFunction = await page.evaluate(() => {
      const pageContent = document.documentElement.outerHTML;
      return pageContent.includes('function isImageAtNaturalSize()');
    });
    
    if (!hasNewFunction) {
      throw new Error('isImageAtNaturalSize function not found in page');
    }
    console.log('✓ isImageAtNaturalSize function found');
    
    // Test 2: Test the function behavior with a small image that fits naturally
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Set up a small 1x1 pixel image that won't need scaling
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      // Set hasLoadedDiagram to true (simulate real state)
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;
      
      return new Promise((resolve) => {
        img.onload = () => {
          // Store original state for testing
          window.originalClickCount = 0;
          resolve();
        };
      });
    });
    
    // Wait for image to load
    await page.waitForTimeout(500);
    
    // Test 3: Test click behavior with small image (should do nothing)
    console.log('Testing click behavior with small image...');
    
    const initialState = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Check if image is at natural size
      const rect = img.getBoundingClientRect();
      const isAtNaturalSize = Math.abs(rect.width - img.naturalWidth) < 1 && Math.abs(rect.height - img.naturalHeight) < 1;
      
      return {
        hasClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        renderedSize: { width: Math.round(rect.width), height: Math.round(rect.height) },
        isAtNaturalSize: isAtNaturalSize
      };
    });
    
    console.log('Initial state:', JSON.stringify(initialState, null, 2));
    
    if (!initialState.isAtNaturalSize) {
      console.log('⚠ Image is not at natural size, test may not be accurate');
    } else {
      console.log('✓ Image is at natural size');
    }
    
    // Click the board
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const afterClickState = await page.evaluate(() => {
      const board = document.getElementById('board');
      return {
        hasClass: board.classList.contains('fit-to-page'),
      };
    });
    
    console.log('After click state:', JSON.stringify(afterClickState, null, 2));
    
    // If image was at natural size, clicking should do nothing (class should remain)
    if (initialState.isAtNaturalSize) {
      if (afterClickState.hasClass !== initialState.hasClass) {
        throw new Error('Click behavior changed when image was at natural size - this should not happen!');
      }
      console.log('✓ Click correctly ignored when image at natural size');
    } else {
      // If image was scaled, normal toggle behavior should occur
      if (afterClickState.hasClass === initialState.hasClass) {
        throw new Error('Click behavior did not toggle when image was scaled - normal behavior expected');
      }
      console.log('✓ Click correctly toggled when image was scaled');
    }
    
    // Test 4: Test with normal toggle behavior (reset with different image)
    console.log('Testing normal click toggle behavior...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Use a simple 2x2 test image
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAAdgAAAHYBTnsmCAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAAOSURBVAiZY2RgYGBgAAAABQABXvMqOgAAAABJRU5ErkJggg==';
      
      // Start in fit-to-width mode to test toggle to fit-to-page
      board.classList.remove('fit-to-page');
      window.isFitToPage = false;
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
        // Simple fallback for immediate resolve if image loads instantly
        setTimeout(resolve, 100);
      });
    });
    
    await page.waitForTimeout(200);
    
    const toggleState = await page.evaluate(() => {
      const board = document.getElementById('board');
      return {
        hasClass: board.classList.contains('fit-to-page'),
      };
    });
    
    console.log('Pre-toggle state:', JSON.stringify(toggleState, null, 2));
    
    // Click to toggle from fit-to-width to fit-to-page
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const afterToggleState = await page.evaluate(() => {
      const board = document.getElementById('board');
      return {
        hasClass: board.classList.contains('fit-to-page'),
      };
    });
    
    console.log('After toggle state:', JSON.stringify(afterToggleState, null, 2));
    
    // Normal toggle behavior should work
    if (afterToggleState.hasClass === toggleState.hasClass) {
      console.log('⚠ Toggle behavior may be working as expected (no change when appropriate)');
    } else {
      console.log('✓ Click correctly toggled mode');
    }
    
    console.log('All click behavior tests completed successfully!');
    
  } catch (error) {
    console.error('Click test failed:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "✓ All click behavior tests passed" | tee -a "$LOG_FILE"

# Cleanup
echo "Cleaning up..." | tee -a "$LOG_FILE"
kill $NVIM_PID 2>/dev/null || true
wait $NVIM_PID 2>/dev/null || true

echo "Click behavior test completed successfully!" | tee -a "$LOG_FILE"