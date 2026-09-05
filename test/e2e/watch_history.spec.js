/**
 * Watch History page E2E tests.
 *
 * Covers initial focus placement, the toolbar ↔ grid transitions, and
 * BACK into the sidebar (UIDR-028: LEFT stays in the page). The heatmap
 * SVG rects stay mouse-only by design — keyboard users filter via the
 * pill row.
 */
import { test, expect } from "./fixtures/input-method.js"
import {
  expectContext,
  expectFocusInZone,
  getFocusedIndex,
  getZoneItemCount,
} from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

/** Put the cursor in the toolbar whichever context the page started in. */
async function enterToolbar(page, inputAction) {
  const gridCount = await getZoneItemCount(page, "grid")
  if (gridCount > 0) await inputAction("NAVIGATE_UP")
  await expectContext(page, "toolbar")
}

test.describe("watch history navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/history")
    await waitForInputSystem(page)
  })

  test("initial focus lands in the grid when events are present, else in the toolbar", async ({ page }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    const zone = gridCount > 0 ? "grid" : "toolbar"
    await expectContext(page, zone)
    await expectFocusInZone(page, zone)
  })

  test("up from the grid enters the toolbar", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no watch-history events in this environment")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")
    await expectFocusInZone(page, "toolbar")
  })

  test("down from the toolbar returns to the grid", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no watch-history events in this environment")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")
  })

  test("left at the toolbar's first pill is a wall; BACK enters the sidebar", async ({ page, inputAction }) => {
    await enterToolbar(page, inputAction)

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "toolbar")

    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("right from the sidebar returns to the toolbar", async ({ page, inputAction }) => {
    await enterToolbar(page, inputAction)

    await inputAction("BACK")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "toolbar")
  })

  test("filter pills advance focus left→right within the toolbar", async ({
    page,
    inputAction,
  }) => {
    await enterToolbar(page, inputAction)
    const startIndex = await getFocusedIndex(page)

    await inputAction("NAVIGATE_RIGHT")
    const nextIndex = await getFocusedIndex(page)
    expect(nextIndex).toBeGreaterThan(startIndex)
  })
})
