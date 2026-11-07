/**
 * The app as a phone (`campaigns/adaptive-layout.md`): a compact window,
 * a coarse pointer, touch. The `phone` project in playwright.config.js
 * emulates the owner's phone (360×800, dPR 3, touch, mobile viewport).
 *
 * What these guard is the compact shell's contract, not a page's content:
 * the bottom bar carries the watch-and-choose pages and navigates by a tap;
 * a title opens as a sheet the width of the screen; and no page — the plan
 * modal's host included — is wider than the screen. The last matters most
 * on a phone: a mobile viewport answers an overflowing page by zooming the
 * whole page out, which no desktop test can see.
 *
 * Touch-only: nothing here presses a key or a pad button.
 */
import { test, expect } from "@playwright/test"
import { waitForLiveView, waitForSettle } from "./helpers/liveview.js"

const PHONE_WIDTH = 360

// The pages the bar carries, plus the ones reached through them.
const PAGES = ["/", "/library", "/discovery", "/social", "/watchlist"]

async function open(page, path) {
  await page.goto(path)
  await waitForLiveView(page)
  await waitForSettle(page, 300)
}

async function documentWidth(page) {
  return page.evaluate(() => document.documentElement.scrollWidth)
}

test.describe("the compact shell", () => {
  test("the bar is the watch-and-choose pages, and a tap navigates", async ({ page }) => {
    await open(page, "/")

    // The bar's cells: every entry with a compact name, none without.
    await expect(page.locator("#sidebar .sidebar-link:visible:not([data-compact])")).toHaveCount(0)
    for (const id of ["sidebar-home", "sidebar-library", "sidebar-discovery", "sidebar-social"]) {
      await expect(page.locator(`#${id}[data-compact]`)).toBeVisible()
    }
    for (const id of ["sidebar-watchlist", "sidebar-review", "sidebar-downloads", "sidebar-settings"]) {
      await expect(page.locator(`#${id}`)).toBeHidden()
    }

    // The bar sits at the bottom, and main takes the full width.
    const barBox = await page.locator("#sidebar").boundingBox()
    expect(barBox.y + barBox.height).toBeGreaterThan(800 - 2)
    const mainBox = await page.locator("#input-system > main").boundingBox()
    expect(mainBox.x).toBe(0)
    expect(mainBox.width).toBe(PHONE_WIDTH)

    await page.locator("#sidebar-library").tap()
    await page.waitForURL("**/library")
    await waitForLiveView(page)
    await expect(page.locator("#sidebar-library")).toHaveClass(/sidebar-link-active/)
  })

  test("a title opens as a sheet the width of the screen", async ({ page }) => {
    await open(page, "/library")

    const card = page.locator("[phx-click='select_entity']").first()
    test.skip((await card.count()) === 0, "needs a library entry")

    await card.tap()
    const panel = page.locator("#detail-modal .modal-panel--cinematic")
    await expect(panel).toBeVisible()
    // The panel scales in as it opens; poll until the transition has landed.
    await expect.poll(async () => (await panel.boundingBox()).x).toBe(0)
    const box = await panel.boundingBox()
    expect(box.width).toBe(PHONE_WIDTH)
    expect(box.height).toBeGreaterThanOrEqual(800 - 1)
  })

  for (const path of PAGES) {
    test(`${path} is never wider than the screen`, async ({ page }) => {
      await open(page, path)
      expect(await documentWidth(page)).toBeLessThanOrEqual(PHONE_WIDTH)
    })
  }

  // The plan modal is a tenant of the page that opened it (Live.PlanHost):
  // Library is where a phone opens it; Downloads, a desktop page, hosts it
  // too and once widened the viewport beneath it. The seed's first movie
  // serves as the subject (the picker renders the same frame for an owned
  // title).
  for (const host of ["/library", "/downloads"]) {
    test(`the plan modal on ${host} and its host are never wider than the screen`, async ({ page }) => {
      await open(page, `${host}?plan=new&tmdb_id=10513&tmdb_type=movie`)
      const panel = page.locator("#plan-modal .modal-panel--cinematic")
      await expect(panel).toBeVisible()
      await expect.poll(async () => (await panel.boundingBox()).width).toBe(PHONE_WIDTH)
      expect(await documentWidth(page)).toBeLessThanOrEqual(PHONE_WIDTH)
    })
  }
})
