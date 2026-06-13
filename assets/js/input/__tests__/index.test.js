import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context, buildNavGraph, resolveCursorStart } from "../core/index"

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
    expect(inputConfig.layouts.status).toBeDefined()
  })

  test("has cursor start priority for all zones", () => {
    expect(inputConfig.cursorStartPriority.watching).toBeDefined()
    expect(inputConfig.cursorStartPriority.library).toBeDefined()
    expect(inputConfig.cursorStartPriority.settings).toBeDefined()
    expect(inputConfig.cursorStartPriority.status).toBeDefined()
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
    expect(typeof behavior.onClear).toBe("function")
  })

  test("createBehavior returns settings behavior", () => {
    const behavior = inputConfig.createBehavior("settings")
    expect(behavior).not.toBe(null)
  })

  test("createBehavior returns status behavior", () => {
    const behavior = inputConfig.createBehavior("status")
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

describe("Upcoming page nav (real config)", () => {
  const populated = { rail: 5, stragglers: 2, "mini-month": 2, actions: 1, sidebar: 4 }

  test("rail navigates down to stragglers, right to mini-month, left to sidebar, up to actions", () => {
    const graph = buildNavGraph("upcoming", populated, inputConfig)
    expect(graph.rail.down).toBe("stragglers")
    expect(graph.rail.right).toBe("mini-month")
    expect(graph.rail.left).toBe("sidebar")
    expect(graph.rail.up).toBe("actions")
  })

  test("sidebar enters the rail first when populated", () => {
    const graph = buildNavGraph("upcoming", populated, inputConfig)
    expect(graph.sidebar.right).toBe("rail")
    expect(resolveCursorStart("upcoming", populated, inputConfig)).toBe("rail")
  })

  test("an empty rail falls back to stragglers for both sidebar entry and cursor start", () => {
    const counts = { rail: 0, stragglers: 2, "mini-month": 2, actions: 0, sidebar: 4 }
    const graph = buildNavGraph("upcoming", counts, inputConfig)
    expect(graph.sidebar.right).toBe("stragglers")
    expect(resolveCursorStart("upcoming", counts, inputConfig)).toBe("stragglers")
  })

  test("every upcoming context reaches the sidebar via left", () => {
    const graph = buildNavGraph("upcoming", populated, inputConfig)
    for (const context of ["rail", "stragglers", "mini-month", "actions"]) {
      expect(graph[context].left).toBeDefined()
    }
  })
})
