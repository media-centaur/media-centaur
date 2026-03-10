import { describe, expect, test } from "bun:test"
import { createReviewBehavior } from "../review_behavior"

describe("createReviewBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createReviewBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })
})
