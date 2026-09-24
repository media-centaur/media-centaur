/**
 * GamepadSource — translates gamepad input into semantic actions.
 *
 * Event-driven activation: registers passive listeners for gamepadconnected/
 * gamepaddisconnected. Only starts rAF polling when a gamepad is present.
 * Zero CPU when no gamepad connected.
 *
 * Implements the input source contract:
 *   constructor(config) — config includes onAction, onInputDetected callbacks
 *   start()            — begin listening
 *   stop()             — clean up
 */

import { buttonToAction, DEFAULT_BUTTON_MAP, Action } from "./actions"
import { controllerLayout, normalizeButtons, STANDARD_BUTTON_COUNT } from "./controller_layout"
import { debug } from "./debug"

export { detectControllerType } from "./controller_layout"

// Navigation actions that get repeat timing on D-pad buttons
const NAVIGATION_ACTIONS = new Set([
  Action.NAVIGATE_UP,
  Action.NAVIGATE_DOWN,
  Action.NAVIGATE_LEFT,
  Action.NAVIGATE_RIGHT,
])

export class GamepadSource {
  /**
   * @param {Object} config
   * @param {function} config.getGamepads - () => navigator.getGamepads()
   * @param {function} config.requestAnimationFrame
   * @param {function} config.cancelAnimationFrame
   * @param {function} config.addEventListener - window.addEventListener
   * @param {function} config.removeEventListener - window.removeEventListener
   * @param {function} [config.acceptsInput] - () => boolean. Whether this
   *   surface may accept gamepad input — focused, visible, and not an automation
   *   context (see input_gate.js). Defaults to always-on. When it returns false,
   *   all gamepad-driven actions are suppressed (see the gate in _poll).
   * @param {Object} [config.buttonMap] - Button-to-action map
   * @param {number} [config.deadzone=0.3] - Analog stick threshold
   * @param {number} [config.repeatDelay=400] - ms before first axis repeat
   * @param {number} [config.repeatInterval=180] - ms between axis repeats
   * @param {function} config.onAction - Callback: (action) => void
   * @param {function} config.onInputDetected - Callback: (type) => void
   * @param {function} [config.onControllerChanged] - Callback: (type) => void
   */
  constructor(config) {
    this._getGamepads = config.getGamepads
    this._requestAnimationFrame = config.requestAnimationFrame
    this._cancelAnimationFrame = config.cancelAnimationFrame
    this._addEventListener = config.addEventListener
    this._removeEventListener = config.removeEventListener
    this._acceptsInput = config.acceptsInput ?? (() => true)
    this._buttonMap = config.buttonMap ?? DEFAULT_BUTTON_MAP
    this._deadzone = config.deadzone ?? 0.3
    this._repeatDelay = config.repeatDelay ?? 400
    this._repeatInterval = config.repeatInterval ?? 180
    this._onAction = config.onAction
    this._onInputDetected = config.onInputDetected
    this._onControllerChanged = config.onControllerChanged

    // Pre-allocated state (no per-frame allocations). Every index here is a
    // standard-layout button index — see controller_layout.js.
    this._prevButtons = new Array(STANDARD_BUTTON_COUNT).fill(false)
    // Repeat timing for navigation buttons (D-pad): { startTime, lastFireTime } or null
    this._buttonRepeat = new Array(STANDARD_BUTTON_COUNT).fill(null)
    // Scratch space for this frame's normalized button state
    this._normalizedButtons = new Array(STANDARD_BUTTON_COUNT).fill(false)
    // Layout of the currently adopted device, or null when none is connected
    this._layout = null
    this._axisState = {
      x: { direction: null, startTime: 0, lastFireTime: 0 },
      y: { direction: null, startTime: 0, lastFireTime: 0 },
    }
    this._rafId = null
    this._lastGamepadId = null
    this._running = false
    // True while the gate is suppressing input (surface unfocused, hidden, or
    // automation). Tracked only to emit a single debug line on each transition.
    this._inputGateActive = false

    // Injectable clock for testing
    this._now = () => Date.now()

    this._onConnected = this._onConnected.bind(this)
    this._onDisconnected = this._onDisconnected.bind(this)
    this._poll = this._poll.bind(this)
  }

