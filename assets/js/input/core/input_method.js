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
  constructor(initial = InputMethod.MOUSE) {
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
