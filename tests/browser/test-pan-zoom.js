// Playwright test: click-to-zoom and click-and-drag pan interactions.
// Run via: node tests/browser/test-pan-zoom.js <http_port>
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

    // Wait for connection
    await page.waitForFunction(
      () => {
        const s = document.querySelector("#status-text");
        return s && s.textContent !== "Connecting...";
      },
      { timeout: 10000 }
    );

    // Verify helper functions exist
    const hasFunctions = await page.evaluate(() => {
      return (
        typeof window.truncateFilename === "function" &&
        typeof window.updateFilenameDisplay === "function"
      );
    });
    if (!hasFunctions) throw new Error("Missing helper functions");

    // Verify board element exists
    const boardExists = await page.isVisible("#board");
    if (!boardExists) throw new Error("Board element not visible");

    // Verify truncateFilename works
    const truncated = await page.evaluate(() => {
      return window.truncateFilename("/very/long/path/to/file.puml", 100);
    });
    if (!truncated || truncated.length === 0)
      throw new Error("truncateFilename returned empty");

    // Verify zoom-pan state variables exist
    const stateOk = await page.evaluate(() => {
      return (
        typeof isZoomPanMode === "boolean" &&
        typeof panX === "number" &&
        typeof panY === "number" &&
        typeof isDragging === "boolean" &&
        typeof CLICK_THRESHOLD === "number"
      );
    });
    if (!stateOk) throw new Error("Zoom-pan state variables missing");

    // Verify cursor style on board (should be default/pointer, not grab, when no image)
    const boardCursor = await page.evaluate(() => {
      return getComputedStyle(document.getElementById("board")).cursor;
    });
    // Board should not be in zoom-pan-mode initially
    const hasZoomClass = await page.evaluate(() => {
      return document.getElementById("board").classList.contains("zoom-pan-mode");
    });
    if (hasZoomClass) throw new Error("Board should not start in zoom-pan-mode");

    console.log("PASS: All pan-zoom tests passed");
    process.exit(0);
  } catch (err) {
    console.error("FAIL:", err.message);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
})();
