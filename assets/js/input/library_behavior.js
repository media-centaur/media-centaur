/**
 * Library page behavior.
 *
 * Extracts library-specific concerns from the orchestrator:
 * - Sort order tracking → signals grid memory clear
 * - Escape clears the filter input
 *
 * All external dependencies are injected via the `dom` parameter,
 * following the same DI pattern as the orchestrator itself.
 *
 * Zone, filter, and sort state live in the URL (managed by LiveView's
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
 * @param {LibraryDom} dom - DOM interface for filter operations
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createLibraryBehavior(dom) {
  let lastSortOrder = null

  return {
    onAttach() {},
    onDetach() {},

    /**
     * Escape clears the library filter if it has content.
     * Returns true if consumed, false to let the orchestrator handle it.
     */
    onEscape() {
      const filter = dom.getFilter()
      if (filter && filter.value) {
        filter.clear()
        return true
      }
      return false
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
