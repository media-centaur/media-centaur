/**
 * Detail-modal pinned-backdrop geometry E2E.
 *
 * The pinned orientation block repaints the panel backdrop as its own
 * opaque backing (an <img> clone — see .orientation-backing in app.css).
 * The illusion only works if the clone's box is identical to the panel
 * backdrop's box whenever the block is pinned: same cover fit in the
 * same box ⇒ the same rendered image. These tests assert that box
 * equality directly — after opening, after pinning, and after the
 * LiveView-patch scenario that has already broken it once (season
 * collapse/expand wiping the hook-published --modal-rail-w inline
 * style; morphdom syncs patched elements back to server markup).
 *
 * Geometry-only: input method is irrelevant, so the gamepad project is
 * skipped. Agent-side equivalents for interactive debugging live in
 * ~/scripts/agents/mc-ui-probe (align / shift / toggle).
 */
import { test, expect } from "./fixtures/input-method.js"
import { waitForLiveView } from "./helpers/liveview.js"

/** Box delta between the backing image clone and the panel backdrop img. */
async function measureBoxes(page) {
  return page.evaluate(() => {
    const image = document.querySelector(".orientation-backing-image")
    const panelImg = document.querySelector(".modal-page-backdrop img")
    if (!image || !panelImg) return { missing: true }
    const scroller = document.querySelector("#detail-scrollport")
    const block = document.querySelector(".detail-orientation")
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1
    const pinInset = parseFloat(getComputedStyle(block).top) * zoom
    const i = image.getBoundingClientRect()
    const p = panelImg.getBoundingClientRect()
    const s = scroller.getBoundingClientRect()
    const b = block.getBoundingClientRect()
    return {
      pinned: Math.abs(b.top - (s.top + pinInset)) < 2,
      scrollTop: scroller.scrollTop,
      railPublished: getComputedStyle(scroller).getPropertyValue("--modal-rail-w").trim(),
      pinScrollPublished: getComputedStyle(scroller).getPropertyValue("--detail-pin-scroll").trim(),
      railMeasured: scroller.offsetWidth - scroller.clientWidth,
      dx: i.left - p.left,
      dy: i.top - p.top,
      dw: i.width - p.width,
      dh: i.height - p.height,
    }
  })
}

function expectBoxEquality(boxes) {
  expect(boxes.pinned).toBe(true)
  // 1px tolerance: sub-pixel layout rounding. Anything larger means the
  // clone runs a different cover fit and the imagery visibly doubles.
  expect(Math.abs(boxes.dx)).toBeLessThan(1)
  expect(Math.abs(boxes.dy)).toBeLessThan(1)
  expect(Math.abs(boxes.dw)).toBeLessThan(1)
  expect(Math.abs(boxes.dh)).toBeLessThan(1)
}

// Poster cards in the library grid zone ONLY. A bare [data-entity-id]
// also matches the hero card's action buttons — clicking those STARTS
// PLAYBACK on the instance under test (it launched mpv on the dev
// daily-driver). Keep every click this spec makes scoped to elements
// whose phx-click opens the detail modal.
const GRID_CARD = '[data-nav-zone="grid"] [data-entity-id][phx-click="select_entity"]'

/** Open a TV entry whose detail can actually pin the orientation block
 * (long enough content, artwork present). Tries the first few cards;
 * false if none qualifies — geometry can't be exercised on this
 * library, so callers skip. */
async function openPinnableTvDetail(page) {
  // /library, NOT "/" — the home page's hero action buttons also carry
  // [data-entity-id], and clicking those starts playback.
  await page.goto("/library?tab=tv")
  await waitForLiveView(page)
  // Grid items stream in after mount — wait for them rather than
  // sampling the count immediately.
  try {
    await page.waitForSelector(GRID_CARD, { timeout: 5000 })
  } catch {
    return false
  }
  const cardCount = Math.min(await page.locator(GRID_CARD).count(), 5)
  for (let index = 0; index < cardCount; index++) {
    await page.locator(GRID_CARD).nth(index).click()
    await expect(page.locator('#detail-modal[data-state="open"]')).toBeVisible()
    const usable = await page
      .waitForFunction(() => {
        const img = document.querySelector(
          '#detail-modal[data-state="open"] .modal-page-backdrop img'
        )
        // The orientation block's images (logo lockup, backing clone)
        // must also be settled: a logo finishing after sampling grows
        // the block and shifts every measured offset below it.
        const blockImgs = [...document.querySelectorAll(
          '#detail-modal[data-state="open"] .detail-orientation img'
        )]
        return img && img.complete && img.naturalWidth > 0 &&
          !!document.querySelector(".orientation-backing-image") &&
          blockImgs.every((i) => i.complete)
      }, { timeout: 3000 })
      .then(() => true)
      .catch(() => false)
    if (usable && (await pinBlock(page))) return true
    await page.keyboard.press("Escape")
    await expect(page.locator('#detail-modal[data-state="open"]')).toBeHidden()
  }
  return false
}

