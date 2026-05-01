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

const fs = require("node:fs")

const REPO_ROOT = path.resolve(__dirname, "..", "..")
const OUT_BASE = path.join(REPO_ROOT, "docs-site", "assets", "screenshots")

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
  // ─── Home ────────────────────────────────────────────────────────────
  // The cinematic landing page. Each section is gated by `:if` on
  // assigned data, so the seeded showcase DB needs Continue Watching
  // and Coming Up populated for these shots to render. See
  // lib/media_centarr/showcase.ex.
  {
    name: "home",
    url: "/",
    waitFor: "section[data-row='continue-watching']",
    settleMs: 400,
  },
  {
    name: "home-coming-up",
    url: "/",
    waitFor: "section[data-row='coming-up']",
    action: async (page) => {
      await page
        .locator("section[data-row='coming-up']")
        .scrollIntoViewIfNeeded({ timeout: 5_000 })
        .catch(() => {})
    },
    settleMs: 400,
  },

  // ─── Library ─────────────────────────────────────────────────────────
  { name: "library-grid", url: "/library", settleMs: 400 },
  {
    name: "library-in-progress",
    url: "/library?in_progress=1",
    settleMs: 400,
  },
  {
    name: "library-detail-movie",
    url: `/library?selected=${NOSFERATU_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv",
    url: `/library?selected=${BEVERLY_HILLBILLIES_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },
  {
    name: "library-detail-tv-pioneer",
    url: `/library?selected=${PIONEER_ONE_ID}`,
    waitFor: "#detail-modal[data-state='open']",
  },

  // ─── Upcoming ────────────────────────────────────────────────────────
  { name: "upcoming-calendar", url: "/upcoming", settleMs: 600 },
  {
    name: "upcoming-track-modal",
    url: "/upcoming",
    action: async (page) => {
      // The Track New Show button lives in UpcomingCards; clicking
      // pushes `open_track_modal` and focuses the modal's search input.
      await page
        .locator("[phx-click*='open_track_modal']")
        .first()
        .click({ timeout: 5_000 })
        .catch(() => {})
    },
    settleMs: 800,
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

  // ─── History (Watch History) ────────────────────────────────────────
  // /history is `WatchHistoryLive` — heatmap + stats + rewatch badges.
  // (The pre-redistribution `history.png` shot meant download-history;
  //  see `download-activity` below for that surface.)
  { name: "history-heatmap", url: "/history", settleMs: 500 },
  {
    name: "history-rewatch-badges",
    url: "/history",
    action: async (page) => {
      // Scroll past the heatmap + stats so the paginated event list
      // with `Nx` rewatch badges fills the viewport.
      await page.evaluate(() => window.scrollTo(0, 700)).catch(() => {})
    },
    settleMs: 500,
  },

  // ─── Status / Acquisition / Console ─────────────────────────────────
  { name: "status", url: "/status" },
  { name: "download", url: "/download", settleMs: 800 },
  {
    name: "download-activity",
    url: "/download?filter=all",
    settleMs: 800,
  },
  {
    name: "download-search",
    url: "/download",
    action: async (page) => {
      // Type a public-domain title into the search input and submit.
      // In showcase mode, Prowlarr is stubbed (see
      // MediaCentarr.Showcase.Stubs) — the stub returns fixture
      // release candidates regardless of the query string, so any
      // submission populates the results card.
      const input = page.locator("input[name='query']")
      await input.fill("Night of the Living Dead")
      await page.locator("button[type='submit']").click()
      // Wait for the results card to appear. The AcquisitionLive
      // template only renders the results section when @groups is
      // non-empty, so a presence-check on the section heading is
      // enough to know the async search returned.
      await page
        .waitForFunction(
          () =>
            document.body.innerText.includes("Night of the Living Dead") &&
            document.querySelector("input[name='query']")?.value,
          null,
          { timeout: 5_000 },
        )
        .catch(() => {})
      // Scroll to the first result group so the screenshot captures
      // the results rather than the queue card at the top.
      await page
        .locator("[data-nav-zone='results'], [data-nav-zone='sections']")
        .first()
        .scrollIntoViewIfNeeded({ timeout: 2_000 })
        .catch(() => {})
    },
    settleMs: 1500,
  },
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
    url: "/library",
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

// Seed localStorage before every page load so every shot renders with
// the sidebar collapsed. The key is owned by root.html.heex —
// phx:sidebar-collapsed drives data-sidebar="collapsed" on <html>.
test.beforeEach(async ({ context }) => {
  await context.addInitScript(() => {
    try {
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
  test(`tour: ${stop.name}`, async ({ page }, testInfo) => {
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

    // Project metadata chooses the output subdir — "" for web, "4k" for
    // supersampled. See screenshot-tour.config.js.
    const subdir = testInfo.project.metadata?.outSubdir ?? ""
    const outDir = path.join(OUT_BASE, subdir)
    fs.mkdirSync(outDir, { recursive: true })
    const outPath = path.join(outDir, `${stop.name}.png`)
    await page.screenshot({ path: outPath, fullPage: false })

    // Placeholder-ratio guard — if >50% of /media-images/* tags on this
    // stop resolve to the SVG placeholder plug, the seed almost certainly
    // didn't produce real images (bad TMDB_API_KEY, network, etc.) and
    // the marketing screenshot is a wall of dark tiles. Fail the stop
    // rather than silently ship a visually-broken capture.
    const audit = await page.evaluate(async () => {
      const imgs = Array.from(document.querySelectorAll('img[src^="/media-images/"]'))
      const results = await Promise.all(
        imgs.map(async (img) => {
          try {
            const resp = await fetch(img.src, { method: "HEAD", cache: "no-store" })
            const ct = resp.headers.get("content-type") || ""
            return { src: img.src, placeholder: ct.includes("svg+xml") }
          } catch {
            return { src: img.src, placeholder: true }
          }
        }),
      )
      return {
        total: results.length,
        placeholders: results.filter((r) => r.placeholder).length,
        placeholderSrcs: results.filter((r) => r.placeholder).map((r) => r.src),
      }
    })

    if (audit.total > 0) {
      const realCount = audit.total - audit.placeholders
      const realRatio = realCount / audit.total
      const firstOffenders = audit.placeholderSrcs.slice(0, 3).join("\n    ")
      expect(
        realRatio,
        `${stop.name}: only ${realCount}/${audit.total} images are real files — need >50% to pass. ` +
          `TMDB_API_KEY set? First placeholder srcs:\n    ${firstOffenders}`,
      ).toBeGreaterThan(0.5)
    }
  })
}
