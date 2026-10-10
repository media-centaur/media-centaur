import { describe, expect, test } from "bun:test"
import { createProfilesBehavior } from "../profiles_behavior"

describe("profiles behavior", () => {
  test("does not activate items on focus — a tile switches the profile only on an explicit SELECT", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("defines no onEscape — BACK is the state machine's (the sidebar, when the shell is present)", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
