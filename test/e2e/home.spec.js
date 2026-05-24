/**
 * Home page (`/`) E2E tests.
 *
 * The home page is a vertical stack of horizontal SHELF zones (hero +
 * Continue Watching / Recently Added / Coming Up rows). Up/Down crosses
 * between shelves, Left/Right navigates within a shelf, Left-wall enters the
 * sidebar, and SELECT opens the detail modal (BACK restores focus to the
 * originating card).
 *
 * Content is data-dependent — tests that need a populated shelf detect it
 * and skip when the dev library is empty, mirroring library/settings specs.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, getZoneItemCount, getFocusedNavItem } from "./helpers/input.js"
import { waitForInputSystem, waitForSettle } from "./helpers/liveview.js"

const SHELVES = ["hero", "continue", "recently", "coming_up"]

async function navContext(page) {
  return page.evaluate(() => document.documentElement.getAttribute("data-nav-context"))
}

async function populatedShelves(page) {
  const found = []
  for (const zone of SHELVES) {
    if ((await getZoneItemCount(page, zone)) > 0) found.push(zone)
  }
  return found
}

// Shelves populate after the LiveView connects and loads data, a beat after
// the input hook sets data-nav-context. Wait for both.
async function waitForHome(page) {
  await waitForInputSystem(page)
  await page
    .waitForFunction(
      () => !!document.querySelector("[data-nav-zone] [data-nav-item]"),
      { timeout: 8000 },
    )
    .catch(() => {})
  await waitForSettle(page, 200)
}

test.describe("home navigation", () => {
  test.beforeEach(async ({ navigateTo }) => {
    await navigateTo("/")
  })

  test("lands in a focusable shelf context, never the empty grid", async ({ page }) => {
    await waitForHome(page)
    // Regression guard for the start() onAttach crash: the home page has no
    // grid, so cursor-start must resolve to a populated shelf. The bug left
    // the page stuck in the empty GRID context with no focusable item.
    const context = await navContext(page)
    expect(context).not.toBe("grid")

    if ((await populatedShelves(page)).length > 0) {
      expect(SHELVES).toContain(context)
    }
  })

  test("down crosses to the next shelf", async ({ page, inputAction }) => {
    await waitForHome(page)
    if ((await populatedShelves(page)).length < 2) {
      test.skip()
      return
    }

    const before = await navContext(page)
    await inputAction("NAVIGATE_DOWN")
    await waitForSettle(page, 150)
    const after = await navContext(page)

    expect(after).not.toBe(before)
    expect(SHELVES).toContain(after)
  })

  test("right navigates within a shelf without changing context", async ({ page, inputAction }) => {
    await waitForHome(page)
    const context = await navContext(page)
    if (!SHELVES.includes(context) || (await getZoneItemCount(page, context)) < 2) {
      test.skip()
      return
    }

    const before = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_RIGHT")
    await waitForSettle(page, 120)

    expect(await navContext(page)).toBe(context)
    expect(await getFocusedNavItem(page)).not.toBe(before)
  })

  test("left at the start of a shelf enters the sidebar", async ({ page, inputAction }) => {
    await waitForHome(page)
    if (!SHELVES.includes(await navContext(page))) {
      test.skip()
      return
    }

    // Cursor-start focuses the first item, so LEFT is at the row's left wall.
    await inputAction("NAVIGATE_LEFT")
    await expectContext(page, "sidebar")
  })

  test("select opens the detail modal and back restores the shelf", async ({ page, inputAction }) => {
    await waitForHome(page)
    let context = await navContext(page)
    if (!SHELVES.includes(context)) {
      test.skip()
      return
    }

    // Avoid the hero's Play (autoplay) button — drop to a content shelf if
    // possible so SELECT just opens the modal.
    if (context === "hero" && (await populatedShelves(page)).length > 1) {
      await inputAction("NAVIGATE_DOWN")
      await waitForSettle(page, 150)
      context = await navContext(page)
    }
    if (context === "hero") {
      test.skip()
      return
    }

    await inputAction("SELECT")
    await expectContext(page, "modal")

    await inputAction("BACK")
    await waitForSettle(page, 300)
    expect(SHELVES).toContain(await navContext(page))
  })
})
