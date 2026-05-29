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
  describe("onEscape()", () => {
    test("always returns sidebar to navigate back", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onEscape()).toBe("sidebar")
    })

    test("returns sidebar regardless of the context just visited", () => {
      const behavior = createLibraryBehavior(mockDom())
      behavior.onZoneChanged(Context.TOOLBAR)
      behavior.onZoneChanged(Context.GRID)
      behavior.onZoneChanged(Context.MODAL)
      behavior.onZoneChanged(Context.GRID)
      expect(behavior.onEscape()).toBe("sidebar")
    })
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

  describe("onZoneChanged() scroll reset", () => {
    test("scrolls the page to the very top when focus reaches the toolbar", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)

      behavior.onZoneChanged(Context.TOOLBAR)

      expect(dom.scrolledToTop).toBe(true)
    })

    test("does not scroll for non-toolbar contexts", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)

      behavior.onZoneChanged(Context.GRID)
      behavior.onZoneChanged(Context.MODAL)
      behavior.onZoneChanged(Context.DRAWER)
      behavior.onZoneChanged("sidebar")

      expect(dom.scrolledToTop).toBe(false)
    })
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
