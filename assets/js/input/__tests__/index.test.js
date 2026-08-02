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

describe("Incoming page nav (real config)", () => {
  // One tab's content renders at a time: the zone tabs route down into
  // whichever content zone the active tab populated.
  const comingUpView = { omnibox: 1, zone_tabs: 3, coming_up_list: 6, sidebar: 4 }

  test("Coming up view: tabs sit between the omnibox and the agenda", () => {
    const graph = buildNavGraph("incoming", comingUpView, inputConfig)
    expect(graph.omnibox.down).toBe("zone_tabs")
    expect(graph.zone_tabs.up).toBe("omnibox")
    expect(graph.zone_tabs.down).toBe("coming_up_list")
    expect(graph.coming_up_list.up).toBe("zone_tabs")
    expect(resolveCursorStart("incoming", comingUpView, inputConfig)).toBe("coming_up_list")
  })

  test("Activity view: tabs route into drafts → pursuits → other downloads", () => {
    const counts = { omnibox: 1, zone_tabs: 3, drafts: 1, pursuits: 3, other_downloads: 2, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.zone_tabs.down).toBe("drafts")
    expect(graph.drafts.down).toBe("pursuits")
    expect(graph.pursuits.down).toBe("other_downloads")
    expect(graph.other_downloads.up).toBe("pursuits")
    expect(resolveCursorStart("incoming", counts, inputConfig)).toBe("pursuits")
  })

  test("History view: tabs route into the ledger; sidebar falls through to it", () => {
    const counts = { omnibox: 1, zone_tabs: 3, ledger: 5, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.zone_tabs.down).toBe("ledger")
    expect(graph.ledger.up).toBe("zone_tabs")
    expect(graph.sidebar.right).toBe("ledger")
  })

  test("search owns the page: only the flat results grid below the omnibox", () => {
    const counts = { omnibox: 1, grid: 8, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.omnibox.down).toBe("grid")
    expect(graph.grid.up).toBe("omnibox")
  })

  test("forecast-only (no tabs in the DOM): the agenda leans on the candidate fallback", () => {
    const counts = { omnibox: 1, coming_up_list: 6, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.coming_up_list.up).toBe("omnibox")
    expect(resolveCursorStart("incoming", counts, inputConfig)).toBe("coming_up_list")
  })

  test("sidebar enters the agenda first; cursor starts there too", () => {
    const graph = buildNavGraph("incoming", comingUpView, inputConfig)
    expect(graph.sidebar.right).toBe("coming_up_list")
  })

  test("every incoming context reaches the sidebar via left", () => {
    const counts = {
      omnibox: 1, zone_tabs: 3, grid: 2, coming_up_list: 6,
      drafts: 1, pursuits: 3, ledger: 5, other_downloads: 1, sidebar: 4,
    }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    for (const context of [
      "omnibox",
      "zone_tabs",
      "coming_up_list",
      "grid",
      "drafts",
      "pursuits",
      "ledger",
      "other_downloads",
    ]) {
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
