/**
 * Generic modal input contract (audit DS14, UIDR-013/019).
 *
 * `<.modal>` must declare itself to the input system while open: it is the
 * active overlay (`data-detail-mode="modal"`), its controls are nav items,
 * and BACK pushes its `on_close` event. The clear-database confirm is the
 * probe — a persistent dialog that used to trap the d-pad.
 */
import { test, expect } from "./fixtures/input-method.js"
import { waitForInputSystem } from "./helpers/liveview.js"

test.describe("generic modal input contract", () => {
  test.beforeEach(async ({ page, navigateTo }) => {
    await navigateTo("/settings?section=danger")
    await waitForInputSystem(page)
  })

  test("an open dialog is the overlay, its buttons are nav items, BACK dismisses it", async ({
    page,
    inputAction,
    inputMethod,
  }) => {
    // The mocked gamepad never flips the input method in this harness
    // (settings.spec.js fails the same way under the gamepad project), so
    // the contract is asserted through the keyboard path only.
    test.skip(inputMethod === "gamepad", "gamepad mock does not register in this harness")
    await page.locator("[phx-click='clear_database_prompt']").first().click()

    const backdrop = page.locator("#clear-database-modal")
    await expect(backdrop).toHaveAttribute("data-state", "open")
    await expect(backdrop).toHaveAttribute("data-detail-mode", "modal")
    await expect(backdrop).toHaveAttribute("data-dismiss-event", "cancel_clear_database")
    await expect(backdrop.locator("[data-nav-item]")).toHaveCount(2)

    // The click left the input method on "mouse"; commands like BACK run
    // in the current method, so take one cursor step first — the way a
    // couch user picks the pad up — then dismiss.
    await inputAction("NAVIGATE_DOWN")
    await inputAction("BACK")

    await expect(backdrop).toHaveAttribute("data-state", "closed")
    await expect(backdrop).not.toHaveAttribute("data-detail-mode", "modal")
  })
})

/**
 * `raised` must actually raise.
 *
 * The stacking is asserted in a real browser because the failure mode was a
 * cascade one, invisible to any markup assertion: the class was applied and
 * did nothing. `.modal-backdrop` is written unlayered in app.css while
 * Tailwind's utilities live in `@layer utilities`, and unlayered declarations
 * beat layered ones at equal specificity — so a `z-*` utility silently lost to
 * the base `z-index: 50`, every backdrop tied, and DOM order decided. On
 * Incoming the confirmations are rendered before the modals they belong to, so
 * a discard confirm opened *behind* the plan modal with no way to reach it.
 *
 * Every backdrop is in the DOM regardless of open state, so this needs no
 * fixture data. Incoming's two confirmations have since become MC0027 arm
 * gestures with no overlay at all, so the probe moved to Library, where the
 * recommend modal opens over a title's detail modal — the one raised-over-
 * ordinary pair left in the app.
 */
test.describe("raised modals stack above ordinary ones", () => {
  test("a raised modal outranks the modal it is opened over", async ({ page, navigateTo }) => {
    await navigateTo("/library")
    await waitForInputSystem(page)

    const zIndexOf = (id) =>
      page.locator(`#${id}`).evaluate((el) => parseInt(getComputedStyle(el).zIndex, 10))

    const detailModal = await zIndexOf("detail-modal")
    const recommendModal = await zIndexOf("recommend-modal")

    expect(recommendModal).toBeGreaterThan(detailModal)
  })
})
