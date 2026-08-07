import { describe, expect, test, beforeEach } from "bun:test"
import { DetailBodyScroll } from "./detail_body_scroll"
import { installSyncAnimationFrame } from "../test_support/dom_stubs"

// The detail body and the port it scrolls in. `scrollIntoView` on the resume
// row stands in for the browser's centring by parking the port at a known
// offset, so a test can tell "the server centred the resume episode" apart
// from "something scrolled to the top".
const RESUME_OFFSET = 1200

function buildBody({ entityId = "entity-1", view = "main", scrollToResume, resumeTarget = true } = {}) {
  const listeners = {}

  const port = {
    scrollTop: 0,
    addEventListener(event, handler) {
      listeners[event] = handler
    },
    removeEventListener(event, handler) {
      if (listeners[event] === handler) delete listeners[event]
    },
    _fireScroll() {
      listeners.scroll?.()
    },
    _listening() {
      return listeners.scroll !== undefined
    },
  }

  const dataset = { entityId, view }
  if (scrollToResume) dataset.scrollToResume = ""

  const el = {
    dataset,
    closest(selector) {
      return selector === "#detail-scrollport" ? port : null
    },
    querySelector(selector) {
      if (selector !== "[data-resume-target]" || !resumeTarget) return null
      return {
        scrollIntoView() {
          port.scrollTop = RESUME_OFFSET
        },
      }
    },
  }

  return { el, port }
}

function mountedOn(el) {
  const hook = Object.create(DetailBodyScroll)
  hook.el = el
  hook.mounted()
  return hook
}

// A sub-view swap is a LiveView patch: the server rewrites `data-view` on the
// same element, then the hook's `updated()` runs.
function patchTo(hook, attrs) {
  Object.assign(hook.el.dataset, attrs)
  hook.updated()
}

// The user drags the body somewhere; the port's scroll events are what the
// hook listens to.
function scrollTo(port, offset) {
  port.scrollTop = offset
  port._fireScroll()
}

beforeEach(() => {
  installSyncAnimationFrame()
})

describe("DetailBodyScroll — entering a view for the first time", () => {
  test("centres the resume episode when the server marks one", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    mountedOn(el)
    expect(port.scrollTop).toBe(RESUME_OFFSET)
  })

  test("opens the main view at the top when there is no resume row to return to", () => {
    const { el, port } = buildBody({ scrollToResume: false })
    port.scrollTop = 400
    mountedOn(el)
    expect(port.scrollTop).toBe(0)
  })

  test("opens More info at the top rather than where the episode list was", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "credits" })

    expect(port.scrollTop).toBe(0)
  })

  test("opens Manage at the top rather than where the episode list was", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "info" })

    expect(port.scrollTop).toBe(0)
  })

  test("does not chase a resume row from a sub-view that has none", () => {
    // `data-scroll-to-resume` is entity state, not view state — the server
    // leaves it on while More info is showing.
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "credits" })

    expect(port.scrollTop).not.toBe(RESUME_OFFSET)
  })
})

describe("DetailBodyScroll — returning to a view", () => {
  test("restores where the episode list was, not the top", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "credits" })
    patchTo(hook, { view: "main" })

    expect(port.scrollTop).toBe(900)
  })

  test("each view keeps its own position", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "credits" })
    scrollTo(port, 300)

    patchTo(hook, { view: "main" })
    expect(port.scrollTop).toBe(900)

    patchTo(hook, { view: "credits" })
    expect(port.scrollTop).toBe(300)
  })

  test("Manage keeps its own position independently of More info", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)

    patchTo(hook, { view: "credits" })
    scrollTo(port, 300)

    patchTo(hook, { view: "info" })
    expect(port.scrollTop).toBe(0)
    scrollTo(port, 150)

    patchTo(hook, { view: "credits" })
    expect(port.scrollTop).toBe(300)

    patchTo(hook, { view: "info" })
    expect(port.scrollTop).toBe(150)
  })
})

describe("DetailBodyScroll — patches that are not view swaps", () => {
  test("leaves the position alone when a season expands", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, {})

    expect(port.scrollTop).toBe(900)
  })

  test("forgets the previous title's positions when the entity changes", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)
    patchTo(hook, { view: "credits" })

    // Opening a different title, straight into the view the last one left on.
    patchTo(hook, { entityId: "entity-2", view: "main" })
    expect(port.scrollTop).toBe(RESUME_OFFSET)

    patchTo(hook, { view: "credits" })
    expect(port.scrollTop).toBe(0)
  })
})

describe("DetailBodyScroll — destroyed()", () => {
  test("releases the port's scroll listener", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    expect(port._listening()).toBe(true)

    hook.destroyed()

    expect(port._listening()).toBe(false)
  })
})
