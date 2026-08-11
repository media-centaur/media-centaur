import { describe, expect, test, beforeEach } from "bun:test"
import { DetailBodyScroll } from "./detail_body_scroll"
import { installSyncAnimationFrame } from "../test_support/dom_stubs"

// The detail body and the port it scrolls in. `scrollIntoView` on the resume
// row stands in for the browser's centring by parking the port at a known
// offset, so a test can tell "the server centred the resume episode" apart
// from "something scrolled to the top".
const RESUME_OFFSET = 1200

const CONTENT_HEIGHT = 5000
const VIEWPORT_HEIGHT = 800

// The port clamps, because the browser does. Verified against the running app
// with `chromium-probe`: clicking a view control rebuilds the body sheet, the
// content height collapses mid-patch, and the browser pins `scrollTop` to 0 on
// its own — no script writes it. A mock that lets `scrollTop` hold any value
// cannot see that failure at all, which is how it shipped.
function buildBody({
  scrollKey = "entity-1",
  view = "main",
  scrollToResume,
  resumeTarget = true,
  contentHeight = CONTENT_HEIGHT,
} = {}) {
  const listeners = {}

  const port = {
    _top: 0,
    _contentHeight: contentHeight,
    _max() {
      return Math.max(0, this._contentHeight - VIEWPORT_HEIGHT)
    },
    get scrollTop() {
      return this._top
    },
    set scrollTop(value) {
      const clamped = Math.max(0, Math.min(value, this._max()))
      if (clamped === this._top) return
      this._top = clamped
      listeners.scroll?.()
    },
    // What morphdom does to the sheet: the old children go, the new ones
    // arrive. While it is empty there is nothing to scroll, so the browser
    // clamps — and growing the content back does not restore the position.
    _rebuildContent(height) {
      this._contentHeight = 0
      this.scrollTop = this._top
      this._contentHeight = height
    },
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

  const dataset = { scrollKey, view }
  if (scrollToResume) dataset.scrollToResume = ""

  const el = {
    dataset,
    closest(selector) {
      return selector === ".modal-detail-scroll" ? port : null
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

// A sub-view swap is a LiveView patch: the hook sees the element go, the sheet
// is rebuilt, then `updated()` runs against the new content.
function patchTo(hook, attrs, { contentHeight = null } = {}) {
  const port = hook.el.closest(".modal-detail-scroll")
  hook.beforeUpdate()
  Object.assign(hook.el.dataset, attrs)
  port._rebuildContent(contentHeight ?? port._contentHeight)
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

  // Entering a sub-view used to park the port at 0. That reads as the whole
  // modal snapping back to the top: the orientation block is sticky, so
  // leaving the pinned position throws the entire 21:9 hero back into view
  // for a swap that only changed the body. Nothing moves now — the header
  // stays pinned exactly where it was and only the content under it changes.
  test("leaves the reader where they are when More info opens", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "credits" })

    expect(port.scrollTop).toBe(900)
  })

  test("leaves the reader where they are when Manage opens", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 900)

    patchTo(hook, { view: "info" })

    expect(port.scrollTop).toBe(900)
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
  test("a modal opened straight onto More info still starts at the top", () => {
    // A fresh document, not a swap: nothing is being preserved, so the entry
    // rule applies as it always did.
    const { el, port } = buildBody({ view: "credits", scrollToResume: true })
    port.scrollTop = 700
    mountedOn(el)

    expect(port.scrollTop).toBe(0)
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
    expect(port.scrollTop).toBe(300)
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
    patchTo(hook, { scrollKey: "entity-2", view: "main" })
    expect(port.scrollTop).toBe(RESUME_OFFSET)

    // Still no reset on a sub-view swap — the offsets were cleared, not the
    // rule about not moving the reader.
    patchTo(hook, { view: "credits" })
    expect(port.scrollTop).toBe(RESUME_OFFSET)
  })
})

describe("DetailBodyScroll — the sheet rebuild", () => {
  test("survives the browser clamping the port to 0 mid-patch", () => {
    // The failure the original mock could not express. `_rebuildContent`
    // empties the sheet exactly as morphdom does, which clamps the port to 0
    // before `updated()` ever runs. Reading the position after the patch reads
    // the clamp, so the hook has to have captured it in `beforeUpdate`.
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 2000)

    patchTo(hook, { view: "info" }, { contentHeight: 9000 })

    expect(port.scrollTop).toBe(2000)
  })

  test("gear, scroll down, back — lands where the episode list was", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 2000)

    patchTo(hook, { view: "info" }, { contentHeight: 9000 })
    scrollTo(port, 600)
    patchTo(hook, { view: "main" }, { contentHeight: CONTENT_HEIGHT })

    expect(port.scrollTop).toBe(2000)
  })

  test("survives content that arrives one patch late", () => {
    // Manage loads its file list asynchronously, so it lands as two patches:
    // an empty sheet, then the files. Verified with `chromium-probe` — on the
    // first patch `max` is 0, so the offset is unreachable, and on the second
    // the port is sitting on a clamp the reader never chose. A hook that only
    // ever re-reads the port adopts that clamp as the answer.
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 2000)

    patchTo(hook, { view: "info" }, { contentHeight: 0 })
    expect(port.scrollTop).toBe(0)

    patchTo(hook, {}, { contentHeight: 9000 })

    expect(port.scrollTop).toBe(2000)
  })

  test("a goal reached is not re-applied over the reader's own scrolling", () => {
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 2000)

    patchTo(hook, { view: "info" }, { contentHeight: 0 })
    patchTo(hook, {}, { contentHeight: 9000 })
    expect(port.scrollTop).toBe(2000)

    scrollTo(port, 500)
    patchTo(hook, {}, { contentHeight: 9000 })

    expect(port.scrollTop).toBe(500)
  })

  test("an offset the new view cannot reach settles at its bottom", () => {
    // A short panel simply has nowhere to put the reader. Best effort, no
    // retry loop — the clamp is the answer, not a failure to be worked around.
    const { el, port } = buildBody({ scrollToResume: true })
    const hook = mountedOn(el)
    scrollTo(port, 3000)

    patchTo(hook, { view: "credits" }, { contentHeight: 1200 })

    expect(port.scrollTop).toBe(400)
  })
})
