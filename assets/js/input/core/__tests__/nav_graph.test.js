import { describe, expect, test } from "bun:test"
import { buildNavGraph, resolveCursorStart } from "../nav_graph"

// Test config — matches the app's layouts for realistic testing
const TEST_LAYOUTS = {
  watching: {
    zone_tabs: { down: ["grid"],             left: ["sidebar"] },
    grid:      { up: ["zone_tabs"],          left: ["sidebar"], right: ["drawer"] },
    sidebar:   { right: ["grid", "zone_tabs"] },
    drawer:    { left: ["grid"] },
  },
  library: {
    zone_tabs: { down: ["toolbar", "grid"],  left: ["sidebar"] },
    toolbar:   { up: ["zone_tabs"],          down: ["grid"],   left: ["sidebar"] },
    grid:      { up: ["toolbar", "zone_tabs"], left: ["sidebar"], right: ["drawer"] },
    sidebar:   { right: ["grid", "toolbar", "zone_tabs"] },
    drawer:    { left: ["grid", "toolbar"] },
  },
  upcoming: {
    zone_tabs: { down: ["upcoming"],           left: ["sidebar"] },
    upcoming:  { up: ["zone_tabs"],            left: ["sidebar"] },
    grid:      { up: ["upcoming", "zone_tabs"], left: ["upcoming", "sidebar"] },
    sidebar:   { right: ["upcoming", "grid", "zone_tabs"] },
  },
  settings: {
    sections:  { right: ["grid"],            left: ["sidebar"] },
    grid:      { left: ["sections"] },
    sidebar:   { right: ["sections", "grid"] },
  },
  status: {
    toolbar:    { down: ["grid"], left: ["sidebar"] },
    grid:       { up: ["toolbar"], down: ["drill-in"], left: ["sidebar"] },
    "drill-in": { up: ["grid"], left: ["sidebar"] },
    sidebar:    { right: ["grid", "toolbar"] },
  },
  download: {
    omnibox:         { down: ["grid", "drafts", "pursuits", "history"], left: ["sidebar"] },
    grid:            { up: ["omnibox"], down: ["drafts", "pursuits", "history"], left: ["sidebar"] },
    drafts:          { up: ["grid", "omnibox"], down: ["pursuits", "history"], left: ["sidebar"] },
    pursuits:        { up: ["drafts", "grid", "omnibox"], down: ["history", "other_downloads"], left: ["sidebar"] },
    history:         { up: ["pursuits", "drafts", "grid", "omnibox"], down: ["other_downloads"], left: ["sidebar"] },
    other_downloads: { up: ["history", "pursuits"], left: ["sidebar"] },
    sidebar:         { right: ["pursuits", "omnibox", "history"] },
  },
  home: {
    hero:      { down: ["continue", "recently", "coming_up"], left: ["sidebar"] },
    continue:  { up: ["hero"], down: ["recently", "coming_up"], left: ["sidebar"] },
    recently:  { up: ["continue", "hero"], down: ["coming_up"], left: ["sidebar"] },
    coming_up: { up: ["recently", "continue", "hero"], left: ["sidebar"] },
    sidebar:   { right: ["hero", "continue", "recently", "coming_up"] },
  },
}

const TEST_ALWAYS_POPULATED = ["sidebar", "sections"]

const TEST_CURSOR_START_PRIORITY = {
  watching:  ["grid", "zone_tabs", "sidebar"],
  library:   ["grid", "toolbar", "zone_tabs", "sidebar"],
  upcoming:  ["upcoming", "grid", "zone_tabs", "sidebar"],
  settings:  ["sections", "grid", "sidebar"],
  status:    ["grid", "toolbar", "sidebar"],
  download:  ["pursuits", "omnibox", "sidebar"],
  home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
}

const CONFIG = { layouts: TEST_LAYOUTS, alwaysPopulated: TEST_ALWAYS_POPULATED }

const CURSOR_CONFIG = {
  cursorStartPriority: TEST_CURSOR_START_PRIORITY,
  alwaysPopulated: TEST_ALWAYS_POPULATED,
}

/** Counts where everything is populated */
function fullCounts() {
  return { grid: 12, toolbar: 3, zone_tabs: 2, sidebar: 4, drawer: 5 }
}

