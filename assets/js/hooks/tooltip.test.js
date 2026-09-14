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
} from "./tooltip"

// Any anchor with a label tips. Sidebar links are the exception: expanded,
// the label text is right on the link, so a tooltip would be a redundant
// echo — they tip only while the rail is collapsed.
describe("shouldShow", () => {
  test("a labelled anchor outside the sidebar → true, whatever the rail state", () => {
    expect(shouldShow({ inSidebar: false, sidebarState: undefined, label: "Review" })).toBe(true)
    expect(shouldShow({ inSidebar: false, sidebarState: "collapsed", label: "Review" })).toBe(true)
  })

  test("collapsed sidebar with a label → true", () => {
    expect(shouldShow({ inSidebar: true, sidebarState: "collapsed", label: "Home" })).toBe(true)
  })

  test("expanded sidebar (attribute absent) → false", () => {
    expect(shouldShow({ inSidebar: true, sidebarState: undefined, label: "Home" })).toBe(false)
    expect(shouldShow({ inSidebar: true, sidebarState: "", label: "Home" })).toBe(false)
  })

  test("no label → false anywhere", () => {
    expect(shouldShow({ inSidebar: true, sidebarState: "collapsed", label: undefined })).toBe(false)
    expect(shouldShow({ inSidebar: false, sidebarState: undefined, label: "" })).toBe(false)
  })
})

// A real pointer click means the user is acting on the anchor — hide. But
// keyboard nav activates links on focus via element.click(), which fires
// with detail 0; hiding on those would kill the tooltip the instant focus
// reveals it.
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
// along a row of icons reads as one continuous label instead of N pops.
describe("showDelay", () => {
  test("cold start → full delay", () => {
    expect(showDelay({ visible: false, hiddenAt: null, now: 10_000 })).toBe(COLD_DELAY_MS)
  })

  test("currently visible (moving between anchors) → instant", () => {
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

// getBoundingClientRect returns viewport coordinates — already multiplied
// by the root `zoom` UI scale — while the tooltip's transform lengths get
// multiplied by that zoom again at render. Dividing the rect by the scale
// keeps (X/S)×S = X physical, the same idiom as the modal height clamps.
describe("tooltipPosition", () => {
  const rect = { left: 16, right: 52, top: 100, bottom: 136, width: 36, height: 36 }

  test("right: x clears the anchor's right edge by the gap, y centers on it", () => {
    expect(tooltipPosition(rect, 1, "right")).toEqual({ x: 66, y: 118 })
  })

  test("bottom (the default): x centers on the anchor, y clears its bottom edge by a tighter gap", () => {
    expect(tooltipPosition(rect, 1)).toEqual({ x: 34, y: 144 })
    expect(tooltipPosition(rect, 1, "bottom")).toEqual({ x: 34, y: 144 })
  })

  test("rect coordinates are divided by the UI scale; the gap is local", () => {
    expect(tooltipPosition(rect, 2, "right")).toEqual({ x: 40, y: 59 })
    expect(tooltipPosition(rect, 2, "bottom")).toEqual({ x: 17, y: 76 })
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
// open tooltip can glide between anchors; the entrance variant starts a
// few px back along the placement axis for the slide-in.
describe("tooltipTransforms", () => {
  test("right: resting places and centers vertically; entrance slides in from the left", () => {
    const { resting, entrance } = tooltipTransforms({ x: 62, y: 118 }, "right")
    expect(resting).toBe("translate3d(62px, 118px, 0) translateY(-50%)")
    expect(entrance).toBe(`${resting} translateX(-6px)`)
  })

  test("bottom: resting places and centers horizontally; entrance slides in from above", () => {
    const { resting, entrance } = tooltipTransforms({ x: 34, y: 150 })
    expect(resting).toBe("translate3d(34px, 150px, 0) translateX(-50%)")
    expect(entrance).toBe(`${resting} translateY(-6px)`)
  })
})
