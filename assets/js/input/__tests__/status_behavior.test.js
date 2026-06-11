import { describe, expect, test } from "bun:test"
import { createStatusBehavior } from "../status_behavior"

describe("createStatusBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createStatusBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createStatusBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
