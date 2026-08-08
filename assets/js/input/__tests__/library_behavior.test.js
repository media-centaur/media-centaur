import { describe, expect, test } from "bun:test"
import { createLibraryBehavior } from "../library_behavior"
import { Context } from "../core/index.js"

/**
 * Mock DOM interface — provides controllable filter and scroll operations.
 */
function mockDom({ filterValue = "" } = {}) {
  let currentFilterValue = filterValue
  let cleared = false
  let scrolledToTop = false

  return {
    getFilter() {
      if (currentFilterValue === null) return null
      return {
        get value() { return currentFilterValue },
        clear() {
          currentFilterValue = ""
          cleared = true
        },
      }
    },
    scrollToTop() { scrolledToTop = true },
    get cleared() { return cleared },
    get scrolledToTop() { return scrolledToTop },
  }
}

describe("Library behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createLibraryBehavior(mockDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  describe("onClear()", () => {
    test("clears filter and returns 'grid' so focus follows the unfiltered content", () => {
      const dom = mockDom({ filterValue: "some search" })
      const behavior = createLibraryBehavior(dom)
      const result = behavior.onClear()
      expect(dom.cleared).toBe(true)
      expect(result).toBe("grid")
    })

    test("does nothing and returns falsy when filter is empty", () => {
      const dom = mockDom({ filterValue: "" })
      const behavior = createLibraryBehavior(dom)
      const result = behavior.onClear()
      expect(dom.cleared).toBe(false)
      expect(result).toBeFalsy()
    })

    test("does nothing and returns falsy when filter element does not exist", () => {
      const dom = mockDom({ filterValue: null })
      const behavior = createLibraryBehavior(dom)
      const result = behavior.onClear()
      expect(dom.cleared).toBe(false)
      expect(result).toBeFalsy()
    })
  })

  // The behavior must never scroll the window itself. An instant scrollTo(0)
  // on zone change fights the reveal glide already in flight: the jump reads
  // as a jerk, and the glide's surviving target then drags the page back down,
  // scrolling the toolbar and cursor off the top. The toolbar's resting place
  // is declared on its markup (`data-nav-reveal-block="start"` + a page-top
  // scroll-margin) so revealItem glides there — the single scroll owner.
  test("does not scroll the window when focus reaches the toolbar — the reveal owns the scroll", () => {
    const dom = mockDom()
    const behavior = createLibraryBehavior(dom)

    behavior.onZoneChanged?.(Context.TOOLBAR)

    expect(dom.scrolledToTop).toBe(false)
  })

  describe("onSyncState()", () => {
    test("signals grid memory clear on sort order change", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onSyncState({ getSortOrder: () => "alpha" }))
        .toEqual({ clearGridMemory: true })
    })

    test("does not signal on same sort order", () => {
      const behavior = createLibraryBehavior(mockDom())
      behavior.onSyncState({ getSortOrder: () => "alpha" })
      expect(behavior.onSyncState({ getSortOrder: () => "alpha" }))
        .toEqual({ clearGridMemory: false })
    })

    test("signals again when sort order changes", () => {
      const behavior = createLibraryBehavior(mockDom())
      behavior.onSyncState({ getSortOrder: () => "alpha" })
      expect(behavior.onSyncState({ getSortOrder: () => "year" }))
        .toEqual({ clearGridMemory: true })
    })

    test("does not signal when sort order is null", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onSyncState({ getSortOrder: () => null }))
        .toEqual({ clearGridMemory: false })
    })
  })
})
