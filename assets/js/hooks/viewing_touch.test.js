import { afterEach, beforeEach, describe, expect, mock, test } from "bun:test"
import { ViewingTouch, formatClock, scrubAt, seekSeconds, tapAction } from "./viewing_touch"
import { installMutationObserver, restoreGlobals } from "../test_support/dom_stubs"

describe("seekSeconds — a point on the seek bar as a position in the file", () => {
  test("the point's share of the bar's width, in whole seconds", () => {
    expect(seekSeconds(150, { left: 100, width: 400 }, 2000)).toBe(250)
    expect(seekSeconds(300, { left: 100, width: 400 }, 2000)).toBe(1000)
  })

  test("a point past either end lands on that end", () => {
    expect(seekSeconds(50, { left: 100, width: 400 }, 2000)).toBe(0)
    expect(seekSeconds(900, { left: 100, width: 400 }, 2000)).toBe(2000)
  })

  test("no duration or no width is no seek", () => {
    expect(seekSeconds(150, { left: 100, width: 400 }, 0)).toBe(null)
    expect(seekSeconds(150, { left: 100, width: 0 }, 2000)).toBe(null)
  })
})

// The client half of the clock's format: the same cases as
// `MediaCentaur.Format.format_seconds/1` in format_test.exs.
describe("formatClock — the time over the thumb, in the clock's format", () => {
  test("minutes and seconds under an hour, hours above it", () => {
    expect(formatClock(0)).toBe("0:00")
    expect(formatClock(65)).toBe("1:05")
    expect(formatClock(599)).toBe("9:59")
    expect(formatClock(3600)).toBe("1:00:00")
    expect(formatClock(3725)).toBe("1:02:05")
  })

  test("a fraction is truncated, and nothing is 0:00", () => {
    expect(formatClock(65.9)).toBe("1:05")
    expect(formatClock(null)).toBe("0:00")
    expect(formatClock(NaN)).toBe("0:00")
  })
})

describe("scrubAt — where a finger on the bar is", () => {
  test("the share, the seconds and the label at the point", () => {
    expect(scrubAt(300, { left: 100, width: 400 }, 2000)).toEqual({ share: 0.5, seconds: 1000, label: "16:40" })
  })

  test("clamped to the bar's ends", () => {
    expect(scrubAt(0, { left: 100, width: 400 }, 2000)).toEqual({ share: 0, seconds: 0, label: "0:00" })
    expect(scrubAt(999, { left: 100, width: 400 }, 2000)).toEqual({ share: 1, seconds: 2000, label: "33:20" })
  })

  test("nothing without a duration", () => {
    expect(scrubAt(300, { left: 100, width: 400 }, 0)).toBe(null)
  })
})

describe("tapAction — what a tap on the OSD does", () => {
  const target = (matches) => ({ closest: (selector) => (matches.includes(selector) ? {} : null) })

  test("the seek bar is the pointer path's (press, drag, release)", () => {
    expect(tapAction(target(["[data-viewing-seek]"]))).toBe("seek")
  })

  test("a control answers for itself", () => {
    expect(tapAction(target(["button"]))).toBe(null)
  })

  test("the picture shows or hides the bar", () => {
    expect(tapAction(target([]))).toBe("tap")
  })
})

// A fake element: listeners that `fire` reaches, a style with custom
// properties, attributes, a dataset — what the hook touches, nothing more.
function fakeElement(extra = {}) {
  const listeners = {}
  const attrs = {}
  const style = {}
  return {
    dataset: {},
    textContent: "",
    style: { setProperty: (k, v) => (style[k] = v), get: (k) => style[k] },
    addEventListener(type, handler) {
      ;(listeners[type] ??= []).push(handler)
    },
    removeEventListener(type, handler) {
      listeners[type] = (listeners[type] ?? []).filter((h) => h !== handler)
    },
    fire(type, event) {
      for (const handler of [...(listeners[type] ?? [])]) handler(event)
    },
    listenerCount(type) {
      return (listeners[type] ?? []).length
    },
    setAttribute: (k, v) => (attrs[k] = v),
    removeAttribute: (k) => delete attrs[k],
    getAttribute: (k) => (k in attrs ? attrs[k] : null),
    hasAttribute: (k) => k in attrs,
    ...extra,
  }
}

