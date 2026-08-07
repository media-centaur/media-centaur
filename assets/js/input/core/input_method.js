/**
 * Input method detection — tracks whether the user is using
 * mouse, keyboard, or gamepad.
 *
 * Pure state machine. No DOM dependency.
 */

export const InputMethod = Object.freeze({
  MOUSE: "mouse",
  KEYBOARD: "keyboard",
  GAMEPAD: "gamepad",
})

export class InputMethodDetector {
  /**
   * Starts in KEYBOARD, not MOUSE. This is a ten-foot appliance: the cursor is
   * already parked on a page's primary action at load (the home hero's Play
   * button), and it has to look parked there. Defaulting to MOUSE left the
   * focus ring unpainted until the first keypress, so a fresh load — or a hard
   * reload — read as "nothing is selected". A genuine mouse user is switched
   * over by their first pointer movement, which costs them one frame of an
   * extra ring. `root.html.heex` carries the matching static `data-input` so
   * the very first paint agrees, before this ever runs.
   */
  constructor(initial = InputMethod.KEYBOARD) {
    this._current = initial
  }

  get current() {
    return this._current
  }

  /**
   * Observe a raw event type and return the new input method,
   * or null if unchanged.
   *
   * @param {string} eventType - DOM event type (keydown, mousemove, gamepadconnected, etc.)
   * @returns {string|null} New InputMethod value, or null if no change
   */
  observe(eventType) {
    let next

    switch (eventType) {
      case "keydown":
      case "keyup":
        next = InputMethod.KEYBOARD
        break

      case "mousemove":
      case "mousedown":
      case "click":
      case "wheel":
        next = InputMethod.MOUSE
        break

      case "gamepadbutton":
      case "gamepadaxis":
        next = InputMethod.GAMEPAD
        break

      default:
        return null
    }

    if (next === this._current) return null
    this._current = next
    return next
  }
}
