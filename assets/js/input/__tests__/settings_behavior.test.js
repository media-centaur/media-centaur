import { describe, expect, test } from "bun:test"
import { createSettingsBehavior } from "../settings_behavior"

describe("settings behavior", () => {
  test("activateOnFocus includes sections", () => {
    const behavior = createSettingsBehavior()
    expect(behavior.activateOnFocus).toEqual(["sections"])
  })

  test("defines no onEscape — BACK is a no-op in content; left from the grid reaches sections", () => {
    const behavior = createSettingsBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
