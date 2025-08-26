const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  console.log('Testing filename truncation fix with requestAnimationFrame...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ 
    viewport: { width: 400, height: 300 } // Small window to force truncation
  });
  const page = await context.newPage();
  
  // Load the HTML file directly to test the JavaScript behavior
  const htmlPath = path.join(__dirname, '..', 'lua', 'plantuml', 'assets', 'viewer.html');
  const htmlContent = fs.readFileSync(htmlPath, 'utf8');
  
  try {
    // Set the page content
    await page.setContent(htmlContent);
    
    // Test: Simulate the WebSocket message sequence that happens on initial load
    console.log('Testing initial load with safe filename display...');
    
    const testResult = await page.evaluate(() => {
      return new Promise((resolve) => {
        // Reset state
        window.currentFilename = '';
        document.getElementById('file').textContent = '';
        
        // Set the long filename that should be truncated
        const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
        
        // Simulate what happens in the WebSocket message handler
        window.currentFilename = longFilename;
        
        // Call the safe version (which uses requestAnimationFrame)
        updateFilenameDisplaySafe();
        
        // Wait for the requestAnimationFrame to complete and check the result
        requestAnimationFrame(() => {
          const result = document.getElementById('file').textContent;
          const filenameSection = document.querySelector('.filename-section');
          const availableWidth = filenameSection.getBoundingClientRect().width - 20;
          
          // Create canvas for text measurement
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d');
          const fileEl = document.getElementById('file');
          ctx.font = getComputedStyle(fileEl).font;
          const fullTextWidth = ctx.measureText(longFilename).width;
          
          resolve({
            originalFilename: longFilename,
            displayedResult: result,
            availableWidth: availableWidth,
            fullTextWidth: fullTextWidth,
            shouldTruncate: fullTextWidth > availableWidth,
            isProperlyTruncated: result.startsWith('...') && result.endsWith('some_component.puml'),
            functionUsed: 'updateFilenameDisplaySafe'
          });
        });
      });
    });
    
    console.log('Test results:');
    console.log('  Original filename:', testResult.originalFilename);
    console.log('  Displayed result:', testResult.displayedResult);
    console.log('  Available width:', testResult.availableWidth);
    console.log('  Full text width:', testResult.fullTextWidth);
    console.log('  Should truncate:', testResult.shouldTruncate);
    console.log('  Is properly truncated:', testResult.isProperlyTruncated);
    console.log('  Function used:', testResult.functionUsed);
    
    // Verify the fix
    if (testResult.shouldTruncate && !testResult.isProperlyTruncated) {
      console.log('\n❌ FAIL: Filename should be truncated but is not');
      process.exit(1);
    } else if (testResult.shouldTruncate && testResult.isProperlyTruncated) {
      console.log('\n✅ SUCCESS: Filename is properly truncated on initial load');
    } else {
      console.log('\n✅ SUCCESS: Filename fits completely, no truncation needed');
    }
    
    // Test resize behavior still works
    console.log('\nTesting resize behavior...');
    
    const resizeResult = await page.evaluate(() => {
      return new Promise((resolve) => {
        // Change window size to trigger resize
        const filenameSection = document.querySelector('.filename-section');
        filenameSection.style.width = '200px';
        
        // Trigger resize event
        window.dispatchEvent(new Event('resize'));
        
        // Wait for requestAnimationFrame to complete
        requestAnimationFrame(() => {
          const result = document.getElementById('file').textContent;
          resolve({
            resizeResult: result,
            isProperlyTruncated: result.startsWith('...') && result.endsWith('some_component.puml')
          });
        });
      });
    });
    
    console.log('Resize test results:');
    console.log('  Result after resize:', resizeResult.resizeResult);
    console.log('  Properly truncated:', resizeResult.isProperlyTruncated);
    
    if (resizeResult.isProperlyTruncated) {
      console.log('\n✅ SUCCESS: Resize behavior still works correctly');
    } else {
      console.log('\n❌ FAIL: Resize behavior broken');
      process.exit(1);
    }
    
    console.log('\n🎉 All tests passed! The fix appears to work correctly.');
    
  } catch (error) {
    console.error('Test failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();