  start() {
    this._running = true
    this._addEventListener("gamepadconnected", this._onConnected)
    this._addEventListener("gamepaddisconnected", this._onDisconnected)

    // Check if a gamepad is already connected (handles page reload
    // or hook remount after sidebar navigation)
    const gamepads = this._getGamepads()
    for (const gp of gamepads) {
      if (gp?.connected) {
        this._adoptGamepad(gp)
        // Signal gamepad presence so the orchestrator sets input method
        // and starts the mousemove cooldown. Without this, a layout-shift
        // mousemove after hook remount would immediately reset to mouse.
        // Suppressed unless this surface may accept input — the gamepad must
        // not claim the input method for an unfocused, hidden, or automation
        // surface (e.g. a game has focus, or a headless debug browser).
        if (this._acceptsInput()) this._onInputDetected("gamepadbutton")
        // Prime button state so held buttons don't fire a false rising edge
        this._primeButtons(gp)
        this._startPolling()
        break
      }
    }
  }

  stop() {
    this._running = false
    this._removeEventListener("gamepadconnected", this._onConnected)
    this._removeEventListener("gamepaddisconnected", this._onDisconnected)
    this._stopPolling()
    this._resetState()
  }

  /**
   * Pause polling without tearing down connect/disconnect listeners.
   * Used when the document becomes hidden (workspace switch, tab change).
   * Clears repeat and axis state so no stale timers carry over on resume.
   */
  pause() {
    this._stopPolling()
    this._buttonRepeat.fill(null)
    this._axisState.x.direction = null
    this._axisState.y.direction = null
  }

  /**
   * Resume polling after a pause. Primes button state from the current
   * gamepad snapshot to prevent false rising edges from buttons that
   * changed state while the document was hidden.
   */
  resume() {
    if (!this._running) return
    const gamepads = this._getGamepads()
    for (const gp of gamepads) {
      if (gp?.connected) {
        this._primeButtons(gp)
        this._startPolling()
        return
      }
    }
  }

  _onConnected(event) {
    this._adoptGamepad(event.gamepad)
    if (!this._rafId) {
      this._startPolling()
    }
  }

  _onDisconnected() {
    // Check if any gamepads remain
    const gamepads = this._getGamepads()
    const anyConnected = gamepads.some(gp => gp?.connected)
    if (!anyConnected) {
      this._stopPolling()
      this._resetState()
    }
  }

  /**
   * Adopt a gamepad: derive its layout and announce the label family.
   *
   * Guarded on the device id, so calling it per frame costs one comparison and
   * the polling loop stays allocation-free. Every other method assumes
   * `_layout` matches the device being polled, which is what the guard buys.
   */
  _adoptGamepad(gamepad) {
    if (gamepad.id === this._lastGamepadId) return
    this._lastGamepadId = gamepad.id
    this._layout = controllerLayout(gamepad)
    debug("gamepad adopted:", gamepad.id, "layout:", this._layout.name, "labels:", this._layout.labels)
    this._onControllerChanged?.(this._layout.labels)
  }

  /**
   * Project this frame's raw snapshot onto standard-layout button state.
   * @returns {boolean[]} the source-owned scratch array
   */
  _normalizedButtonState(gamepad) {
    return normalizeButtons(gamepad, this._layout, this._deadzone, this._normalizedButtons)
  }

  /**
   * Read current button state without firing actions.
   * Prevents false rising edges when a button is already held
   * at the time polling starts (e.g. hook remount during sidebar nav).
   */
  _primeButtons(gamepad) {
    this._adoptGamepad(gamepad)
    const pressed = this._normalizedButtonState(gamepad)
    for (let i = 0; i < this._prevButtons.length; i++) {
      this._prevButtons[i] = pressed[i]
    }
  }

  _startPolling() {
    if (this._rafId) return
    this._rafId = this._requestAnimationFrame(this._poll)
  }

  _stopPolling() {
    if (this._rafId) {
      this._cancelAnimationFrame(this._rafId)
      this._rafId = null
    }
  }

  _resetState() {
    this._prevButtons.fill(false)
    this._buttonRepeat.fill(null)
    this._axisState.x.direction = null
    this._axisState.y.direction = null
    this._lastGamepadId = null
    this._layout = null
  }

