import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"

describe("App config", () => {
  test("has all required context selectors", () => {
    expect(inputConfig.contextSelectors[Context.GRID]).toBeDefined()
    expect(inputConfig.contextSelectors[Context.DRAWER]).toBeDefined()
    expect(inputConfig.contextSelectors[Context.MODAL]).toBeDefined()
    expect(inputConfig.contextSelectors[Context.TOOLBAR]).toBeDefined()
    expect(inputConfig.contextSelectors.sidebar).toBeDefined()
    expect(inputConfig.contextSelectors.sections).toBeDefined()
    expect(inputConfig.contextSelectors[Context.ZONE_TABS]).toBeDefined()
  })

  test("has layouts for all zones", () => {
    expect(inputConfig.layouts.watching).toBeDefined()
    expect(inputConfig.layouts.library).toBeDefined()
    expect(inputConfig.layouts.settings).toBeDefined()
    expect(inputConfig.layouts.dashboard).toBeDefined()
  })

  test("has cursor start priority for all zones", () => {
    expect(inputConfig.cursorStartPriority.watching).toBeDefined()
    expect(inputConfig.cursorStartPriority.library).toBeDefined()
    expect(inputConfig.cursorStartPriority.settings).toBeDefined()
    expect(inputConfig.cursorStartPriority.dashboard).toBeDefined()
  })

  test("has primaryMenu set", () => {
    expect(inputConfig.primaryMenu).toBe("sidebar")
  })

  test("settings behavior has activateOnFocus for sections", () => {
    const behavior = inputConfig.createBehavior("settings")
    expect(behavior.activateOnFocus).toContain("sections")
  })

  test("has instanceTypes for sidebar and sections", () => {
    expect(inputConfig.instanceTypes.sidebar).toBe(Context.MENU)
    expect(inputConfig.instanceTypes.sections).toBe(Context.MENU)
  })

  test("has alwaysPopulated list", () => {
    expect(inputConfig.alwaysPopulated).toContain("sidebar")
    expect(inputConfig.alwaysPopulated).toContain("sections")
  })

  test("has activeClassNames", () => {
    expect(inputConfig.activeClassNames.length).toBeGreaterThan(0)
  })

  test("has createBehavior function", () => {
    expect(typeof inputConfig.createBehavior).toBe("function")
  })

  test("createBehavior returns library behavior", () => {
    const behavior = inputConfig.createBehavior("library")
    expect(behavior).not.toBe(null)
    expect(typeof behavior.onEscape).toBe("function")
  })

  test("createBehavior returns settings behavior", () => {
    const behavior = inputConfig.createBehavior("settings")
    expect(behavior).not.toBe(null)
  })

  test("createBehavior returns dashboard behavior", () => {
    const behavior = inputConfig.createBehavior("dashboard")
    expect(behavior).not.toBe(null)
  })

  test("createBehavior returns null for unknown", () => {
    expect(inputConfig.createBehavior("unknown")).toBe(null)
  })

  test("context selectors keys match cursor start priority contexts", () => {
    for (const zone of Object.keys(inputConfig.cursorStartPriority)) {
      for (const context of inputConfig.cursorStartPriority[zone]) {
        expect(inputConfig.contextSelectors[context]).toBeDefined()
      }
    }
  })
})
