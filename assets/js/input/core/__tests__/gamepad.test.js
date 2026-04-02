import { describe, expect, test, beforeEach, mock } from "bun:test"
import { GamepadSource, detectControllerType } from "../gamepad"
import { Action } from "../actions"

function createMockGamepadEnv() {
  const listeners = {}
  let gamepads = [null, null, null, null]
  const rafCallbacks = []
  let rafId = 1

  return {
    addEventListener(type, fn) {
      listeners[type] = listeners[type] || []
      listeners[type].push(fn)
    },
    removeEventListener(type, fn) {
      if (listeners[type]) {
        listeners[type] = listeners[type].filter(f => f !== fn)
      }
    },
    getGamepads: () => [...gamepads],
    requestAnimationFrame(fn) {
      const id = rafId++
      rafCallbacks.push({ id, fn })
      return id
    },
    cancelAnimationFrame(id) {
      const index = rafCallbacks.findIndex(c => c.id === id)
      if (index >= 0) rafCallbacks.splice(index, 1)
    },
    // Test helpers
    _listeners: listeners,
    _rafCallbacks: rafCallbacks,
    _setGamepad(index, gamepad) {
      gamepads[index] = gamepad
    },
    _clearGamepads() {
      gamepads = [null, null, null, null]
    },
    _dispatchEvent(type, detail = {}) {
      for (const fn of (listeners[type] || [])) {
        fn(detail)
      }
    },
    _flushRAF() {
      const cbs = rafCallbacks.splice(0)
      cbs.forEach(({ fn }) => fn())
    },
    _tickRAF(count = 1) {
      for (let i = 0; i < count; i++) {
        const cbs = rafCallbacks.splice(0)
        cbs.forEach(({ fn }) => fn())
      }
    },
  }
}

function makeGamepad(overrides = {}) {
  const buttons = Array.from({ length: 17 }, () => ({ pressed: false }))
  return {
    connected: true,
    id: "Xbox 360 Controller (STANDARD GAMEPAD)",
    buttons,
    axes: [0, 0, 0, 0],
    ...overrides,
  }
}

