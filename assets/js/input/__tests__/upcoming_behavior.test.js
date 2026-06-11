import { describe, expect, test } from "bun:test"
import { createUpcomingBehavior } from "../upcoming_behavior"

describe("Upcoming behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createUpcomingBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
