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
    test("clears filter and returns true when filter has content", () => {
      const dom = mockDom({ filterValue: "some search" })
      const behavior = createLibraryBehavior(dom)
      expect(behavior.onEscape()).toBe(true)
      expect(dom.cleared).toBe(true)
    })

    test("returns false when filter is empty", () => {
      const behavior = createLibraryBehavior(mockDom({ filterValue: "" }))
      expect(behavior.onEscape()).toBe(false)
    })

    test("returns false when filter element does not exist", () => {
      const behavior = createLibraryBehavior(mockDom({ filterValue: null }))
      expect(behavior.onEscape()).toBe(false)
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
