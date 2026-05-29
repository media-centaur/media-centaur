/**
 * Library page behavior.
 *
 * Extracts library-specific concerns from the orchestrator:
 * - Sort order tracking → signals grid memory clear
 * - CLEAR action clears the filter input
 * - BACK navigates to the sidebar
 * - Reaching the toolbar (the topmost context) pins the page to the top so
 *   the header and tabs are fully visible
 *
 * All external dependencies are injected via the `dom` parameter,
 * following the same DI pattern as the orchestrator itself.
 *
 * Tab, filter, and sort state live in the URL (managed by LiveView's
 * handle_params). The input system doesn't need to persist these —
 * the URL is the single source of truth.
 */

import { Context } from "./core/index.js"

/**
 * @typedef {Object} LibraryDom
 * @property {function(): {value: string, clear: function}|null} getFilter
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
  scrollToTop() {
    window.scrollTo({ top: 0, behavior: "instant" })
  },
}

/**
 * Create a library page behavior instance.
 * @param {LibraryDom} dom - DOM interface for filter and scroll operations
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createLibraryBehavior(dom) {
  let lastSortOrder = null

  return {
    onAttach() {},
    onDetach() {},

    /**
     * Reaching the toolbar means the user has navigated to the top of the
     * library view — pin the page to the very top so the header and tabs are
     * fully visible (scrollIntoView("nearest") stops flush with the tab,
     * clipping the main padding above it).
     */
    onZoneChanged(context) {
      if (context === Context.TOOLBAR) {
        dom.scrollToTop()
      }
    },

    /**
     * BACK navigates to the sidebar.
     */
    onEscape() {
      return "sidebar"
    },

    /**
     * CLEAR clears the library filter if it has content.
     *
     * Returns "grid" when a clear happens so the orchestrator follows focus
     * into the now-unfiltered grid — otherwise focus stayed in the toolbar
     * and the user had to manually navigate down to see their library.
     */
    onClear() {
      const filter = dom.getFilter()
      if (filter && filter.value) {
        filter.clear()
        return "grid"
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