// The OSD with its seek bar: 400 px wide from x=100, a 2000 s file at 25 %.
function osd() {
  const time = fakeElement()
  const state = fakeElement()
  const bar = fakeElement({
    getBoundingClientRect: () => ({ left: 100, width: 400 }),
    setPointerCapture: mock(() => {}),
    releasePointerCapture: mock(() => {}),
    querySelector: (selector) => ({ ".viewing-scrub-state": state, ".viewing-scrub-time": time })[selector] ?? null,
  })
  bar.dataset.duration = "2000"
  bar.setAttribute("aria-valuenow", "25")
  bar.closest = (selector) => (selector === "[data-viewing-seek]" ? bar : null)
  const el = fakeElement()
  return { el, bar, state, time }
}

function mountHook(el) {
  const hook = Object.create(ViewingTouch)
  hook.el = el
  hook.pushEvent = mock(() => {})
  hook.mounted()
  return hook
}

const pointer = (target, clientX, type = "touch") => ({
  target,
  clientX,
  pointerId: 7,
  isPrimary: true,
  pointerType: type,
  preventDefault: mock(() => {}),
})

describe("ViewingTouch — press, drag, release on the seek bar", () => {
  let hook, parts, observers

  beforeEach(() => {
    observers = installMutationObserver()
    parts = osd()
    hook = mountHook(parts.el)
  })

  afterEach(() => {
    hook.destroyed()
    restoreGlobals()
  })

  test("a drag moves the thumb and the time under the finger, and seeks once, on release", () => {
    const { el, bar, state, time } = parts
    el.fire("pointerdown", pointer(bar, 200))
    expect(state.hasAttribute("data-active")).toBe(true)
    expect(state.style.get("--scrub")).toBe("0.25")
    expect(state.style.get("--scrub-x")).toBe("100px")
    expect(time.textContent).toBe("8:20")
    expect(bar.setPointerCapture).toHaveBeenCalledWith(7)

    bar.fire("pointermove", pointer(bar, 300))
    expect(state.style.get("--scrub")).toBe("0.5")
    expect(time.textContent).toBe("16:40")
    expect(hook.pushEvent).not.toHaveBeenCalled()

    bar.fire("pointerup", pointer(bar, 400))
    expect(hook.pushEvent).toHaveBeenCalledTimes(1)
    expect(hook.pushEvent).toHaveBeenCalledWith("viewing_command", { command: "seek_to", seconds: 1500 })
    expect(bar.listenerCount("pointermove")).toBe(0)
  })

  test("a press and release without a move is a tap: one seek at the point", () => {
    const { el, bar } = parts
    el.fire("pointerdown", pointer(bar, 300))
    bar.fire("pointerup", pointer(bar, 300))
    expect(hook.pushEvent).toHaveBeenCalledTimes(1)
    expect(hook.pushEvent).toHaveBeenCalledWith("viewing_command", { command: "seek_to", seconds: 1000 })
  })

  test("a click on the bar pushes nothing: the pointer path already did", () => {
    const { el, bar } = parts
    el.fire("click", { target: bar })
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  test("a click on the picture still shows or hides the bar", () => {
    const { el } = parts
    const picture = { closest: () => null }
    el.fire("click", { target: picture })
    expect(hook.pushEvent).toHaveBeenCalledWith("viewing_tap", {})
  })

  test("the scrub stays after release until the server's position reaches it", () => {
    const { el, bar, state } = parts
    el.fire("pointerdown", pointer(bar, 300))
    bar.fire("pointerup", pointer(bar, 300))
    expect(state.hasAttribute("data-active")).toBe(true)
    expect(observers).toHaveLength(1)
    expect(observers[0].observing).toBe(true)

    bar.setAttribute("aria-valuenow", "26") // the old position's next tick
    observers[0].fire()
    expect(state.hasAttribute("data-active")).toBe(true)

    bar.setAttribute("aria-valuenow", "50") // the seek landed
    observers[0].fire()
    expect(state.hasAttribute("data-active")).toBe(false)
    expect(observers[0].observing).toBe(false)
  })

  test("a cancelled pointer drops the scrub without seeking", () => {
    const { el, bar, state } = parts
    el.fire("pointerdown", pointer(bar, 300))
    bar.fire("pointercancel", pointer(bar, 300))
    expect(hook.pushEvent).not.toHaveBeenCalled()
    expect(state.hasAttribute("data-active")).toBe(false)
  })

  test("a press off the bar is not a scrub", () => {
    const { el, state } = parts
    el.fire("pointerdown", pointer({ closest: () => null }, 300))
    expect(state.hasAttribute("data-active")).toBe(false)
  })
})
