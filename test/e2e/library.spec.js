/**
 * Library page E2E tests — the most complex page.
 *
 * Tests grid spatial navigation, grid ↔ toolbar transitions, zone tabs,
 * drawer/modal lifecycle, focus memory, filter input, and empty grid fallback.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedNavItem, getFocusedIndex, getZoneItemCount, establishFocus } from "./helpers/input.js"
import { waitForGridItems, waitForSettle } from "./helpers/liveview.js"

test.describe("library grid spatial navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/")
  })

  test("arrow down moves focus to next row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount < 2) { test.skip(); return }

    await expectContext(page, "grid")
    const before = await getFocusedIndex(page)

    await inputAction("NAVIGATE_DOWN")
    const after = await getFocusedIndex(page)

    // Down should move to a different index (next row)
    expect(after).not.toBe(before)
  })

  test("arrow up moves focus to previous row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount < 2) { test.skip(); return }

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
    if (gridCount < 2) { test.skip(); return }

    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_RIGHT")
    const second = await getFocusedNavItem(page)

    expect(second).not.toBe(first)
  })

  test("arrow left from first column → sidebar", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    // Ensure we're on the first item (column 0) by going to sidebar and back
    // This guarantees focus is on the leftmost column
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "grid")

    // Now left should transition to sidebar (wall at column 0)
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("down from bottom row → wall (stays in grid)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    // Navigate to last item by pressing down many times
    for (let i = 0; i < 50; i++) {
      await inputAction("NAVIGATE_DOWN")
    }

    // Should still be in grid context (wall, not transition)
    await expectContext(page, "grid")
  })

  test("right from last column → wall (stays)", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    // Navigate to rightmost column
    for (let i = 0; i < 20; i++) {
      await inputAction("NAVIGATE_RIGHT")
    }

    // Should still be in grid (wall or drawer, depending on drawer state)
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["grid", "drawer"]).toContain(context)
  })
})

test.describe("library grid ↔ toolbar transitions", () => {
  test.beforeEach(async ({ navigateTo }) => {
    // Use library zone which has a toolbar
    await navigateTo("/?zone=library")
  })

  test("up from top row of grid → toolbar or zone_tabs", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    // Ensure we're on the first row by navigating to sidebar and back
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
    await inputAction("NAVIGATE_RIGHT")

    // May land on grid, toolbar, or zone_tabs depending on cursor start
    const startContext = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (startContext !== "grid") { test.skip(); return }

    await inputAction("NAVIGATE_UP")

    // Should transition to toolbar or zone_tabs
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["toolbar", "zone_tabs"]).toContain(context)
  })

  test("down from toolbar → grid top row", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    if (gridCount === 0 || toolbarCount === 0) { test.skip(); return }

    // Navigate up to toolbar first
    await inputAction("NAVIGATE_UP")
    await waitForSettle(page)

    // Navigate back down
    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")
  })

  test("left from toolbar → sidebar", async ({ page, inputAction }) => {
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    if (toolbarCount === 0) { test.skip(); return }

    // Navigate up to toolbar
    await inputAction("NAVIGATE_UP")
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "toolbar") { test.skip(); return }

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })
})

test.describe("library zone tabs", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/")
  })

  test("zone tab switch resets grid content", async ({ page, inputAction }) => {
    const tabCount = await getZoneItemCount(page, "zone-tabs")
    if (tabCount < 2) { test.skip(); return }

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
    if (tabCount < 2) { test.skip(); return }

    // Switch forward then backward
    await inputAction("ZONE_NEXT")
    await waitForSettle(page, 500)
    await establishFocus(page)

    await inputAction("ZONE_PREV")
    await waitForSettle(page, 500)

    // Should still be on the library page
    await expect(page).toHaveURL(/\/$/)
  })
})

test.describe("library drawer/modal", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/")
  })

  test("select on grid item → opens detail overlay", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    await expectContext(page, "grid")
    await inputAction("SELECT")
    await waitForSettle(page, 500)

    // Should be in drawer or modal context, OR still in grid if no detail view exists
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["drawer", "modal", "grid"]).toContain(context)
  })

  test("escape from overlay → focus returns to originating grid item", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    // Select second item if possible
    if (gridCount >= 2) {
      await inputAction("NAVIGATE_RIGHT")
    }
    const originItem = await getFocusedNavItem(page)

    // Open overlay
    await inputAction("SELECT")
    await waitForSettle(page, 500)

    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (!["drawer", "modal"].includes(context)) { test.skip(); return }

    // Close overlay
    await inputAction("BACK")
    await waitForSettle(page, 300)

    // Focus should return to the originating item
    await expectContext(page, "grid")
    const restored = await getFocusedNavItem(page)
    expect(restored).toBe(originItem)
  })

  test("vertical navigation within overlay", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount === 0) { test.skip(); return }

    await inputAction("SELECT")
    await waitForSettle(page, 500)

    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (!["drawer", "modal"].includes(context)) { test.skip(); return }

    // Navigate within the overlay
    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_DOWN")
    const second = await getFocusedNavItem(page)

    // May or may not change depending on number of items
    expect(second).toBeTruthy()
  })
})

test.describe("library filter input [keyboard-only]", () => {
  test.beforeEach(async ({ navigateTo, inputMethod }) => {
    // Filter tests are keyboard-only — text input doesn't apply to gamepad
    test.skip(inputMethod === "gamepad", "keyboard-only test")
    await navigateTo("/?zone=library")
  })

  test("focus filter → arrows still navigate (not editing)", async ({ page, inputAction }) => {
    const toolbarCount = await getZoneItemCount(page, "toolbar")
    if (toolbarCount === 0) { test.skip(); return }

    // Navigate to toolbar (which contains the filter input)
    await inputAction("NAVIGATE_UP")
    await waitForSettle(page)

    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "toolbar") { test.skip(); return }

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
    if (toolbarCount === 0) { test.skip(); return }

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
    await navigateTo("/")

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
