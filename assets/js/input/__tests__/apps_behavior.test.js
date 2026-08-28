import { describe, expect, test } from "bun:test"

import { createAppsBehavior } from "../apps_behavior.js"

describe("apps behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createAppsBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — app cards must never launch on focus", () => {
    const behavior = createAppsBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})
