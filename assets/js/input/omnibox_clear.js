/**
 * The omnibox's CLEAR, shared by the pages that host the media search
 * (Discovery, and Incoming until cutover): wipe the box client-side and
 * dispatch `input` so LiveView hears the change. One mode's input is
 * rendered at a time (media vs release search on Incoming).
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

/** The rendered omnibox input, whichever mode is up. */
export function omniboxInput() {
  const el = document.getElementById("omnibox-media-input")
    ?? document.getElementById("omnibox-release-input")
  return clearableInput(el)
}
