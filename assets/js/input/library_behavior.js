/**
 * Library page behavior.
 *
 * Extracts library-specific concerns from the orchestrator:
 * - Sort order tracking → signals grid memory clear
 * - CLEAR action clears the filter input
 * - BACK navigates to the sidebar (or sections from tracking grid)
 * - Upcoming zone: calendar left/right changes month, tracking SELECT
 *   drills into tracking card grid
 *
 * All external dependencies are injected via the `dom` parameter,
 * following the same DI pattern as the orchestrator itself.
 *
 * Zone, filter, and sort state live in the URL (managed by LiveView's
 * handle_params). The input system doesn't need to persist these —
 * the URL is the single source of truth.
 */

import { Action, Context } from "./core/index.js"

/**
 * @typedef {Object} LibraryDom
 * @property {function(): {value: string, clear: function}|null} getFilter
 * @property {function(): void} clickPrevMonth
 * @property {function(): void} clickNextMonth
 * @property {function(): void} scrollToTop
 */

/** Default DOM implementation for production use. */
const REAL_DOM = {
  getFilter() {
    const el = document.getElementById("library-filter")
    if (!el) return null
    return {
      get value() { return el.value },
      clear() {
        el.value = ""
        el.dispatchEvent(new Event("input", { bubbles: true }))
      },
    }
  },
  clickPrevMonth() {
    document.querySelector("[phx-click='prev_month']")?.click()
  },
  clickNextMonth() {
    document.querySelector("[phx-click='next_month']")?.click()
  },
  scrollToTop() {
    window.scrollTo({ top: 0, behavior: "instant" })
  },
}

/**
 * Create a library page behavior instance.
 * @param {LibraryDom} dom - DOM interface for filter and calendar operations
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createLibraryBehavior(dom) {
  let lastSortOrder = null
  let currentContext = null
  // Set by onAction when tracking drill-in happens, cleared when leaving grid
  let trackingDrillIn = false

  return {
    onAttach() {},
    onDetach() {},

    /**
     * Track context changes — clear tracking drill-in flag when leaving grid.
     */
    onZoneChanged(context) {
      // Only clear drill-in on real context changes, not temporary overlays
      if (context !== Context.GRID && context !== Context.MODAL && context !== Context.DRAWER) {
        trackingDrillIn = false
      }
      // Reaching the zone tabs means the user has navigated to the top of
      // the library view — pin the page to the very top so the tabs and
      // top padding are fully visible (scrollIntoView("nearest") stops
      // flush with the tab, clipping the main padding above it).
      if (context === Context.ZONE_TABS) {
        dom.scrollToTop()
      }
      currentContext = context
    },

    /**
     * Intercept actions in the upcoming zone:
     * - Calendar: LEFT/RIGHT changes month
     * - Tracking section: SELECT drills into tracking card grid
     */
    onAction(action, context, focused) {
      if (context !== "upcoming") return false

      const sectionType = focused?.dataset?.sectionType

      // Calendar: left/right navigates months
      if (sectionType === "calendar") {
        if (action === Action.NAVIGATE_LEFT) {
          dom.clickPrevMonth()
          return true
        }
        if (action === Action.NAVIGATE_RIGHT) {
          dom.clickNextMonth()
          return true
        }
      }

      // Tracking section: SELECT drills into tracking card grid
      if (sectionType === "tracking" && action === Action.SELECT) {
        trackingDrillIn = true
        return { transitionTo: Context.GRID }
      }

      return false
    },

    /**
     * BACK navigates to upcoming sections from tracking grid, sidebar otherwise.
     */
    onEscape() {
      if (currentContext === Context.GRID && trackingDrillIn) return "upcoming"
      return "sidebar"
    },

    /**
     * CLEAR clears the library filter if it has content.
     */
    onClear() {
      const filter = dom.getFilter()
      if (filter && filter.value) {
        filter.clear()
      }
    },

    /**
     * Check if sort order changed and signal that grid memory should clear.
     * @param {Object} reader - The DomReader interface
     * @returns {{ clearGridMemory: boolean }}
     */
    onSyncState(reader) {
      const sortOrder = reader.getSortOrder()
      if (sortOrder && sortOrder !== lastSortOrder) {
        lastSortOrder = sortOrder
        return { clearGridMemory: true }
      }
      return { clearGridMemory: false }
    },
  }
}

/** Re-export the real DOM for the registry to pass through in production. */
export { REAL_DOM as libraryDom }
