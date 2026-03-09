import { describe, expect, test, beforeEach } from "bun:test"
import { FocusContextMachine, Context } from "../focus_context"
import { Action } from "../actions"

describe("FocusContextMachine", () => {
  let machine

  beforeEach(() => {
    machine = new FocusContextMachine()
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

    test("right with drawer open switches to drawer context", () => {
      machine.presentationChanged("drawer")
      // presentationChanged("drawer") switches context to DRAWER
      // Reset to GRID to test the grid→drawer transition
      machine._context = Context.GRID

      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "focus_context", target: Context.DRAWER })
      expect(machine.context).toBe(Context.DRAWER)
    })

    test("zone cycling produces zone_cycle directive", () => {
      expect(machine.transition(Action.ZONE_NEXT)).toEqual({ type: "zone_cycle", direction: "next" })
      expect(machine.transition(Action.ZONE_PREV)).toEqual({ type: "zone_cycle", direction: "prev" })
    })
  })

  describe("Grid wall transitions", () => {
    test("up wall in watching zone goes to zone tabs", () => {
      machine.zoneChanged("watching")
      const directive = machine.gridWall("up")
      expect(directive).toEqual({ type: "focus_first", context: Context.ZONE_TABS })
      expect(machine.context).toBe(Context.ZONE_TABS)
    })

    test("up wall in library zone goes to toolbar", () => {
      machine.zoneChanged("library")
      const directive = machine.gridWall("up")
      expect(directive).toEqual({ type: "focus_first", context: Context.TOOLBAR })
      expect(machine.context).toBe(Context.TOOLBAR)
    })

    test("left wall goes to sidebar", () => {
      const directive = machine.gridWall("left")
      expect(directive).toEqual({ type: "enter_sidebar" })
      expect(machine.context).toBe(Context.SIDEBAR)
    })

    test("down wall is no-op", () => {
      expect(machine.gridWall("down")).toEqual({ type: "none" })
    })

    test("right wall is no-op", () => {
      expect(machine.gridWall("right")).toEqual({ type: "none" })
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
    })

    test("starts in drawer context", () => {
      expect(machine.context).toBe(Context.DRAWER)
    })

    test("up/down navigate vertically", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("left switches to grid context", () => {
      const directive = machine.transition(Action.NAVIGATE_LEFT)
      expect(directive).toEqual({ type: "focus_context", target: Context.GRID })
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
      machine._context = Context.TOOLBAR
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

    test("select activates", () => {
      expect(machine.transition(Action.SELECT)).toEqual({ type: "activate" })
    })
  })

  describe("Sidebar context", () => {
    beforeEach(() => {
      machine._context = Context.SIDEBAR
    })

    test("up/down navigate vertically", () => {
      expect(machine.transition(Action.NAVIGATE_UP)).toEqual({ type: "navigate", direction: "up" })
      expect(machine.transition(Action.NAVIGATE_DOWN)).toEqual({ type: "navigate", direction: "down" })
    })

    test("right exits to grid", () => {
      const directive = machine.transition(Action.NAVIGATE_RIGHT)
      expect(directive).toEqual({ type: "exit_sidebar" })
      expect(machine.context).toBe(Context.GRID)
    })

    test("left is wall", () => {
      expect(machine.transition(Action.NAVIGATE_LEFT)).toEqual({ type: "none" })
    })

    test("back exits to grid", () => {
      const directive = machine.transition(Action.BACK)
      expect(directive).toEqual({ type: "exit_sidebar" })
      expect(machine.context).toBe(Context.GRID)
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
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "focus_first", context: Context.TOOLBAR })
      expect(machine.context).toBe(Context.TOOLBAR)
    })

    test("down goes to grid in watching zone", () => {
      machine.zoneChanged("watching")
      machine._context = Context.ZONE_TABS
      const directive = machine.transition(Action.NAVIGATE_DOWN)
      expect(directive).toEqual({ type: "focus_first", context: Context.GRID })
      expect(machine.context).toBe(Context.GRID)
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
})