describe("GamepadSource", () => {
  let env, actions, inputDetections, controllerChanges, source

  beforeEach(() => {
    env = createMockGamepadEnv()
    actions = []
    inputDetections = []
    controllerChanges = []
    source = new GamepadSource({
      getGamepads: env.getGamepads,
      requestAnimationFrame: env.requestAnimationFrame,
      cancelAnimationFrame: env.cancelAnimationFrame,
      addEventListener: env.addEventListener,
      removeEventListener: env.removeEventListener,
      onAction: (action) => actions.push(action),
      onInputDetected: (type) => inputDetections.push(type),
      onControllerChanged: (type) => controllerChanges.push(type),
      deadzone: 0.3,
      repeatDelay: 400,
      repeatInterval: 180,
    })
  })

  describe("idle-until-connected lifecycle", () => {
    test("start registers gamepad event listeners", () => {
      source.start()
      expect(env._listeners.gamepadconnected?.length).toBe(1)
      expect(env._listeners.gamepaddisconnected?.length).toBe(1)
    })

    test("no rAF loop when no gamepad connected", () => {
      source.start()
      expect(env._rafCallbacks.length).toBe(0)
    })

    test("rAF loop starts on gamepadconnected", () => {
      source.start()
      env._setGamepad(0, makeGamepad())
      env._dispatchEvent("gamepadconnected", { gamepad: makeGamepad() })

      expect(env._rafCallbacks.length).toBe(1)
    })

    test("rAF loop stops when last gamepad disconnects", () => {
      source.start()
      env._setGamepad(0, makeGamepad())
      env._dispatchEvent("gamepadconnected", { gamepad: makeGamepad() })
      expect(env._rafCallbacks.length).toBe(1)

      // Disconnect
      env._clearGamepads()
      env._dispatchEvent("gamepaddisconnected", { gamepad: makeGamepad() })

      // Pending rAF should be cancelled
      expect(source._rafId).toBe(null)
    })

    test("handles gamepad already connected on start (page reload)", () => {
      env._setGamepad(0, makeGamepad())
      source.start()

      // Should detect the already-connected gamepad and start polling
      expect(env._rafCallbacks.length).toBe(1)
      // Should signal gamepad presence for input method detection
      expect(inputDetections).toEqual(["gamepadbutton"])
    })

    test("buttons held during start do not fire false rising edge", () => {
      const gamepad = makeGamepad()
      // D-pad down is already held when source starts (e.g. hook remount)
      gamepad.buttons[13] = { pressed: true }
      env._setGamepad(0, gamepad)

      source.start()

      // First poll frame — button already held, should NOT fire
      env._tickRAF()
      expect(actions).toEqual([])

      // Release and re-press — should fire normally
      gamepad.buttons[13] = { pressed: false }
      env._tickRAF()
      gamepad.buttons[13] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_DOWN])
    })

    test("stop removes all listeners and stops polling", () => {
      source.start()
      env._setGamepad(0, makeGamepad())
      env._dispatchEvent("gamepadconnected", { gamepad: makeGamepad() })

      source.stop()

      expect(env._listeners.gamepadconnected?.length ?? 0).toBe(0)
      expect(env._listeners.gamepaddisconnected?.length ?? 0).toBe(0)
      expect(source._rafId).toBe(null)
    })
  })

  describe("button edge detection", () => {
    test("button press fires action once (rising edge)", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      // Frame 1: button not pressed → no action
      env._tickRAF()
      expect(actions).toEqual([])

      // Frame 2: button 0 (A/SELECT) pressed
      gamepad.buttons[0] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.SELECT])

      // Frame 3: button still held → no repeat
      actions.length = 0
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("button release then re-press fires again", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      // Initial poll
      env._tickRAF()

      // Press
      gamepad.buttons[0] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.SELECT])

      // Release
      gamepad.buttons[0] = { pressed: false }
      env._tickRAF()

      // Re-press
      actions.length = 0
      gamepad.buttons[0] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.SELECT])
    })

    test("unmapped buttons are ignored", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      env._tickRAF() // initial state

      // Button 2 (X) is not in default map
      gamepad.buttons[2] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("D-pad buttons produce navigation actions", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial state

      gamepad.buttons[12] = { pressed: true } // up
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])

      actions.length = 0
      gamepad.buttons[12] = { pressed: false }
      gamepad.buttons[13] = { pressed: true } // down
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_DOWN])
    })

    test("fires onInputDetected for button presses", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      gamepad.buttons[0] = { pressed: true }
      env._tickRAF()

      expect(inputDetections).toContain("gamepadbutton")
    })
  })

  describe("D-pad repeat timing", () => {
    test("D-pad tap fires once, held does not repeat within delay", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Press D-pad up
      gamepad.buttons[12] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])

      // Hold for 200ms — within repeatDelay (400ms), no repeat
      actions.length = 0
      currentTime = now + 200
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("D-pad held past delay repeats at interval", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Press D-pad up
      gamepad.buttons[12] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])

      // After repeatDelay (400ms), first repeat
      actions.length = 0
      currentTime = now + 401
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])

      // After repeatInterval (180ms), second repeat
      actions.length = 0
      currentTime = now + 401 + 181
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])
    })

    test("D-pad release clears repeat state", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Press and release D-pad
      gamepad.buttons[12] = { pressed: true }
      env._tickRAF()
      gamepad.buttons[12] = { pressed: false }
      currentTime = now + 50
      env._tickRAF()

      // Re-press — fires immediately (fresh repeat timer)
      actions.length = 0
      gamepad.buttons[12] = { pressed: true }
      currentTime = now + 100
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_UP])
    })

    test("non-navigation buttons do not repeat when held", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Press A (SELECT) — fires once
      gamepad.buttons[0] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.SELECT])

      // Hold well past repeatDelay — should NOT repeat
      actions.length = 0
      currentTime = now + 1000
      env._tickRAF()
      expect(actions).toEqual([])
    })
  })

  describe("analog stick deadzone", () => {
    test("values below deadzone produce no action", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Below deadzone (0.3)
      gamepad.axes[0] = 0.2
      gamepad.axes[1] = -0.1
      env._tickRAF()

      const navActions = actions.filter(a => a.startsWith("NAVIGATE"))
      expect(navActions).toEqual([])
    })

    test("values above deadzone produce navigation action", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Right stick above deadzone
      gamepad.axes[0] = 0.8
      env._tickRAF()

      expect(actions).toContain(Action.NAVIGATE_RIGHT)
    })

    test("fires onInputDetected for axis movement", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      gamepad.axes[1] = 0.8
      env._tickRAF()

      expect(inputDetections).toContain("gamepadaxis")
    })
  })

  describe("analog stick repeat timing", () => {
    test("direction held fires once, then repeats after delay", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Push stick right
      gamepad.axes[0] = 0.8
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_RIGHT])

      // Hold — within repeatDelay (400ms), no repeat
      actions.length = 0
      currentTime = now + 200
      env._tickRAF()
      expect(actions).toEqual([])

      // After repeatDelay, first repeat
      actions.length = 0
      currentTime = now + 401
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_RIGHT])

      // After repeatInterval (180ms), second repeat
      actions.length = 0
      currentTime = now + 401 + 181
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_RIGHT])
    })

    test("direction change resets repeat timer", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Push right
      gamepad.axes[0] = 0.8
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_RIGHT])

      // Change to down — should fire immediately
      actions.length = 0
      currentTime = now + 100
      gamepad.axes[0] = 0
      gamepad.axes[1] = 0.8
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_DOWN])

      // Hold down — need full repeatDelay from direction change
      actions.length = 0
      currentTime = now + 200 // only 100ms since direction change
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("returning stick to center clears repeat state", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Push right
      gamepad.axes[0] = 0.8
      env._tickRAF()

      // Return to center
      gamepad.axes[0] = 0
      currentTime = now + 100
      env._tickRAF()

      // Push right again — should fire immediately (fresh repeat)
      actions.length = 0
      gamepad.axes[0] = 0.8
      currentTime = now + 200
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_RIGHT])
    })
  })

  describe("controller type detection", () => {
    test("detects Xbox controller", () => {
      expect(detectControllerType("Xbox 360 Controller (STANDARD GAMEPAD)")).toBe("xbox")
      expect(detectControllerType("Xbox One Controller")).toBe("xbox")
      expect(detectControllerType("xinput")).toBe("xbox")
    })

    test("detects PlayStation controller", () => {
      expect(detectControllerType("PLAYSTATION(R)3 Controller")).toBe("playstation")
      expect(detectControllerType("DualSense Wireless Controller")).toBe("playstation")
      expect(detectControllerType("DualShock 4")).toBe("playstation")
      expect(detectControllerType("Sony PLAYSTATION(R)4 Controller")).toBe("playstation")
    })

    test("returns generic for unknown controllers", () => {
      expect(detectControllerType("Unknown Gamepad")).toBe("generic")
      expect(detectControllerType("")).toBe("generic")
    })

    test("onControllerChanged called on gamepadconnected", () => {
      source.start()
      const gamepad = makeGamepad({ id: "Xbox 360 Controller" })
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      expect(controllerChanges).toEqual(["xbox"])
    })
  })

  describe("pause/resume", () => {
    test("pause stops polling loop", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      expect(env._rafCallbacks.length).toBe(1)

      source.pause()
      expect(source._rafId).toBe(null)
      expect(env._rafCallbacks.length).toBe(0)
    })

    test("pause keeps gamepad connect/disconnect listeners active", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      source.pause()

      expect(env._listeners.gamepadconnected?.length).toBe(1)
      expect(env._listeners.gamepaddisconnected?.length).toBe(1)
    })

    test("resume restarts polling when gamepad still connected", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      source.pause()
      expect(source._rafId).toBe(null)

      source.resume()
      expect(env._rafCallbacks.length).toBe(1)
    })

    test("resume does not start polling when no gamepad connected", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      source.pause()
      env._clearGamepads()

      source.resume()
      expect(env._rafCallbacks.length).toBe(0)
    })

    test("resume primes buttons to prevent false rising edge", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial poll

      source.pause()

      // Button pressed while paused
      gamepad.buttons[0] = { pressed: true }

      source.resume()

      // First poll after resume — button already held, should NOT fire
      actions.length = 0
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("pause clears repeat timers", () => {
      const now = Date.now()
      let currentTime = now
      source._now = () => currentTime

      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Press D-pad down and accumulate time toward repeat
      gamepad.buttons[13] = { pressed: true }
      env._tickRAF()
      expect(actions).toEqual([Action.NAVIGATE_DOWN])

      // Advance 300ms (close to repeatDelay of 400ms)
      currentTime = now + 300

      source.pause()
      source.resume()

      // After resume, the repeat timer is reset — 300ms does not carry over
      // Need another full 400ms from resume to get a repeat
      actions.length = 0
      currentTime = now + 350 // only 50ms since resume
      env._tickRAF()
      expect(actions).toEqual([])
    })

    test("pause clears axis state", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      // Push stick right
      gamepad.axes[0] = 0.8
      env._tickRAF()
      expect(actions).toContain(Action.NAVIGATE_RIGHT)

      source.pause()
      source.resume()

      // Stick still held right — fires as new direction (axis state was cleared)
      actions.length = 0
      env._tickRAF()
      expect(actions).toContain(Action.NAVIGATE_RIGHT)
    })

    test("resume is a no-op after stop", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      source.stop()
      source.resume()

      expect(env._rafCallbacks.length).toBe(0)
      expect(source._rafId).toBe(null)
    })

    test("gamepad connected while paused is picked up on resume", () => {
      source.start()
      // No gamepad initially — no polling
      expect(env._rafCallbacks.length).toBe(0)

      source.pause()

      // Gamepad connects while paused (listener still active)
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      // _onConnected starts polling even during pause — that's fine,
      // but let's verify resume works correctly
      source.pause() // ensure paused again
      source.resume()
      expect(env._rafCallbacks.length).toBe(1)
    })

    test("gamepad disconnected while paused — resume does not poll", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })

      source.pause()

      // Gamepad disconnects while paused
      env._clearGamepads()
      env._dispatchEvent("gamepaddisconnected", { gamepad })

      source.resume()
      expect(env._rafCallbacks.length).toBe(0)
    })
  })

  describe("no actions after stop", () => {
    test("button presses ignored after stop", () => {
      source.start()
      const gamepad = makeGamepad()
      env._setGamepad(0, gamepad)
      env._dispatchEvent("gamepadconnected", { gamepad })
      env._tickRAF() // initial

      source.stop()
      actions.length = 0

      // Even if we manually push a raf callback, actions shouldn't fire
      gamepad.buttons[0] = { pressed: true }
      // No rAF should be queued after stop
      expect(env._rafCallbacks.length).toBe(0)
    })
  })
})
