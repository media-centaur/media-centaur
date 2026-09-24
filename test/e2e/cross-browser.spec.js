/**
 * Cross-browser smoke.
 *
 * Equal support, not equal verification. The navigation suite runs in Chromium
 * only — mirroring it across browsers would double its cost forever to catch a
 * rare class of bug. This narrow spec covers the features whose support
 * actually differs, and Chromium runs it too as the control: an assertion that
 * only ever runs where it passes is not a test.
 *
 * An audit of what the frontend uses put its effective Firefox floor at ~128
 * (`@property`); `oklch`, `color-mix`, `@container`, `:has()`, `backdrop-filter`,
 * `checkVisibility`, `<dialog>` and `inert` are all comfortably inside range.
 * Exactly one feature is not: CSS scroll-driven animations, which Firefox still
 * ships behind `layout.css.scroll-driven-animations.enabled`.
 *
 * See docs/plans/2026-09-24-firefox-parity-and-controller-layout.md.
 */
import { test, expect } from "@playwright/test"
import { waitForLiveView, waitForInputSystem } from "./helpers/liveview.js"

const GRID_CARD = '[data-nav-zone="grid"] [data-entity-id][phx-click="select_entity"]'

/**
 * Open the first library card's detail modal.
 *
 * Deliberately an element-level click rather than a pointer one. A poster
 * card's centre is covered by its own play overlay, and a pointer click there
 * starts playback — which on a real instance launches mpv. Two independent
 * hazards also sit on the geometric path: the sidebar is a 52px rail that
 * expands to 200px on hover and overlays the grid's first column, and a
 * browser's virtual pointer starts at (0, 0), inside that rail.
 *
 * The click is setup here, not the behaviour under test — this spec asserts
 * CSS. Pointer-level interaction is covered by the navigation suite.
 */
async function openFirstDetail(page) {
  await page.locator(GRID_CARD).first().evaluate((card) => card.click())
}

/** Vertical translate of an element's computed transform, in px. */
async function translateY(page, selector) {
  return page.evaluate((css) => {
    const el = document.querySelector(css)
    if (!el) return null
    const transform = getComputedStyle(el).transform
    if (!transform || transform === "none") return 0
    const matrix = new DOMMatrixReadOnly(transform)
    return matrix.m42
  }, selector)
}

test("scroll-driven animation never leaves the detail sheet stuck risen", async ({ page }) => {
  // The detail backdrop's sheet replica rises with scroll, driven by a named
  // scroll timeline. Where `animation-timeline` is unsupported the declaration
  // is dropped at parse time and the animation falls back to the document
  // timeline — with no duration (so 0s) and `animation-fill-mode: both`, which
  // snaps the sheet permanently to its fully-risen end state. Unscrolled, it
  // must sit where the layout put it, in every browser.
  await page.goto("/library?tab=tv")
  await waitForLiveView(page)
  await page.waitForSelector(GRID_CARD, { timeout: 15_000 })

  await openFirstDetail(page)
  await expect(page.locator('#detail-modal[data-state="open"]')).toBeVisible()

  // The rise cap is published by the DetailScrollGeometry hook on mount, not
  // on scroll — so the defect is visible without scrolling at all. Waiting for
  // a non-zero value is what makes this assertion meaningful: at zero the
  // risen and resting states coincide and the test could not fail.
  await page.waitForFunction(() => {
    const scroller = document.querySelector("#detail-modal-scrollport")
    if (!scroller) return false
    const rise = getComputedStyle(scroller).getPropertyValue("--detail-sheet-max-rise")
    return parseFloat(rise) > 0
  }, { timeout: 10_000 })

  expect(await page.locator(".orientation-backing-sheet").count()).toBeGreaterThan(0)
  expect(Math.abs(await translateY(page, ".orientation-backing-sheet"))).toBeLessThan(1)
})

test("the library grid renders and navigates", async ({ page }) => {
  // Cheapest possible proof that the input system itself runs in this engine:
  // a keypress moves the cursor. The nav suite proves the rest, in Chromium.
  await page.goto("/library?tab=tv")
  await waitForLiveView(page)
  await waitForInputSystem(page)
  await page.waitForSelector(GRID_CARD, { timeout: 15_000 })

  await page.locator(GRID_CARD).first().focus()
  const before = await page.evaluate(() => document.activeElement?.dataset.entityId)

  await page.keyboard.press("ArrowRight")
  await page.waitForTimeout(150)
  const after = await page.evaluate(() => document.activeElement?.dataset.entityId)

  expect(before).toBeTruthy()
  expect(after).toBeTruthy()
  expect(after).not.toBe(before)
})

test("the home shelves render", async ({ page }) => {
  // The shelves' edge-fade masks are scroll-driven too, but correctly wrapped
  // in @supports, so they simply do not fade where the feature is missing.
  // What must hold either way is that the shelf renders its cards.
  await page.goto("/")
  await waitForLiveView(page)

  await expect(page.locator(".row-scroll").first()).toBeVisible()
  expect(await page.locator(".row-scroll [data-nav-item]").count()).toBeGreaterThan(0)
})
