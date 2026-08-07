import { describe, expect, test, beforeEach } from "bun:test"
import { InputMethodDetector, InputMethod } from "../input_method"

describe("InputMethodDetector", () => {
  let detector

  beforeEach(() => {
    detector = new InputMethodDetector()
  })

  // Media Centaur is driven from a couch, not a desk: the cursor is already
  // parked on a page's primary action at load, and it has to LOOK parked
  // there. Defaulting to MOUSE meant the focus ring stayed invisible until the
  // user pressed a key — so a fresh load looked like nothing was selected. A
  // real mouse user is switched back by their first movement.
  test("defaults to KEYBOARD so the focus ring is painted from first render", () => {
    expect(detector.current).toBe(InputMethod.KEYBOARD)
  })

  test("a mouse user is switched over as soon as the pointer actually moves", () => {
    expect(detector.observe("mousemove")).toBe(InputMethod.MOUSE)
    expect(detector.current).toBe(InputMethod.MOUSE)
  })

  test("accepts custom initial method", () => {
    const d = new InputMethodDetector(InputMethod.KEYBOARD)
    expect(d.current).toBe(InputMethod.KEYBOARD)
  })

  // These state the method they start from rather than leaning on the
  // constructor default, so a change to that default cannot quietly turn a
  // transition test into a no-op assertion.
  test("keydown switches to KEYBOARD", () => {
    const fromMouse = new InputMethodDetector(InputMethod.MOUSE)
    expect(fromMouse.observe("keydown")).toBe(InputMethod.KEYBOARD)
    expect(fromMouse.current).toBe(InputMethod.KEYBOARD)
  })

  test("keyup switches to KEYBOARD", () => {
    const fromMouse = new InputMethodDetector(InputMethod.MOUSE)
    expect(fromMouse.observe("keyup")).toBe(InputMethod.KEYBOARD)
    expect(fromMouse.current).toBe(InputMethod.KEYBOARD)
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
    const fromMouse = new InputMethodDetector(InputMethod.MOUSE)
    expect(fromMouse.observe("mousemove")).toBe(null)
    expect(fromMouse.observe("mousedown")).toBe(null)
    expect(fromMouse.observe("click")).toBe(null)
  })

  test("returns null for unknown event types", () => {
    expect(detector.observe("scroll")).toBe(null)
    expect(detector.observe("touchstart")).toBe(null)
    expect(detector.observe("focus")).toBe(null)
  })

  test("transitions: mouse → keyboard → gamepad → mouse", () => {
    const detector = new InputMethodDetector(InputMethod.MOUSE)
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

  // The wheel is mouse hardware: a user scrolling with it has taken the
  // pointer, exactly like moving it. Without this, wheel input left the
  // system in keyboard mode and reveal glides fought the user's scrolling.
  test("wheel switches to mouse", () => {
    expect(detector.observe("wheel")).toBe(InputMethod.MOUSE)
    expect(detector.current).toBe(InputMethod.MOUSE)
  })
})
