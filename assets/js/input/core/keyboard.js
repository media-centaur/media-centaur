/**
 * KeyboardSource — translates keyboard events into semantic actions.
 *
 * Owns keyboard-specific concerns: keydown listener, text input two-mode
 * handling, data-captures-keys bypass, and key-to-action mapping.
 *
 * Implements the input source contract:
 *   constructor(config) — config includes onAction, onInputDetected callbacks
 *   start()            — begin listening
 *   stop()             — clean up
 */

import { keyToAction, DEFAULT_KEY_MAP } from "./actions"

const TEXT_INPUT_ELEMENTS = new Set(["INPUT", "TEXTAREA"])

export class KeyboardSource {
  /**
   * @param {Object} config
   * @param {Object} config.document - Document for addEventListener
   * @param {Object} [config.keyMap] - Key-to-action map (defaults to DEFAULT_KEY_MAP)
   * @param {function} config.onAction - Callback: (action) => void
   * @param {function} config.onInputDetected - Callback: (type) => void
   */
  constructor(config) {
    this._document = config.document
    this._keyMap = config.keyMap ?? DEFAULT_KEY_MAP
    this._onAction = config.onAction
    this._onInputDetected = config.onInputDetected
    this._inputEditing = false
    this._handleKeyDown = this._handleKeyDown.bind(this)
  }

  start() {
    this._document.addEventListener("keydown", this._handleKeyDown)
  }

  stop() {
    this._document.removeEventListener("keydown", this._handleKeyDown)
    this._inputEditing = false
  }

  /**
   * Pause keyboard listening without resetting editing state.
   * Used when the document becomes hidden (workspace switch, tab change).
   */
  pause() {
    this._document.removeEventListener("keydown", this._handleKeyDown)
  }

  /**
   * Resume keyboard listening after a pause.
   * Preserves editing state across visibility changes.
   */
  resume() {
    this._document.addEventListener("keydown", this._handleKeyDown)
  }

  _handleKeyDown(event) {
    this._onInputDetected("keydown")

    // Elements with data-captures-keys handle their own keyboard interaction
    if (event.target?.closest("[data-captures-keys]")) {
      return
    }

    const isTextInput = TEXT_INPUT_ELEMENTS.has(event.target?.tagName)

    if (isTextInput) {
      // Escape on a text input: clear value, exit edit mode
      if (event.key === "Escape") {
        if (event.target.value) {
          event.target.value = ""
          event.target.dispatchEvent(new Event("input", { bubbles: true }))
        }
        this._inputEditing = false
        event.preventDefault()
        return
      }

      if (this._inputEditing) {
        // Enter exits edit mode back to navigation
        if (event.key === "Enter") {
          this._inputEditing = false
          event.preventDefault()
        }
        // All other keys pass through to the input
        return
      }

      // Focused but not editing — Enter activates edit mode
      if (event.key === "Enter") {
        this._inputEditing = true
        event.preventDefault()
        return
      }

      // Printable character → activate edit mode and let it type
      if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
        this._inputEditing = true
        return
      }

      // Arrow keys / other nav keys — handle as normal navigation
      const action = keyToAction(event.key, { targetIsInput: false }, this._keyMap)
      if (!action) return
      event.preventDefault()
      this._onAction(action)
      return
    }

    // Normal (non-text-input) key handling
    const action = keyToAction(event.key, { targetIsInput: false }, this._keyMap)
    if (!action) return

    event.preventDefault()
    // Stop bubbling so LiveView's phx-window-keydown (on window) never fires.
    // The input system is the sole keyboard authority when active.
    event.stopPropagation()
    this._onAction(action)
  }

  /**
   * Reset editing state. Called by orchestrator when navigating away
   * from a text input via a non-keyboard source action.
   */
  resetEditing() {
    this._inputEditing = false
  }
}
