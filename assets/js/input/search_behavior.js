/**
 * Search page behavior.
 *
 * Navigation is the framework's, via the `search` zone layout in
 * config.js (the omnibox over the hero over the shelves). The page's own
 * contribution is CLEAR: wipe the omnibox query — the one clearable text
 * surface — and stay where the cursor is. Clearing the query hands the
 * page back from the search results to the hero and the shelves.
 *
 * The DOM is injected, as the Downloads behavior's is.
 */

import { omniboxInput } from "./omnibox_clear"

/**
 * @typedef {Object} SearchDom
 * @property {function(): {value: string, clear: function}|null} getOmniboxInput
 */

const REAL_DOM = {
  getOmniboxInput: () => omniboxInput("omnibox-media-input"),
}

/**
 * @param {SearchDom} dom
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createSearchBehavior(dom = REAL_DOM) {
  return {
    onAttach() {},
    onDetach() {},
    onClear() {
      const input = dom.getOmniboxInput()
      if (input && input.value) input.clear()
    },
  }
}

export { REAL_DOM as searchDom }
