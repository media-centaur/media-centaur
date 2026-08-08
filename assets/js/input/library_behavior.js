/**
 * Library page behavior.
 *
 * Extracts library-specific concerns from the orchestrator:
 * - Sort order tracking → signals grid memory clear
 * - CLEAR action clears the filter input
 * - BACK navigates to the sidebar
 *
 * Deliberately no scrolling here. The toolbar's resting place (page top,
 * header included) is declared on its markup via `data-nav-reveal-block`
 * plus a page-top scroll-margin, so `revealItem` glides there — an instant
 * window scroll from a behavior fights the glide already in flight.
 *
 * All external dependencies are injected via the `dom` parameter,
 * following the same DI pattern as the orchestrator itself.
 *
 * Tab, filter, and sort state live in the URL (managed by LiveView's
 * handle_params). The input system doesn't need to persist these —
 * the URL is the single source of truth.
 */

/**
 * @typedef {Object} LibraryDom
 * @property {function(): {value: string, clear: function}|null} getFilter
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
