const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  console.log('Creating demonstration screenshots...');
  
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ 
    viewport: { width: 800, height: 400 }
  });
  const page = await context.newPage();
  
  // Load the HTML file
  const htmlPath = path.join(__dirname, '..', 'lua', 'plantuml', 'assets', 'viewer.html');
  const htmlContent = fs.readFileSync(htmlPath, 'utf8');
  
  try {
    await page.setContent(htmlContent);
    
    // Simulate the fixed behavior
    await page.evaluate(() => {
      // Set the long filename from the bug report
      const longFilename = '/Users/charles/src/fi/firmware/src/fi/some_component.puml';
      window.currentFilename = longFilename;
      
      // Simulate WebSocket message arrival with the fix
      updateFilenameDisplaySafe();
      
      // Also set status to make it look realistic
      document.getElementById('status-text').textContent = 'Live';
      document.getElementById('status').className = 'pill ok';
      
      // Set a timestamp
      document.getElementById('timestamp').textContent = 'Updated: 2025-08-26 09:42:46';
      
      // Set server URL
      const serverUrl = document.getElementById('server-url');
      serverUrl.textContent = 'http://localhost:8080/png/~1U9ojbCrkdJ0GXVSyXTTLi-YoMLH1u2Ah0dnjejkghH...';
      serverUrl.style.display = 'block';
    });
    
    // Wait for the requestAnimationFrame to complete
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Take screenshot of the fixed behavior
    await page.screenshot({ 
      path: 'tests/screenshots/filename-truncation-fixed.png',
      fullPage: false
    });
    
    console.log('✅ Screenshot saved: tests/screenshots/filename-truncation-fixed.png');
    console.log('The screenshot shows the filename properly truncated with the fix applied.');
    
  } catch (error) {
    console.error('Screenshot generation failed:', error);
    process.exit(1);
  } finally {
    await browser.close();
  }
})();