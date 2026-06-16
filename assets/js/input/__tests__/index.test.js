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
    expect(inputConfig.layouts.guide).toBeDefined()
  })

  test("has cursor start priority for all zones", () => {
    expect(inputConfig.cursorStartPriority.watching).toBeDefined()
    expect(inputConfig.cursorStartPriority.library).toBeDefined()
    expect(inputConfig.cursorStartPriority.settings).toBeDefined()
    expect(inputConfig.cursorStartPriority.status).toBeDefined()
  })

  test("setup tour is a sidebar-less single-grid wizard", () => {
    expect(inputConfig.layouts.setup).toBeDefined()
    expect(inputConfig.layouts.setup.grid).toBeDefined()
    expect(inputConfig.cursorStartPriority.setup).toEqual(["grid"])
  })

  test("setup behavior resolves and does not activate on focus", () => {
    const behavior = inputConfig.createBehavior("setup")
    expect(behavior).not.toBeNull()
    expect(behavior.activateOnFocus ?? []).toEqual([])
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

  test("guide behavior + chapter/outline menus resolve", () => {
    const behavior = inputConfig.createBehavior("guide")
    expect(behavior).not.toBeNull()
    expect(behavior.activateOnFocus).toContain("guide_chapters")
    expect(inputConfig.instanceTypes.guide_chapters).toBe(Context.MENU)
    expect(inputConfig.instanceTypes.guide_outline).toBe(Context.MENU)
    expect(inputConfig.cursorStartPriority.guide).toBeDefined()
    expect(inputConfig.alwaysPopulated).toContain("guide_chapters")
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

describe("Guide page nav (real config)", () => {
  const populated = { guide_chapters: 22, guide_outline: 4, sidebar: 7 }

  test("chapters: right to outline, left to sidebar; outline left to chapters", () => {
    const graph = buildNavGraph("guide", populated, inputConfig)
    expect(graph.guide_chapters.right).toBe("guide_outline")
    expect(graph.guide_chapters.left).toBe("sidebar")
    expect(graph.guide_outline.left).toBe("guide_chapters")
  })

  test("sidebar enters the chapter list; cursor starts there", () => {
    const graph = buildNavGraph("guide", populated, inputConfig)
    expect(graph.sidebar.right).toBe("guide_chapters")
    expect(resolveCursorStart("guide", populated, inputConfig)).toBe("guide_chapters")
  })

  test("no outline (short chapter / below xl): right from chapters has no target", () => {
    const counts = { guide_chapters: 22, guide_outline: 0, sidebar: 7 }
    const graph = buildNavGraph("guide", counts, inputConfig)
    expect(graph.guide_chapters.right).toBeUndefined()
    expect(resolveCursorStart("guide", counts, inputConfig)).toBe("guide_chapters")
  })
})
