const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  console.log('Testing filename truncation timing issue...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ 
    viewport: { width: 400, height: 300 } // Use an even smaller window like mobile size
  });
  const page = await context.newPage();
  
  // Load the HTML file directly to test the JavaScript behavior
  const htmlPath = path.join(__dirname, '..', 'lua', 'plantuml', 'assets', 'viewer.html');
  const htmlContent = fs.readFileSync(htmlPath, 'utf8');
  
  try {
    // Set the page content
    await page.setContent(htmlContent);
    
    // Test 1: Simulate the timing issue that occurs on initial page load
    console.log('Test 1: Simulating initial page load timing issue...');
    
    const timingTestResult = await page.evaluate(() => {
      // Reset to initial state
      window.currentFilename = '';
      document.getElementById('file').textContent = '';
      
      // Set a long filename that should be truncated
      const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
      window.currentFilename = longFilename;
      
      // Force layout reflow by accessing offsetHeight
      document.body.offsetHeight;
      
      // Get the width immediately (this simulates what happens on initial load)
      const filenameSection = document.querySelector('.filename-section');
      const initialWidth = filenameSection.getBoundingClientRect().width;
      
      // Call updateFilenameDisplay immediately (as it happens on initial WebSocket message)
      updateFilenameDisplay();
      const immediateResult = document.getElementById('file').textContent;
      
      // Wait a bit and try again to see if it's different
      return new Promise(resolve => {
        requestAnimationFrame(() => {
          // Force another layout calculation
          document.body.offsetHeight;
          
          // Get width after layout is complete
          const layoutCompleteWidth = filenameSection.getBoundingClientRect().width;
          
          // Update again with proper width
          updateFilenameDisplay();
          const afterLayoutResult = document.getElementById('file').textContent;
          
          resolve({
            originalFilename: longFilename,
            initialWidth: initialWidth,
            layoutCompleteWidth: layoutCompleteWidth,
            immediateResult: immediateResult,
            afterLayoutResult: afterLayoutResult,
            widthChanged: initialWidth !== layoutCompleteWidth,
            resultChanged: immediateResult !== afterLayoutResult,
            immediateResultTruncated: immediateResult.startsWith('...'),
            afterLayoutResultTruncated: afterLayoutResult.startsWith('...')
          });
        });
      });
    });
    
    console.log('Timing test results:');
    console.log('  Original filename:', timingTestResult.originalFilename);
    console.log('  Initial width:', timingTestResult.initialWidth);
    console.log('  Layout complete width:', timingTestResult.layoutCompleteWidth);
    console.log('  Width changed:', timingTestResult.widthChanged);
    console.log('  Immediate result:', timingTestResult.immediateResult);
    console.log('  After layout result:', timingTestResult.afterLayoutResult);
    console.log('  Result changed:', timingTestResult.resultChanged);
    console.log('  Immediate result truncated:', timingTestResult.immediateResultTruncated);
    console.log('  After layout result truncated:', timingTestResult.afterLayoutResultTruncated);
    
    // Test 2: Test the width calculation issue in detail
    console.log('\nTest 2: Debugging width calculation...');
    
    const widthDebugResult = await page.evaluate(() => {
      const filenameSection = document.querySelector('.filename-section');
      const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
      
      // Test different scenarios
      const currentWidth = filenameSection.getBoundingClientRect().width;
      const maxWidth = currentWidth - 20;
      
      // Create canvas for text measurement (like the truncateFilename function does)
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      const fileEl = document.getElementById('file');
      ctx.font = getComputedStyle(fileEl).font;
      
      const fullTextWidth = ctx.measureText(longFilename).width;
      
      return {
        filenameSection_width: currentWidth,
        maxWidth_for_truncation: maxWidth,
        fullTextWidth: fullTextWidth,
        shouldTruncate: fullTextWidth > maxWidth,
        font_used: ctx.font
      };
    });
    
    console.log('Width debugging results:');
    console.log('  Filename section width:', widthDebugResult.filenameSection_width);
    console.log('  Max width for truncation:', widthDebugResult.maxWidth_for_truncation);
    console.log('  Full text width:', widthDebugResult.fullTextWidth);
    console.log('  Should truncate:', widthDebugResult.shouldTruncate);
    console.log('  Font used:', widthDebugResult.font_used);
    
    // Test 3: Test the resize behavior to confirm it works correctly
    console.log('\nTest 3: Testing resize behavior...');
    
    const resizeTestResult = await page.evaluate(() => {
      // Set a controlled width
      const filenameSection = document.querySelector('.filename-section');
      filenameSection.style.width = '250px';
      
      // Force layout
      document.body.offsetHeight;
      
      // Update filename display
      updateFilenameDisplay();
      const resizeResult = document.getElementById('file').textContent;
      
      return {
        resizeResult: resizeResult,
        isProperlyTruncated: resizeResult.startsWith('...') && resizeResult.endsWith('some_component.puml')
      };
    });
    
    console.log('Resize test results:');
    console.log('  Resize result:', resizeTestResult.resizeResult);
    console.log('  Properly truncated:', resizeTestResult.isProperlyTruncated);
    
    // Determine if we've reproduced the bug
    const bugReproduced = timingTestResult.widthChanged && 
                         !timingTestResult.immediateResultTruncated && 
                         timingTestResult.afterLayoutResultTruncated;
    
    if (bugReproduced) {
      console.log('\n✓ BUG REPRODUCED: Initial width calculation failed, causing truncation to not work until layout is complete');
    } else {
      console.log('\n? Bug may not be fully reproduced in this test environment');
    }
    
    // The bug exists if the immediate result is not properly truncated but should be
    const originalLength = timingTestResult.originalFilename.length;
    const immediateLength = timingTestResult.immediateResult.length;
    
    if (originalLength > 50 && immediateLength === originalLength) {
      console.log('\n✓ CONFIRMED: Filename not truncated on initial load (full path displayed)');
      console.log('  This matches the bug report - filename shows full path until resize');
    }
    
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();