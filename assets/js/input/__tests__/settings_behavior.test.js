import { describe, expect, test } from "bun:test"
import { createSettingsBehavior } from "../settings_behavior"

describe("settings behavior", () => {
  test("activateOnFocus includes sections", () => {
    const behavior = createSettingsBehavior()
    expect(behavior.activateOnFocus).toEqual(["sections"])
  })

  test("onEscape returns sections", () => {
    const behavior = createSettingsBehavior()
    expect(behavior.onEscape()).toBe("sections")
  })
})
