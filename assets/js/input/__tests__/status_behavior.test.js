import { describe, expect, test } from "bun:test"
import { createStatusBehavior } from "../status_behavior"

describe("createStatusBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createStatusBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("onEscape returns sidebar", () => {
    const behavior = createStatusBehavior()
    expect(behavior.onEscape()).toBe("sidebar")
  })
})
