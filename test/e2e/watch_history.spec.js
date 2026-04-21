/**
 * Watch History page E2E tests.
 *
 * Covers the toolbar ↔ grid transitions, initial focus placement, and
 * BACK to sidebar. The heatmap SVG rects stay mouse-only by design —
 * keyboard users filter via the pill row.
 */
import { test, expect } from "./fixtures/input-method.js"
import {
  expectContext,
  expectFocusInZone,
  getFocusedIndex,
  getZoneItemCount,
} from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

test.describe("watch history navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/watch-history")
    await waitForInputSystem(page)
  })

  test("initial focus lands in the toolbar", async ({ page }) => {
    await expectContext(page, "toolbar")
    await expectFocusInZone(page, "toolbar")
  })

  test("down from toolbar enters the grid when events are present", async ({
    page,
    inputAction,
  }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no watch-history events in this environment")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")
    await expectFocusInZone(page, "grid")
  })

  test("up from grid returns to the toolbar", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no watch-history events in this environment")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")
  })

  test("left from toolbar → sidebar", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("escape from toolbar → sidebar", async ({ page, inputAction }) => {
    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("right from sidebar returns to the toolbar", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "toolbar")
  })

  test("filter pills advance focus left→right within the toolbar", async ({
    page,
    inputAction,
  }) => {
    const startIndex = await getFocusedIndex(page)

    await inputAction("NAVIGATE_RIGHT")
    const nextIndex = await getFocusedIndex(page)
    expect(nextIndex).toBeGreaterThan(startIndex)
  })
})
