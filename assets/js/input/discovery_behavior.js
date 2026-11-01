/**
 * Discovery page behavior.
 *
 * Navigation is the framework's, via the `discovery` zone layout in
 * config.js (the omnibox over the hero over the shelves). The page's own
 * contribution is CLEAR: wipe the omnibox query — the one clearable text
 * surface — and stay where the cursor is. Clearing the query hands the
 * page back from the search results to the hero and the shelves.
 *
 * The DOM is injected, as the Incoming behavior's is.
 */

import { omniboxInput } from "./omnibox_clear"

/**
 * @typedef {Object} DiscoveryDom
 * @property {function(): {value: string, clear: function}|null} getOmniboxInput
 */

const REAL_DOM = {
  getOmniboxInput: omniboxInput,
}

/**
 * @param {DiscoveryDom} dom
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createDiscoveryBehavior(dom = REAL_DOM) {
  return {
    onAttach() {},
    onDetach() {},
    onClear() {
      const input = dom.getOmniboxInput()
      if (input && input.value) input.clear()
    },
  }
}

export { REAL_DOM as discoveryDom }
