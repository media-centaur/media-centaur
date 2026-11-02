/**
 * Downloads page E2E tests (UIDR-015, amended at the Discovery campaign's
 * cutover: the get stage, UIDR-057).
 *
 * Covers cursor start on the pursuits, the vertical zone chain (the release
 * search box → zone tabs → the active tab's zone), BACK to the sidebar and
 * LEFT never reaching it. One tab's content renders at a time: a fresh
 * mount lands on Activity (`pursuits`, `drafts`); History holds the
 * `ledger`. Zone presence depends on live data (active pursuits, terminal
 * history), so each cross-zone test skips when its target zone is empty
 * rather than asserting a fixed page shape. Without Prowlarr the page is
 * its gap state and has no zones but the sidebar.
 */
import { test, expect } from "./fixtures/input-method.js"
import {
  expectContext,
  expectFocusInZone,
  getZoneItemCount,
} from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

test.describe("downloads navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/downloads")
    await waitForInputSystem(page)
  })

  test("initial focus follows the cursor start priority", async ({ page }) => {
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    const tabCount = await getZoneItemCount(page, "zone-tabs")

    if (pursuitCount > 0) {
      await expectContext(page, "pursuits")
      await expectFocusInZone(page, "pursuits")
    } else if (tabCount > 0) {
      await expectContext(page, "zone_tabs")
    } else {
      await expectContext(page, "sidebar")
    }
  })

  test("up from the pursuits reaches the zone tabs, then the search box", async ({
    page,
    inputAction,
  }) => {
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    test.skip(pursuitCount === 0, "nothing in flight in this environment")

    await expectContext(page, "pursuits")
    // Walk up until the top row, then one more step crosses to the tabs.
    for (let step = 0; step < pursuitCount; step++) {
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
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    const draftCount = await getZoneItemCount(page, "drafts")
    test.skip(pursuitCount === 0 && draftCount === 0, "no tab content in this environment")

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
    expect(["drafts", "pursuits"]).toContain(context)
  })

  test("back reaches the sidebar; right returns", async ({ page, inputAction }) => {
    const tabCount = await getZoneItemCount(page, "zone-tabs")
    test.skip(tabCount === 0, "no indexer in this environment: the page has no zones to return to")

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

  test("left in a downloads zone never reaches the sidebar", async ({
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
