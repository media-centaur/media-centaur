import { afterEach, describe, expect, test } from "bun:test"
import { ScrollRow, decodeImages, edges, step } from "./scroll_row"
import { installGlobal, installResizeObserver, restoreGlobals } from "../test_support/dom_stubs"
import { scrollGlider } from "../scroll_glider.js"

afterEach(restoreGlobals)

describe("edges", () => {
  test("a track at scroll 0 is at its start", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: false,
    })
  })

  test("a track mid-row is at neither end", () => {
    expect(edges({ scrollLeft: 800, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: false,
    })
  })

  // Browsers report fractional scroll offsets under a root zoom; a track
  // 0.6px short of its maximum is at its end.
  test("a track within a pixel of its maximum is at its end", () => {
    expect(edges({ scrollLeft: 1999.4, scrollWidth: 3000, clientWidth: 1000 })).toEqual({
      atStart: false,
      atEnd: true,
    })
  })

  test("a track that fits is at both ends", () => {
    expect(edges({ scrollLeft: 0, scrollWidth: 900, clientWidth: 1000 })).toEqual({
      atStart: true,
      atEnd: true,
    })
  })

  // Trackpad and touch overscroll report offsets past either end.
  test("overscroll past either end still reads as that end", () => {
    expect(edges({ scrollLeft: -5, scrollWidth: 3000, clientWidth: 1000 })).toEqual({ atStart: true, atEnd: false })
    expect(edges({ scrollLeft: 2500, scrollWidth: 3000, clientWidth: 1000 })).toEqual({ atStart: false, atEnd: true })
  })
})

describe("step", () => {
  // One screenful less one card and its gap: the last visible card stays
  // as the reader's anchor, the rule the track's scroll padding states for
  // the cursor.
  test("is the scrollport less one card and its gap", () => {
    expect(step({ clientWidth: 1000, cardWidth: 200, gap: 8 })).toBe(792)
  })

  // A scrollport narrower than two cards (UI scale 2× on a small window)
  // still moves a whole card, never a sliver.
  test("is never less than one card", () => {
    expect(step({ clientWidth: 300, cardWidth: 200, gap: 8 })).toBe(200)
  })
})

// A wrapper element with a track inside it, as the component renders them,
// under a fake glider that records what it was asked. `hover` is what the
// page's `(hover: hover)` query answers. `glider: false` leaves the hook
// to find its own.
function mount({
  hover = true,
  glider = true,
  scrollLeft = 0,
  scrollWidth = 3000,
  clientWidth = 1000,
  cardWidth = 200,
  gap = 8,
  images = [],
} = {}) {
  installGlobal("matchMedia", (query) => ({ matches: query === "(hover: hover)" && hover }))
  installGlobal("getComputedStyle", () => ({ columnGap: `${gap}px` }))
  const observers = installResizeObserver()

  function element() {
    const attributes = {}
    const listeners = {}
    return {
      attributes,
      listeners,
      setAttribute: (name, value) => {
        attributes[name] = value
      },
      removeAttribute: (name) => {
        delete attributes[name]
      },
      hasAttribute: (name) => name in attributes,
      toggleAttribute(name, force) {
        if (force) attributes[name] = ""
        else delete attributes[name]
      },
      addEventListener: (type, fn) => {
        listeners[type] = fn
      },
      removeEventListener: (type, fn) => {
        if (listeners[type] === fn) delete listeners[type]
      },
    }
  }

  const track = Object.assign(element(), {
    scrollLeft,
    scrollWidth,
    clientWidth,
    firstElementChild: { offsetWidth: cardWidth },
    getBoundingClientRect: () => ({ left: 0, right: clientWidth }),
  })
  const el = Object.assign(element(), {
    querySelector: (sel) => (sel === ":scope > .row-scroll" ? track : null),
    querySelectorAll: (sel) => (sel === "img" ? images : []),
  })

  const glides = []
  const idle = []
  const hook = Object.assign(Object.create(ScrollRow), { el, whenIdle: (callback) => idle.push(callback) })
  if (glider) hook.glider = { glide: (box, target) => glides.push({ box, target }) }
  hook.mounted()

  const arrow = (direction) => ({
    target: { closest: (sel) => (sel === "[data-scroll-row-arrow]" ? { dataset: { scrollRowArrow: direction } } : null) },
  })

  return {
    hook,
    el,
    track,
    glides,
    observers,
    arrow,
    idle,
    runIdle: () => idle.splice(0).forEach((callback) => callback()),
    press: (direction) => el.listeners.click(arrow(direction)),
  }
}

/** A poster `<img>` that counts its decode() calls, at `left` px in the track. */
function image(decode = () => Promise.resolve(), left = 0) {
  const img = { decodes: 0, getBoundingClientRect: () => ({ left, right: left + 200 }) }
  img.decode = () => {
    img.decodes += 1
    return decode()
  }
  return img
}

