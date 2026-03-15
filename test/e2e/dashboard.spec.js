/**
 * Dashboard page E2E tests.
 *
 * Tests sequential section card navigation, sidebar transitions,
 * escape behavior, and initial focus placement.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocusInZone, getFocusedNavItem, getFocusedIndex } from "./helpers/input.js"
import { waitForSections } from "./helpers/liveview.js"

test.describe("dashboard navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/dashboard")
  })

  test("initial focus lands on first section card", async ({ page }) => {
    await expectContext(page, "sections")
    await waitForSections(page)
    await expectFocusInZone(page, "sections")
  })

  test("down/up navigates through section cards", async ({ page, inputAction }) => {
    await waitForSections(page)

    const firstIndex = await getFocusedIndex(page)

    await inputAction("NAVIGATE_DOWN")
    const secondIndex = await getFocusedIndex(page)
    expect(secondIndex).toBeGreaterThan(firstIndex)

    await inputAction("NAVIGATE_UP")
    const backIndex = await getFocusedIndex(page)
    expect(backIndex).toBe(firstIndex)
  })

  test("left from sections → sidebar", async ({ page, inputAction }) => {
    await waitForSections(page)

    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("escape from sections → sidebar", async ({ page, inputAction }) => {
    await waitForSections(page)

    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("right from sidebar → sections", async ({ page, inputAction }) => {
    await waitForSections(page)

    // Enter sidebar
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")

    // Exit sidebar to content
    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "sections")
  })
})
