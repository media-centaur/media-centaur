import { describe, expect, test } from "bun:test"
import {
  COLD_DELAY_MS,
  WARM_WINDOW_MS,
  clickHides,
  parseUiScale,
  shouldShow,
  showDelay,
  tooltipPosition,
  tooltipTransforms,
} from "./sidebar_tooltip"

// Tooltips only exist for the collapsed rail — expanded mode shows the
// label text right on the link, so a tooltip would be a redundant echo.
describe("shouldShow", () => {
  test("collapsed sidebar with a label → true", () => {
    expect(shouldShow("collapsed", "Home")).toBe(true)
  })

  test("expanded sidebar (attribute absent) → false", () => {
    expect(shouldShow(undefined, "Home")).toBe(false)
    expect(shouldShow("", "Home")).toBe(false)
  })

  test("no label → false even when collapsed", () => {
    expect(shouldShow("collapsed", undefined)).toBe(false)
    expect(shouldShow("collapsed", "")).toBe(false)
  })
})

// A real pointer click means the user is navigating away or toggling the
// rail — hide. But keyboard nav in the sidebar activates links on focus via
// element.click(), which fires with detail 0; hiding on those would kill the
// tooltip the instant focus reveals it.
describe("clickHides", () => {
  test("pointer click (detail ≥ 1) → hide", () => {
    expect(clickHides({ detail: 1 })).toBe(true)
    expect(clickHides({ detail: 2 })).toBe(true)
  })

  test("synthetic activation click (detail 0) → keep the tooltip", () => {
    expect(clickHides({ detail: 0 })).toBe(false)
  })
})

// First hover waits a beat; once a tooltip is "warm" (visible now, or
// hidden only a moment ago) the next one shows instantly, so sweeping
// down the rail reads as one continuous label instead of N delayed pops.
describe("showDelay", () => {
  test("cold start → full delay", () => {
    expect(showDelay({ visible: false, hiddenAt: null, now: 10_000 })).toBe(COLD_DELAY_MS)
  })

  test("currently visible (moving between links) → instant", () => {
    expect(showDelay({ visible: true, hiddenAt: null, now: 10_000 })).toBe(0)
  })

  test("hidden within the warm window → instant", () => {
    const now = 10_000
    expect(showDelay({ visible: false, hiddenAt: now - WARM_WINDOW_MS + 1, now })).toBe(0)
  })

  test("hidden longer than the warm window ago → full delay again", () => {
    const now = 10_000
    expect(showDelay({ visible: false, hiddenAt: now - WARM_WINDOW_MS - 1, now })).toBe(
      COLD_DELAY_MS
    )
  })
})

// The tooltip sits to the right of the link, vertically centered on it.
// getBoundingClientRect returns viewport coordinates — already multiplied
// by the root `zoom` UI scale — while the tooltip's transform lengths get
// multiplied by that zoom again at render. Dividing the rect by the scale
// keeps (X/S)×S = X physical, the same idiom as the modal height clamps.
describe("tooltipPosition", () => {
  test("x clears the link's right edge by the gap", () => {
    const rect = { right: 52, top: 100, height: 36 }
    expect(tooltipPosition(rect, 1)).toEqual({ x: 66, y: 118 })
  })

  test("rect coordinates are divided by the UI scale; the gap is local", () => {
    const rect = { right: 52, top: 100, height: 36 }
    expect(tooltipPosition(rect, 2)).toEqual({ x: 40, y: 59 })
  })
})

// `--ui-scale` arrives as a raw custom-property string from computed style.
describe("parseUiScale", () => {
  test("numeric string → number", () => {
    expect(parseUiScale("2.0")).toBe(2)
    expect(parseUiScale(" 1.25")).toBe(1.25)
  })

  test("absent or malformed → 1 (unscaled)", () => {
    expect(parseUiScale("")).toBe(1)
    expect(parseUiScale(undefined)).toBe(1)
    expect(parseUiScale("auto")).toBe(1)
    expect(parseUiScale("0")).toBe(1)
  })
})

// Positioning is done entirely in `transform` (compositor-only) so the
// open tooltip can glide between icons; the entrance variant starts a few
// px left of resting for the slide-in.
describe("tooltipTransforms", () => {
  test("resting transform places and centers the tooltip", () => {
    const { resting } = tooltipTransforms({ x: 62, y: 118 })
    expect(resting).toBe("translate3d(62px, 118px, 0) translateY(-50%)")
  })

  test("entrance transform adds a leftward offset onto resting", () => {
    const { resting, entrance } = tooltipTransforms({ x: 62, y: 118 })
    expect(entrance).toBe(`${resting} translateX(-6px)`)
  })
})
