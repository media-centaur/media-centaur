import { describe, expect, test } from "bun:test"
import { createHomeBehavior } from "../home_behavior"

describe("home behavior", () => {
  test("onEscape returns sidebar", () => {
    const behavior = createHomeBehavior()
    expect(behavior.onEscape()).toBe("sidebar")
  })

  test("does not auto-activate shelf items on focus", () => {
    const behavior = createHomeBehavior()
    // Shelves must not open the detail modal merely by moving focus across
    // cards — activation only happens on an explicit SELECT.
    expect(behavior.activateOnFocus).toBeUndefined()
  })
})
