import { describe, expect, test } from "bun:test"
import { gamepadInputAllowed } from "../input_gate"

// The gamepad gate decides whether a connected controller may drive the UI.
// Unlike the keyboard (which the OS scopes to the focused window), the Gamepad
// API reports controller state globally — so a backgrounded, hidden, or
// headless/automation surface would otherwise keep firing actions. The gate is
// the single predicate that closes all three holes. See gamepad.js `_poll`.
describe("gamepadInputAllowed", () => {
  const active = { hasFocus: true, visibilityState: "visible", webdriver: false }

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
    // hasFocus:true / visible, so focus+visibility alone do not catch it. The
    // webdriver flag is the deterministic marker we set on those launches.
    expect(gamepadInputAllowed({ ...active, webdriver: true })).toBe(false)
  })

  test("suppresses input when every signal is unfavorable", () => {
    expect(gamepadInputAllowed({ hasFocus: false, visibilityState: "hidden", webdriver: true })).toBe(false)
  })

  test("treats a missing/undefined env as not-allowed (fail closed)", () => {
    expect(gamepadInputAllowed({})).toBe(false)
  })
})
