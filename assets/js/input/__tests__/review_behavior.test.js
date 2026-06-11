import { describe, expect, test } from "bun:test"
import { createReviewBehavior } from "../review_behavior"

describe("createReviewBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createReviewBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createReviewBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
