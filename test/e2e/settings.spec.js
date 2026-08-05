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

  test("escape in grid is a no-op; left returns to sections", async ({ page, inputAction }) => {
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

    // BACK does nothing in content
    await inputAction("BACK")
    await expectContext(page, "grid")

    // Left at the grid's left edge returns to sections
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sections")
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

  test("escape in sections is a no-op — left is the way to the sidebar", async ({ page, inputAction }) => {
    // Navigate to sections
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    if (context !== "sections") {
      await inputAction("NAVIGATE_LEFT")
    }
    await expectContext(page, "sections")

    await inputAction("BACK")
    await expectContext(page, "sections")
  })
})

test.describe("interface scale picker", () => {
  // Regression guard. `phx-value-value` collided with the <button> native
  // `value` property, so clicking the scale picker sent %{"value" => ""} and
  // silently did nothing. A `render_click/3` LiveViewTest can't catch this —
  // it reads the attribute off the DOM and never simulates the browser's
  // native-value merge. Only a real click can. (The author-time side is
  // guarded by Credo MC0021 NoPhxValueValue; this guards the behaviour.)
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/settings?section=preferences")
  })

  test.afterEach(async ({ page }) => {
    // Leave the shared instance at 100% so a stuck scale doesn't zoom the
    // rest of the suite.
    await page.getByRole("button", { name: "100%", exact: true }).click()
    // parseFloat: the value is "1.0" when server-rendered but "1" after the
    // pushed event's JSON number goes through setProperty.
    await expect
      .poll(() =>
        page.evaluate(() =>
          parseFloat(
            document.documentElement.style.getPropertyValue("--ui-scale-pref"),
          ),
        ),
      )
      .toBe(1)
  })

  test("clicking a scale actually rescales the shell", async ({ page }) => {
    await page.getByRole("button", { name: "100%", exact: true }).waitFor()

    await page.getByRole("button", { name: "125%", exact: true }).click()

    // The click lands as the preference factor on <html>…
    await expect
      .poll(() =>
        page.evaluate(() =>
          parseFloat(
            document.documentElement.style.getPropertyValue("--ui-scale-pref"),
          ),
        ),
      )
      .toBe(1.25)

    // …and the effective scale the shell zooms by is auto × preference
    // (both registered `<number>` properties, so computed style resolves
    // the calc to a plain number).
    const { auto, effective } = await page.evaluate(() => {
      const styles = getComputedStyle(document.documentElement)
      return {
        auto: parseFloat(styles.getPropertyValue("--auto-scale")),
        effective: parseFloat(styles.getPropertyValue("--ui-scale")),
      }
    })
    expect(effective).toBeCloseTo(auto * 1.25, 5)

    // And the picker reflects the now-active option.
    await expect(
      page.locator('button[phx-click="set_ui_scale"][aria-pressed="true"]'),
    ).toHaveText("125%")
  })

  test("auto scale tracks the screen against the 1920px reference width", async ({
    page,
  }) => {
    // The head script derives --auto-scale from screen.width (CSS px) over
    // the 1920 reference, floored at 0.7 — no user input involved.
    const { screenWidth, auto } = await page.evaluate(() => ({
      screenWidth: screen.width,
      auto: parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue(
          "--auto-scale",
        ),
      ),
    }))
    const expected = Math.max(0.7, screenWidth / 1920)
    expect(auto).toBeCloseTo(expected, 3)
  })
})