  _poll() {
    this._rafId = null
    if (!this._running) return

    const gamepads = this._getGamepads()
    let gamepad = null
    for (const gp of gamepads) {
      if (gp?.connected) {
        gamepad = gp
        break
      }
    }

    if (!gamepad) {
      // Disconnect race — no gamepad found, stop loop
      this._resetState()
      return
    }

    // A device can appear or be swapped without an event reaching us, so the
    // layout is re-derived from whatever we are actually polling. Id-guarded.
    this._adoptGamepad(gamepad)

    // Input gate. The Gamepad API reports controller state globally — even when
    // this surface is not the one the user is looking at. Keyboard input is
    // naturally focus-scoped by the OS; gamepad polling is not. So suppress every
    // gamepad-driven action whenever this surface is not eligible to accept input
    // (unfocused, hidden, or an automation/headless context — see input_gate.js).
    // We keep priming button state and rescheduling the loop, so input resumes
    // the instant the surface becomes active again: event-independent (does not
    // rely on blur/focus firing, which is unreliable on tiling/multi-monitor WMs)
    // and self-healing. Priming also ensures a button held at the moment input
    // resumes does not register as a fresh press.
    if (!this._acceptsInput()) {
      if (!this._inputGateActive) {
        this._inputGateActive = true
        debug("gamepad suppressed — surface inactive (unfocused, hidden, or automation)")
      }
      this._primeButtons(gamepad)
      this._axisState.x.direction = null
      this._axisState.y.direction = null
      this._rafId = this._requestAnimationFrame(this._poll)
      return
    }
    if (this._inputGateActive) {
      this._inputGateActive = false
      debug("gamepad resumed — surface active")
    }

    try {
      this._pollButtons(gamepad)
      this._pollAxes(gamepad)
    } catch (error) {
      console.error("[GamepadSource] poll error:", error)
    }

    // Continue loop (don't hold gamepad reference)
    this._rafId = this._requestAnimationFrame(this._poll)
  }

  _pollButtons(gamepad) {
    // Standard-layout indices from here down, whatever the device reported.
    const buttons = this._normalizedButtonState(gamepad)
    const now = this._now()
    for (let i = 0; i < this._prevButtons.length; i++) {
      const pressed = buttons[i]
      const wasPressed = this._prevButtons[i]

      if (pressed && !wasPressed) {
        // Rising edge — button just pressed
        const action = buttonToAction(i, this._buttonMap)
        if (action) {
          this._onInputDetected("gamepadbutton")
          this._onAction(action)
          // Start repeat timer for navigation buttons
          if (NAVIGATION_ACTIONS.has(action)) {
            this._buttonRepeat[i] = { startTime: now, lastFireTime: now }
          }
        }
      } else if (pressed && wasPressed) {
        // Button held — check repeat for navigation buttons
        const repeat = this._buttonRepeat[i]
        if (repeat) {
          const elapsed = now - repeat.startTime
          const sinceLastFire = now - repeat.lastFireTime
          if (elapsed >= this._repeatDelay && sinceLastFire >= this._repeatInterval) {
            const action = buttonToAction(i, this._buttonMap)
            if (action) {
              repeat.lastFireTime = now
              this._onInputDetected("gamepadbutton")
              this._onAction(action)
            }
          }
        }
      } else if (!pressed && wasPressed) {
        // Released — clear repeat state
        this._buttonRepeat[i] = null
      }

      this._prevButtons[i] = pressed
    }
  }

  _pollAxes(gamepad) {
    const now = this._now()
    // The left stick only — a D-pad on hat axes is normalized into button
    // state instead, so it travels the same binding and repeat path as a real
    // D-pad rather than getting a second, parallel one here.
    const { x: stickX, y: stickY } = this._layout.stickAxes
    const axisX = gamepad.axes[stickX] ?? 0
    const axisY = gamepad.axes[stickY] ?? 0

    this._processAxis("x", axisX, Action.NAVIGATE_LEFT, Action.NAVIGATE_RIGHT, now)
    this._processAxis("y", axisY, Action.NAVIGATE_UP, Action.NAVIGATE_DOWN, now)
  }

  _processAxis(axis, value, negativeAction, positiveAction, now) {
    const state = this._axisState[axis]
    const magnitude = Math.abs(value)

    if (magnitude < this._deadzone) {
      // Below deadzone — reset
      if (state.direction) debug("gamepad axis", axis, "returned to center")
      state.direction = null
      return
    }

    const direction = value < 0 ? "negative" : "positive"
    const action = value < 0 ? negativeAction : positiveAction

    if (direction !== state.direction) {
      // New direction — fire immediately, start repeat timer
      debug("gamepad axis", axis, "new direction:", direction, "value:", value.toFixed(3), "action:", action)
      state.direction = direction
      state.startTime = now
      state.lastFireTime = now
      this._onInputDetected("gamepadaxis")
      this._onAction(action)
      return
    }

    // Same direction held — check repeat timing
    const elapsed = now - state.startTime
    const sinceLastFire = now - state.lastFireTime

    if (elapsed >= this._repeatDelay && sinceLastFire >= this._repeatInterval) {
      state.lastFireTime = now
      this._onInputDetected("gamepadaxis")
      this._onAction(action)
    }
  }
}