describe("ScrollRow", () => {
  test("projects the edge state onto the track at mount", () => {
    const { track } = mount({ scrollLeft: 0 })
    expect(track.attributes).toEqual({ "data-at-start": "" })
  })

  test("a track that fits is at both ends", () => {
    const { track } = mount({ scrollWidth: 900 })
    expect(track.attributes).toEqual({ "data-at-start": "", "data-at-end": "" })
  })

  test("follows the track's scroll", () => {
    const { track } = mount()
    track.scrollLeft = 2000
    track.listeners.scroll()
    expect(track.attributes).toEqual({ "data-at-end": "" })
  })

  test("follows a resize", () => {
    const { track, observers } = mount()
    expect(observers[0].targets).toEqual([track])
    track.clientWidth = 3000
    observers[0].fire()
    expect(track.attributes).toEqual({ "data-at-start": "", "data-at-end": "" })
  })

  // morphdom syncs a patched element back to the server's markup, which
  // has no edge attributes; after a patch the hook puts them back.
  test("re-asserts the edge state after a patch", () => {
    const { hook, track } = mount({ scrollLeft: 2000 })
    delete track.attributes["data-at-end"]
    hook.updated()
    expect(track.attributes).toEqual({ "data-at-end": "" })
  })

  test("a press on the right arrow glides one step", () => {
    const { track, glides, press } = mount({ scrollLeft: 0 })
    press("right")
    expect(glides).toEqual([{ box: track, target: { left: 792 } }])
  })

  test("a press on the left arrow glides one step back, clamped at 0", () => {
    const { track, glides, press } = mount({ scrollLeft: 500 })
    press("left")
    expect(glides).toEqual([{ box: track, target: { left: 0 } }])
  })

  test("a press near the end is clamped at the maximum", () => {
    const { track, glides, press } = mount({ scrollLeft: 1500 })
    press("right")
    expect(glides).toEqual([{ box: track, target: { left: 2000 } }])
  })

  test("a press on a track with no cards glides nowhere", () => {
    const { track, glides, press } = mount({ scrollWidth: 900 })
    track.firstElementChild = null
    press("right")
    expect(glides).toEqual([{ box: track, target: { left: 0 } }])
  })

  // The page has one scroll animator; the hook glides on it, so the
  // orchestrator's wheel rule cancels an arrow glide like any other.
  test("glides on the page's one glider", () => {
    const { hook } = mount({ glider: false })
    expect(hook.glider).toBe(scrollGlider)
  })

  test("a click elsewhere in the row is not a press", () => {
    const { el, glides } = mount()
    el.listeners.click({ target: { closest: () => null } })
    expect(glides).toEqual([])
  })

  // Pointer chrome never takes the cursor: in the collection rail the arrows sit
  // outside every nav zone, and a focused arrow would read as foreign focus
  // to the input system's reconciler (`hasForeignFocus`), which would then
  // cede the cursor to it.
  test("mousedown on an arrow is prevented, so the button never takes focus", () => {
    const { el, arrow } = mount()
    let prevented = false
    el.listeners.mousedown({ ...arrow("left"), preventDefault: () => (prevented = true) })
    expect(prevented).toBe(true)
  })

  test("mousedown elsewhere in the row is left alone", () => {
    const { el } = mount()
    let prevented = false
    el.listeners.mousedown({ target: { closest: () => null }, preventDefault: () => (prevented = true) })
    expect(prevented).toBe(false)
  })

  // No pointer, no chrome: the TV's glide frames carry no scroll listener.
  test("without a hovering pointer the hook attaches nothing", () => {
    const { el, track, observers } = mount({ hover: false })
    expect(track.attributes).toEqual({})
    expect(track.listeners).toEqual({})
    expect(el.listeners).toEqual({})
    expect(observers).toEqual([])
  })

  test("updated and destroyed are no-ops on an unattached hook", () => {
    const { hook, track } = mount({ hover: false })
    expect(() => {
      hook.updated()
      hook.destroyed()
    }).not.toThrow()
    expect(track.attributes).toEqual({})
  })

  // The TV draws the page at 1080p, so a shelf below the fold first paints
  // during the glide that brings it into view, and `decoding="sync"`
  // (UIDR-012) makes that frame wait on every poster's decode: 17 posters
  // held Discovery's first vertical glide for 200 ms (2026-11-02, runs
  // 20261102-121100 and -1216xx). Decoded at idle after mount, the glide
  // found them ready. The decode runs with or without a pointer: it is the
  // TV's case.
  test("decodes the track's images once idle, pointer or not", () => {
    const images = [image(), image()]
    const { idle, runIdle } = mount({ hover: false, images })
    expect(images.map((img) => img.decodes)).toEqual([0, 0])
    expect(idle).toHaveLength(1)
    runIdle()
    expect(images.map((img) => img.decodes)).toEqual([1, 1])
  })

  // Only what a vertical reveal would paint: a tile hidden to the right
  // decodes when a sideways glide brings it in, one at a time, which the TV
  // showed at 60 fps; decoding it ahead would only hold its pixels (rule 7).
  test("decodes only the images inside the track's scrollport", () => {
    const shown = image(undefined, 800)
    const hidden = image(undefined, 1200)
    const { runIdle } = mount({ images: [shown, hidden], clientWidth: 1000 })
    runIdle()
    expect(shown.decodes).toBe(1)
    expect(hidden.decodes).toBe(0)
  })

  test("a patch decodes only the images it added", () => {
    const first = image()
    const images = [first]
    const { hook, runIdle } = mount({ images })
    runIdle()
    const added = image()
    images.push(added)
    hook.updated()
    runIdle()
    expect(first.decodes).toBe(1)
    expect(added.decodes).toBe(1)
  })

  // An image that fails to load rejects its decode; the row has nothing to
  // do about it and the rejection must not surface as an unhandled one.
  test("a failing decode is swallowed", async () => {
    const img = image(() => Promise.reject(new Error("broken")))
    await expect(decodeImages([img], new WeakSet())).resolves.toBeUndefined()
    expect(img.decodes).toBe(1)
  })

  test("destroyed releases the listeners and the observer", () => {
    const { hook, el, track, observers } = mount()
    hook.destroyed()
    expect(track.listeners).toEqual({})
    expect(el.listeners).toEqual({})
    expect(observers[0].targets).toEqual([])
  })
})
