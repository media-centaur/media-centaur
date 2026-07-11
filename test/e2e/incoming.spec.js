/**
 * Incoming page E2E tests (the merged Upcoming + Downloads page, DDR-015).
 *
 * Covers cursor start on the shelf, the vertical zone chain
 * (omnibox → shelf → pursuits → ledger), left-to-sidebar, and BACK as a
 * no-op. Zone presence depends on live data (tracked releases, active
 * pursuits, terminal history), so each cross-zone test skips when its
 * target zone is empty rather than asserting a fixed page shape.
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
    const shelfCount = await getZoneItemCount(page, "coming_up")
    const pursuitCount = await getZoneItemCount(page, "pursuits")

    if (shelfCount > 0) {
      await expectContext(page, "coming_up")
      await expectFocusInZone(page, "coming_up")
    } else if (pursuitCount > 0) {
      await expectContext(page, "pursuits")
    } else {
      await expectContext(page, "omnibox")
    }
  })

  test("down from the shelf reaches the operational column", async ({ page, inputAction }) => {
    const shelfCount = await getZoneItemCount(page, "coming_up")
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    const ledgerCount = await getZoneItemCount(page, "ledger")
    test.skip(shelfCount === 0, "no tracked releases in this environment")
    test.skip(pursuitCount === 0 && ledgerCount === 0, "no operational zones in this environment")

    await expectContext(page, "coming_up")
    await inputAction("NAVIGATE_DOWN")
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["drafts", "pursuits", "ledger", "history"]).toContain(context)
  })

  test("up from the shelf reaches the omnibox", async ({ page, inputAction }) => {
    const shelfCount = await getZoneItemCount(page, "coming_up")
    test.skip(shelfCount === 0, "no tracked releases in this environment")

    await expectContext(page, "coming_up")
    await inputAction("NAVIGATE_UP")
    await expectContext(page, "omnibox")
  })

  test("the ledger sits below the pursuits", async ({ page, inputAction }) => {
    const pursuitCount = await getZoneItemCount(page, "pursuits")
    const ledgerCount = await getZoneItemCount(page, "ledger")
    test.skip(pursuitCount === 0 || ledgerCount === 0, "needs both operational zones")

    // Walk down until the pursuits zone, then one more step.
    for (let step = 0; step < 6; step++) {
      const context = await page.evaluate(() =>
        document.documentElement.getAttribute("data-nav-context")
      )
      if (context === "pursuits") break
      await inputAction("NAVIGATE_DOWN")
    }
    await expectContext(page, "pursuits")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "ledger")
  })

  test("left reaches the sidebar; right returns", async ({ page, inputAction }) => {
    const before = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    const after = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(after).toBe(before)
  })

  test("escape in an incoming zone is a no-op — left is the way to the sidebar", async ({
    page,
    inputAction,
  }) => {
    const before = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )

    await inputAction("BACK")

    const after = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(after).toBe(before)
    expect(after).not.toBe("sidebar")
  })
})
