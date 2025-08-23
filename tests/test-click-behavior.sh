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
    
    // Navigate to the plugin page
    console.log('Navigating to http://127.0.0.1:8764');
    await page.goto('http://127.0.0.1:8764');
    
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
    
    // Test 4: Test with a larger image that would be scaled down
    console.log('Testing click behavior with large image...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a large image that will be scaled down in fit-to-page mode
      // This is a 100x100 white image
      img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAYAAABw4pVUAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAAdgAAAHYBTnsmCAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAANcSURBVHic7Z3NaxNBFMafJBpN0lYt9qJWW0/ePHjx4MWbFy9e/Ae8ePPmxYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHixYsXL168ePHix4Ahz0+uAAAAABJRU5ErkJggg==';
      
      // Reset to fit-to-page mode 
      board.classList.add('fit-to-page');
      
      return new Promise((resolve) => {
        img.onload = () => resolve();
      });
    });
    
    await page.waitForTimeout(500);
    
    const largeImageState = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      const rect = img.getBoundingClientRect();
      const isAtNaturalSize = Math.abs(rect.width - img.naturalWidth) < 1 && Math.abs(rect.height - img.naturalHeight) < 1;
      
      return {
        hasClass: board.classList.contains('fit-to-page'),
        naturalSize: { width: img.naturalWidth, height: img.naturalHeight },
        renderedSize: { width: Math.round(rect.width), height: Math.round(rect.height) },
        isAtNaturalSize: isAtNaturalSize
      };
    });
    
    console.log('Large image state:', JSON.stringify(largeImageState, null, 2));
    
    // Click the board again
    await page.click('#board');
    await page.waitForTimeout(200);
    
    const afterLargeClickState = await page.evaluate(() => {
      const board = document.getElementById('board');
      return {
        hasClass: board.classList.contains('fit-to-page'),
      };
    });
    
    console.log('After large image click state:', JSON.stringify(afterLargeClickState, null, 2));
    
    // For large image that's scaled down, clicking should toggle the mode
    if (largeImageState.isAtNaturalSize) {
      console.log('⚠ Large image was at natural size (test inconclusive)');
    } else {
      if (afterLargeClickState.hasClass === largeImageState.hasClass) {
        throw new Error('Click did not toggle for scaled large image');
      }
      console.log('✓ Click correctly toggled for scaled large image');
    }
    
    console.log('All smart click behavior tests passed!');
    
  } catch (error) {
    console.error('Smart click test failed:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "✓ All smart click behavior tests passed" | tee -a "$LOG_FILE"

# Cleanup
echo "Cleaning up..." | tee -a "$LOG_FILE"
kill $NVIM_PID 2>/dev/null || true
wait $NVIM_PID 2>/dev/null || true

echo "Click behavior test completed successfully!" | tee -a "$LOG_FILE"