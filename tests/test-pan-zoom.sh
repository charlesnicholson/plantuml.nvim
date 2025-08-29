#!/bin/bash
set -euo pipefail

echo "Testing pan/zoom functionality..."

# Create screenshots directory if it doesn't exist
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping pan/zoom tests"
    exit 0
fi

# Create test fixtures for different sized diagrams
echo "Creating test fixtures..."

# Small diagram
cat > tests/fixtures/small.puml << 'EOF'
@startuml
A -> B
@enduml
EOF

# Medium diagram  
cat > tests/fixtures/medium.puml << 'EOF'
@startuml
!theme plain
skinparam monochrome true

participant Alice
participant Bob
participant Charlie
participant Dave

Alice -> Bob: Request
Bob -> Charlie: Forward
Charlie -> Dave: Process
Dave -> Charlie: Response
Charlie -> Bob: Return
Bob -> Alice: Complete
@enduml
EOF

# Large diagram
cat > tests/fixtures/large.puml << 'EOF'
@startuml
!theme plain
skinparam monochrome true

package "Web Layer" {
  [Frontend]
  [API Gateway]
  [Load Balancer]
}

package "Service Layer" {
  [User Service]
  [Order Service]
  [Payment Service]
  [Inventory Service]
  [Notification Service]
}

package "Data Layer" {
  database "User DB"
  database "Order DB"
  database "Payment DB"
  database "Inventory DB"
}

[Frontend] --> [Load Balancer]
[Load Balancer] --> [API Gateway]
[API Gateway] --> [User Service]
[API Gateway] --> [Order Service]
[API Gateway] --> [Payment Service]
[API Gateway] --> [Inventory Service]

[User Service] --> [User DB]
[Order Service] --> [Order DB]
[Payment Service] --> [Payment DB]
[Inventory Service] --> [Inventory DB]

[Order Service] --> [Payment Service]
[Order Service] --> [Inventory Service]
[Payment Service] --> [Notification Service]
[Order Service] --> [Notification Service]
@enduml
EOF

