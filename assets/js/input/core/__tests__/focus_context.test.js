import { describe, expect, test, beforeEach } from "bun:test"
import { FocusContextMachine, Context, contextType } from "../focus_context"
import { Action } from "../actions"
import { buildNavGraph } from "../nav_graph"

// Test config — matches the app's config for realistic testing
const TEST_INSTANCE_TYPES = {
  sidebar: Context.MENU,
  sections: Context.MENU,
}

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
  settings: {
    sections:  { right: ["grid"],            left: ["sidebar"] },
    grid:      { left: ["sections"] },
    sidebar:   { right: ["sections", "grid"] },
  },
}

const TEST_ALWAYS_POPULATED = ["sidebar", "sections"]

const GRAPH_CONFIG = { layouts: TEST_LAYOUTS, alwaysPopulated: TEST_ALWAYS_POPULATED }

/** Build a nav graph with all contexts populated */
function fullGraph(zone, options = {}) {
  const counts = { grid: 12, toolbar: 3, zone_tabs: 2, sidebar: 4, drawer: 5 }
  return buildNavGraph(zone, counts, { ...options, ...GRAPH_CONFIG })
}

function createMachine(overrides = {}) {
  return new FocusContextMachine({
    instanceTypes: TEST_INSTANCE_TYPES,
    primaryMenu: "sidebar",
    ...overrides,
  })
}

