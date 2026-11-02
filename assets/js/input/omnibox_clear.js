/**
 * A search box's CLEAR, shared by the pages that carry one — Discovery's
 * media search (`#omnibox-media-input`) and Downloads' release search
 * (`#omnibox-release-input`): wipe the box client-side and dispatch
 * `input` so LiveView hears the change. Each behaviour names its own
 * input; one page renders one box.
 */

/** Wrap an input element in the {value, clear} interface, or null. */
export function clearableInput(el) {
  if (!el) return null
  return {
    get value() { return el.value },
    clear() {
      el.value = ""
      el.dispatchEvent(new Event("input", { bubbles: true }))
    },
  }
}

/** The page's search input by id, or null while the page does not render it. */
export function omniboxInput(id) {
  return clearableInput(document.getElementById(id))
}
