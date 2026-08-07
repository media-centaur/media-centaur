import { describe, expect, test } from "bun:test"
import { createScrollGlide } from "../scroll_glide"

/** A stand-in for a scroll container — only the two offsets matter. */
function fakeBox({ left = 0, top = 0 } = {}) {
  return { scrollLeft: left, scrollTop: top }
}

/**
 * A hand-driven clock and frame pump, so tests advance time explicitly
 * instead of waiting on a real rAF.
 */
function harness({ tau } = {}) {
  let clock = 0
  let pending = null
  const glide = createScrollGlide({
    requestAnimationFrame: (fn) => { pending = fn },
    now: () => clock,
    tau,
  })
  return {
    glide,
    /** Advance `ms` and run one frame. */
    frame(ms) {
      clock += ms
      const fn = pending
      pending = null
      if (fn) fn()
    },
    /** Advance in `count` equal frames totalling `ms`. */
    frames(ms, count) {
      for (let i = 0; i < count; i++) this.frame(ms / count)
    },
    get idle() { return pending === null },
  }
}

describe("createScrollGlide", () => {
  test("moves the box toward the target instead of jumping to it", () => {
    const h = harness()
    const box = fakeBox()

    h.glide.glide(box, { left: 1000 })
    expect(box.scrollLeft).toBe(0) // nothing happens until a frame runs

    h.frame(16)
    expect(box.scrollLeft).toBeGreaterThan(0)
    expect(box.scrollLeft).toBeLessThan(1000)
  })

  test("converges on the target exactly and then stops asking for frames", () => {
    const h = harness()
    const box = fakeBox()

    h.glide.glide(box, { left: 1000, top: 250 })
    for (let i = 0; i < 200 && !h.idle; i++) h.frame(16)

    expect(box.scrollLeft).toBe(1000)
    expect(box.scrollTop).toBe(250)
    expect(h.idle).toBe(true)
  })

  // The property the whole module exists for. Chromium's native smooth scroll
  // restarts its ease-in on every retarget, so input arriving faster than the
  // animation (a held arrow repeats every ~33ms) leaves the row pinned in the
  // slow part of the curve — measured: the cursor ran 3015px off-screen while
  // scrollLeft stayed at 3. Speed here depends only on distance remaining, so
  // a target that keeps running away is chased harder, never slower.
  test("retargeting mid-flight speeds up rather than restarting the easing", () => {
    const h = harness()
    const box = fakeBox()

    h.glide.glide(box, { left: 1000 })
    h.frame(16)
    const firstStep = box.scrollLeft
    const before = box.scrollLeft

    h.glide.glide(box, { left: 5000 })
    h.frame(16)
    const stepAfterRetarget = box.scrollLeft - before

    expect(stepAfterRetarget).toBeGreaterThan(firstStep)
  })

  test("speed is proportional to the distance remaining", () => {
    const near = harness()
    const nearBox = fakeBox()
    near.glide.glide(nearBox, { left: 100 })
    near.frame(16)

    const far = harness()
    const farBox = fakeBox()
    far.glide.glide(farBox, { left: 1000 })
    far.frame(16)

    // Ten times the distance, ten times the movement in the same frame — so a
    // far target arrives in about the same time as a near one, which is what
    // keeps a held direction glued to the cursor.
    expect(farBox.scrollLeft / nearBox.scrollLeft).toBeCloseTo(10, 1)
  })

  test("position depends on elapsed time, not on how many frames elapsed", () => {
    const coarse = harness()
    const coarseBox = fakeBox()
    coarse.glide.glide(coarseBox, { left: 1000 })
    coarse.frames(96, 1)

    const fine = harness()
    const fineBox = fakeBox()
    fine.glide.glide(fineBox, { left: 1000 })
    fine.frames(96, 12)

    // A dropped-frame stutter must not change where the row ends up.
    expect(fineBox.scrollLeft).toBeCloseTo(coarseBox.scrollLeft, 0)
  })

  test("an axis that was not given a target is left alone", () => {
    const h = harness()
    const box = fakeBox({ left: 40, top: 900 })

    h.glide.glide(box, { left: 0 })
    for (let i = 0; i < 200 && !h.idle; i++) h.frame(16)

    expect(box.scrollLeft).toBe(0)
    expect(box.scrollTop).toBe(900)
  })

  test("a target equal to the current position never schedules a frame", () => {
    const h = harness()
    const box = fakeBox({ left: 500 })

    h.glide.glide(box, { left: 500 })

    expect(h.idle).toBe(true)
  })

  test("cancel stops a glide where it stands", () => {
    const h = harness()
    const box = fakeBox()

    h.glide.glide(box, { left: 1000 })
    h.frame(16)
    const stopped = box.scrollLeft
    h.glide.cancel(box)
    h.frame(16)

    expect(box.scrollLeft).toBe(stopped)
    expect(h.idle).toBe(true)
  })

  test("animates several boxes at once", () => {
    const h = harness()
    const row = fakeBox()
    const page = fakeBox()

    h.glide.glide(row, { left: 800 })
    h.glide.glide(page, { top: 400 })
    for (let i = 0; i < 200 && !h.idle; i++) h.frame(16)

    expect(row.scrollLeft).toBe(800)
    expect(page.scrollTop).toBe(400)
  })

  // A wheel scroll hands scroll authority to the pointer: every glide, on
  // every box, must stop where it stands instead of fighting the user.
  test("cancelAll stops every glide in flight", () => {
    const h = harness()
    const row = fakeBox()
    const page = fakeBox()

    h.glide.glide(row, { left: 800 })
    h.glide.glide(page, { top: 400 })
    h.frame(16)
    const rowStopped = row.scrollLeft
    const pageStopped = page.scrollTop

    h.glide.cancelAll()
    h.frame(16)

    expect(row.scrollLeft).toBe(rowStopped)
    expect(page.scrollTop).toBe(pageStopped)
    expect(h.glide.isGliding(row)).toBe(false)
    expect(h.glide.isGliding(page)).toBe(false)
    expect(h.idle).toBe(true)
  })
})
