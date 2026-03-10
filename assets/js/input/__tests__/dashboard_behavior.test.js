import { describe, expect, test } from "bun:test"
import { createDashboardBehavior } from "../dashboard_behavior"

describe("createDashboardBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createDashboardBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })
})
