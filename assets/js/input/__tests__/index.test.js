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

  test("release search owns the page: only the flat results grid below the omnibox", () => {
    const counts = { omnibox: 1, grid: 8, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.omnibox.down).toBe("grid")
    expect(graph.grid.up).toBe("omnibox")
  })

  test("media search: the chip strip sits between the omnibox and the result rows", () => {
    const counts = { omnibox: 1, toolbar: 2, grid: 8, sidebar: 4 }
    const graph = buildNavGraph("incoming", counts, inputConfig)
    expect(graph.omnibox.down).toBe("toolbar")
    expect(graph.toolbar.up).toBe("omnibox")
    expect(graph.toolbar.down).toBe("grid")
    expect(graph.grid.up).toBe("toolbar")
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

  test("no incoming context has a left edge — the sidebar is BACK's job", () => {
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
      expect(graph[context].left).toBeUndefined()
    }
    // The node BACK checks for is still declared
    expect(graph.sidebar).toBeDefined()
  })
})

describe("Guide page nav (real config)", () => {
  const populated = { guide_chapters: 22, guide_outline: 4, sidebar: 7 }

  test("chapters: right to outline; outline left to chapters; no sidebar edge", () => {
    const graph = buildNavGraph("guide", populated, inputConfig)
    expect(graph.guide_chapters.right).toBe("guide_outline")
    expect(graph.guide_chapters.left).toBeUndefined()
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

// The detail modal's body swaps per sub-view: the episode list is a tree, but
// the Cast view is a photo grid, so it navigates as its own SHELF-typed region
// (geometry answers adjacency across the grid sections and the Show more
// button). Only one body zone is in the DOM at a time; the candidate lists in
// the overlay layout route DOWN to whichever one is populated.
describe("Detail overlay cast region (real config)", () => {
  const openDetail = counts =>
    buildNavGraph("library", counts, {
      ...inputConfig,
      overlayLayout: inputConfig.overlays.detail.layout,
    })

  test("the cast body is a shelf-typed region of the detail overlay", () => {
    expect(inputConfig.instanceTypes.detail_cast).toBe(Context.SHELF)
    expect(inputConfig.contextSelectors.detail_cast).toBe("[data-nav-zone='detail_cast'] [data-nav-item]")
    expect(inputConfig.overlays.detail.entry).toContain("detail_cast")
  })

  test("cast view showing: down from the action row enters the cast grid, BACK climbs out", () => {
    const graph = openDetail({ detail_actions: 3, detail_list: 0, detail_cast: 24, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("detail_cast")
    expect(graph.detail_cast.back).toBe("detail_actions")
  })

  // Unlike the tree — where up at the top deliberately stays put and BACK is
  // the way out — a spatial grid has a geometric "above": the action row. UP
  // from the top row climbs to it.
  test("cast view showing: up from the top row climbs to the action row", () => {
    const graph = openDetail({ detail_actions: 3, detail_list: 0, detail_cast: 24, grid: 12, sidebar: 7 })
    expect(graph.detail_cast.up).toBe("detail_actions")
  })

  test("episode list showing: down still enters the tree", () => {
    const graph = openDetail({ detail_actions: 3, detail_list: 20, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("detail_list")
  })
})

// The plan modal (UIDR-029): its board is a vertical head (status, verdict
// and their controls) over the episode grid over the rest (release rows,
// decisions, footer). The grid is a SHELF — a 2-D arrangement resolved by
// geometry, like the cast grid — between two TREE regions. Nothing declares
// a `back` edge: BACK dismisses the modal from anywhere, as it did when the
// modal was one flat list. Movies render no grid; the candidate lists fall
// through head ↔ body. The other stages (targeting, movie confirm, error)
// put every control in `plan_body`, so they navigate as the one list they
// always were.
describe("Plan overlay regions (real config)", () => {
  const openPlan = counts =>
    buildNavGraph("incoming", counts, {
      ...inputConfig,
      overlayLayout: inputConfig.overlays.plan.layout,
    })

  test("head and body are trees, the grid is a shelf, entry prefers head then body", () => {
    expect(inputConfig.instanceTypes.plan_head).toBe(Context.TREE)
    expect(inputConfig.instanceTypes.plan_grid).toBe(Context.SHELF)
    expect(inputConfig.instanceTypes.plan_body).toBe(Context.TREE)
    expect(inputConfig.overlays.plan.entry).toEqual(["plan_head", "plan_body", "plan_grid"])
    expect(inputConfig.contextSelectors.plan_grid).toBe("[data-nav-zone='plan_grid'] [data-nav-item]")
  })

  test("series board: down from the head enters the grid, down from the grid the body, and back up", () => {
    const graph = openPlan({ plan_head: 2, plan_grid: 22, plan_body: 6, sidebar: 7 })
    expect(graph.plan_head.down).toBe("plan_grid")
    expect(graph.plan_grid.down).toBe("plan_body")
    expect(graph.plan_grid.up).toBe("plan_head")
    expect(graph.plan_body.up).toBe("plan_grid")
  })

  test("movie board (no grid): head and body meet directly", () => {
    const graph = openPlan({ plan_head: 2, plan_grid: 0, plan_body: 6, sidebar: 7 })
    expect(graph.plan_head.down).toBe("plan_body")
    expect(graph.plan_body.up).toBe("plan_head")
  })

  test("no region declares a back edge — BACK dismisses the modal from anywhere", () => {
    const graph = openPlan({ plan_head: 2, plan_grid: 22, plan_body: 6, sidebar: 7 })
    expect(graph.plan_head.back).toBeUndefined()
    expect(graph.plan_grid.back).toBeUndefined()
    expect(graph.plan_body.back).toBeUndefined()
  })
})

// The Manage sub-view's toolbar card is a horizontal strip (Delete all,
// Rematch, Refresh artwork, the ID links) — walking it vertically as tree
// items made DOWN step sideways. It is its own TOOLBAR-typed region: LEFT/
// RIGHT move along the card, DOWN drops past it into the folder ledger, UP
// climbs back to the action row (a toolbar is spatial — it has an "above").
// The region only exists while Manage is showing; empty, the candidate lists
// route DOWN straight to whichever body is populated, as before.
describe("Detail overlay Manage tools region (real config)", () => {
  const openDetail = counts =>
    buildNavGraph("library", counts, {
      ...inputConfig,
      overlayLayout: inputConfig.overlays.detail.layout,
    })

  test("the manage toolbar is a toolbar-typed region of the detail overlay", () => {
    expect(inputConfig.instanceTypes.manage_tools).toBe(Context.TOOLBAR)
    expect(inputConfig.contextSelectors.manage_tools).toBe("[data-nav-zone='manage_tools'] [data-nav-item]")
    expect(inputConfig.overlays.detail.entry).toContain("manage_tools")
  })

  // The ledger is its OWN tree region, not a reuse of detail_list: per-context
  // cursor memory is keyed by context name, so sharing the name meant moving
  // through the Manage ledger overwrote the episode list's remembered
  // position — coming back to Episodes then entered at the ledger's index
  // instead of the resume episode.
  test("the manage ledger is a tree-typed region distinct from the episode list", () => {
    expect(inputConfig.instanceTypes.manage_list).toBe(Context.TREE)
    expect(inputConfig.contextSelectors.manage_list).toBe("[data-nav-zone='manage_list'] [data-nav-item]")
    expect(inputConfig.overlays.detail.entry).toContain("manage_list")
  })

  test("manage showing: down from the action row lands on the toolbar, then the ledger", () => {
    const graph = openDetail({ detail_actions: 3, manage_tools: 5, manage_list: 12, detail_list: 0, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("manage_tools")
    expect(graph.manage_tools.down).toBe("manage_list")
  })

  test("manage showing: up and BACK climb from the toolbar to the action row", () => {
    const graph = openDetail({ detail_actions: 3, manage_tools: 5, manage_list: 12, detail_list: 0, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(graph.manage_tools.up).toBe("detail_actions")
    expect(graph.manage_tools.back).toBe("detail_actions")
  })

  test("other sub-views: with no toolbar, down falls through to the body", () => {
    const graph = openDetail({ detail_actions: 3, manage_tools: 0, manage_list: 0, detail_list: 20, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("detail_list")
  })

  // UP from a tree's top row climbs to whatever sits spatially above it:
  // the ledger to the Manage toolbar card, the episode list to the action row.
  test("up from a tree top climbs to what sits above it", () => {
    const manage = openDetail({ detail_actions: 3, manage_tools: 5, manage_list: 12, detail_list: 0, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(manage.manage_list.up).toBe("manage_tools")
    expect(manage.manage_list.back).toBe("detail_actions")

    const episodes = openDetail({ detail_actions: 3, manage_tools: 0, manage_list: 0, detail_list: 20, detail_cast: 0, grid: 12, sidebar: 7 })
    expect(episodes.detail_list.up).toBe("detail_actions")
  })
})

// The collection modal's poster rail (UIDR-023) is the picker between the
// action row and the body: a horizontal strip of member tiles, so it is a
// TOOLBAR-typed region — LEFT/RIGHT walk it, DOWN drops past it into
// whichever body is populated (a collection's body is its extras list), UP
// and BACK climb to the action row. The region only exists for collections;
// empty, every candidate list falls through past it.
describe("Detail overlay collection rail region (real config)", () => {
  const openDetail = counts =>
    buildNavGraph("library", counts, {
      ...inputConfig,
      overlayLayout: inputConfig.overlays.detail.layout,
    })

  test("the rail is a toolbar-typed region of the detail overlay", () => {
    expect(inputConfig.instanceTypes.detail_rail).toBe(Context.TOOLBAR)
    expect(inputConfig.contextSelectors.detail_rail).toBe("[data-nav-zone='detail_rail'] [data-nav-item]")
    expect(inputConfig.overlays.detail.entry).toContain("detail_rail")
  })

  test("collection showing: down from the action row lands on the rail, then the extras body", () => {
    const graph = openDetail({ detail_actions: 4, detail_rail: 3, detail_list: 2, detail_cast: 0, manage_tools: 0, manage_list: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("detail_rail")
    expect(graph.detail_rail.down).toBe("detail_list")
    expect(graph.detail_rail.up).toBe("detail_actions")
    expect(graph.detail_rail.back).toBe("detail_actions")
  })

  test("cast view showing: up from the cast grid climbs to the rail before the action row", () => {
    const graph = openDetail({ detail_actions: 4, detail_rail: 3, detail_list: 0, detail_cast: 24, manage_tools: 0, manage_list: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_cast.up).toBe("detail_rail")
    expect(graph.detail_actions.down).toBe("detail_rail")
  })

  test("no rail (non-collection): every list falls through past it", () => {
    const graph = openDetail({ detail_actions: 4, detail_rail: 0, detail_list: 20, detail_cast: 0, manage_tools: 0, manage_list: 0, grid: 12, sidebar: 7 })
    expect(graph.detail_actions.down).toBe("detail_list")
    expect(graph.detail_list.up).toBe("detail_actions")
  })

  test("the rail enters at the selected member's tile", () => {
    expect(inputConfig.entryDefaults.detail_rail).toBe("[data-selected]")
  })
})
