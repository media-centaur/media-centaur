import { describe, expect, test } from "bun:test"
import { createLibraryBehavior } from "../library_behavior"

/**
 * Mock DOM interface — provides controllable filter.
 */
function mockDom({ filterValue = "" } = {}) {
  let currentFilterValue = filterValue
  let cleared = false

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
    get cleared() { return cleared },
  }
}

describe("Library behavior", () => {
  describe("onEscape()", () => {
    test("returns sidebar to navigate back", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onEscape()).toBe("sidebar")
    })
  })

  describe("onClear()", () => {
    test("clears filter when filter has content", () => {
      const dom = mockDom({ filterValue: "some search" })
      const behavior = createLibraryBehavior(dom)
      behavior.onClear()
      expect(dom.cleared).toBe(true)
    })

    test("does nothing when filter is empty", () => {
      const dom = mockDom({ filterValue: "" })
      const behavior = createLibraryBehavior(dom)
      behavior.onClear()
      expect(dom.cleared).toBe(false)
    })

    test("does nothing when filter element does not exist", () => {
      const dom = mockDom({ filterValue: null })
      const behavior = createLibraryBehavior(dom)
      behavior.onClear()
      expect(dom.cleared).toBe(false)
    })
  })

  describe("onSyncState()", () => {
    test("signals grid memory clear on sort order change", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onSyncState({ getSortOrder: () => "title_asc" }))
        .toEqual({ clearGridMemory: true })
    })

    test("does not signal on same sort order", () => {
      const behavior = createLibraryBehavior(mockDom())
      behavior.onSyncState({ getSortOrder: () => "title_asc" })
      expect(behavior.onSyncState({ getSortOrder: () => "title_asc" }))
        .toEqual({ clearGridMemory: false })
    })

    test("signals again when sort order changes", () => {
      const behavior = createLibraryBehavior(mockDom())
      behavior.onSyncState({ getSortOrder: () => "title_asc" })
      expect(behavior.onSyncState({ getSortOrder: () => "year_desc" }))
        .toEqual({ clearGridMemory: true })
    })

    test("does not signal when sort order is null", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onSyncState({ getSortOrder: () => null }))
        .toEqual({ clearGridMemory: false })
    })
  })
})