/** Scroll the detail scroller far enough to pin the block; false if the
 * content is too short to ever pin. */
async function pinBlock(page) {
  return page.evaluate(() => {
    const scroller = document.querySelector("#detail-scrollport")
    scroller.scrollTop = scroller.scrollHeight
    scroller.getBoundingClientRect()
    const block = document.querySelector(".detail-orientation")
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1
    const pinInset = parseFloat(getComputedStyle(block).top) * zoom
    const s = scroller.getBoundingClientRect()
    const b = block.getBoundingClientRect()
    return Math.abs(b.top - (s.top + pinInset)) < 2
  })
}

test.describe("detail pinned-backdrop geometry", () => {
  test.beforeEach(async ({ inputMethod }) => {
    test.skip(inputMethod === "gamepad", "geometry is input-method independent")
  })

  test("backing clone box equals panel backdrop box while pinned", async ({ page }) => {
    if (!(await openPinnableTvDetail(page))) { test.skip(); return }

    const boxes = await measureBoxes(page)
    expectBoxEquality(boxes)
    // The published rail var must match the real gutter, or the clip
    // window is narrower than the panel and the imagery shifts left.
    expect(boxes.railPublished).toBe(`${boxes.railMeasured}px`)
  })

  test("backing sheet replica tracks the content edge while pinned", async ({ page }) => {
    if (!(await openPinnableTvDetail(page))) { test.skip(); return }

    // The hook publishes the scroll offset at which the block pins; the
    // sheet replica's rise is phased from it.
    const pinScroll = await page.evaluate(() => {
      const scroller = document.querySelector("#detail-scrollport")
      return parseFloat(getComputedStyle(scroller).getPropertyValue("--detail-pin-scroll"))
    })
    expect(pinScroll).toBeGreaterThan(0)

    // The illusion's invariant: the replica's top edge must coincide with
    // the real sheet's top edge (= #detail-content's top, whose
    // background IS the sheet) at every pinned depth — one conceptual
    // sheet, split across the backing boundary. Constant-free: compares
    // two live rects.
    for (const depth of [150, 500]) {
      const delta = await page.evaluate(async ({ pinScroll, depth }) => {
        const scroller = document.querySelector("#detail-scrollport")
        scroller.scrollTop = pinScroll + depth
        // Scroll-driven animations resolve on the frame after the scroll;
        // two rAFs guarantee the transform is current before sampling.
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
        const sheet = document.querySelector(".orientation-backing-sheet")
        const content = document.querySelector("#detail-content")
        if (!sheet || !content) return { missing: true }
        return { dt: sheet.getBoundingClientRect().top - content.getBoundingClientRect().top }
      }, { pinScroll, depth })
      expect(delta.missing).toBeFalsy()
      expect(Math.abs(delta.dt)).toBeLessThan(1)
    }
  })

  test("box equality survives season collapse + re-expand (morphdom patch)", async ({ page }) => {
    if (!(await openPinnableTvDetail(page))) { test.skip(); return }

    const before = await measureBoxes(page)
    expectBoxEquality(before)

    // Collapse the expanded season (chevron-down marks it), then re-expand.
    const expandedHeader = page
      .locator('[phx-click="toggle_season"]:has([class*="chevron-down"])')
      .first()
    if ((await expandedHeader.count()) === 0) { test.skip(); return }
    const seasonValue = await expandedHeader.getAttribute("phx-value-season")

    await expandedHeader.click()
    await expect(
      page.locator(
        `[phx-click="toggle_season"][phx-value-season="${seasonValue}"] [class*="chevron-right"]`
      )
    ).toBeVisible()

    await page
      .locator(`[phx-click="toggle_season"][phx-value-season="${seasonValue}"]`)
      .click()
    await expect(
      page.locator(
        `[phx-click="toggle_season"][phx-value-season="${seasonValue}"] [class*="chevron-down"]`
      )
    ).toBeVisible()

    if (!(await pinBlock(page))) { test.skip(); return }
    const after = await measureBoxes(page)
    expectBoxEquality(after)
    expect(after.railPublished).toBe(`${after.railMeasured}px`)
    // Both hook-published vars live in the same client-written inline
    // style that morphdom wipes — re-assert covers the pin phase too.
    expect(after.pinScrollPublished).not.toBe("")
  })
})
