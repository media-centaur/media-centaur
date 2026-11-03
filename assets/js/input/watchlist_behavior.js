/**
 * Watchlist page behaviour (campaign discovery.md, M15).
 *
 * Navigation is the framework's, via the `watchlist` zone layout in
 * config.js: the toolbar over the rows (a TREE across the rung groups, a
 * row's rung select its sub-item, the open menu nested). The page's own
 * contribution is CLEAR, which wipes the search over the names; focus
 * stays put, since the narrowed rows are where the cursor already is.
 *
 * The DOM is injected, as the Downloads and Discovery behaviours do.
 */

import { clearableInput } from "./omnibox_clear"

/** Default DOM implementation for production use. */
const REAL_DOM = {
  getSearchInput: () => clearableInput(document.getElementById("watchlist-search")),
}

/**
 * @param {{getSearchInput: function(): {value: string, clear: function}|null}} dom
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createWatchlistBehavior(dom = REAL_DOM) {
  return {
    onClear() {
      const input = dom.getSearchInput()
      if (input && input.value) input.clear()
    },
  }
}

export { REAL_DOM as watchlistDom }
