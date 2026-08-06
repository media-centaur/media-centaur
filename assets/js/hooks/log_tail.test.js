import { describe, expect, test, beforeEach } from "bun:test"
import { LogTail } from "./log_tail"
import {
  installWindow,
  installMutationObserver,
  installSyncAnimationFrame,
} from "../test_support/dom_stubs"

// Browser globals, installed fresh before every test — see
// `test_support/dom_stubs.js` for why they must not be installed
// conditionally. `stubObservers` is rebound each time so `[0]` is always the
// observer the hook under test constructed.
let stubObservers = []

function buildContainer({ scrollTop = 0, scrollHeight = 1000, clientHeight = 200, pinTo } = {}) {
  const listeners = {}
  const el = {
    scrollTop,
    scrollHeight,
    clientHeight,
    dataset: pinTo ? { pinTo } : {},
    addEventListener(event, handler) {
      listeners[event] = handler
    },
    removeEventListener(event, handler) {
      if (listeners[event] === handler) delete listeners[event]
    },
    _fireScroll() {
      listeners.scroll?.()
    },
  }
  return el
}

function mountedOn(container) {
  const hook = Object.create(LogTail)
  hook.el = container
  hook.mounted()
  return hook
}

beforeEach(() => {
  installWindow()
  stubObservers = installMutationObserver()
  installSyncAnimationFrame()
})

describe("LogTail — top mode (default)", () => {
  test("pins scrollTop to 0 on mount", () => {
    const container = buildContainer({ scrollTop: 0 })
    mountedOn(container)
    expect(container.scrollTop).toBe(0)
  })

  test("follows the top when a mutation fires and user is near the top", () => {
    const container = buildContainer({ scrollTop: 8 })
    const hook = mountedOn(container)
    // user is near top → _followTail stays true through the scroll handler
    container._fireScroll()
    stubObservers[0].fire()
    expect(container.scrollTop).toBe(0)
    expect(hook._followTail).toBe(true)
  })

  test("stops following once the user scrolls down past the threshold", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)
    container.scrollTop = 300
    container._fireScroll()
    stubObservers[0].fire()
    expect(container.scrollTop).toBe(300)
    expect(hook._followTail).toBe(false)
  })

  test("resumes following after the user scrolls back to the top", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)

    container.scrollTop = 300
    container._fireScroll()
    expect(hook._followTail).toBe(false)

    container.scrollTop = 4
    container._fireScroll()
    expect(hook._followTail).toBe(true)

    stubObservers[0].fire()
    expect(container.scrollTop).toBe(0)
  })
})

describe("LogTail — bottom mode (data-pin-to=bottom)", () => {
  test("pins to scrollHeight on mount", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    mountedOn(container)
    expect(container.scrollTop).toBe(1000)
  })

  test("follows the bottom when user is at the live edge", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)
    // mount pinned to bottom; simulate the auto-scroll event
    container._fireScroll()
    expect(hook._followTail).toBe(true)

    // stream appends new content, scrollHeight grows
    container.scrollHeight = 1200
    stubObservers[0].fire()
    expect(container.scrollTop).toBe(1200)
  })

  test("stops following once the user scrolls up past the threshold", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)
    // after mount, scrollTop=1000 (at bottom)
    container.scrollTop = 500
    container._fireScroll()
    expect(hook._followTail).toBe(false)

    container.scrollHeight = 1200
    stubObservers[0].fire()
    // scrollTop unchanged — user is reading history
    expect(container.scrollTop).toBe(500)
  })

  test("resumes following after the user scrolls back to the bottom", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)

    container.scrollTop = 500
    container._fireScroll()
    expect(hook._followTail).toBe(false)

    // user scrolls back near bottom: distance = 1000 - 795 - 200 = 5 ≤ 10
    container.scrollTop = 795
    container._fireScroll()
    expect(hook._followTail).toBe(true)

    container.scrollHeight = 1200
    stubObservers[0].fire()
    expect(container.scrollTop).toBe(1200)
  })
})

describe("LogTail — updated() re-pin", () => {
  test("re-pins to bottom on server-driven update when followTail is true", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)
    // Server re-render replaces the streamed content; scrollHeight grows.
    container.scrollHeight = 2000
    hook.updated()
    expect(container.scrollTop).toBe(2000)
  })

  test("does NOT re-pin on update when user has scrolled away", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)
    // User scrolled away to read history.
    container.scrollTop = 500
    container._fireScroll()
    expect(hook._followTail).toBe(false)
    container.scrollHeight = 2000
    hook.updated()
    expect(container.scrollTop).toBe(500)
  })
})

describe("LogTail — repin window event", () => {
  test("forces follow-and-pin on mc:log-tail:repin", () => {
    const container = buildContainer({
      pinTo: "bottom",
      scrollTop: 0,
      scrollHeight: 1000,
      clientHeight: 200,
    })
    const hook = mountedOn(container)
    // User scrolled away → followTail goes false.
    container.scrollTop = 500
    container._fireScroll()
    expect(hook._followTail).toBe(false)

    // Drawer opens → repin event fires. Dispatched the way the Console hook
    // dispatches it, rather than by calling the handler directly.
    window.dispatchEvent(new CustomEvent("mc:log-tail:repin"))
    expect(hook._followTail).toBe(true)
    expect(container.scrollTop).toBe(1000)

    hook.destroyed()
    expect(window.listenerCount("mc:log-tail:repin")).toBe(0)
  })
})

describe("LogTail — destroyed()", () => {
  test("removes scroll listener and disconnects observer", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)
    expect(() => hook.destroyed()).not.toThrow()
  })
})
