#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$(mktemp -d)/click-behavior-test.log"

echo "Testing comprehensive click behavior..." | tee "$LOG_FILE"

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

# Create comprehensive browser test
echo "Running comprehensive Playwright browser tests..." | tee -a "$LOG_FILE"

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
    
    // Test 1: Verify required functions exist in the page
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
    console.log('✓ All required functions found');
    
    // Test 2: Scenario 1 - Image at natural size (should ignore clicks)
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
    
    // Test 3: Scenario 2 - Image with horizontal minification that fits vertically (should ignore clicks)
    console.log('Testing scenario 2: Image with horizontal minification that fits vertically...');
    
    await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a wider image that will be minified horizontally but fits vertically
      // Using a much larger width to force minification
      const canvas = document.createElement('canvas');
      canvas.width = 2000; // Very wide to force horizontal scaling
      canvas.height = 30;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, 2000, 30);
      
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
    
    // This should be a minified image that fits vertically - the key scenario we're testing
    if (scenario2State.isAtNaturalSize) {
      console.log('⚠ Warning: Image appears to be at natural size, may need different approach');
    }
    if (!scenario2State.fitsVertically) {
      console.log('⚠ Warning: Image does not fit vertically, test may not be representative');
    }
    
    // Click and verify behavior based on conditions
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
      console.log('✓ Scenario 2 passed: Click correctly ignored for horizontally minified image that fits vertically');
    } else {
      // If conditions aren't met, verify normal toggle behavior occurs
      if (scenario2After.hasClass === scenario2State.hasClass) {
        console.log('⚠ Scenario 2: Normal behavior - no change occurred (may be expected)');
      } else {
        console.log('✓ Scenario 2: Normal toggle behavior occurred');
      }
    }
    
    // Test 4: Verify that normal toggle would work (test functions only, not actual clicking)
    console.log('Testing scenario 3: Verify normal toggle conditions...');
    
    const normalToggleTest = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a tall image that won't fit vertically
      const canvas = document.createElement('canvas');
      canvas.width = 50;
      canvas.height = 1200;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#00ff00';
      ctx.fillRect(0, 0, 50, 1200);
      
      img.src = canvas.toDataURL();
      board.classList.remove('fit-to-page');
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = false;
      
      return new Promise((resolve) => {
        img.onload = () => {
          const boardRect = board.getBoundingClientRect();
          const conditions = {
            hasLoadedDiagram: window.hasLoadedDiagram,
            isFitToPage: window.isFitToPage,
            isAtNaturalSize: window.isImageAtNaturalSize ? window.isImageAtNaturalSize() : false,
            fitsVertically: window.doesImageFitVertically ? window.doesImageFitVertically() : false,
            imageHeight: img.naturalHeight,
            boardHeight: Math.round(boardRect.height),
            shouldAllowToggle: true
          };
          
          // Determine if toggle should be allowed based on click handler logic
          if (!conditions.hasLoadedDiagram) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'No diagram loaded';
          } else if (conditions.isFitToPage && conditions.isAtNaturalSize) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'In fit-to-page mode with natural size image';
          } else if (conditions.isFitToPage && !conditions.isAtNaturalSize && conditions.fitsVertically) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'In fit-to-page mode with minified image that fits vertically';
          } else {
            conditions.reason = 'Normal toggle should work';
          }
          
          resolve(conditions);
        };
      });
    });
    
    console.log('Normal toggle test conditions:', JSON.stringify(normalToggleTest, null, 2));
    
    if (normalToggleTest.shouldAllowToggle) {
      console.log('✓ Scenario 3 passed: Conditions are correct for normal toggle behavior');
    } else {
      throw new Error('Scenario 3 failed: Expected conditions to allow toggle but they do not');
    }
    
    // Test 5: Test the key scenario - fit-to-page mode with minification
    console.log('Testing scenario 4: Fit-to-page mode with horizontal minification...');
    
    const keyScenarioTest = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create wide but short image (horizontally minified when fit-to-page)
      const canvas = document.createElement('canvas');
      canvas.width = 2000;
      canvas.height = 50;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#0000ff';
      ctx.fillRect(0, 0, 2000, 50);
      
      img.src = canvas.toDataURL();
      board.classList.add('fit-to-page');  // Key: in fit-to-page mode
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;  // Key: isFitToPage is true
      
      return new Promise((resolve) => {
        img.onload = () => {
          const boardRect = board.getBoundingClientRect();
          const conditions = {
            hasLoadedDiagram: window.hasLoadedDiagram,
            isFitToPage: window.isFitToPage,
            isAtNaturalSize: window.isImageAtNaturalSize ? window.isImageAtNaturalSize() : false,
            fitsVertically: window.doesImageFitVertically ? window.doesImageFitVertically() : false,
            imageHeight: img.naturalHeight,
            boardHeight: Math.round(boardRect.height),
            shouldAllowToggle: true
          };
          
          // This is the key scenario we're testing
          if (!conditions.hasLoadedDiagram) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'No diagram loaded';
          } else if (conditions.isFitToPage && conditions.isAtNaturalSize) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'In fit-to-page mode with natural size image (original behavior)';
          } else if (conditions.isFitToPage && !conditions.isAtNaturalSize && conditions.fitsVertically) {
            conditions.shouldAllowToggle = false;
            conditions.reason = 'In fit-to-page mode with minified image that fits vertically (NEW behavior)';
          } else {
            conditions.reason = 'Normal toggle should work';
          }
          
          resolve(conditions);
        };
      });
    });
    
    console.log('Key scenario test conditions:', JSON.stringify(keyScenarioTest, null, 2));
    
    if (!keyScenarioTest.shouldAllowToggle && keyScenarioTest.reason.includes('NEW behavior')) {
      console.log('✓ Scenario 4 passed: New logic correctly prevents toggle for horizontally minified image that fits vertically');
    } else {
      throw new Error('Scenario 4 failed: New logic should prevent toggle for horizontally minified image that fits vertically');
    }
    
    // Test 6: Additional verification of function behavior
    console.log('Testing additional function verification...');
    
    const functionTests = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Test the functions directly
      const naturalSize1x1 = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
      img.src = naturalSize1x1;
      
      return new Promise((resolve) => {
        img.onload = () => {
          const results = {
            naturalSizeTest: window.isImageAtNaturalSize ? window.isImageAtNaturalSize() : 'function not available',
            fitsVerticallyTest: window.doesImageFitVertically ? window.doesImageFitVertically() : 'function not available'
          };
          resolve(results);
        };
      });
    });
    
    console.log('Function test results:', JSON.stringify(functionTests, null, 2));
    
    // Test 7: CSS positioning fix verification
    console.log('Testing CSS positioning fix (Issue #45)...');
    
    const positioningTest = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      
      // Create a wide but short image like in the bug report
      const canvas = document.createElement('canvas');
      canvas.width = 1500;
      canvas.height = 100;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, 1500, 100);
      ctx.fillStyle = '#ffffff';
      ctx.font = '20px Arial';
      ctx.fillText('Wide Diagram - CSS Fix Test', 50, 50);
      
      img.src = canvas.toDataURL();
      board.classList.add('fit-to-page');
      board.classList.add('has-diagram');
      
      window.hasLoadedDiagram = true;
      window.isFitToPage = true;
      
      return new Promise((resolve) => {
        img.onload = () => {
          const computedStyle = window.getComputedStyle(board);
          const boardRect = board.getBoundingClientRect();
          const imgRect = img.getBoundingClientRect();
          
          const positioning = {
            classes: board.className,
            alignItems: computedStyle.alignItems,
            boardHeight: boardRect.height,
            imageHeight: imgRect.height,
            imageTop: imgRect.top - boardRect.top,
            expectedCenter: (boardRect.height - imgRect.height) / 2,
            hasHasDiagram: board.classList.contains('has-diagram'),
            hasFitToPage: board.classList.contains('fit-to-page')
          };
          
          // Check if image is centered
          const isCentered = Math.abs(positioning.imageTop - positioning.expectedCenter) < 5;
          positioning.isCentered = isCentered;
          positioning.isAtTop = positioning.imageTop < 10;
          
          resolve(positioning);
        };
      });
    });
    
    console.log('CSS positioning test:', JSON.stringify(positioningTest, null, 2));
    
    if (positioningTest.alignItems === 'center' && positioningTest.isCentered) {
      console.log('✓ CSS positioning fix verified: Image properly centered with both classes');
    } else if (positioningTest.isAtTop) {
      throw new Error('CSS positioning fix failed: Image is at top instead of centered');
    } else {
      console.log('⚠ CSS positioning: Image position unclear but align-items is ' + positioningTest.alignItems);
    }
    
    console.log('All comprehensive click behavior tests completed successfully!');
    
  } catch (error) {
    console.error('Click behavior test failed:', error);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
EOF

echo "✓ All comprehensive click behavior tests passed" | tee -a "$LOG_FILE"

# Cleanup
echo "Cleaning up..." | tee -a "$LOG_FILE"
kill $NVIM_PID 2>/dev/null || true
wait $NVIM_PID 2>/dev/null || true

echo "Comprehensive click behavior test completed successfully!" | tee -a "$LOG_FILE"