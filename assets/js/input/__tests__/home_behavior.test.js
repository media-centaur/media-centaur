import { describe, expect, test } from "bun:test"
import { createHomeBehavior } from "../home_behavior"

function mockDom() {
  let scrolledToTop = false
  return {
    scrollToTop() { scrolledToTop = true },
    get scrolledToTop() { return scrolledToTop },
  }
}

describe("home behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createHomeBehavior(mockDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  test("does not auto-activate shelf items on focus", () => {
    const behavior = createHomeBehavior(mockDom())
    // Shelves must not open the detail modal merely by moving focus across
    // cards — activation only happens on an explicit SELECT.
    expect(behavior.activateOnFocus).toBeUndefined()
  })

  describe("onZoneChanged() scroll reset", () => {
    test("scrolls the page to the top when focus reaches the hero shelf", () => {
      // The hero is the topmost shelf (≤65vh, anchored at the page top), so
      // scrolling back up to its Play / More info buttons should reveal the
      // whole hero — not leave it half-clipped by scrollIntoView('nearest').
      const dom = mockDom()
      const behavior = createHomeBehavior(dom)

      behavior.onZoneChanged("hero")

      expect(dom.scrolledToTop).toBe(true)
    })

    test("does not scroll when focus reaches a lower shelf", () => {
      const dom = mockDom()
      const behavior = createHomeBehavior(dom)

      behavior.onZoneChanged("continue")
      behavior.onZoneChanged("recently")
      behavior.onZoneChanged("coming_up")
      behavior.onZoneChanged("modal")
      behavior.onZoneChanged("sidebar")

      expect(dom.scrolledToTop).toBe(false)
    })
  })
})
