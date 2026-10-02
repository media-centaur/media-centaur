/**
 * Incoming page E2E tests (the merged Upcoming + Downloads page, UIDR-015;
 * the Watchlist as its first tab, UIDR-050).
 *
 * Covers cursor start on the Watchlist rows, the vertical zone chain
 * (omnibox → zone tabs → the active tab's zone), BACK to the sidebar and
 * LEFT never reaching it. One tab's content renders at a time: a fresh
 * mount lands on the Watchlist (`title_rows`) unless live activity pulls
 * it to Activity (`pursuits`). Zone presence depends on live data (listed
 * titles, active pursuits, terminal history), so each cross-zone test
 * skips when its target zone is empty rather than asserting a fixed page
 * shape.
 */
import { test, expect } from "./fixtures/input-method.js"
import {
  expectContext,
  expectFocusInZone,
  getZoneItemCount,
} from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

test.describe("incoming navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/incoming")
    await waitForInputSystem(page)
  })

  test("initial focus follows the cursor start priority", async ({ page }) => {
    const watchlistCount = await getZoneItemCount(page, "title_rows")
    const pursuitCount = await getZoneItemCount(page, "pursuits")

    if (watchlistCount > 0) {
      await expectContext(page, "title_rows")
      await expectFocusInZone(page, "title_rows")
    } else if (pursuitCount > 0) {
      await expectContext(page, "pursuits")
    } else {
      await expectContext(page, "omnibox")
    }
  })

  test("up from the watchlist reaches the zone tabs, then the omnibox", async ({
    page,
    inputAction,
  }) => {
    const watchlistCount = await getZoneItemCount(page, "title_rows")
    test.skip(watchlistCount === 0, "no listed titles in this environment")

    await expectContext(page, "title_rows")
    // Walk up until the top row, then one more step crosses to the tabs.
    for (let step = 0; step < watchlistCount; step++) {
      await inputAction("NAVIGATE_UP")
      const context = await page.evaluate(() =>
        document.documentElement.getAttribute("data-nav-context")
      )
      if (context === "zone_tabs") break
    }
    await expectContext(page, "zone_tabs")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "omnibox")
  })

  test("down from the zone tabs enters the active tab's zone", async ({ page, inputAction }) => {
    const watchlistCount = await getZoneItemCount(page, "title_rows")
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    test.skip(watchlistCount === 0 && pursuitCount === 0, "no tab content in this environment")

    // From wherever the cursor started, climb to the tabs.
    for (let step = 0; step < 12; step++) {
      const context = await page.evaluate(() =>
        document.documentElement.getAttribute("data-nav-context")
      )
      if (context === "zone_tabs") break
      await inputAction("NAVIGATE_UP")
    }
    await expectContext(page, "zone_tabs")

    await inputAction("NAVIGATE_DOWN")
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["title_rows", "drafts", "pursuits", "ledger"]).toContain(context)
  })

  test("back reaches the sidebar; right returns", async ({ page, inputAction }) => {
    const before = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )

    await inputAction("BACK")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    const after = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(after).toBe(before)
  })

  test("left in an incoming zone never reaches the sidebar", async ({
    page,
    inputAction,
  }) => {
    // UIDR-028: LEFT is lateral movement within the page. It may move between
    // this page's own zones, but it never escapes to the main menu.
    await inputAction("NAVIGATE_LEFT")

    const after = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(after).not.toBe("sidebar")
  })
})
