// Screenshot tour — navigates to every major UI surface under the
// showcase profile and saves PNGs into docs-site/assets/screenshots/.
//
// Add a new stop by appending to `TOUR`. If the target needs a specific
// wait condition, use `waitFor` (a selector) or extend `settleMs`.
const { test, expect } = require("@playwright/test")
const path = require("node:path")

const REPO_ROOT = path.resolve(__dirname, "..", "..")
const OUT_DIR = path.join(REPO_ROOT, "docs-site", "assets", "screenshots")

/**
 * Each tour stop describes one URL and the PNG filename it produces.
 *
 * @typedef {object} Stop
 * @property {string} name       Output filename (no extension).
 * @property {string} url        Path or full URL to navigate to.
 * @property {string} [waitFor]  Optional selector to wait for before capturing.
 * @property {number} [settleMs] Extra pause (ms) after navigation/mount.
 */

/** @type {Stop[]} */
const TOUR = [
  { name: "library-grid", url: "/", waitFor: "[data-nav-item], .empty-state" },
  { name: "continue-watching", url: "/?zone=watching" },
  { name: "upcoming-releases", url: "/?zone=upcoming" },
  { name: "release-tracking", url: "/status" },
  { name: "review-queue", url: "/review" },
  { name: "watch-history", url: "/history" },
  { name: "settings-overview", url: "/settings" },
  { name: "console", url: "/console" },
  { name: "download", url: "/download" },
]

async function waitForLiveView(page) {
  // Phoenix LiveView adds phx-connected to the socket root once the
  // channel join completes. This is a stable signal we're mounted.
  await page.waitForFunction(
    () => document.querySelector(".phx-connected, [data-phx-main]") !== null,
    null,
    { timeout: 15_000 },
  )
}

for (const stop of TOUR) {
  test(`tour: ${stop.name}`, async ({ page }) => {
    await page.goto(stop.url, { waitUntil: "domcontentloaded" })
    await waitForLiveView(page)

    if (stop.waitFor) {
      await page
        .waitForSelector(stop.waitFor, { timeout: 5_000 })
        .catch(() => {
          /* missing is fine — capture whatever rendered. */
        })
    }

    // Additional settle pass — network-idle covers async data, the short
    // extra delay covers LiveView's post-mount :after events.
    await page.waitForLoadState("networkidle").catch(() => {})
    await page.waitForTimeout(stop.settleMs ?? 400)

    const outPath = path.join(OUT_DIR, `${stop.name}.png`)
    await page.screenshot({ path: outPath, fullPage: false })
    expect(outPath).toBeTruthy()
  })
}
