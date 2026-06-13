// MouseAutofocus — focus an element on mount ONLY when the user is driving
// with the mouse.
//
// Expected shape:
//   <input phx-hook="MouseAutofocus" id="..." />
//
// Autofocus-on-mount is a pointer affordance: a mouse user who lands on a
// search surface expects the cursor already in the box. For keyboard and
// gamepad users the input system owns focus (see ADR-053, focus-ownership
// boundary) — an unconditional `phx-mounted={JS.focus()}` yanks focus out of
// navigation the instant the page renders. That is the downloads-omnibox bug:
// keyboard-navigating the sidebar onto /download would steal focus into the
// query box.
//
// `data-input` on <html> is the single-owner projection of the active input
// method (mouse/keyboard/gamepad). It survives live_redirect — destroy() only
// writes sessionStorage, never resets the attribute — so reading it at mount
// is race-free regardless of hook mount ordering.

/**
 * Should an element autofocus on mount, given the active input method?
 * Only the pointer (mouse, or the unset default) opts in; keyboard/gamepad
 * keep focus with the input system.
 * @param {string|null|undefined} inputMethod - value of <html data-input>
 * @returns {boolean}
 */
export function shouldAutofocus(inputMethod) {
  return inputMethod == null || inputMethod === "" || inputMethod === "mouse"
}

export const MouseAutofocus = {
  mounted() {
    if (shouldAutofocus(document.documentElement.dataset.input)) {
      this.el.focus()
    }
  },
}
