/**
 * Watch history page behavior.
 *
 * Navigation is the framework's, via the `watch_history` zone layout in
 * config.js: the toolbar (type filter, search, the date chip while a day is
 * picked) over the `history_rows` tree — one item per row, its Remove the
 * row's sub-item, then the pager. The heatmap is not a nav zone: picking a
 * day from it is pointer-only, and the date chip clears it.
 *
 * The page's own contribution is CLEAR: it wipes the search, sets the type
 * filter back to All and drops the date chip — each through the control the
 * page already draws, so the LiveView hears the same events a click sends.
 * Focus stays put.
 *
 * The DOM is injected, as the Watchlist and Library behaviours do.
 */

import { clearableInput } from "./omnibox_clear"

/** Default DOM implementation for production use. */
const REAL_DOM = {
  getSearchInput: () => clearableInput(document.getElementById("history-search")),
  resetType() {
    const all = document.querySelector("#history-filter [phx-value-choice='all']")
    if (all && all.getAttribute("aria-pressed") !== "true") all.click()
  },
  clearDate() {
    document.getElementById("history-date-filter")?.click()
  },
}

/**
 * @param {{getSearchInput: function(): {value: string, clear: function}|null, resetType: function(), clearDate: function()}} dom
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createWatchHistoryBehavior(dom = REAL_DOM) {
  return {
    onClear() {
      const input = dom.getSearchInput()
      if (input && input.value) input.clear()
      dom.resetType()
      dom.clearDate()
    },
  }
}
