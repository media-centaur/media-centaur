/**
 * Status page E2E tests.
 *
 * The page is three zones: a `toolbar` above a `grid` of health tiles, with
 * the `sidebar` as the main menu. It used to be a vertical `sections` list,
 * and these tests used to assert LEFT as the way to the sidebar — both were
 * true once. Per UIDR-028 LEFT is lateral movement that never reaches the main
 * menu, and BACK is the way there from any content context.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedIndex } from "./helpers/input.js"
import { waitForGridItems } from "./helpers/liveview.js"

test.describe("status navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/status")
  })

  test("initial focus lands in the tile grid", async ({ page }) => {
    await waitForGridItems(page)
    await expectContext(page, "grid")
    await expectFocusInZone(page, "grid")
  })

  test("down/up navigates the tile grid", async ({ page, inputAction }) => {
    await waitForGridItems(page)

    const firstIndex = await getFocusedIndex(page)

    await inputAction("NAVIGATE_DOWN")
    const secondIndex = await getFocusedIndex(page)
    expect(secondIndex).toBeGreaterThan(firstIndex)

    await inputAction("NAVIGATE_UP")
    const backIndex = await getFocusedIndex(page)
    expect(backIndex).toBe(firstIndex)
  })

  test("back from the grid enters the sidebar", async ({ page, inputAction }) => {
    await waitForGridItems(page)

    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("left at the grid's left edge stays in the grid", async ({ page, inputAction }) => {
    // UIDR-028: no zone layout declares a left edge to the sidebar, so LEFT
    // walls at the content's edge rather than escaping the page.
    await waitForGridItems(page)

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "grid")
  })

  test("right from the sidebar returns to the grid", async ({ page, inputAction }) => {
    await waitForGridItems(page)

    await inputAction("BACK")
    await expectContext(page, "sidebar")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "grid")
  })

  test("up from the grid's top row reaches the toolbar", async ({ page, inputAction }) => {
    await waitForGridItems(page)

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "toolbar")
  })
})
