import { describe, expect, test } from "bun:test"
import { shouldAutofocus } from "./mouse_autofocus"

// Autofocus-on-mount is a pointer affordance: a mouse user who lands on a
// search surface expects the cursor already in the box. Keyboard and gamepad
// users do NOT — the input system owns focus for them, and grabbing it on
// mount steals focus away from navigation (the downloads-omnibox bug).
describe("shouldAutofocus", () => {
  test("mouse → autofocus", () => {
    expect(shouldAutofocus("mouse")).toBe(true)
  })

  test("keyboard → no autofocus (input system owns focus)", () => {
    expect(shouldAutofocus("keyboard")).toBe(false)
  })

  test("gamepad → no autofocus (input system owns focus)", () => {
    expect(shouldAutofocus("gamepad")).toBe(false)
  })

  test("unset defaults to mouse (the static <html> default)", () => {
    // data-input is statically "mouse" in root.html.heex, but be defensive:
    // an absent/empty value means "no non-pointer method has claimed input",
    // which is the mouse case.
    expect(shouldAutofocus(undefined)).toBe(true)
    expect(shouldAutofocus(null)).toBe(true)
    expect(shouldAutofocus("")).toBe(true)
  })

  test("unknown method → no autofocus (only the pointer opts in)", () => {
    // Fail safe: anything that isn't recognised as the pointer should not
    // steal focus. Only "mouse"/unset autofocuses.
    expect(shouldAutofocus("touch")).toBe(false)
  })
})
