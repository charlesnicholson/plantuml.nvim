// Playwright test: status indicator shows correct states.
// Before any diagram loads: "Connected" (not "Live").
// "Live" only appears after a diagram image successfully loads.
// Run via: node tests/browser/test-status-states.js <http_port>
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

    // Wait for WebSocket connection (status changes from "Connecting...")
    await page.waitForFunction(
      () => {
        const s = document.querySelector("#status-text");
        return s && s.textContent !== "Connecting..." && s.textContent !== "connecting";
      },
      { timeout: 10000 }
    );

    // Verify status is "Connected" (not "Live") since no diagram has loaded
    const statusText = await page.textContent("#status-text");
    if (statusText === "Live") {
      throw new Error(
        'Status should be "Connected" before any diagram loads, got "Live"'
      );
    }
    if (statusText !== "Connected") {
      // Accept other transient states (e.g., "Starting Docker...") but not "Live"
      console.log("INFO: Status is '" + statusText + "' (acceptable transient state)");
    } else {
      console.log("OK: Status is 'Connected' before diagram load");
    }

    // Verify the status pill has the "ok" class (green dot)
    const pillClass = await page.getAttribute("#status", "class");
    if (!pillClass.includes("ok")) {
      throw new Error("Status pill should have 'ok' class, got: " + pillClass);
    }

    // Verify hasLoadedDiagram is false in the page context
    const hasLoaded = await page.evaluate(() => window.hasLoadedDiagram || false);
    if (hasLoaded) {
      throw new Error("hasLoadedDiagram should be false when no image loaded");
    }

    // Verify the placeholder is visible (no diagram delivered in this test)
    const phVisible = await page.isVisible("#ph");
    if (!phVisible) {
      throw new Error("Placeholder should be visible when no diagram is loaded");
    }

    console.log("PASS: All status state tests passed");
    process.exit(0);
  } catch (err) {
    console.error("FAIL:", err.message);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
})();
