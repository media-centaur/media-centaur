/**
 * Review → Identity, the bulk list (UIDR-058), driven by keyboard and gamepad.
 *
 * Runs against the E2E instance's seeded review scenarios
 * (`MediaCentaur.Showcase.ReviewScenarios`): seventeen waiting rows under
 * their title dividers, one dismissed. The rows are the cursor start;
 * ticking rows brings up the match bar, whose search results sit to the
 * right of the rows and below the bar.
 *
 * Nothing here presses a result or Dismiss: the instance's state is shared
 * by every test in the run.
 */
import { test, expect } from "./fixtures/input-method.js"
import { expectContext, getFocusedNavItem, getZoneItemCount } from "./helpers/input.js"
import { waitForReviewItems } from "./helpers/liveview.js"

// The focused element's visible text, for finding a row by what it says.
async function focusedText(page) {
  return page.evaluate(() => document.activeElement?.textContent?.replace(/\s+/g, " ").trim() ?? "")
}

// Walks down the rows until the focused one reads `text`.
async function walkToRow(page, inputAction, text) {
  const rows = await getZoneItemCount(page, "review-rows")
  for (let step = 0; step < rows; step++) {
    if ((await focusedText(page)).includes(text)) return
    await inputAction("NAVIGATE_DOWN")
  }
  throw new Error(`no review row reads ${JSON.stringify(text)}`)
}

test.describe("review navigation", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/review")
    await waitForReviewItems(page, { min: 17 })
  })

  test("the page opens on the rows", async ({ page }) => {
    await expectContext(page, "review-rows")
  })

  test("down and up walk the rows", async ({ page, inputAction }) => {
    const first = await getFocusedNavItem(page)
    await inputAction("NAVIGATE_DOWN")
    const second = await getFocusedNavItem(page)
    expect(second).not.toBe(first)

    await inputAction("NAVIGATE_UP")
    expect(await getFocusedNavItem(page)).toBe(first)
  })

  test("up from the first row reaches the toolbar", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_UP")
    await expectContext(page, "review-toolbar")
  })

  test("ticking a title's divider brings up the match bar and its search", async ({ page, inputAction }) => {
    await walkToRow(page, inputAction, "Sample Show 6 files")
    await inputAction("SELECT")

    // One press ticks the six episodes beneath the divider; the bar searches
    // their title and finds the show.
    await expect(page.locator("[data-nav-zone='review-results'] [data-nav-item]").first()).toContainText(
      "The Sample Show Hour",
    )
    await expectContext(page, "review-rows")

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "review-results")

    await inputAction("NAVIGATE_UP")
    await expectContext(page, "review-bar")
  })

  test("back from the bar or its results returns to the rows", async ({ page, inputAction }) => {
    await walkToRow(page, inputAction, "Sample Show 6 files")
    const divider = await getFocusedNavItem(page)
    await inputAction("SELECT")
    await expect(page.locator("[data-nav-zone='review-results'] [data-nav-item]").first()).toBeVisible()

    await inputAction("NAVIGATE_RIGHT")
    await expectContext(page, "review-results")
    await inputAction("BACK")
    await expectContext(page, "review-rows")
    expect(await getFocusedNavItem(page)).toBe(divider)

    // UP from the results lands on the bar's search box. Escape on a
    // non-empty input clears it before it means BACK (docs/input-system.md
    // § Text Input Handling), so step onto the bar's next control first.
    await inputAction("NAVIGATE_RIGHT")
    await inputAction("NAVIGATE_UP")
    await expectContext(page, "review-bar")
    await inputAction("NAVIGATE_RIGHT")
    await inputAction("BACK")
    await expectContext(page, "review-rows")
  })

  test("back from the rows enters the sidebar", async ({ page, inputAction }) => {
    // UIDR-028: BACK is the way to the main menu from any content context.
    await inputAction("BACK")
    await expectContext(page, "sidebar")
  })

  test("left from the rows never reaches the sidebar", async ({ page, inputAction }) => {
    await inputAction("NAVIGATE_LEFT")
    const context = await page.evaluate(() => document.documentElement.getAttribute("data-nav-context"))
    expect(context).not.toBe("sidebar")
  })
})
