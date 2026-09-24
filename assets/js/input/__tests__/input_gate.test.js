import { describe, expect, test } from "bun:test"
import { gamepadInputAllowed } from "../input_gate"

// The gamepad gate decides whether a connected controller may drive the UI.
// Unlike the keyboard (which the OS scopes to the focused window), the Gamepad
// API reports controller state globally — so a backgrounded, hidden, or
// headless/automation surface would otherwise keep firing actions. The gate is
// the single predicate that closes all three holes. See gamepad.js `_poll`.
describe("gamepadInputAllowed", () => {
  const active = { hasFocus: true, visibilityState: "visible", automation: false }

  test("allows input on a focused, visible, non-automation surface", () => {
    expect(gamepadInputAllowed(active)).toBe(true)
  })

  test("suppresses input when the document is unfocused", () => {
    // Real game on another workspace holds OS focus; controller is global.
    expect(gamepadInputAllowed({ ...active, hasFocus: false })).toBe(false)
  })

  test("suppresses input when the document is hidden", () => {
    // Backgrounded tab / occluded window still polling.
    expect(gamepadInputAllowed({ ...active, visibilityState: "hidden" })).toBe(false)
  })

  test("suppresses input in a prerender visibility state", () => {
    expect(gamepadInputAllowed({ ...active, visibilityState: "prerender" })).toBe(false)
  })

  test("suppresses input in an automation context even when focused and visible", () => {
    // The headless debug browser (mc-debug-browser --enable-automation) reports
    // hasFocus:true / visible, so focus+visibility alone do not catch it.
    expect(gamepadInputAllowed({ ...active, automation: true })).toBe(false)
  })

  test("suppresses input when every signal is unfavorable", () => {
    expect(gamepadInputAllowed({ hasFocus: false, visibilityState: "hidden", automation: true })).toBe(false)
  })

  test("treats a missing/undefined env as not-allowed (fail closed)", () => {
    expect(gamepadInputAllowed({})).toBe(false)
  })

  // A windowed surface proves it deserves the controller by holding focus and
  // being visible. An automation surface fakes both, so it cannot prove it that
  // way — it declares instead. That is how an E2E run drives a gamepad without
  // reopening the hole the gate exists to close.
  describe("declared entitlement", () => {
    test("an automation surface that declares itself the driver is allowed", () => {
      expect(gamepadInputAllowed({ ...active, automation: true, automationDrivesInput: true })).toBe(true)
    })

    test("an automation surface that declares nothing stays suppressed", () => {
      expect(gamepadInputAllowed({ ...active, automation: true, automationDrivesInput: false })).toBe(false)
      expect(gamepadInputAllowed({ ...active, automation: true })).toBe(false)
    })

    test("a declaration does not substitute for focus or visibility", () => {
      const declared = { automation: true, automationDrivesInput: true }
      expect(gamepadInputAllowed({ ...active, ...declared, hasFocus: false })).toBe(false)
      expect(gamepadInputAllowed({ ...active, ...declared, visibilityState: "hidden" })).toBe(false)
    })

    test("a declaration on a non-automation surface changes nothing", () => {
      expect(gamepadInputAllowed({ ...active, automationDrivesInput: true })).toBe(true)
    })
  })
})
