/**
 * ControlsBridge — connects the Controls LiveView to the input system.
 *
 * Two jobs:
 *   1. One-shot capture — when the LiveView enters listening state, install
 *      a capture-phase keydown (or gamepad button) listener that fires
 *      exactly once, then pushes the captured value back as "controls:bind".
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
   */
  constructor(config) {
    this._window = config.window
    this._pushEvent = config.pushEvent
  }

  /**
   * Begin listening for the next keyboard event. Escape cancels.
   * @param {{id: string}} ctx
   */
  listenKeyboard(ctx = {}) {
    const handler = (event) => {
      event.preventDefault()
      event.stopPropagation()

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
  }

  /**
   * Begin listening for the next gamepad button edge. External polling
   * from the existing GamepadSource emits a custom event that we listen
   * to — avoiding duplicate polling loops.
   *
   * @param {{id: string}} ctx
   */
  listenGamepad(ctx = {}) {
    const handler = (event) => {
      const button = event.detail?.button
      this._pushEvent("controls:bind", {
        id: ctx.id,
        kind: "gamepad",
        value: button,
      })
    }

    this._window.addEventListener("input:gamepadCapture", handler, { once: true })
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
