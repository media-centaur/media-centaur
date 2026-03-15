/**
 * Review page E2E tests.
 *
 * Tests the master-detail navigation pattern: review list ↔ detail panel,
 * focus memory, and escape chains.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedNavItem, getZoneItemCount } from "./helpers/input.js"
import { waitForSettle } from "./helpers/liveview.js"

test.describe("review navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/review")
  })

  test("initial focus on review list or sidebar", async ({ page }) => {
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    // If review list has items, focus goes there; otherwise sidebar
    expect(["review-list", "sidebar"]).toContain(context)
  })

  test("down/up through review list items", async ({ page, inputAction }) => {
    const listCount = await getZoneItemCount(page, "review-list")
    if (listCount < 2) {
      test.skip()
      return
    }

    await expectContext(page, "review-list")

    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_DOWN")
    const second = await getFocusedNavItem(page)
    expect(second).not.toBe(first)

    await inputAction("NAVIGATE_UP")
    const backToFirst = await getFocusedNavItem(page)
    expect(backToFirst).toBe(first)
  })

  test("right from list → detail panel", async ({ page, inputAction }) => {
    const listCount = await getZoneItemCount(page, "review-list")
    const detailCount = await getZoneItemCount(page, "review-detail")
    if (listCount === 0 || detailCount === 0) {
      test.skip()
      return
    }

    await expectContext(page, "review-list")
    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "review-detail")
  })

  test("down/up through detail panel buttons", async ({ page, inputAction }) => {
    const listCount = await getZoneItemCount(page, "review-list")
    const detailCount = await getZoneItemCount(page, "review-detail")
    if (listCount === 0 || detailCount < 2) {
      test.skip()
      return
    }

    // Navigate into detail
    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "review-detail")

    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_DOWN")
    const second = await getFocusedNavItem(page)
    expect(second).not.toBe(first)
  })

  test("left from detail → list (focus memory)", async ({ page, inputAction }) => {
    const listCount = await getZoneItemCount(page, "review-list")
    const detailCount = await getZoneItemCount(page, "review-detail")
    if (listCount < 2 || detailCount === 0) {
      test.skip()
      return
    }

    // Navigate to second list item
    await inputAction("NAVIGATE_DOWN")
    const listItem = await getFocusedNavItem(page)

    // Enter detail
    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "review-detail")

    // Return to list
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "review-list")

    // Same list item should be focused
    const restored = await getFocusedNavItem(page)
    expect(restored).toBe(listItem)
  })

  test("escape from review → sidebar", async ({ page, inputAction }) => {
    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("left from list → sidebar", async ({ page, inputAction }) => {
    const listCount = await getZoneItemCount(page, "review-list")
    if (listCount === 0) {
      test.skip()
      return
    }

    await expectContext(page, "review-list")
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })
})
