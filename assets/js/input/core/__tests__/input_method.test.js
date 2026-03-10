import { describe, expect, test, beforeEach } from "bun:test"
import { InputMethodDetector, InputMethod } from "../input_method"

describe("InputMethodDetector", () => {
  let detector

  beforeEach(() => {
    detector = new InputMethodDetector()
  })

  test("defaults to MOUSE", () => {
    expect(detector.current).toBe(InputMethod.MOUSE)
  })

  test("accepts custom initial method", () => {
    const d = new InputMethodDetector(InputMethod.KEYBOARD)
    expect(d.current).toBe(InputMethod.KEYBOARD)
  })

  test("keydown switches to KEYBOARD", () => {
    const result = detector.observe("keydown")
    expect(result).toBe(InputMethod.KEYBOARD)
    expect(detector.current).toBe(InputMethod.KEYBOARD)
  })

  test("keyup switches to KEYBOARD", () => {
    const result = detector.observe("keyup")
    expect(result).toBe(InputMethod.KEYBOARD)
    expect(detector.current).toBe(InputMethod.KEYBOARD)
  })

  test("mousemove switches to MOUSE", () => {
    // First switch to keyboard
    detector.observe("keydown")
    const result = detector.observe("mousemove")
    expect(result).toBe(InputMethod.MOUSE)
    expect(detector.current).toBe(InputMethod.MOUSE)
  })

  test("mousedown switches to MOUSE", () => {
    detector.observe("keydown")
    const result = detector.observe("mousedown")
    expect(result).toBe(InputMethod.MOUSE)
  })

  test("click switches to MOUSE", () => {
    detector.observe("keydown")
    const result = detector.observe("click")
    expect(result).toBe(InputMethod.MOUSE)
  })

  test("gamepadbutton switches to GAMEPAD", () => {
    const result = detector.observe("gamepadbutton")
    expect(result).toBe(InputMethod.GAMEPAD)
    expect(detector.current).toBe(InputMethod.GAMEPAD)
  })

  test("gamepadaxis switches to GAMEPAD", () => {
    const result = detector.observe("gamepadaxis")
    expect(result).toBe(InputMethod.GAMEPAD)
  })

  test("returns null when method unchanged", () => {
    // Already MOUSE, mousemove should return null
    expect(detector.observe("mousemove")).toBe(null)
    expect(detector.observe("mousedown")).toBe(null)
    expect(detector.observe("click")).toBe(null)
  })

  test("returns null for unknown event types", () => {
    expect(detector.observe("scroll")).toBe(null)
    expect(detector.observe("touchstart")).toBe(null)
    expect(detector.observe("focus")).toBe(null)
  })

  test("transitions: mouse → keyboard → gamepad → mouse", () => {
    expect(detector.current).toBe(InputMethod.MOUSE)

    expect(detector.observe("keydown")).toBe(InputMethod.KEYBOARD)
    expect(detector.current).toBe(InputMethod.KEYBOARD)

    expect(detector.observe("gamepadbutton")).toBe(InputMethod.GAMEPAD)
    expect(detector.current).toBe(InputMethod.GAMEPAD)

    expect(detector.observe("mousemove")).toBe(InputMethod.MOUSE)
    expect(detector.current).toBe(InputMethod.MOUSE)
  })

  test("repeated same-method events return null", () => {
    detector.observe("keydown")
    expect(detector.observe("keydown")).toBe(null)
    expect(detector.observe("keyup")).toBe(null)
  })
})
