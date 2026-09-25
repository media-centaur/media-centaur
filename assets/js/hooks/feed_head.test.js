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
  const el = {}
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

test("the server's scroll-to-top lands on the window; destroyed disconnects", () => {
  const { hook, handlers, scrolls, disconnected } = mount()

  handlers["feed:scroll_top"]()
  expect(scrolls).toEqual([{ top: 0, behavior: "instant" }])

  hook.destroyed()
  expect(disconnected()).toBe(true)
})
