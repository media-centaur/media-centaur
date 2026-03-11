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

// Navigation actions that get repeat timing on D-pad buttons
const NAVIGATION_ACTIONS = new Set([
  Action.NAVIGATE_UP,
  Action.NAVIGATE_DOWN,
  Action.NAVIGATE_LEFT,
  Action.NAVIGATE_RIGHT,
])

/**
 * Detect controller type from gamepad.id string.
 * @param {string} id - Gamepad.id
 * @returns {"xbox"|"playstation"|"generic"}
 */
export function detectControllerType(id) {
  const lower = id.toLowerCase()
  if (lower.includes("xbox") || lower.includes("xinput")) return "xbox"
  if (lower.includes("playstation") || lower.includes("dualshock") || lower.includes("dualsense") || lower.includes("sony")) return "playstation"
  return "generic"
}

export class GamepadSource {
  /**
   * @param {Object} config
   * @param {function} config.getGamepads - () => navigator.getGamepads()
   * @param {function} config.requestAnimationFrame
   * @param {function} config.cancelAnimationFrame
   * @param {function} config.addEventListener - window.addEventListener
   * @param {function} config.removeEventListener - window.removeEventListener
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
    this._buttonMap = config.buttonMap ?? DEFAULT_BUTTON_MAP
    this._deadzone = config.deadzone ?? 0.3
    this._repeatDelay = config.repeatDelay ?? 400
    this._repeatInterval = config.repeatInterval ?? 180
    this._onAction = config.onAction
    this._onInputDetected = config.onInputDetected
    this._onControllerChanged = config.onControllerChanged

    // Pre-allocated state (no per-frame allocations)
    this._prevButtons = new Array(17).fill(false)
    // Repeat timing for navigation buttons (D-pad): { startTime, lastFireTime } or null
    this._buttonRepeat = new Array(17).fill(null)
    this._axisState = {
      x: { direction: null, startTime: 0, lastFireTime: 0 },
      y: { direction: null, startTime: 0, lastFireTime: 0 },
    }
    this._rafId = null
    this._lastGamepadId = null
    this._running = false

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
        this._detectController(gp)
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

  _onConnected(event) {
    this._detectController(event.gamepad)
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

  _detectController(gamepad) {
    if (gamepad.id !== this._lastGamepadId) {
      this._lastGamepadId = gamepad.id
      const type = detectControllerType(gamepad.id)
      this._onControllerChanged?.(type)
    }
  }

  /**
   * Read current button state without firing actions.
   * Prevents false rising edges when a button is already held
   * at the time polling starts (e.g. hook remount during sidebar nav).
   */
  _primeButtons(gamepad) {
    const buttons = gamepad.buttons
    for (let i = 0; i < this._prevButtons.length && i < buttons.length; i++) {
      this._prevButtons[i] = buttons[i].pressed
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
    const buttons = gamepad.buttons
    const now = this._now()
    for (let i = 0; i < this._prevButtons.length && i < buttons.length; i++) {
      const pressed = buttons[i].pressed
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
    const axisX = gamepad.axes[0] ?? 0
    const axisY = gamepad.axes[1] ?? 0

    this._processAxis("x", axisX, Action.NAVIGATE_LEFT, Action.NAVIGATE_RIGHT, now)
    this._processAxis("y", axisY, Action.NAVIGATE_UP, Action.NAVIGATE_DOWN, now)
  }

  _processAxis(axis, value, negativeAction, positiveAction, now) {
    const state = this._axisState[axis]
    const magnitude = Math.abs(value)

    if (magnitude < this._deadzone) {
      // Below deadzone — reset
      state.direction = null
      return
    }

    const direction = value < 0 ? "negative" : "positive"
    const action = value < 0 ? negativeAction : positiveAction

    if (direction !== state.direction) {
      // New direction — fire immediately, start repeat timer
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
