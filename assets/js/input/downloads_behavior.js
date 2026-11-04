/**
 * Downloads page behavior.
 *
 * Navigation is handled by the framework via the `downloads` zone layout in
 * config.js. The page's own contribution is CLEAR: the page has two
 * clearable text surfaces — the release search box and the History zone's
 * title filter. CLEAR wipes the search box first; when it is already empty
 * it falls through to the history search. Focus stays where it is — unlike
 * the library (where clearing the filter jumps focus into the unfiltered
 * grid), neither clear changes what zone the user should be in.
 *
 * All external dependencies are injected via the `dom` parameter, following
 * the same DI pattern as the library behavior.
 */

/**
 * @typedef {Object} DownloadsDom
 * @property {function(): {value: string, clear: function}|null} getOmniboxInput
 * @property {function(): {value: string, clear: function}|null} getHistorySearch
 */

import { clearableInput, omniboxInput } from "./omnibox_clear"

/** Default DOM implementation for production use. */
const REAL_DOM = {
  getOmniboxInput: () => omniboxInput("omnibox-release-input"),
  getHistorySearch() {
    return clearableInput(document.getElementById("history-search"))
  },
}

/**
 * Create a download page behavior instance.
 * @param {DownloadsDom} dom - DOM interface for the clearable inputs
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createDownloadsBehavior(dom = REAL_DOM) {
  return {
    onAttach() {},
    onDetach() {},

    /**
     * CLEAR wipes the first non-empty clearable input: omnibox query,
     * then history search. Returns undefined — focus stays put.
     */
    onClear() {
      for (const input of [dom.getOmniboxInput(), dom.getHistorySearch()]) {
        if (input && input.value) {
          input.clear()
          return
        }
      }
    },
  }
}

/** Re-export the real DOM for the registry to pass through in production. */
export { REAL_DOM as downloadsDom }
