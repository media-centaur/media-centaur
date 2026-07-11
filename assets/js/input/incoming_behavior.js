/**
 * Incoming page behavior.
 *
 * Navigation (including left-at-the-edge into the sidebar) is handled by
 * the framework via the `incoming` zone layout in config.js. The page's
 * own contribution is CLEAR: the page has two clearable text
 * surfaces — the omnibox query (the page's primary search) and the History
 * zone's title filter. CLEAR wipes the omnibox first; when it is already
 * empty it falls through to the history search. Focus stays where it is —
 * unlike the library (where clearing the filter jumps focus into the
 * unfiltered grid), neither clear changes what zone the user should be in.
 *
 * All external dependencies are injected via the `dom` parameter, following
 * the same DI pattern as the library behavior.
 */

/**
 * @typedef {Object} IncomingDom
 * @property {function(): {value: string, clear: function}|null} getOmniboxInput
 * @property {function(): {value: string, clear: function}|null} getHistorySearch
 */

/** Wrap an input element in the {value, clear} interface, or null. */
function clearableInput(el) {
  if (!el) return null
  return {
    get value() { return el.value },
    clear() {
      el.value = ""
      el.dispatchEvent(new Event("input", { bubbles: true }))
    },
  }
}

/** Default DOM implementation for production use. */
const REAL_DOM = {
  getOmniboxInput() {
    // One mode's input is rendered at a time (media vs release search).
    const el = document.getElementById("omnibox-media-input")
      ?? document.getElementById("omnibox-release-input")
    return clearableInput(el)
  },
  getHistorySearch() {
    return clearableInput(document.querySelector("[data-nav-zone='history'] input[type='search']"))
  },
}

/**
 * Create a download page behavior instance.
 * @param {IncomingDom} dom - DOM interface for the clearable inputs
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createIncomingBehavior(dom = REAL_DOM) {
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
export { REAL_DOM as incomingDom }
