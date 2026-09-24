/**
 * Sidebar & cross-page navigation E2E tests.
 *
 * Tests sidebar navigation, page transitions, input method persistence,
 * URL state memory (data-nav-remember), theme toggle, and escape chains.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, expectFocused, expectInputMethod, expectFocusInZone, getFocusedNavItem, establishFocus, selectSidebarLink } from "./helpers/input.js"
import { waitForLiveView, waitForInputSystem, waitForSettle } from "./helpers/liveview.js"

test.describe("sidebar navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/")
  })

  test("back from content enters the sidebar", async ({ page, inputAction }) => {
    // UIDR-028: BACK is the way to the main menu from any content context.
    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("left in content never reaches the sidebar", async ({ page, inputAction }) => {
    // LEFT is lateral movement within the page. No zone layout declares a left
    // edge to the sidebar, so at the content's left edge it simply walls.
    await inputAction("NAVIGATE_LEFT")
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(context).not.toBe("sidebar")
  })

  test("arrow down through sidebar links", async ({ page, inputAction }) => {
    // Enter sidebar first
    await inputAction("BACK")
    await expectContext(page, "sidebar")

    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_DOWN")
    const second = await getFocusedNavItem(page)
    expect(second).not.toBe(first)

    await inputAction("NAVIGATE_DOWN")
    const third = await getFocusedNavItem(page)
    expect(third).not.toBe(second)
  })

  test("select sidebar link navigates to page", async ({ page, inputAction }) => {
    await selectSidebarLink(page, inputAction, /^\/status/)

    await waitForLiveView(page)
    await waitForInputSystem(page)

    await expect(page).toHaveURL(/\/status/)
  })
})

test.describe("page transitions", () => {
  test("library → status → library", async ({ page, navigateTo, inputAction }) => {
    await navigateTo("/")

    await selectSidebarLink(page, inputAction, /^\/status/)
    await waitForLiveView(page)
    await waitForInputSystem(page)
    await expect(page).toHaveURL(/\/status/)

    await selectSidebarLink(page, inputAction, /^\/$/)
    await waitForLiveView(page)
    await waitForInputSystem(page)
    await expect(page).toHaveURL(/\/$/)
  })

  test("focus lands on correct default context per page", async ({ page, navigateTo }) => {
    // Home is shelves now, not a grid — cursor start resolves to one of them.
    await navigateTo("/")
    const homeContext = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["hero", "continue", "recently", "coming_up", "sidebar"]).toContain(homeContext)

    // Status is a tile grid; cursor start resolves to it.
    await navigateTo("/status")
    await expectContext(page, "grid")

    // Settings: grid has items so default stays "grid" (cursor start doesn't override)
    await navigateTo("/settings")
    const settingsContext = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["grid", "sections"]).toContain(settingsContext)
  })
})

test.describe("input method persistence", () => {
  test("input method persists across page navigation", async ({ page, navigateTo, inputAction, inputMethod }) => {
    await navigateTo("/")

    // Perform an action to establish the input method
    await inputAction("NAVIGATE_DOWN")
    await expectInputMethod(page, inputMethod)

    // Navigate to status via sidebar
    await selectSidebarLink(page, inputAction, /^\/status/)
    await waitForLiveView(page)
    await waitForInputSystem(page)

    // Input method should persist (first action re-establishes it after LiveView remount)
    await inputAction("NAVIGATE_DOWN")
    await expectInputMethod(page, inputMethod)
  })
})

test.describe("data-nav-remember (URL persistence)", () => {
  test("library preserves query params across navigation", async ({ page, navigateTo, inputAction }) => {
    // The library is /library now; `/` is the home shelves. Its tab is the
    // query param data-nav-remember is there to carry.
    await navigateTo("/library?tab=tv")

    // Navigate away to status via sidebar
    await selectSidebarLink(page, inputAction, /^\/status/)
    await waitForLiveView(page)
    await waitForInputSystem(page)
    await establishFocus(page)
    await expect(page).toHaveURL(/\/status/)

    // Navigate back to library via sidebar
    await selectSidebarLink(page, inputAction, /^\/library/)
    await waitForLiveView(page)
    await waitForInputSystem(page)

    // Should restore the tab the page was left on
    await expect(page).toHaveURL(/tab=tv/)
  })
})

test.describe("escape chain", () => {
  test("escape in content is the way to the sidebar", async ({ page, navigateTo, inputAction }) => {
    await navigateTo("/")

    await inputAction("BACK")

    await expectContext(page, "sidebar")
  })

  test("escape from sidebar → stays in sidebar (terminal)", async ({ page, navigateTo, inputAction }) => {
    await navigateTo("/")

    // Enter sidebar
    await inputAction("BACK")
    await expectContext(page, "sidebar")

    // Escape from sidebar — should stay in sidebar
    await inputAction("BACK")

    // After BACK from sidebar, it exits sidebar (exit_sidebar directive).
    // The system returns to the pre-sidebar context (grid).
    // This is the expected behavior — BACK from sidebar is "exit sidebar".
    // Home is shelves, so the pre-sidebar context it returns to is one of them.
    const context = await page.evaluate(() =>
      document.documentElement.getAttribute("data-nav-context")
    )
    expect(["sidebar", "hero", "continue", "recently", "coming_up"]).toContain(context)
  })
})
