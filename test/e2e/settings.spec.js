/**
 * Settings page E2E tests.
 *
 * Tests the activate-on-focus behavior (unique to settings), section ↔ grid
 * transitions, and escape chains.
 *
 * Note: The settings page may start with context "grid" (not "sections")
 * because the cursor start priority only overrides when the default context
 * is empty, and the settings grid has items.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedNavItem, getZoneItemCount, establishFocus } from "./helpers/input.js"
import { waitForSections, waitForSettle } from "./helpers/liveview.js"

test.describe("settings navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/settings")
  })

  test("sections are navigable", async ({ page, inputAction }) => {
    // Settings may start on grid or sections depending on content.
    // Navigate to sections explicitly.
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
    }

    await waitForSections(page)
    await expectContext(page, "sections")
    await expectFocusInZone(page, "sections")
  })

  test("activate-on-focus updates content panel", async ({ page, inputAction }) => {
    // Navigate to sections
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
      await expectContext(page, "sections")
    }
    await waitForSections(page)

    const firstSection = await getFocusedNavItem(page)

    // Navigate down to next section — content should update automatically
    await inputAction("NAVIGATE_DOWN")
    await waitForSettle(page, 200)

    const secondSection = await getFocusedNavItem(page)
    expect(secondSection).not.toBe(firstSection)

    // Sections context should still be active
    await expectContext(page, "sections")
  })

  test("right from sections → grid content area", async ({ page, inputAction }) => {
    // Navigate to sections first
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
    }
    await waitForSections(page)

    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount > 0) {
      await inputAction("NAVIGATE_RIGHT")
      await expectContext(page, "grid")
    }
  })

  test("left from grid → sections (same section focused)", async ({ page, inputAction }) => {
    // Ensure we're on grid
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context === "sections") {
      const gridCount = await getZoneItemCount(page, "grid")
      if (gridCount === 0) { test.skip(); return }
      await inputAction("NAVIGATE_RIGHT")
    }
    await expectContext(page, "grid")

    // Navigate to sections
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sections")

    // Navigate to second section
    await inputAction("NAVIGATE_DOWN")
    const sectionBefore = await getFocusedNavItem(page)

    // Enter grid
    const gridCount = await getZoneItemCount(page, "grid")
    if (gridCount > 0) {
      await inputAction("NAVIGATE_RIGHT")
      await expectContext(page, "grid")

      // Return to sections
      await inputAction("NAVIGATE_LEFT")
      await expectContext(page, "sections")

      // Same section should be focused (focus memory)
      const sectionAfter = await getFocusedNavItem(page)
      expect(sectionAfter).toBe(sectionBefore)
    }
  })

  test("escape from grid → sections or sidebar", async ({ page, inputAction }) => {
    // Ensure we're on grid
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context === "sections") {
      const gridCount = await getZoneItemCount(page, "grid")
      if (gridCount === 0) { test.skip(); return }
      await inputAction("NAVIGATE_RIGHT")
    }
    await expectContext(page, "grid")

    // Escape — settings behavior onEscape returns "sections"
    await inputAction("BACK")
    const afterContext = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["sidebar", "sections"]).toContain(afterContext)
  })

  test("left from sections → sidebar", async ({ page, inputAction }) => {
    // Navigate to sections
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
    }
    await expectContext(page, "sections")

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("escape from sections → sidebar", async ({ page, inputAction }) => {
    // Navigate to sections
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
    }
    await expectContext(page, "sections")

    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })
})