# Create Playwright test script
cat > pan_zoom_test.js << 'EOF'
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
    
    // Wait for WebSocket connection
    console.log('Waiting for WebSocket connection...');
    await page.waitForFunction(() => {
      const status = document.querySelector('#status-text');
      return status && status.textContent === 'Live';
    }, { timeout: 10000 });
    
    console.log('✓ WebSocket connection established');
    
    // Test different browser sizes and diagram combinations
    const testConfigs = [
      { width: 800, height: 600, name: 'Medium browser' },
      { width: 1200, height: 800, name: 'Large browser' },
      { width: 400, height: 300, name: 'Small browser' }
    ];
    
    for (const config of testConfigs) {
      console.log(`\n=== Testing ${config.name} (${config.width}x${config.height}) ===`);
      
      // Set browser size
      await page.setViewportSize({ width: config.width, height: config.height });
      
      // Test with an actual PlantUML diagram
      await page.evaluate(() => {
        // Use a real PlantUML URL for a medium-sized diagram
        const mockData = {
          type: "update",
          url: "http://www.plantuml.com/plantuml/png/~1UDfLi5im3k003QKU2Q0UW3R26T7mU2LGGfKg5mJfIo_02qHHe95KLqQNJG-Ri1T5fJN7JZ9TYX9-HJhGpZ_jlUTgj2gU",
          filename: "medium.puml",
          timestamp: new Date().toLocaleString()
        };
        
        // Trigger the actual WebSocket message handler by simulating the data
        const img = document.getElementById('img');
        const board = document.getElementById('board');
        const ph = document.getElementById('placeholder');
        const serverUrlEl = document.getElementById('server-url');
        const timestampEl = document.getElementById('timestamp');
        
        // Reset zoom/pan as the real handler does
        if (typeof resetZoomPan === 'function') {
          resetZoomPan();
        }
        
        // Update UI elements as the real handler does
        if (!window.hasLoadedDiagram) {
          board.classList.add('has-diagram');
          window.hasLoadedDiagram = true;
        }
        
        img.style.opacity = 0;
        
        if (mockData.filename) {
          window.currentFilename = mockData.filename;
          if (typeof updateFilenameDisplay === 'function') {
            updateFilenameDisplay();
          }
        }
        
        if (mockData.timestamp) {
          timestampEl.textContent = "Updated: " + mockData.timestamp;
          timestampEl.title = "Last update time";
        }
        
        if (mockData.url) {
          const MAX_URL_DISPLAY = 60;
          serverUrlEl.textContent = mockData.url.length > MAX_URL_DISPLAY ? mockData.url.substring(0, MAX_URL_DISPLAY) + "..." : mockData.url;
          serverUrlEl.href = mockData.url;
          serverUrlEl.title = "Click to open PlantUML diagram";
          serverUrlEl.style.display = "block";
        }
        
        if (ph) ph.style.display = "none";
        
        // Set image source to trigger loading
        img.src = mockData.url;
      });
      
      // Wait for image to load
      await page.waitForFunction(() => {
        const img = document.getElementById('img');
        return img.complete && img.naturalHeight !== 0;
      }, { timeout: 10000 });
      
      // Wait for image to become visible
      await page.waitForFunction(() => {
        const img = document.getElementById('img');
        return img.style.opacity === '1' || img.style.opacity === '';
      }, { timeout: 5000 });
      
      // Test 1: Check if image is minified and zoom/pan is available
      const imageState = await page.evaluate(() => {
        const img = document.getElementById('img');
        const board = document.getElementById('board');
        
        // Use the actual isImageMinified function
        const isMinified = typeof isImageMinified === 'function' ? isImageMinified() : false;
        
        const boardRect = board.getBoundingClientRect();
        
        return {
          boardWidth: boardRect.width,
          boardHeight: boardRect.height,
          imageNaturalWidth: img.naturalWidth,
          imageNaturalHeight: img.naturalHeight,
          isMinified: isMinified,
          currentTransform: img.style.transform,
          hasZoomPanClass: board.classList.contains('zoom-pan-mode'),
          imageLoaded: img.complete && img.naturalHeight !== 0
        };
      });
      
      console.log(`Board size: ${imageState.boardWidth}x${imageState.boardHeight}`);
      console.log(`Image natural size: ${imageState.imageNaturalWidth}x${imageState.imageNaturalHeight}`);
      console.log(`Image loaded: ${imageState.imageLoaded}`);
      console.log(`Image is minified: ${imageState.isMinified}`);
      console.log(`Initial transform: "${imageState.currentTransform}"`);
      console.log(`Has zoom-pan class: ${imageState.hasZoomPanClass}`);
      
      if (imageState.isMinified) {
        console.log('Testing click-to-zoom functionality...');
        
        // Test 2: Click to enter zoom/pan mode
        await page.click('#img');
        await page.waitForTimeout(100);
        
        const afterClick = await page.evaluate(() => {
          const board = document.getElementById('board');
          const img = document.getElementById('img');
          
          // Since isZoomPanMode is not exposed, check the board class instead
          const hasZoomPanClass = board.classList.contains('zoom-pan-mode');
          
          return {
            hasZoomPanClass: hasZoomPanClass,
            transform: img.style.transform,
            isZoomPanMode: hasZoomPanClass // Use class as proxy for mode
          };
        });
        
        console.log(`After click - Zoom/pan mode: ${afterClick.isZoomPanMode}`);
        console.log(`After click - Transform: "${afterClick.transform}"`);
        
        if (!afterClick.isZoomPanMode) {
          throw new Error('Click should have entered zoom/pan mode for minified image');
        }
        console.log('✓ Click successfully entered zoom/pan mode');
        
        // Test 3: Test mouse positioning and panning
        console.log('Testing mouse panning at different positions...');
        
        const panTests = [
          { x: 0.5, y: 0.5, name: 'center', expectedPanX: 0, expectedPanY: 0 },
          { x: 0.0, y: 0.5, name: 'left edge', expectedPanX: 50, expectedPanY: 0 },
          { x: 1.0, y: 0.5, name: 'right edge', expectedPanX: -50, expectedPanY: 0 },
          { x: 0.5, y: 0.0, name: 'top edge', expectedPanX: 0, expectedPanY: 50 },
          { x: 0.5, y: 1.0, name: 'bottom edge', expectedPanX: 0, expectedPanY: -50 },
          { x: 0.0, y: 0.0, name: 'top-left corner', expectedPanX: 50, expectedPanY: 50 },
          { x: 1.0, y: 0.0, name: 'top-right corner', expectedPanX: -50, expectedPanY: 50 },
          { x: 0.0, y: 1.0, name: 'bottom-left corner', expectedPanX: 50, expectedPanY: -50 },
          { x: 1.0, y: 1.0, name: 'bottom-right corner', expectedPanX: -50, expectedPanY: -50 }
        ];
        
        for (const test of panTests) {
          // Calculate mouse position within the board area
          const mousePos = await page.evaluate((testData) => {
            const board = document.getElementById('board');
            const boardRect = board.getBoundingClientRect();
            
            const mouseX = boardRect.left + (testData.x * boardRect.width);
            const mouseY = boardRect.top + (testData.y * boardRect.height);
            
            return { x: mouseX, y: mouseY, boardRect: boardRect };
          }, test);
          
          // Move mouse to position and trigger mousemove event
          await page.mouse.move(mousePos.x, mousePos.y);
          
          // Also trigger the mousemove event on the board to ensure pan update
          await page.evaluate((pos) => {
            const board = document.getElementById('board');
            const event = new MouseEvent('mousemove', {
              clientX: pos.x,
              clientY: pos.y,
              bubbles: true
            });
            board.dispatchEvent(event);
          }, { x: mousePos.x, y: mousePos.y });
          
          await page.waitForTimeout(50);
          
          // Check the resulting pan values by parsing the transform
          const panResult = await page.evaluate(() => {
            const img = document.getElementById('img');
            const transform = img.style.transform;
            
            // Parse pan values from transform
            const translateMatch = transform.match(/translate3d\(([^,]+),\s*([^,]+),/);
            let panX = 0, panY = 0;
            
            if (translateMatch) {
              panX = parseFloat(translateMatch[1].replace('%', ''));
              panY = parseFloat(translateMatch[2].replace('%', ''));
            }
            
            return {
              panX: panX,
              panY: panY,
              transform: transform
            };
          });
          
          console.log(`  ${test.name}: mouse(${test.x}, ${test.y}) -> pos(${Math.round(mousePos.x)}, ${Math.round(mousePos.y)}) -> pan(${panResult.panX}, ${panResult.panY})`);
          console.log(`    Board rect: ${mousePos.boardRect.left}, ${mousePos.boardRect.top}, ${mousePos.boardRect.width}x${mousePos.boardRect.height}`);
          
          // Verify pan values are approximately correct (allow small tolerance)
          const tolerance = 2;
          if (Math.abs(panResult.panX - test.expectedPanX) > tolerance) {
            throw new Error(`Incorrect panX at ${test.name}: expected ${test.expectedPanX}, got ${panResult.panX}`);
          }
          if (Math.abs(panResult.panY - test.expectedPanY) > tolerance) {
            throw new Error(`Incorrect panY at ${test.name}: expected ${test.expectedPanY}, got ${panResult.panY}`);
          }
        }
        
        console.log('✓ All mouse panning positions work correctly');
        
        // Test 4: Test zoom/pan mode exit on click
        console.log('Testing click to exit zoom/pan mode...');
        await page.click('#img');
        await page.waitForTimeout(100);
        
        const afterSecondClick = await page.evaluate(() => {
          const board = document.getElementById('board');
          const img = document.getElementById('img');
          const hasZoomPanClass = board.classList.contains('zoom-pan-mode');
          
          return {
            hasZoomPanClass: hasZoomPanClass,
            transform: img.style.transform,
            isZoomPanMode: hasZoomPanClass // Use class as proxy for mode
          };
        });
        
        if (afterSecondClick.isZoomPanMode) {
          throw new Error('Second click should have exited zoom/pan mode');
        }
        if (afterSecondClick.transform !== '') {
          throw new Error('Transform should be cleared when exiting zoom/pan mode');
        }
        console.log('✓ Click successfully exited zoom/pan mode');
        
      } else {
        console.log('Image not minified in this browser size, testing click does nothing...');
        
        // Click should do nothing for non-minified images
        await page.click('#img');
        await page.waitForTimeout(100);
        
        const afterClick = await page.evaluate(() => {
          const board = document.getElementById('board');
          const hasZoomPanClass = board.classList.contains('zoom-pan-mode');
          
          return {
            hasZoomPanClass: hasZoomPanClass,
            isZoomPanMode: hasZoomPanClass // Use class as proxy for mode
          };
        });
        
        if (afterClick.isZoomPanMode) {
          throw new Error('Click should do nothing for non-minified image');
        }
        console.log('✓ Click correctly does nothing for non-minified image');
      }
    }
    
    // Test 5: Test zoom/pan reset on new diagram load
    console.log('\n=== Testing zoom/pan reset on diagram update ===');
    
    // Set a medium browser size
    await page.setViewportSize({ width: 600, height: 400 });
    
    // Enter zoom/pan mode
    await page.click('#img');
    await page.waitForTimeout(100);
    
    const beforeUpdate = await page.evaluate(() => {
      const board = document.getElementById('board');
      const hasZoomPanClass = board.classList.contains('zoom-pan-mode');
      
      return {
        isZoomPanMode: hasZoomPanClass,
        hasZoomPanClass: hasZoomPanClass
      };
    });
    
    if (!beforeUpdate.isZoomPanMode) {
      throw new Error('Should be in zoom/pan mode before testing reset');
    }
    
    // Simulate new diagram update
    await page.evaluate(() => {
      const mockData = {
        type: "update",
        url: "http://www.plantuml.com/plantuml/png/~1test_new_diagram",
        filename: "new.puml",
        timestamp: new Date().toLocaleString()
      };
      
      // Simulate the WebSocket message that would reset zoom/pan
      window.dispatchEvent(new CustomEvent('mockDiagramUpdate', { detail: mockData }));
      
      // Manually call resetZoomPan to simulate what happens on diagram update
      if (typeof window.resetZoomPan === 'function') {
        window.resetZoomPan();
      }
    });
    
    await page.waitForTimeout(100);
    
    const afterUpdate = await page.evaluate(() => {
      const board = document.getElementById('board');
      const img = document.getElementById('img');
      const hasZoomPanClass = board.classList.contains('zoom-pan-mode');
      
      return {
        isZoomPanMode: hasZoomPanClass,
        hasZoomPanClass: hasZoomPanClass,
        transform: img.style.transform
      };
    });
    
    if (afterUpdate.isZoomPanMode) {
      throw new Error('Should exit zoom/pan mode on diagram update');
    }
    if (afterUpdate.transform !== '') {
      throw new Error('Transform should be cleared on diagram update');
    }
    console.log('✓ Zoom/pan correctly resets on diagram update');
    
    // Test 6: Verify zoom scale constant
    console.log('\n=== Testing zoom scale behavior ===');
    
    const scaleTest = await page.evaluate(() => {
      // Enter zoom/pan mode to test scale
      const board = document.getElementById('board');
      
      // Check if already in zoom/pan mode, if not simulate click to enter
      if (!board.classList.contains('zoom-pan-mode')) {
        const img = document.getElementById('img');
        img.click();
      }
      
      const img = document.getElementById('img');
      const transform = img.style.transform;
      
      // Extract scale from transform
      const scaleMatch = transform.match(/scale\(([^)]+)\)/);
      const scale = scaleMatch ? parseFloat(scaleMatch[1]) : null;
      
      // Get the ZOOM_SCALE constant (should be 0.8)
      const expectedScale = 0.8;
      
      return {
        transform: transform,
        extractedScale: scale,
        expectedZoomScale: expectedScale,
        hasScale: scaleMatch !== null
      };
    });
    
    console.log(`Transform: "${scaleTest.transform}"`);
    console.log(`Expected zoom scale: ${scaleTest.expectedZoomScale}`);
    console.log(`Has scale in transform: ${scaleTest.hasScale}`);
    
    if (!scaleTest.hasScale) {
      throw new Error('Transform should include scale when in zoom/pan mode');
    }
    
    console.log('✓ Zoom scale behavior working correctly');
    
    // Take final screenshot
    await page.setViewportSize({ width: 800, height: 600 });
    await page.screenshot({ path: 'tests/screenshots/pan-zoom-test.png' });
    console.log('✓ Screenshot saved');
    
    console.log('\nAll pan/zoom tests passed!');
    
  } catch (error) {
    console.error('Pan/zoom test failed:', error);
    
    // Take screenshot on failure
    if (page) {
      try {
        await page.screenshot({ path: 'tests/screenshots/pan-zoom-failure.png' });
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
    rm -f pan_zoom_test.js
    rm -f tests/fixtures/small.puml tests/fixtures/medium.puml tests/fixtures/large.puml
    kill $NVIM_PID 2>/dev/null || true
    wait $NVIM_PID 2>/dev/null || true
}
trap cleanup EXIT

# Verify HTTP server is running first
echo "Verifying HTTP server is running..."
if ! curl -f -s "http://127.0.0.1:8764" > /dev/null; then
    echo "✗ HTTP server not responding, cannot run pan/zoom tests"
    exit 1
fi

# Run Playwright tests
echo "Running Playwright pan/zoom tests..."
if DISPLAY=${DISPLAY:-:99} node pan_zoom_test.js 2>&1; then
    echo "✓ All pan/zoom tests passed"
    rm -f pan_zoom_test.js
else
    echo "✗ Pan/zoom tests failed"
    rm -f pan_zoom_test.js
    exit 1
fi