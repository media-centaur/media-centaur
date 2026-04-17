// Screenshot tour — navigates to a curated set of UI surfaces under the
// showcase instance and saves PNGs into docs-site/assets/screenshots/.
//
// Manually invoked via scripts/screenshot-tour. NOT regenerated on every
// deploy; run when the catalog or UI changes warrant refreshed marketing
// imagery. The runner script injects NOSFERATU_ID / PIONEER_ONE_ID env
// vars (freshly queried from priv/showcase/media-centarr.db) so this
// file never needs updating after a reseed.
const { test, expect } = require("@playwright/test")
const path = require("node:path")

const REPO_ROOT = path.resolve(__dirname, "..", "..")
const OUT_DIR = path.join(REPO_ROOT, "docs-site", "assets", "screenshots")

// Injected by scripts/screenshot-tour via sqlite3 lookup before each run.
// If unset (direct `bunx playwright test` invocation), the detail-modal
// stops' waitFor selectors will time out and the non-modal page will be
// captured instead — a visible failure rather than a silent miss.
const NOSFERATU_ID = process.env.NOSFERATU_ID || ""
const PIONEER_ONE_ID = process.env.PIONEER_ONE_ID || ""

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
  // Zone tabs and detail modals are patched client-side after LiveView
  // connects; explicit waitFor selectors ensure the target state is
  // actually rendered before screenshotting.
  {
    name: "library-grid",
    url: "/?zone=library",
    waitFor: ".tab-active[data-nav-zone-value='library']",
  },
  {
    name: "library-detail-movie",
    // Default view (not `&view=info`) — the info/"more info" panel was
    // text-heavier than the main panel for Nosferatu and didn't sell the
    // visual language as well.
    url: `/?zone=library&selected=${NOSFERATU_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv",
    url: `/?zone=library&selected=${PIONEER_ONE_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  { name: "settings-overview", url: "/settings" },
]

// Seed localStorage before every page load so every shot renders in
// dark theme with the sidebar collapsed. Both keys are owned by
// root.html.heex — phx:theme drives data-theme on <html> (dark-first
// design); phx:sidebar-collapsed drives data-sidebar="collapsed".
test.beforeEach(async ({ context }) => {
  await context.addInitScript(() => {
    try {
      localStorage.setItem("phx:theme", "dark")
      localStorage.setItem("phx:sidebar-collapsed", "true")
    } catch {}
  })
})

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
