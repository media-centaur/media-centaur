/**
 * Download (Acquisition) page E2E tests.
 *
 * Covers the sections ↔ grid transitions, initial focus placement, and
 * BACK to sidebar. The grid-side tests skip when no search results are
 * present, since the acquisition page only populates the results zone
 * after a user-triggered search.
 */
import { test, expect } from "./fixtures/input-method.js"
import {
  expectContext,
  expectFocusInZone,
  getFocusedIndex,
  getZoneItemCount,
} from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

test.describe("download navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/download")
    await waitForInputSystem(page)
  })

  test("initial focus lands in the sections zone", async ({ page }) => {
    await expectContext(page, "sections")
    await expectFocusInZone(page, "sections")
  })

  test("right advances focus within the sections form", async ({ page, inputAction }) => {
    const startIndex = await getFocusedIndex(page)

    await inputAction("NAVIGATE_RIGHT")
    const nextIndex = await getFocusedIndex(page)
    expect(nextIndex).toBeGreaterThan(startIndex)
  })

  test("down from sections enters the grid when results are present", async ({
    page,
    inputAction,
  }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no search results in this environment")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")
    await expectFocusInZone(page, "grid")
  })

  test("up from grid returns to the sections", async ({ page, inputAction }) => {
    const gridCount = await getZoneItemCount(page, "grid")
    test.skip(gridCount === 0, "no search results in this environment")

    await inputAction("NAVIGATE_DOWN")
    await expectContext(page, "grid")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "sections")
  })

  test("left from sections → sidebar", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("escape from sections → sidebar", async ({ page, inputAction }) => {
    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("right from sidebar returns to the sections", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "sections")
  })
})
