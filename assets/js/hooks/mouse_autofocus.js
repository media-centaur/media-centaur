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
//
// A touch screen reads as the mouse: a tap raises the mouse compatibility
// events, so a phone arrives on Discovery with `data-input="mouse"`. There
// the affordance inverts — focusing the box raises the on-screen keyboard
// over the page the user just opened — so on a coarse pointer focus is by
// tap only. The pointer class is the browser's media feature, never the
// device (the compact shell's one rule for input sizing).

/**
 * Should an element autofocus on mount, given the active input method and
 * the pointer class? Only a fine pointer (mouse, or the unset default) opts
 * in; keyboard/gamepad keep focus with the input system, and a coarse
 * pointer waits for the tap.
 * @param {string|null|undefined} inputMethod - value of <html data-input>
 * @param {boolean} coarsePointer - `(pointer: coarse)` matches
 * @returns {boolean}
 */
export function shouldAutofocus(inputMethod, coarsePointer = false) {
  if (coarsePointer) return false
  return inputMethod == null || inputMethod === "" || inputMethod === "mouse"
}

// The live gate: the active input method and the pointer class.
export function autofocusAllowed() {
  return shouldAutofocus(
    document.documentElement.dataset.input,
    window.matchMedia("(pointer: coarse)").matches
  )
}

export const MouseAutofocus = {
  mounted() {
    if (autofocusAllowed()) {
      this.el.focus()
    }
  },
}
