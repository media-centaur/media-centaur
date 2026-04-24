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
const NOSFERATU_ID = process.env.NOSFERATU_ID || ""
const PIONEER_ONE_ID = process.env.PIONEER_ONE_ID || ""
const BEVERLY_HILLBILLIES_ID = process.env.BEVERLY_HILLBILLIES_ID || ""

/**
 * @typedef {object} Stop
 * @property {string} name       Output filename (no extension).
 * @property {string} url        Path or full URL to navigate to.
 * @property {string} [waitFor]  Optional selector to wait for before capturing.
 * @property {number} [settleMs] Extra pause (ms) after navigation/mount.
 * @property {(page: import("@playwright/test").Page) => Promise<void>} [action]
 *   Optional per-stop action that runs after waitFor and before the
 *   final settle + screenshot (click, scroll, focus, etc.).
 */

/** @type {Stop[]} */
const TOUR = [
  // ─── Library ─────────────────────────────────────────────────────────
  {
    name: "library-grid",
    url: "/?zone=library",
    waitFor: ".tab-active[data-nav-zone-value='library']",
  },
  {
    name: "library-detail-movie",
    url: `/?zone=library&selected=${NOSFERATU_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv",
    url: `/?zone=library&selected=${BEVERLY_HILLBILLIES_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv-pioneer",
    url: `/?zone=library&selected=${PIONEER_ONE_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },

  // ─── Review ──────────────────────────────────────────────────────────
  { name: "review-queue", url: "/review" },
  {
    name: "review-detail",
    url: "/review",
    action: async (page) => {
      const first = page.locator("[data-review-pending]").first()
      await first.click({ timeout: 5_000 }).catch(() => {})
    },
    settleMs: 600,
  },

  // ─── Status / releases / history / console ──────────────────────────
  {
    name: "release-tracking",
    url: "/status",
    action: async (page) => {
      const card = page.locator("[data-status-releases]").first()
      await card.scrollIntoViewIfNeeded({ timeout: 5_000 }).catch(() => {})
    },
    settleMs: 300,
  },
  { name: "status", url: "/status" },
  { name: "history", url: "/history" },
  { name: "download", url: "/download" },
  { name: "console", url: "/console" },

  // ─── Settings ────────────────────────────────────────────────────────
  { name: "settings-overview", url: "/settings" },
  { name: "settings-library", url: "/settings?section=library", settleMs: 300 },
  { name: "settings-tmdb", url: "/settings?section=tmdb", settleMs: 300 },
  {
    name: "settings-download-clients",
    url: "/settings?section=acquisition",
    action: async (page) => {
      await page
        .locator("#settings-download-client")
        .scrollIntoViewIfNeeded({ timeout: 5_000 })
        .catch(() => {})
    },
    settleMs: 300,
  },
  {
    name: "settings-prowlarr",
    url: "/settings?section=acquisition",
    action: async (page) => {
      await page
        .locator("#settings-prowlarr")
        .scrollIntoViewIfNeeded({ timeout: 5_000 })
        .catch(() => {})
    },
    settleMs: 300,
  },

  // ─── A11y / input system ────────────────────────────────────────────
  {
    name: "keyboard-focus",
    url: "/?zone=library",
    waitFor: ".tab-active[data-nav-zone-value='library']",
    action: async (page) => {
      // The focus ring is gated by `<html data-input="keyboard">` (set at
      // runtime by input/core/dom_adapter.js when keyboard activity is
      // detected). Playwright's .focus() doesn't trigger that detection,
      // so set it explicitly before focusing a nav item — otherwise the
      // focus outline is suppressed (mouse-input styling).
      await page.evaluate(() => {
        document.documentElement.dataset.input = "keyboard"
      })
      // Skip past sidebar/tab bar — first library card is the meaningful
      // subject of this shot. Grid zone wraps the library cards.
      await page.locator("[data-nav-zone='grid'] [data-nav-item]").first().focus()
    },
    settleMs: 300,
  },

  // ─── Known gaps (omitted stops) ──────────────────────────────────────
  // playback-overlay: mpv renders the overlay, not the browser;
  //   Playwright can't capture it.
  // first-run: requires an empty DB, which conflicts with the populated
  //   showcase. Capture manually if needed.
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

    if (stop.action) {
      await stop.action(page)
    }

    await page.waitForLoadState("networkidle").catch(() => {})
    await page.waitForTimeout(stop.settleMs ?? 400)

    const outPath = path.join(OUT_DIR, `${stop.name}.png`)
    await page.screenshot({ path: outPath, fullPage: false })
    expect(outPath).toBeTruthy()
  })
}
