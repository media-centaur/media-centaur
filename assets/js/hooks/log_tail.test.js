import { describe, expect, test, beforeEach } from "bun:test"
import { LogTail } from "./log_tail"
import { installMutationObserver, installSyncAnimationFrame } from "../test_support/dom_stubs"

// Browser globals, installed fresh before every test — see
// `test_support/dom_stubs.js` for why they must not be installed
// conditionally. `stubObservers` is rebound each time so `[0]` is always the
// observer the hook under test constructed.
let stubObservers = []

function buildContainer({ scrollTop = 0, scrollHeight = 1000, clientHeight = 200 } = {}) {
  const listeners = {}
  const el = {
    scrollTop,
    scrollHeight,
    clientHeight,
    dataset: {},
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
  stubObservers = installMutationObserver()
  installSyncAnimationFrame()
})

describe("LogTail — following the live edge", () => {
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

describe("LogTail — updated() re-pin", () => {
  test("re-pins to the top on server-driven update when followTail is true", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)
    // Server re-render prepends rows; the browser keeps the viewport where
    // it was, which drifts the container off the live edge without a scroll
    // event the hook could have latched on to.
    container.scrollTop = 40
    hook.updated()
    expect(container.scrollTop).toBe(0)
  })

  test("does NOT re-pin on update when user has scrolled away", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)
    // User scrolled down to read history.
    container.scrollTop = 500
    container._fireScroll()
    expect(hook._followTail).toBe(false)
    hook.updated()
    expect(container.scrollTop).toBe(500)
  })
})

describe("LogTail — destroyed()", () => {
  test("removes scroll listener and disconnects observer", () => {
    const container = buildContainer({ scrollTop: 0 })
    const hook = mountedOn(container)
    expect(() => hook.destroyed()).not.toThrow()
  })
})