describe("buildNavGraph", () => {
  describe("library zone, all populated", () => {
    const graph = buildNavGraph("library", fullCounts(), { ...CONFIG, drawerOpen: true })

    test("toolbar down goes to grid", () => {
      expect(graph.toolbar.down).toBe("grid")
    })

    test("toolbar up goes to zone_tabs", () => {
      expect(graph.toolbar.up).toBe("zone_tabs")
    })

    test("toolbar left goes to sidebar", () => {
      expect(graph.toolbar.left).toBe("sidebar")
    })

    test("zone_tabs down goes to toolbar (first candidate)", () => {
      expect(graph.zone_tabs.down).toBe("toolbar")
    })

    test("zone_tabs left goes to sidebar", () => {
      expect(graph.zone_tabs.left).toBe("sidebar")
    })

    test("grid up goes to toolbar (first candidate)", () => {
      expect(graph.grid.up).toBe("toolbar")
    })

    test("grid left goes to sidebar", () => {
      expect(graph.grid.left).toBe("sidebar")
    })

    test("grid right goes to drawer when open", () => {
      expect(graph.grid.right).toBe("drawer")
    })

    test("sidebar right goes to grid (first candidate)", () => {
      expect(graph.sidebar.right).toBe("grid")
    })

    test("drawer left goes to grid (first candidate)", () => {
      expect(graph.drawer.left).toBe("grid")
    })
  })

  describe("library zone, empty grid", () => {
    const counts = { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("library", counts, CONFIG)

    test("toolbar down blocked (grid is only candidate)", () => {
      expect(graph.toolbar.down).toBeUndefined()
    })

    test("zone_tabs down skips empty toolbar? no — toolbar is populated, goes there", () => {
      expect(graph.zone_tabs.down).toBe("toolbar")
    })

    test("grid up still goes to toolbar", () => {
      expect(graph.grid.up).toBe("toolbar")
    })

    test("sidebar right skips empty grid, goes to toolbar", () => {
      expect(graph.sidebar.right).toBe("toolbar")
    })

    test("drawer left skips empty grid, goes to toolbar", () => {
      const withDrawer = buildNavGraph("library", counts, { ...CONFIG, drawerOpen: true })
      expect(withDrawer.drawer.left).toBe("toolbar")
    })
  })

  describe("library zone, empty grid and toolbar", () => {
    const counts = { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("library", counts, CONFIG)

    test("zone_tabs down skips both empty candidates, blocked", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("sidebar right skips grid and toolbar, goes to zone_tabs", () => {
      expect(graph.sidebar.right).toBe("zone_tabs")
    })

    test("grid up skips toolbar, goes to zone_tabs", () => {
      expect(graph.grid.up).toBe("zone_tabs")
    })
  })

  describe("library zone, only sidebar populated", () => {
    const counts = { grid: 0, toolbar: 0, zone_tabs: 0, sidebar: 4 }
    const graph = buildNavGraph("library", counts, CONFIG)

    test("zone_tabs down blocked", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("zone_tabs left goes to sidebar", () => {
      expect(graph.zone_tabs.left).toBe("sidebar")
    })

    test("sidebar right blocked (all candidates empty)", () => {
      expect(graph.sidebar.right).toBeUndefined()
    })
  })

  describe("upcoming zone, sections populated", () => {
    const counts = { upcoming: 5, grid: 0, zone_tabs: 3, sidebar: 4 }
    const graph = buildNavGraph("upcoming", counts, CONFIG)

    test("zone_tabs down goes to upcoming", () => {
      expect(graph.zone_tabs.down).toBe("upcoming")
    })

    test("upcoming up goes to zone_tabs", () => {
      expect(graph.upcoming.up).toBe("zone_tabs")
    })

    test("upcoming left goes to sidebar", () => {
      expect(graph.upcoming.left).toBe("sidebar")
    })

    test("upcoming has no right edge (not defined in layout)", () => {
      expect(graph.upcoming.right).toBeUndefined()
    })

    test("sidebar right goes to upcoming (first populated candidate)", () => {
      expect(graph.sidebar.right).toBe("upcoming")
    })
  })

  describe("upcoming zone, with tracking grid", () => {
    const counts = { upcoming: 5, grid: 8, zone_tabs: 3, sidebar: 4 }
    const graph = buildNavGraph("upcoming", counts, CONFIG)

    test("grid up goes to upcoming (first populated candidate)", () => {
      expect(graph.grid.up).toBe("upcoming")
    })

    test("grid left goes to upcoming (first populated candidate)", () => {
      expect(graph.grid.left).toBe("upcoming")
    })

    test("sidebar right goes to upcoming over grid", () => {
      expect(graph.sidebar.right).toBe("upcoming")
    })
  })

  describe("upcoming zone, sections empty", () => {
    const counts = { upcoming: 0, grid: 0, zone_tabs: 3, sidebar: 4 }
    const graph = buildNavGraph("upcoming", counts, CONFIG)

    test("zone_tabs down blocked (upcoming is only candidate and empty)", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("sidebar right goes to zone_tabs (upcoming and grid empty)", () => {
      expect(graph.sidebar.right).toBe("zone_tabs")
    })
  })

  describe("watching zone, all populated", () => {
    const graph = buildNavGraph("watching", fullCounts(), CONFIG)

    test("zone_tabs down goes to grid", () => {
      expect(graph.zone_tabs.down).toBe("grid")
    })

    test("grid up goes to zone_tabs", () => {
      expect(graph.grid.up).toBe("zone_tabs")
    })

    test("grid left goes to sidebar", () => {
      expect(graph.grid.left).toBe("sidebar")
    })

    test("sidebar right goes to grid", () => {
      expect(graph.sidebar.right).toBe("grid")
    })

    test("no toolbar in watching layout", () => {
      expect(graph.toolbar).toBeUndefined()
    })
  })

  describe("watching zone, empty grid", () => {
    const counts = { grid: 0, zone_tabs: 2, sidebar: 4 }
    const graph = buildNavGraph("watching", counts, CONFIG)

    test("zone_tabs down blocked (grid is only candidate)", () => {
      expect(graph.zone_tabs.down).toBeUndefined()
    })

    test("sidebar right skips empty grid, goes to zone_tabs", () => {
      expect(graph.sidebar.right).toBe("zone_tabs")
    })
  })

  describe("watching zone, only sidebar populated", () => {
    const counts = { grid: 0, zone_tabs: 0, sidebar: 4 }
    const graph = buildNavGraph("watching", counts, CONFIG)

    test("sidebar right blocked", () => {
      expect(graph.sidebar.right).toBeUndefined()
    })
  })

  describe("drawer edges", () => {
    test("grid right has no edge when drawer is closed", () => {
      const graph = buildNavGraph("library", fullCounts(), { ...CONFIG, drawerOpen: false })
      expect(graph.grid.right).toBeUndefined()
    })

    test("grid right goes to drawer when open", () => {
      const graph = buildNavGraph("library", fullCounts(), { ...CONFIG, drawerOpen: true })
      expect(graph.grid.right).toBe("drawer")
    })

    test("drawer context excluded entirely when closed", () => {
      const graph = buildNavGraph("library", fullCounts(), { ...CONFIG, drawerOpen: false })
      expect(graph.drawer).toBeUndefined()
    })

    test("drawer left goes to grid when open and populated", () => {
      const graph = buildNavGraph("library", fullCounts(), { ...CONFIG, drawerOpen: true })
      expect(graph.drawer.left).toBe("grid")
    })

    test("drawer left skips empty grid, goes to toolbar", () => {
      const counts = { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4, drawer: 5 }
      const graph = buildNavGraph("library", counts, { ...CONFIG, drawerOpen: true })
      expect(graph.drawer.left).toBe("toolbar")
    })

    test("drawer left skips empty grid and toolbar, blocked (no more candidates)", () => {
      const counts = { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4, drawer: 5 }
      const graph = buildNavGraph("library", counts, { ...CONFIG, drawerOpen: true })
      expect(graph.drawer.left).toBeUndefined()
    })
  })

  describe("settings zone, all populated", () => {
    const counts = { grid: 6, sections: 4, sidebar: 4 }
    const graph = buildNavGraph("settings", counts, CONFIG)

    test("sections right goes to grid", () => {
      expect(graph.sections.right).toBe("grid")
    })

    test("sections left goes to sidebar", () => {
      expect(graph.sections.left).toBe("sidebar")
    })

    test("grid left goes to sections", () => {
      expect(graph.grid.left).toBe("sections")
    })

    test("sidebar right goes to sections (first candidate)", () => {
      expect(graph.sidebar.right).toBe("sections")
    })

    test("no zone_tabs or toolbar in settings layout", () => {
      expect(graph.zone_tabs).toBeUndefined()
      expect(graph.toolbar).toBeUndefined()
    })
  })

  describe("settings zone, empty grid", () => {
    const counts = { grid: 0, sections: 4, sidebar: 4 }
    const graph = buildNavGraph("settings", counts, CONFIG)

    test("sections right blocked (grid is only candidate)", () => {
      expect(graph.sections.right).toBeUndefined()
    })

    test("sidebar right goes to sections", () => {
      expect(graph.sidebar.right).toBe("sections")
    })
  })

  describe("status zone, drill-in open (a subsystem is selected)", () => {
    const counts = { toolbar: 1, grid: 9, "drill-in": 4, sidebar: 4 }
    const graph = buildNavGraph("status", counts, CONFIG)

    test("toolbar down goes to the tile grid", () => {
      expect(graph.toolbar.down).toBe("grid")
    })

    test("grid down goes to the drill-in, up to the toolbar", () => {
      expect(graph.grid.down).toBe("drill-in")
      expect(graph.grid.up).toBe("toolbar")
    })

    test("drill-in up returns to the grid", () => {
      expect(graph["drill-in"].up).toBe("grid")
    })

    test("every zone has a left edge to the sidebar", () => {
      for (const zone of ["toolbar", "grid", "drill-in"]) {
        expect(graph[zone].left).toBe("sidebar")
      }
    })

    test("sidebar right goes to the grid (first candidate)", () => {
      expect(graph.sidebar.right).toBe("grid")
    })
  })

  describe("status zone, drill-in closed (no subsystem selected)", () => {
    const counts = { toolbar: 1, grid: 9, "drill-in": 0, sidebar: 4 }
    const graph = buildNavGraph("status", counts, CONFIG)

    test("grid down blocked (drill-in is only candidate and empty)", () => {
      expect(graph.grid.down).toBeUndefined()
    })

    test("grid up and left still resolve", () => {
      expect(graph.grid.up).toBe("toolbar")
      expect(graph.grid.left).toBe("sidebar")
    })
  })

  describe("download zone, all populated (search results + drafts + pursuits + orphans)", () => {
    const counts = { omnibox: 3, grid: 5, drafts: 2, pursuits: 4, history: 1, other_downloads: 2, sidebar: 4 }
    const graph = buildNavGraph("download", counts, CONFIG)

    test("omnibox down goes to grid (search results, first candidate)", () => {
      expect(graph.omnibox.down).toBe("grid")
    })

    test("grid down goes to drafts, up to omnibox", () => {
      expect(graph.grid.down).toBe("drafts")
      expect(graph.grid.up).toBe("omnibox")
    })

    test("drafts down goes to pursuits, up to grid", () => {
      expect(graph.drafts.down).toBe("pursuits")
      expect(graph.drafts.up).toBe("grid")
    })

    test("pursuits down goes to history, up to drafts", () => {
      expect(graph.pursuits.down).toBe("history")
      expect(graph.pursuits.up).toBe("drafts")
    })

    test("history down goes to other_downloads", () => {
      expect(graph.history.down).toBe("other_downloads")
    })

    test("other_downloads has no down edge (bottom zone)", () => {
      expect(graph.other_downloads.down).toBeUndefined()
    })

    test("every zone has a left edge to the sidebar", () => {
      for (const zone of ["omnibox", "grid", "drafts", "pursuits", "history", "other_downloads"]) {
        expect(graph[zone].left).toBe("sidebar")
      }
    })

    test("sidebar right goes to pursuits (first candidate)", () => {
      expect(graph.sidebar.right).toBe("pursuits")
    })

    test("no zone_tabs, toolbar, or drawer in download layout", () => {
      expect(graph.zone_tabs).toBeUndefined()
      expect(graph.toolbar).toBeUndefined()
      expect(graph.drawer).toBeUndefined()
    })
  })

  describe("download zone, conditional zones absent (no search, no drafts, no orphans)", () => {
    const counts = { omnibox: 3, grid: 0, drafts: 0, pursuits: 4, history: 1, other_downloads: 0, sidebar: 4 }
    const graph = buildNavGraph("download", counts, CONFIG)

    test("omnibox down skips empty grid and drafts, lands on pursuits", () => {
      expect(graph.omnibox.down).toBe("pursuits")
    })

    test("pursuits up skips empty drafts and grid, lands on omnibox", () => {
      expect(graph.pursuits.up).toBe("omnibox")
    })

    test("history down blocked (other_downloads is only candidate and empty)", () => {
      expect(graph.history.down).toBeUndefined()
    })

    test("sidebar right goes to pursuits", () => {
      expect(graph.sidebar.right).toBe("pursuits")
    })
  })

  describe("download zone, nothing tracked yet (only omnibox and collapsed history)", () => {
    const counts = { omnibox: 3, grid: 0, drafts: 0, pursuits: 0, history: 1, other_downloads: 0, sidebar: 4 }
    const graph = buildNavGraph("download", counts, CONFIG)

    test("omnibox down reaches history via its disclosure toggle", () => {
      expect(graph.omnibox.down).toBe("history")
    })

    test("history up skips empty zones, lands on omnibox", () => {
      expect(graph.history.up).toBe("omnibox")
    })

    test("sidebar right skips empty pursuits, goes to omnibox", () => {
      expect(graph.sidebar.right).toBe("omnibox")
    })
  })

  describe("home zone, all shelves populated", () => {
    const counts = { hero: 2, continue: 5, recently: 8, coming_up: 4, sidebar: 4 }
    const graph = buildNavGraph("home", counts, CONFIG)

    test("hero down goes to continue (first candidate)", () => {
      expect(graph.hero.down).toBe("continue")
    })

    test("hero left goes to sidebar", () => {
      expect(graph.hero.left).toBe("sidebar")
    })

    test("hero has no up edge (top shelf)", () => {
      expect(graph.hero.up).toBeUndefined()
    })

    test("continue up goes to hero, down to recently", () => {
      expect(graph.continue.up).toBe("hero")
      expect(graph.continue.down).toBe("recently")
    })

    test("recently up goes to continue, down to coming_up", () => {
      expect(graph.recently.up).toBe("continue")
      expect(graph.recently.down).toBe("coming_up")
    })

    test("coming_up up goes to recently, has no down edge (bottom shelf)", () => {
      expect(graph.coming_up.up).toBe("recently")
      expect(graph.coming_up.down).toBeUndefined()
    })

    test("sidebar right goes to hero (first candidate)", () => {
      expect(graph.sidebar.right).toBe("hero")
    })
  })

  describe("home zone, no hero (continue is first shelf)", () => {
    const counts = { hero: 0, continue: 5, recently: 8, coming_up: 4, sidebar: 4 }
    const graph = buildNavGraph("home", counts, CONFIG)

    test("sidebar right skips empty hero, goes to continue", () => {
      expect(graph.sidebar.right).toBe("continue")
    })

    test("continue up blocked (only hero candidate, empty)", () => {
      expect(graph.continue.up).toBeUndefined()
    })
  })

  describe("home zone, sparse middle shelves", () => {
    const counts = { hero: 2, continue: 0, recently: 0, coming_up: 4, sidebar: 4 }
    const graph = buildNavGraph("home", counts, CONFIG)

    test("hero down skips empty continue/recently, goes to coming_up", () => {
      expect(graph.hero.down).toBe("coming_up")
    })

    test("coming_up up skips empty recently/continue, goes to hero", () => {
      expect(graph.coming_up.up).toBe("hero")
    })
  })

  describe("home zone, only sidebar populated", () => {
    const counts = { hero: 0, continue: 0, recently: 0, coming_up: 0, sidebar: 4 }
    const graph = buildNavGraph("home", counts, CONFIG)

    test("sidebar right blocked (all shelves empty)", () => {
      expect(graph.sidebar.right).toBeUndefined()
    })
  })

  describe("edge cases", () => {
    test("unknown zone returns empty graph", () => {
      expect(buildNavGraph("unknown", fullCounts(), CONFIG)).toEqual({})
    })
  })
})

describe("resolveCursorStart", () => {
  test("library zone with full counts returns grid", () => {
    expect(resolveCursorStart("library", fullCounts(), CURSOR_CONFIG)).toBe("grid")
  })

  test("upcoming zone returns upcoming when populated", () => {
    expect(resolveCursorStart("upcoming", { upcoming: 5, grid: 0, zone_tabs: 3, sidebar: 4 }, CURSOR_CONFIG)).toBe("upcoming")
  })

  test("upcoming zone falls back to grid when upcoming is empty", () => {
    expect(resolveCursorStart("upcoming", { upcoming: 0, grid: 8, zone_tabs: 3, sidebar: 4 }, CURSOR_CONFIG)).toBe("grid")
  })

  test("library zone with empty grid returns toolbar", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4 }, CURSOR_CONFIG)).toBe("toolbar")
  })

  test("library zone with empty grid and toolbar returns zone_tabs", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 0, zone_tabs: 2, sidebar: 4 }, CURSOR_CONFIG)).toBe("zone_tabs")
  })

  test("library zone with only sidebar returns sidebar", () => {
    expect(resolveCursorStart("library", { grid: 0, toolbar: 0, zone_tabs: 0, sidebar: 4 }, CURSOR_CONFIG)).toBe("sidebar")
  })

  test("watching zone with full counts returns grid", () => {
    expect(resolveCursorStart("watching", fullCounts(), CURSOR_CONFIG)).toBe("grid")
  })

  test("watching zone with empty grid returns zone_tabs", () => {
    expect(resolveCursorStart("watching", { grid: 0, zone_tabs: 2, sidebar: 4 }, CURSOR_CONFIG)).toBe("zone_tabs")
  })

  test("watching zone with only sidebar returns sidebar", () => {
    expect(resolveCursorStart("watching", { grid: 0, zone_tabs: 0, sidebar: 4 }, CURSOR_CONFIG)).toBe("sidebar")
  })

  test("settings zone with full counts returns sections", () => {
    expect(resolveCursorStart("settings", { sections: 4, grid: 6, sidebar: 4 }, CURSOR_CONFIG)).toBe("sections")
  })

  test("settings zone always starts at sections (always populated)", () => {
    expect(resolveCursorStart("settings", { sections: 0, grid: 6, sidebar: 4 }, CURSOR_CONFIG)).toBe("sections")
  })

  test("status zone starts at the tile grid", () => {
    expect(resolveCursorStart("status", { grid: 9, toolbar: 1, sidebar: 4 }, CURSOR_CONFIG)).toBe("grid")
  })

  test("status zone falls back to toolbar when the board is empty", () => {
    expect(resolveCursorStart("status", { grid: 0, toolbar: 1, sidebar: 4 }, CURSOR_CONFIG)).toBe("toolbar")
  })

  test("download zone with active pursuits starts at pursuits", () => {
    expect(resolveCursorStart("download", { pursuits: 4, omnibox: 3, sidebar: 4 }, CURSOR_CONFIG)).toBe("pursuits")
  })

  test("download zone with no pursuits falls back to omnibox", () => {
    expect(resolveCursorStart("download", { pursuits: 0, omnibox: 3, sidebar: 4 }, CURSOR_CONFIG)).toBe("omnibox")
  })

  test("download zone with nothing rendered falls back to sidebar", () => {
    expect(resolveCursorStart("download", { pursuits: 0, omnibox: 0, sidebar: 4 }, CURSOR_CONFIG)).toBe("sidebar")
  })

  test("home zone returns hero when populated", () => {
    expect(resolveCursorStart("home", { hero: 2, continue: 5, recently: 8, coming_up: 4, sidebar: 4 }, CURSOR_CONFIG)).toBe("hero")
  })

  test("home zone falls back to continue when hero is empty", () => {
    expect(resolveCursorStart("home", { hero: 0, continue: 5, recently: 8, coming_up: 4, sidebar: 4 }, CURSOR_CONFIG)).toBe("continue")
  })

  test("home zone falls back to coming_up when only it is populated", () => {
    expect(resolveCursorStart("home", { hero: 0, continue: 0, recently: 0, coming_up: 4, sidebar: 4 }, CURSOR_CONFIG)).toBe("coming_up")
  })

  test("home zone falls back to sidebar when all shelves empty", () => {
    expect(resolveCursorStart("home", { hero: 0, continue: 0, recently: 0, coming_up: 0, sidebar: 4 }, CURSOR_CONFIG)).toBe("sidebar")
  })

  test("unknown zone returns null", () => {
    expect(resolveCursorStart("unknown", fullCounts(), CURSOR_CONFIG)).toBeNull()
  })
})
