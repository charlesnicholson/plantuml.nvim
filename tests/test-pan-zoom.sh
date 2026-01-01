#!/bin/bash
set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-utils.sh"

echo "Testing pan/zoom functionality..."

# Setup isolated test environment
setup_test_env

# Create screenshots directory
mkdir -p tests/screenshots

# Check if Playwright is available
if ! command -v npx &> /dev/null || ! npx playwright --version &> /dev/null; then
    echo "⚠ Playwright not available, skipping pan/zoom tests"
    exit 0
fi

# Create test fixtures for different sized diagrams
echo "Creating test fixtures..."
mkdir -p tests/fixtures

cat > tests/fixtures/small.puml << 'EOF'
@startuml
A -> B
@enduml
EOF

cat > tests/fixtures/medium.puml << 'EOF'
@startuml
!theme plain
skinparam monochrome true
participant Alice
participant Bob
Alice -> Bob: Request
Bob -> Alice: Response
@enduml
EOF

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
if ! curl -f -s "http://127.0.0.1:$TEST_HTTP_PORT" > /dev/null; then
    echo "✗ HTTP server not responding, cannot run pan/zoom tests"
    exit 1
fi

# Create Playwright test script
cat > "$TEST_TMP_DIR/pan_zoom_test.js" << 'ENDOFJS'
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

    console.log(`Navigating to http://127.0.0.1:${TEST_PORT}`);
    await page.goto(`http://127.0.0.1:${TEST_PORT}`, { waitUntil: 'networkidle' });

    // Wait for WebSocket connection
    await page.waitForFunction(() => {
      const status = document.querySelector('#status-text');
      return status && status.textContent !== 'Connecting...';
    }, { timeout: 10000 });

    console.log('✓ WebSocket connection established');

    // Test with medium browser size
    console.log('\n=== Testing Medium browser (800x600) ===');
    await page.setViewportSize({ width: 800, height: 600 });

    // Load a mock diagram
    await page.evaluate(() => {
      const mockData = {
        type: "update",
        url: "http://www.plantuml.com/plantuml/png/~1UDfLi5im3k003QKU2Q0UW3R26T7mU2LGGfKg5mJfIo_02qHHe95KLqQNJG-Ri1T5fJN7JZ9TYX9-HJhGpZ_jlUTgj2gU",
        filename: "medium.puml",
        timestamp: new Date().toLocaleString()
      };

      const img = document.getElementById('img');
      const board = document.getElementById('board');
      const ph = document.getElementById('ph');
      const serverUrlEl = document.getElementById('server-url');
      const timestampEl = document.getElementById('timestamp');

      if (typeof resetZoomPan === 'function') {
        resetZoomPan();
      }

      board.classList.add('has-diagram');
      img.style.opacity = 0;

      window.currentFilename = mockData.filename;
      if (typeof updateFilenameDisplay === 'function') {
        updateFilenameDisplay();
      }

      timestampEl.textContent = "Updated: " + mockData.timestamp;
      serverUrlEl.textContent = mockData.url.substring(0, 60) + "...";
      serverUrlEl.href = mockData.url;
      serverUrlEl.style.display = "block";

      if (ph) ph.style.display = "none";
      img.src = mockData.url;
    });

    // Wait for image to fully load using proper predicate
    await page.waitForFunction(() => {
      const img = document.getElementById('img');
      return img.complete && img.naturalHeight > 0 && img.style.opacity === '1';
    }, { timeout: 15000 });

    console.log('✓ Image loaded');

    // Get image state
    const imageState = await page.evaluate(() => {
      const img = document.getElementById('img');
      const board = document.getElementById('board');
      const isMinified = typeof isImageMinified === 'function' ? isImageMinified() : false;

      return {
        imageNaturalWidth: img.naturalWidth,
        imageNaturalHeight: img.naturalHeight,
        isMinified: isMinified,
        hasZoomPanClass: board.classList.contains('zoom-pan-mode')
      };
    });

    console.log(`Image size: ${imageState.imageNaturalWidth}x${imageState.imageNaturalHeight}`);
    console.log(`Is minified: ${imageState.isMinified}`);

    if (imageState.isMinified) {
      console.log('Testing click-to-zoom functionality...');

      // Click to enter zoom/pan mode
      await page.click('#img');

      // Wait for zoom mode to be active
      await page.waitForFunction(() => {
        const board = document.getElementById('board');
        return board.classList.contains('zoom-pan-mode');
      }, { timeout: 5000 });

      console.log('✓ Entered zoom/pan mode');

      // Test mouse panning
      console.log('Testing mouse panning...');

      // Get image dimensions for calculating expected translations
      const imageDims = await page.evaluate(() => {
        const img = document.getElementById('img');
        const board = document.getElementById('board');
        const boardRect = board.getBoundingClientRect();
        const ZOOM_SCALE = 0.8;
        const zoomedWidth = img.naturalWidth * ZOOM_SCALE;
        const zoomedHeight = img.naturalHeight * ZOOM_SCALE;
        const excessWidth = Math.max(0, zoomedWidth - boardRect.width);
        const excessHeight = Math.max(0, zoomedHeight - boardRect.height);
        return { excessWidth, excessHeight };
      });

      // Pan tests: mouse position -> expected translation
      // panX: 0 = left edge, 0.5 = center, 1 = right edge
      // translateX = excessWidth * (0.5 - panX)
      const panTests = [
        { x: 0.5, y: 0.5, name: 'center' },   // translateX = 0
        { x: 0.0, y: 0.5, name: 'left edge' }, // translateX = excessWidth * 0.5 (positive, shows left)
        { x: 1.0, y: 0.5, name: 'right edge' } // translateX = excessWidth * -0.5 (negative, shows right)
      ];

      for (const test of panTests) {
        const mousePos = await page.evaluate((testData) => {
          const board = document.getElementById('board');
          const rect = board.getBoundingClientRect();
          return {
            x: rect.left + (testData.x * rect.width),
            y: rect.top + (testData.y * rect.height)
          };
        }, test);

        await page.mouse.move(mousePos.x, mousePos.y);

        // Dispatch mousemove event and wait for transform to update
        await page.evaluate((pos) => {
          const board = document.getElementById('board');
          board.dispatchEvent(new MouseEvent('mousemove', {
            clientX: pos.x,
            clientY: pos.y,
            bubbles: true
          }));
        }, mousePos);

        // Wait for transform to be applied (now uses translate instead of translate3d)
        await page.waitForFunction(() => {
          const img = document.getElementById('img');
          return img.style.transform && img.style.transform.includes('translate(');
        }, { timeout: 2000 });

        // Extract translate values (format: translate(Xpx, Ypx) scale(S))
        const panResult = await page.evaluate(() => {
          const img = document.getElementById('img');
          const match = img.style.transform.match(/translate\(([^,]+)px,\s*([^)]+)px\)/);
          return {
            translateX: match ? parseFloat(match[1]) : 0,
            translateY: match ? parseFloat(match[2]) : 0
          };
        });

        // Calculate expected translation based on new formula
        const expectedTranslateX = imageDims.excessWidth * (0.5 - test.x);
        const tolerance = 2;

        if (Math.abs(panResult.translateX - expectedTranslateX) > tolerance) {
          throw new Error(`Incorrect translateX at ${test.name}: expected ${expectedTranslateX.toFixed(1)}, got ${panResult.translateX}`);
        }
        console.log(`  ✓ ${test.name}: translate(${panResult.translateX.toFixed(1)}px, ${panResult.translateY.toFixed(1)}px)`);
      }

      console.log('✓ Mouse panning works correctly');

      // Click to exit zoom mode
      await page.click('#img');

      // Wait for zoom mode to be deactivated
      await page.waitForFunction(() => {
        const board = document.getElementById('board');
        return !board.classList.contains('zoom-pan-mode');
      }, { timeout: 5000 });

      console.log('✓ Exited zoom/pan mode');

    } else {
      console.log('Image not minified, verifying click does nothing...');

      await page.click('#img');

      // Verify we're NOT in zoom mode after a brief moment
      const afterClick = await page.evaluate(() => {
        return document.getElementById('board').classList.contains('zoom-pan-mode');
      });

      if (afterClick) {
        throw new Error('Click should do nothing for non-minified image');
      }
      console.log('✓ Click correctly does nothing for non-minified image');
    }

    // Take screenshot
    await page.screenshot({ path: 'tests/screenshots/pan-zoom-test.png' });
    console.log('✓ Screenshot saved');

    console.log('\nAll pan/zoom tests passed!');

  } catch (error) {
    console.error('Pan/zoom test failed:', error);
    if (page) {
      try {
        await page.screenshot({ path: 'tests/screenshots/pan-zoom-failure.png' });
      } catch (e) {}
    }
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
ENDOFJS

# Run Playwright tests
echo "Running Playwright pan/zoom tests..."
if TEST_HTTP_PORT="$TEST_HTTP_PORT" NODE_PATH="$PLUGIN_DIR/node_modules" DISPLAY=${DISPLAY:-:99} node "$TEST_TMP_DIR/pan_zoom_test.js" 2>&1; then
    echo "✓ All pan/zoom tests passed"
else
    echo "✗ Pan/zoom tests failed"
    exit 1
fi
