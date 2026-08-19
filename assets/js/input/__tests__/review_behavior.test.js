import { describe, expect, test } from "bun:test"
import { createReviewBehavior } from "../review_behavior"

describe("createReviewBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createReviewBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createReviewBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