describe("FocusContextMachine", () => {
  let machine

  beforeEach(() => {
    machine = createMachine()
  })

  test("starts in GRID context", () => {
    expect(machine.context).toBe(Context.GRID)
  })

  describe("Grid context", () => {
    test("arrow keys produce navigate directives", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "navigate", direction: "left" })
      expect(machine.transition(Action.NAVIGATE_RIGHT)).toEqual({ type: "navigate", direction: "right" })
    })

    test("select produces activate", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })

    test("play produces play", () => {
      expect(machine.transition(Action.PLAY)).toEqual({ type: "play" })
    })

    test("back is no-op", () => {
      expect(machine.transition(Action.BACK)).toEqual({ type: "none" })
    })

    test("right always navigates spatially (drawer transition handled by gridWall)", () => {
      machine.presentationChanged("drawer")
      machine._context = Context.GRID

      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "navigate", direction: "right" })
      expect(machine.context).toBe(Context.GRID)
    })

    test("zone cycling produces zone_cycle directive", () => {
      expect(machine.transition(Action.ZONE_NEXT)).toEqual({ type: "zone_cycle", direction: "next" })
      expect(machine.transition(Action.ZONE_PREV)).toEqual({ type: "zone_cycle", direction: "prev" })
    })
  })

  describe("Grid wall transitions", () => {
    test("up wall in watching zone goes to zone tabs", () => {
      machine.zoneChanged("watching")
      machine.setNavGraph(fullGraph("watching"))
      const directive = machine.gridWall("up")
      expect(directive).toEqual({ type: "focus_first", context: Context.ZONE_TABS })
      expect(machine.context).toBe(Context.ZONE_TABS)
    })

    test("up wall in library zone goes to toolbar", () => {
      machine.zoneChanged("library")
      machine.setNavGraph(fullGraph("library"))
      const directive = machine.gridWall("up")
      expect(directive).toEqual({ type: "focus_first", context: Context.TOOLBAR })
      expect(machine.context).toBe(Context.TOOLBAR)
    })

    test("left wall goes to sidebar", () => {
      machine.setNavGraph(fullGraph("watching"))
      const directive = machine.gridWall("left")
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("right wall with drawer open switches to drawer", () => {
      machine.presentationChanged("drawer")
      machine._context = Context.GRID
      machine.setNavGraph(fullGraph("watching", { drawerOpen: true }))
      const directive = machine.gridWall("right")
      expect(directive).toEqual({ type: "focus_context", target: Context.DRAWER })
      expect(machine.context).toBe(Context.DRAWER)
    })

    test("right wall without drawer is no-op", () => {
      machine.setNavGraph(fullGraph("watching"))
      expect(machine.gridWall("right")).toEqual({ type: "none" })
    })

    test("down wall is no-op", () => {
      machine.setNavGraph(fullGraph("watching"))
      expect(machine.gridWall("down")).toEqual({ type: "none" })
    })
  })

  describe("Modal context", () => {
    beforeEach(() => {
      machine.presentationChanged("modal")
    })

    test("starts in modal context", () => {
      expect(machine.context).toBe(Context.MODAL)
    })

    test("up/down navigate vertically", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("left/right are blocked", () => {
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "none" })
      expect(machine.transition(Action.NAVIGATE_RIGHT)).toEqual({ type: "none" })
    })

    test("back dismisses", () => {
      expect(machine.transition(Action.BACK)).toEqual({ type: "dismiss" })
    })

    test("select activates", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })

    test("zone cycling blocked", () => {
      expect(machine.transition(Action.ZONE_NEXT)).toEqual({ type: "none" })
      expect(machine.transition(Action.ZONE_PREV)).toEqual({ type: "none" })
    })

    test("play produces play", () => {
      expect(machine.transition(Action.PLAY)).toEqual({ type: "play" })
    })
  })

  describe("Drawer context", () => {
    beforeEach(() => {
      machine.presentationChanged("drawer")
      machine.setNavGraph(fullGraph("watching", { drawerOpen: true }))
    })

    test("starts in drawer context", () => {
      expect(machine.context).toBe(Context.DRAWER)
    })

    test("up/down navigate vertically", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("left switches to grid at row edge", () => {
      const directive = machine.transition(Action.NAVIGATE_LEFT)
      expect(directive).toEqual({ type: "grid_row_edge", side: "right" })
      expect(machine.context).toBe(Context.GRID)
    })

    test("right is blocked", () => {
      expect(machine.transition(Action.NAVIGATE_RIGHT)).toEqual({ type: "none" })
    })

    test("back dismisses", () => {
      expect(machine.transition(Action.BACK)).toEqual({ type: "dismiss" })
    })

    test("zone cycling works from drawer", () => {
      expect(machine.transition(Action.ZONE_NEXT)).toEqual({ type: "zone_cycle", direction: "next" })
    })
  })

  describe("Toolbar context", () => {
    beforeEach(() => {
      machine.zoneChanged("library")
      machine._context = Context.TOOLBAR
      machine.setNavGraph(fullGraph("library"))
    })

    test("left/right navigate horizontally", () => {
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "navigate", direction: "left" })
      expect(machine.transition(Action.NAVIGATE_RIGHT)).toEqual({ type: "navigate", direction: "right" })
    })

    test("down goes to grid", () => {
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "focus_first", context: Context.GRID })
      expect(machine.context).toBe(Context.GRID)
    })

    test("up goes to zone tabs", () => {
      const directive = machine.transition(Action.NAVIGATE_UP)
      expect(directive).toEqual({ type: "focus_first", context: Context.ZONE_TABS })
      expect(machine.context).toBe(Context.ZONE_TABS)
    })

    test("down blocked when grid is empty", () => {
      const emptyGridGraph = buildNavGraph("library", { grid: 0, toolbar: 3, zone_tabs: 2, sidebar: 4 }, GRAPH_CONFIG)
      machine.setNavGraph(emptyGridGraph)
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "none" })
      expect(machine.context).toBe(Context.TOOLBAR)
    })

    test("select activates", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })
  })

  describe("Sidebar context", () => {
    beforeEach(() => {
      machine._context = "sidebar"
    })

    test("up/down navigate vertically", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("right produces exit_sidebar (context set by orchestrator)", () => {
      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "exit_sidebar" })
      // Context stays SIDEBAR — orchestrator's _executeExitSidebar sets it
      expect(machine.context).toBe("sidebar")
    })

    test("left is wall", () => {
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "none" })
    })

    test("back produces exit_sidebar (context set by orchestrator)", () => {
      const directive = machine.transition(Action.BACK)
      expect(directive).toEqual({ type: "exit_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("select activates", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })
  })

  describe("Zone tabs context", () => {
    beforeEach(() => {
      machine._context = Context.ZONE_TABS
    })

    test("left/right navigate horizontally", () => {
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "navigate", direction: "left" })
      expect(machine.transition(Action.NAVIGATE_RIGHT)).toEqual({ type: "navigate", direction: "right" })
    })

    test("down goes to toolbar in library zone", () => {
      machine.zoneChanged("library")
      machine._context = Context.ZONE_TABS
      machine.setNavGraph(fullGraph("library"))
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "focus_first", context: Context.TOOLBAR })
      expect(machine.context).toBe(Context.TOOLBAR)
    })

    test("down goes to grid in watching zone", () => {
      machine.zoneChanged("watching")
      machine._context = Context.ZONE_TABS
      machine.setNavGraph(fullGraph("watching"))
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "focus_first", context: Context.GRID })
      expect(machine.context).toBe(Context.GRID)
    })

    test("down blocked when target is empty", () => {
      machine.zoneChanged("watching")
      machine._context = Context.ZONE_TABS
      machine.setNavGraph(buildNavGraph("watching", { grid: 0, zone_tabs: 2, sidebar: 4 }, GRAPH_CONFIG))
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "none" })
      expect(machine.context).toBe(Context.ZONE_TABS)
    })

    test("up is wall", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "none" })
    })

    test("select activates tab", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })
  })

  describe("Zone changes", () => {
    test("resets context to grid from non-tab contexts", () => {
      machine._context = Context.TOOLBAR
      machine.zoneChanged("library")
      expect(machine.context).toBe(Context.GRID)
    })

    test("preserves zone_tabs context across zone change", () => {
      machine._context = Context.ZONE_TABS
      machine.zoneChanged("library")
      expect(machine.context).toBe(Context.ZONE_TABS)
    })

    test("clears drawer state", () => {
      machine.presentationChanged("drawer")
      machine.zoneChanged("watching")
      expect(machine._drawerOpen).toBe(false)
    })
  })

  describe("forceContext()", () => {
    test("sets context to the given value", () => {
      machine.forceContext("sidebar")
      expect(machine.context).toBe("sidebar")
    })

    test("can restore to any context", () => {
      machine.forceContext(Context.TOOLBAR)
      expect(machine.context).toBe(Context.TOOLBAR)

      machine.forceContext(Context.ZONE_TABS)
      expect(machine.context).toBe(Context.ZONE_TABS)
    })
  })

  describe("syncDrawerState()", () => {
    test("sets drawer open to true", () => {
      machine.syncDrawerState(true)
      machine.setNavGraph(fullGraph("watching", { drawerOpen: true }))
      // Verify by checking gridWall right behavior
      const directive = machine.gridWall("right")
      expect(directive).toEqual({ type: "focus_context", target: Context.DRAWER })
    })

    test("sets drawer open to false", () => {
      machine.syncDrawerState(true)
      machine.syncDrawerState(false)
      machine.forceContext(Context.GRID)
      machine.setNavGraph(fullGraph("watching", { drawerOpen: false }))
      const directive = machine.gridWall("right")
      expect(directive).toEqual({ type: "none" })
    })
  })

  describe("enterSidebarFromWall()", () => {
    test("sets context to sidebar and returns enter_sidebar directive", () => {
      machine.forceContext(Context.TOOLBAR)
      const directive = machine.enterSidebarFromWall()
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("works from zone tabs context", () => {
      machine.forceContext(Context.ZONE_TABS)
      const directive = machine.enterSidebarFromWall()
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })
  })

  describe("Presentation changes", () => {
    test("opening modal switches to modal context", () => {
      machine.presentationChanged("modal")
      expect(machine.context).toBe(Context.MODAL)
    })

    test("opening drawer switches to drawer context", () => {
      machine.presentationChanged("drawer")
      expect(machine.context).toBe(Context.DRAWER)
    })

    test("closing presentation returns to grid", () => {
      machine.presentationChanged("modal")
      machine.presentationChanged(null)
      expect(machine.context).toBe(Context.GRID)
    })

    test("closing drawer returns to grid", () => {
      machine.presentationChanged("drawer")
      machine.presentationChanged(null)
      expect(machine.context).toBe(Context.GRID)
      expect(machine._drawerOpen).toBe(false)
    })

    test("closing does not change context if already in toolbar", () => {
      machine._context = Context.TOOLBAR
      machine.presentationChanged(null)
      expect(machine.context).toBe(Context.TOOLBAR)
    })
  })

  describe("MENU context type resolver", () => {
    test("sidebar instance resolves to MENU type", () => {
      expect(contextType("sidebar", TEST_INSTANCE_TYPES)).toBe(Context.MENU)
    })

    test("unknown instance resolves to itself", () => {
      expect(contextType("grid", TEST_INSTANCE_TYPES)).toBe("grid")
      expect(contextType("drawer", TEST_INSTANCE_TYPES)).toBe("drawer")
    })

    test("sidebar instance uses _menuTransition via transition()", () => {
      machine._context = "sidebar"
      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "exit_sidebar" })
    })

    test("sidebar back exits sidebar via _menuTransition", () => {
      machine._context = "sidebar"
      const directive = machine.transition(Action.BACK)
      expect(directive).toEqual({ type: "exit_sidebar" })
    })

    test("sidebar left is wall via _menuTransition", () => {
      machine._context = "sidebar"
      const directive = machine.transition(Action.NAVIGATE_LEFT)
      expect(directive).toEqual({ type: "none" })
    })
  })

  describe("sections MENU instance", () => {
    test("sections resolves to MENU type", () => {
      expect(contextType("sections", TEST_INSTANCE_TYPES)).toBe(Context.MENU)
    })

    test("sections right navigates to grid via nav graph", () => {
      machine._context = "sections"
      machine.setNavGraph({ sections: { right: "grid" } })
      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "focus_first", context: "grid" })
      expect(machine.context).toBe("grid")
    })

    test("sections left navigates to sidebar via nav graph", () => {
      machine._context = "sections"
      machine.setNavGraph({ sections: { left: "sidebar" } })
      const directive = machine.transition(Action.NAVIGATE_LEFT)
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("sections back navigates to sidebar via nav graph", () => {
      machine._context = "sections"
      machine.setNavGraph({ sections: { left: "sidebar" } })
      const directive = machine.transition(Action.BACK)
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("sections left with no nav graph edge is no-op", () => {
      machine._context = "sections"
      machine.setNavGraph({ sections: {} })
      const directive = machine.transition(Action.NAVIGATE_LEFT)
      expect(directive).toEqual({ type: "none" })
    })

    test("sections up/down navigate linearly", () => {
      machine._context = "sections"
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("sections select activates", () => {
      machine._context = "sections"
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })
  })

  describe("onContextChanged callback", () => {
    test("fires on context change", () => {
      const calls = []
      const machine = createMachine({ onContextChanged: (ctx) => calls.push(ctx) })
      machine.forceContext("sidebar")
      expect(calls).toEqual(["sidebar"])
    })

    test("does not fire when context unchanged", () => {
      const calls = []
      const machine = createMachine({ onContextChanged: (ctx) => calls.push(ctx) })
      // Machine starts in GRID — forcing to GRID should not fire
      machine.forceContext(Context.GRID)
      expect(calls).toEqual([])
    })

    test("fires from transition", () => {
      const calls = []
      const machine = createMachine({ onContextChanged: (ctx) => calls.push(ctx) })
      machine.zoneChanged("watching")
      machine.setNavGraph(fullGraph("watching"))
      // Grid wall up → zone_tabs
      machine.gridWall("up")
      expect(calls).toContain(Context.ZONE_TABS)
    })

    test("fires from presentationChanged", () => {
      const calls = []
      const machine = createMachine({ onContextChanged: (ctx) => calls.push(ctx) })
      machine.presentationChanged("modal")
      expect(calls).toEqual([Context.MODAL])
    })
  })

  describe("gridWall left is nav-graph-driven", () => {
    test("left wall goes to sidebar when nav graph points there", () => {
      machine.setNavGraph(fullGraph("watching"))
      const directive = machine.gridWall("left")
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe("sidebar")
    })

    test("left wall is no-op when nav graph has no left edge", () => {
      machine.setNavGraph({ grid: {} })
      const directive = machine.gridWall("left")
      expect(directive).toEqual({ type: "none" })
    })

    test("left wall goes to non-sidebar target when nav graph points there", () => {
      machine.setNavGraph({ grid: { left: "sections" } })
      const directive = machine.gridWall("left")
      expect(directive).toEqual({ type: "focus_first", context: "sections" })
      expect(machine.context).toBe("sections")
    })
  })
})
