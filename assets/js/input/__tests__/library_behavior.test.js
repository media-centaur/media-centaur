import { describe, expect, test } from "bun:test"
import { createLibraryBehavior } from "../library_behavior"
import { Action, Context } from "../core/index.js"

/**
 * Mock DOM interface — provides controllable filter and calendar operations.
 */
function mockDom({ filterValue = "" } = {}) {
  let currentFilterValue = filterValue
  let cleared = false
  let prevMonthClicked = false
  let nextMonthClicked = false
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
    clickPrevMonth() { prevMonthClicked = true },
    clickNextMonth() { nextMonthClicked = true },
    scrollToTop() { scrolledToTop = true },
    get cleared() { return cleared },
    get prevMonthClicked() { return prevMonthClicked },
    get nextMonthClicked() { return nextMonthClicked },
    get scrolledToTop() { return scrolledToTop },
  }
}

describe("Library behavior", () => {
  describe("onEscape()", () => {
    test("returns sidebar to navigate back", () => {
      const behavior = createLibraryBehavior(mockDom())
      expect(behavior.onEscape()).toBe("sidebar")
    })

    test("returns upcoming when backing out of tracking grid", () => {
      const behavior = createLibraryBehavior(mockDom())
      const trackingItem = { dataset: { sectionType: "tracking" } }

      // Simulate tracking drill-in via onAction
      behavior.onZoneChanged("upcoming")
      behavior.onAction(Action.SELECT, "upcoming", trackingItem)
      behavior.onZoneChanged(Context.GRID)

      expect(behavior.onEscape()).toBe("upcoming")
    })

    test("returns sidebar when in library browse grid (not via tracking drill-in)", () => {
      const behavior = createLibraryBehavior(mockDom())

      // Simulate: zone_tabs → grid (library browse, no onAction drill-in)
      behavior.onZoneChanged("ZONE_TABS")
      behavior.onZoneChanged(Context.GRID)

      expect(behavior.onEscape()).toBe("sidebar")
    })

    test("clears tracking drill-in state when leaving grid", () => {
      const behavior = createLibraryBehavior(mockDom())
      const trackingItem = { dataset: { sectionType: "tracking" } }

      // Enter tracking grid via onAction
      behavior.onZoneChanged("upcoming")
      behavior.onAction(Action.SELECT, "upcoming", trackingItem)
      behavior.onZoneChanged(Context.GRID)
      expect(behavior.onEscape()).toBe("upcoming")

      // Leave grid back to upcoming — drill-in flag cleared
      behavior.onZoneChanged("upcoming")
      expect(behavior.onEscape()).toBe("sidebar")

      // Enter library grid without drill-in
      behavior.onZoneChanged(Context.GRID)
      expect(behavior.onEscape()).toBe("sidebar")
    })

    test("preserves drill-in through modal overlay", () => {
      const behavior = createLibraryBehavior(mockDom())
      const trackingItem = { dataset: { sectionType: "tracking" } }

      // Drill into tracking grid
      behavior.onZoneChanged("upcoming")
      behavior.onAction(Action.SELECT, "upcoming", trackingItem)
      behavior.onZoneChanged(Context.GRID)

      // Confirmation modal opens (temporary overlay)
      behavior.onZoneChanged(Context.MODAL)

      // Modal closes, back to grid
      behavior.onZoneChanged(Context.GRID)

      // BACK should still return to upcoming, not sidebar
      expect(behavior.onEscape()).toBe("upcoming")
    })
  })

  describe("onAction()", () => {
    test("intercepts LEFT on calendar section to navigate prev month", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)
      const focused = { dataset: { sectionType: "calendar" } }

      const result = behavior.onAction(Action.NAVIGATE_LEFT, "upcoming", focused)

      expect(result).toBe(true)
      expect(dom.prevMonthClicked).toBe(true)
    })

    test("intercepts RIGHT on calendar section to navigate next month", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)
      const focused = { dataset: { sectionType: "calendar" } }

      const result = behavior.onAction(Action.NAVIGATE_RIGHT, "upcoming", focused)

      expect(result).toBe(true)
      expect(dom.nextMonthClicked).toBe(true)
    })

    test("does not intercept UP/DOWN on calendar", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)
      const focused = { dataset: { sectionType: "calendar" } }

      expect(behavior.onAction(Action.NAVIGATE_UP, "upcoming", focused)).toBe(false)
      expect(behavior.onAction(Action.NAVIGATE_DOWN, "upcoming", focused)).toBe(false)
    })

    test("intercepts SELECT on tracking section to drill into grid", () => {
      const behavior = createLibraryBehavior(mockDom())
      const focused = { dataset: { sectionType: "tracking" } }

      const result = behavior.onAction(Action.SELECT, "upcoming", focused)

      expect(result).toEqual({ transitionTo: Context.GRID })
    })

    test("does not intercept SELECT on non-tracking sections", () => {
      const behavior = createLibraryBehavior(mockDom())

      expect(behavior.onAction(Action.SELECT, "upcoming", { dataset: { sectionType: "released" } })).toBe(false)
      expect(behavior.onAction(Action.SELECT, "upcoming", { dataset: { sectionType: "scan" } })).toBe(false)
      expect(behavior.onAction(Action.SELECT, "upcoming", { dataset: { sectionType: "calendar" } })).toBe(false)
    })

    test("does not intercept actions in non-upcoming contexts", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)
      const focused = { dataset: { sectionType: "calendar" } }

      expect(behavior.onAction(Action.NAVIGATE_LEFT, "GRID", focused)).toBe(false)
      expect(behavior.onAction(Action.NAVIGATE_LEFT, "sidebar", focused)).toBe(false)
      expect(dom.prevMonthClicked).toBe(false)
    })

    test("returns false when focused item has no section type", () => {
      const behavior = createLibraryBehavior(mockDom())

      expect(behavior.onAction(Action.SELECT, "upcoming", { dataset: {} })).toBe(false)
      expect(behavior.onAction(Action.SELECT, "upcoming", null)).toBe(false)
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

  describe("onZoneChanged() scroll reset", () => {
    test("scrolls the page to the very top when focus reaches zone tabs", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)

      behavior.onZoneChanged(Context.ZONE_TABS)

      expect(dom.scrolledToTop).toBe(true)
    })

    test("does not scroll for non-zone-tabs contexts", () => {
      const dom = mockDom()
      const behavior = createLibraryBehavior(dom)

      behavior.onZoneChanged(Context.GRID)
      behavior.onZoneChanged("upcoming")
      behavior.onZoneChanged(Context.TOOLBAR)
      behavior.onZoneChanged(Context.MODAL)
      behavior.onZoneChanged(Context.DRAWER)
      behavior.onZoneChanged("sidebar")

      expect(dom.scrolledToTop).toBe(false)
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
