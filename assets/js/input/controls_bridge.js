/**
 * ControlsBridge — connects the Controls LiveView to the input system.
 *
 * Two jobs:
 *   1. One-shot capture — when the LiveView enters listening state, take
 *      the next key (a capture-phase keydown, ahead of KeyboardSource) or
 *      the next gamepad button (GamepadSource.captureNext, ahead of its
 *      button map) and push it back as "controls:bind". Escape cancels
 *      either; the key is swallowed so BACK never fires from it.
 *   2. Hot-swap — on `phx:controls:updated` from the server, dispatch a
 *      DOM event that the input system (orchestrator/sources) listens for
 *      to rebuild its key/button maps without a page reload.
 *
 * The bridge is instantiated inside the LiveView hook's mounted() and its
 * methods are invoked from LiveView handleEvent callbacks.
 */

export class ControlsBridge {
  /**
   * @param {Object} config
   * @param {Object} config.window - Window (or test double) with addEventListener
   * @param {Function} config.pushEvent - (eventName, payload) => void — LiveView hook's pushEvent
   * @param {Function} [config.captureGamepadButton] - (fn) => cancel; hands the
   *   next gamepad button index to fn (GamepadSource.captureNext). Absent when
   *   no gamepad source exists: a gamepad listen then waits for nothing.
   */
  constructor(config) {
    this._window = config.window
    this._pushEvent = config.pushEvent
    this._captureGamepadButton = config.captureGamepadButton ?? null
    this._cancelPending = null
  }

  /**
   * Begin listening for the next keyboard event. Escape cancels.
   * @param {{id: string}} ctx
   */
  listenKeyboard(ctx = {}) {
    this.cancel()

    const handler = (event) => {
      event.preventDefault()
      event.stopPropagation()
      this._cancelPending = null

      if (event.key === "Escape") {
        this._pushEvent("controls:cancel", {})
        return
      }

      this._pushEvent("controls:bind", {
        id: ctx.id,
        kind: "keyboard",
        value: event.key,
      })
    }

    this._window.addEventListener("keydown", handler, { capture: true, once: true })
    this._cancelPending = () => this._window.removeEventListener("keydown", handler, { capture: true })
  }

  /**
   * Begin listening for the next gamepad button. Escape on the keyboard
   * cancels, as it does for a key — the keyboard keeps navigating while a
   * pad slot listens, so a swallowed Escape is the one way out that is
   * not itself a button.
   *
   * @param {{id: string}} ctx
   */
  listenGamepad(ctx = {}) {
    this.cancel()
    if (!this._captureGamepadButton) return

    const onEscape = (event) => {
      if (event.key !== "Escape") return
      event.preventDefault()
      event.stopPropagation()
      this.cancel()
      this._pushEvent("controls:cancel", {})
    }

    const cancelCapture = this._captureGamepadButton((button) => {
      this._window.removeEventListener("keydown", onEscape, { capture: true })
      this._cancelPending = null
      this._pushEvent("controls:bind", {
        id: ctx.id,
        kind: "gamepad",
        value: button,
      })
    })

    this._window.addEventListener("keydown", onEscape, { capture: true })
    this._cancelPending = () => {
      cancelCapture()
      this._window.removeEventListener("keydown", onEscape, { capture: true })
    }
  }

  /** Drop whatever is pending — a new listen, or the hook going away. */
  cancel() {
    const pending = this._cancelPending
    this._cancelPending = null
    if (pending) pending()
  }

  /**
   * Dispatch a DOM event that the input system's orchestrator listens for
   * to rebuild its key and button maps.
   *
   * @param {{keyboard: Object<string, string>, gamepad: Object<number, string>}} maps
   */
  updateMaps(maps) {
    this._window.dispatchEvent(new CustomEvent("input:rebindMaps", { detail: maps }))
  }
}
