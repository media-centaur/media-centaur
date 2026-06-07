import { describe, expect, test } from "bun:test"
import { createUpcomingBehavior } from "../upcoming_behavior"

describe("Upcoming behavior", () => {
  test("onEscape() returns sidebar so a gamepad user is never trapped", () => {
    const behavior = createUpcomingBehavior()
    expect(behavior.onEscape()).toBe("sidebar")
  })
})
