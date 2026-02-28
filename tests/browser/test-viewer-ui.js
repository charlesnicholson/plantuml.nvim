// Playwright test: viewer UI renders correctly and shows status indicators.
// Run via: node tests/browser/test-viewer-ui.js <http_port>
const { chromium } = require("playwright");

const PORT = process.argv[2] || "8764";
const URL = `http://127.0.0.1:${PORT}`;

(async () => {
  let browser;
  try {
    browser = await chromium.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"],
    });

    const page = await browser.newPage();
    await page.goto(URL, { waitUntil: "networkidle" });

    // Wait for WebSocket connection
    await page.waitForFunction(
      () => {
        const s = document.querySelector("#status-text");
        return s && s.textContent !== "Connecting...";
      },
      { timeout: 10000 }
    );

    // Verify page title
    const title = await page.title();
    if (title !== "PlantUML Viewer") throw new Error("Bad title: " + title);

    // Verify status element exists
    const statusText = await page.textContent("#status-text");
    if (!statusText) throw new Error("No status text");

    // Verify placeholder is visible
    const phVisible = await page.isVisible("#ph");
    if (!phVisible) throw new Error("Placeholder not visible");

    // Verify image element exists but is hidden
    const imgDisplay = await page.evaluate(
      () => getComputedStyle(document.getElementById("img")).display
    );
    if (imgDisplay !== "none") throw new Error("Image should be hidden: " + imgDisplay);

    console.log("PASS: All viewer UI tests passed");
    process.exit(0);
  } catch (err) {
    console.error("FAIL:", err.message);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
})();
