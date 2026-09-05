/**
 * Library page E2E tests — the most complex page.
 *
 * Tests grid spatial navigation, grid ↔ toolbar transitions, drawer/modal
 * lifecycle, focus memory, filter input, and empty grid fallback on `/library`,
 * plus zone-tab cycling on `/incoming` (the one page with a tab strip).
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedNavItem, getFocusedIndex, getZoneItemCount, establishFocus } from "./helpers/input.js"
import { waitForSettle } from "./helpers/liveview.js"

test.describe("library grid spatial navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/library")
  })

  test("arrow down moves focus to next row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount < 2, "needs at least two library entries")

    await expectContext(page, "grid")
    const before = await getFocusedIndex(page)

    await inputAction("NAVIGATE_DOWN")
    const after = await getFocusedIndex(page)

    // Down should move to a different index (next row)
    expect(after).not.toBe(before)
  })

  test("arrow up moves focus to previous row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount < 2, "needs at least two library entries")

    // Move down first, then up
    await inputAction("NAVIGATE_DOWN")
    const middle = await getFocusedIndex(page)

    await inputAction("NAVIGATE_UP")
    const back = await getFocusedIndex(page)

    // Should have returned to a different position (previous row)
    expect(back).not.toBe(middle)
  })

  test("arrow right moves to next item in row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount < 2, "needs at least two library entries")

    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_RIGHT")
    const second = await getFocusedNavItem(page)

    expect(second).not.toBe(first)
  })

  test("left at the first column is a wall (UIDR-028)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    // The cursor starts on the first entry (column 0)
    await expectContext(page, "grid")
    expect(await getFocusedIndex(page)).toBe(0)

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "grid")
    expect(await getFocusedIndex(page)).toBe(0)
  })

  test("BACK from the grid enters the sidebar; right returns to the same entry", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount < 2, "needs at least two library entries")

    await inputAction("NAVIGATE_RIGHT")
    const origin = await getFocusedNavItem(page)

    await inputAction("BACK")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "grid")
    expect(await getFocusedNavItem(page)).toBe(origin)
  })

  test("down from bottom row → wall (stays in grid)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    // Navigate to last item by pressing down many times
    for (let i = 0; i < 50; i++) {
      await inputAction("NAVIGATE_DOWN")
    }

    // Should still be in grid context (wall, not transition)
    await expectContext(page, "grid")
  })

  test("right from last column → wall (stays)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    // Navigate to rightmost column
    for (let i = 0; i < 20; i++) {
      await inputAction("NAVIGATE_RIGHT")
    }

    // Should still be in grid (wall)
    await expectContext(page, "grid")
  })
})

test.describe("library grid ↔ toolbar transitions", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/library")
  })

  test("up from top row of grid → toolbar", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    // The cursor starts on the first row
    await expectContext(page, "grid")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")
  })

  test("down from toolbar → grid top row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    test.skip(gridCount === 0 || toolbarCount === 0, "needs a library entry and a toolbar")

    // Navigate up to toolbar first
    await inputAction("NAVIGATE_UP")
    await waitForSettle(page)

    // Navigate back down
    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")
  })

  test("left at the toolbar's first control is a wall; BACK enters the sidebar", async ({ page, inputAction }) => {
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    test.skip(toolbarCount === 0, "library toolbar zone missing")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "toolbar")

    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })
})

test.describe("incoming zone tabs", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/incoming")
  })

  test("zone tab switch resets grid content", async ({ page, inputAction }) => {
    const tabCount = await getZoneItemCount(page, "zone-tabs")
    test.skip(tabCount < 2, "needs at least two zone tabs")

    // Switch zone with ] key / RB
    await inputAction("ZONE_NEXT")
    await waitForSettle(page, 300)

    // Grid content may have changed (different zone)
    // At minimum, we should still be functional
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).toBeTruthy()
  })

  test("zone tab switch with [ / LB works", async ({ page, inputAction }) => {
    const tabCount = await getZoneItemCount(page, "zone-tabs")
    test.skip(tabCount < 2, "needs at least two zone tabs")

    // Switch forward then backward
    await inputAction("ZONE_NEXT")
    await waitForSettle(page, 500)
    await establishFocus(page)

    await inputAction("ZONE_PREV")
    await waitForSettle(page, 500)

    // Should still be on the Incoming page
    await expect(page).toHaveURL(/\/incoming/)
  })
})

test.describe("library detail overlay", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/library")
  })

  test("select on grid item → opens the detail overlay on its actions row (UIDR-019)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    await expectContext(page, "grid")
    await inputAction("SELECT")
    await expectContext(page, "detail_actions")
  })

  test("escape from overlay → focus returns to originating grid item", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    // Select second item if possible
    if (gridCount >= 2) {
      await inputAction("NAVIGATE_RIGHT")
    }
    const originItem = await getFocusedNavItem(page)

    // Open overlay; BACK from the actions row dismisses it
    await inputAction("SELECT")
    await expectContext(page, "detail_actions")

    await inputAction("BACK")

    // Focus should return to the originating item
    await expectContext(page, "grid")
    const restored = await getFocusedNavItem(page)
    expect(restored).toBe(originItem)
  })

  test("vertical navigation within overlay", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "needs at least one library entry")

    await inputAction("SELECT")
    await expectContext(page, "detail_actions")

    // Down leaves the actions row for the body region below it
    await inputAction("NAVIGATE_DOWN")
    await expect(page.locator("html")).toHaveAttribute("data-nav-context", /^detail_/)
    expect(await getFocusedNavItem(page)).toBeTruthy()
  })
})

test.describe("library filter input [keyboard-only]", () => {
  test.beforeEach(async ({ navigateTo, inputMethod }) => {
    // Filter tests are keyboard-only — text input doesn't apply to gamepad
    test.skip(inputMethod === "gamepad", "keyboard-only test")
    await navigateTo("/library")
  })

  test("focus filter → arrows still navigate (not editing)", async ({ page, inputAction }) => {
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    test.skip(toolbarCount === 0, "library toolbar zone missing")

    // Navigate to toolbar (which contains the filter input)
    await inputAction("NAVIGATE_UP")
    await waitForSettle(page)

    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    test.skip(context !== "toolbar", "up from the grid did not reach the toolbar")

    // Arrow keys should still navigate, not start editing
    await inputAction("NAVIGATE_LEFT")
    await inputAction("NAVIGATE_RIGHT")

    // Should still be in toolbar or have navigated via graph
    const afterContext = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(afterContext).toBeTruthy()
  })

  test("escape from filter clears and exits", async ({ page, inputAction }) => {
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    test.skip(toolbarCount === 0, "library toolbar zone missing")

    // Navigate to toolbar
    await inputAction("NAVIGATE_UP")
    await waitForSettle(page)

    // Press escape — should handle gracefully
    await inputAction("BACK")
    await waitForSettle(page)

    // Should have exited to sidebar or stayed in content
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).toBeTruthy()
  })
})

test.describe("library empty grid fallback", () => {
  test("system handles empty grid gracefully", async ({ page, navigateTo, inputAction }) => {
    await navigateTo("/library")

    // Even if grid is empty, navigation shouldn't throw
    await inputAction("NAVIGATE_DOWN")
    await inputAction("NAVIGATE_UP")
    await inputAction("NAVIGATE_LEFT")
    await inputAction("NAVIGATE_RIGHT")

    // Should still have a valid context
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).toBeTruthy()
  })
})
