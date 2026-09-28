import { afterEach, expect, test } from "bun:test"
import { FeedHead } from "./feed_head"
import { installGlobal, restoreGlobals } from "../test_support/dom_stubs"

// The sentinel at the Feed column's top under a fake observer that hands
// back its callback, so a test can play the crossings and read what the
// hook pushed. `pushEvent` and `handleEvent` are the LiveView's; here they
// record.
function mount() {
  let callback = null
  const observed = []
  let disconnected = false

  class FakeIntersectionObserver {
    constructor(cb) {
      callback = cb
    }
    observe(el) {
      observed.push(el)
    }
    disconnect() {
      disconnected = true
    }
  }

  installGlobal("IntersectionObserver", FakeIntersectionObserver)
  const scrolls = []
  installGlobal("window", { scrollTo: (opts) => scrolls.push(opts) })

  const pushed = []
  const handlers = {}
  const listeners = {}
  const el = {
    addEventListener: (name, fn) => {
      listeners[name] = fn
    },
    removeEventListener: (name, fn) => {
      if (listeners[name] === fn) delete listeners[name]
    },
  }
  const hook = Object.assign(Object.create(FeedHead), {
    el,
    pushEvent: (name) => pushed.push(name),
    handleEvent: (name, fn) => {
      handlers[name] = fn
    },
  })
  hook.mounted()

  return {
    hook,
    el,
    observed,
    pushed,
    handlers,
    listeners,
    scrolls,
    cross: (isIntersecting) => callback([{ isIntersecting }]),
    disconnected: () => disconnected,
  }
}

afterEach(restoreGlobals)

test("the sentinel is observed; leaving the top pushes feed_scrolled, returning pushes feed_at_top", () => {
  const { el, observed, pushed, cross } = mount()
  expect(observed).toEqual([el])

  cross(false)
  expect(pushed).toEqual(["feed_scrolled"])

  cross(true)
  expect(pushed).toEqual(["feed_scrolled", "feed_at_top"])
})

test("a crossing is reported once: the same state again pushes nothing", () => {
  const { pushed, cross } = mount()

  cross(true)
  expect(pushed).toEqual([])

  cross(false)
  cross(false)
  expect(pushed).toEqual(["feed_scrolled"])
})

// "N new" scrolls in the browser (`JS.dispatch("feed:scroll-top")` on the
// sentinel); the crossing it causes pushes `feed_at_top`, which lands the
// queue. One round trip, where the server-pushed scroll made two.
test("a scroll-to-top request lands on the window without a server event", () => {
  const { listeners, pushed, scrolls } = mount()

  listeners["feed:scroll-top"]()
  expect(scrolls).toEqual([{ top: 0, behavior: "instant" }])
  expect(pushed).toEqual([])
})

test("destroyed disconnects and stops listening", () => {
  const { hook, listeners, disconnected } = mount()

  hook.destroyed()
  expect(disconnected()).toBe(true)
  expect(listeners["feed:scroll-top"]).toBeUndefined()
})
