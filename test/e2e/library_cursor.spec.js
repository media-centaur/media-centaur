/**
 * Library grid cursor (audit DS4, UIDR-020).
 *
 * daisyUI's `.card` carries a 2px transparent outline, and keyboard/gamepad
 * mode pre-sets `outline-color` on every nav item — which used to paint a
 * permanent primary edge on every poster, leaving the focused card's ring
 * indistinguishable. Only the focused card may draw an outline.
 */
import { test, expect } from "./fixtures/input-method.js"
import { establishFocus } from "./helpers/input.js"
import { waitForInputSystem } from "./helpers/liveview.js"

const outlineWidths = (page) =>
  page.evaluate(() =>
    [...document.querySelectorAll("[data-nav-zone='grid'] [data-nav-item]")].map((card) => ({
      focused: document.activeElement === card,
      outlineWidth: getComputedStyle(card).outlineWidth,
    }))
  )

test.describe("library grid cursor", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/library")
    await waitForInputSystem(page)
  })

  test("only the focused poster card draws an outline", async ({ page }) => {
    const gridCount = await page.locator("[data-nav-zone='grid'] [data-nav-item]").count()
    test.skip(gridCount < 2, "needs at least two library entries")

    // The library opens in the grid context; make sure the cursor sits on a card.
    await establishFocus(page)
    await expect
      .poll(async () => (await outlineWidths(page)).some((c) => c.focused))
      .toBe(true)

    const cards = await outlineWidths(page)
    const focused = cards.filter((c) => c.focused)
    const unfocused = cards.filter((c) => !c.focused)

    // The ring is 2px before the interface scale factor; assert the shape
    // (drawn vs. not drawn), not the scaled pixel value.
    expect(focused).toHaveLength(1)
    expect(parseFloat(focused[0].outlineWidth)).toBeGreaterThan(0)
    expect(unfocused.length).toBeGreaterThan(0)
    for (const card of unfocused) expect(card.outlineWidth).toBe("0px")
  })
})
