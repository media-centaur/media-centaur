import { describe, expect, test } from "bun:test"
import { createSetupBehavior } from "../setup_behavior"

describe("setup behavior", () => {
  test("does not activate items on focus — Begin/Next require an explicit SELECT", () => {
    const behavior = createSetupBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("defines no onEscape — the wizard has no sidebar to exit to", () => {
    const behavior = createSetupBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
