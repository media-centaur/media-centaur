import { describe, expect, test } from "bun:test"
import { createGuideBehavior } from "../guide_behavior"

describe("guide behavior", () => {
  test("activateOnFocus includes guide_chapters (up/down loads each chapter)", () => {
    const behavior = createGuideBehavior()
    expect(behavior.activateOnFocus).toEqual(["guide_chapters"])
  })

  test("does not activate the outline on focus — outline jumps on SELECT only", () => {
    const behavior = createGuideBehavior()
    expect(behavior.activateOnFocus).not.toContain("guide_outline")
  })

  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createGuideBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
