import { describe, expect, test, beforeEach, mock } from "bun:test"
import { InputSystem } from "../index"
import { Context } from "../focus_context"
import { Action } from "../actions"

/**
 * Mock DomReader — returns controllable values for all reader methods.
 */
function createMockReader(overrides = {}) {
  return {
    getZone: () => "watching",
    getPresentation: () => null,
    isDrawerOpen: () => false,
    getSortOrder: () => null,
    getGridColumnCount: () => 4,
    getItemCount: () => 8,
    getFocusedIndex: () => 0,
    getCurrentFocusedItem: () => null,
    getActiveZoneTabIndex: () => 0,
    getActiveToolbarTabIndex: () => 0,
    getZoneTabCount: () => 2,
    getActiveSidebarIndex: () => -1,
    getEntityIndex: () => -1,
    getSidebarCollapsed: () => false,
    getPageBehavior: () => null,
    ...overrides,
  }
}

/**
 * Mock DomWriter — records all calls for assertion.
 */
function createMockWriter() {
  const calls = []
  const writer = new Proxy({}, {
    get(_, prop) {
      return (...args) => {
        calls.push({ method: prop, args })
      }
    },
  })
  return { writer, calls }
}

/**
 * Mock globals (document, sessionStorage, requestAnimationFrame).
 */
function createMockGlobals() {
  const listeners = {}
  const storage = {}
  const rafCallbacks = []

  return {
    document: {
      addEventListener(type, fn) {
        listeners[type] = listeners[type] || []
        listeners[type].push(fn)
      },
      removeEventListener(type, fn) {
        if (listeners[type]) {
          listeners[type] = listeners[type].filter(f => f !== fn)
        }
      },
    },
    sessionStorage: {
      getItem(key) { return storage[key] ?? null },
      setItem(key, value) { storage[key] = value },
      removeItem(key) { delete storage[key] },
    },
    requestAnimationFrame(fn) { rafCallbacks.push(fn) },
    // Test helpers
    _listeners: listeners,
    _storage: storage,
    _rafCallbacks: rafCallbacks,
    _flushRAF() {
      const cbs = rafCallbacks.splice(0)
      cbs.forEach(fn => fn())
    },
    _dispatchKeyDown(key, opts = {}) {
      const event = {
        key,
        target: opts.target || { closest: () => null, tagName: "DIV" },
        ctrlKey: false,
        metaKey: false,
        altKey: false,
        preventDefault: mock(() => {}),
        ...opts,
      }
      for (const fn of (listeners.keydown || [])) {
        fn(event)
      }
      return event
    },
  }
}

function setup(readerOverrides = {}) {
  const reader = createMockReader(readerOverrides)
  const { writer, calls } = createMockWriter()
  const globals = createMockGlobals()
  const system = new InputSystem(reader, writer, globals)
  return { system, reader, writer, calls, globals }
}

describe("InputSystem orchestrator", () => {
  describe("action routing", () => {
    test("arrow down in grid navigates to correct index", () => {
      const { system, reader, calls, globals } = setup({
        getFocusedIndex: () => 0,
        getItemCount: () => 8,
        getGridColumnCount: () => 4,
      })
      system.start({})
      calls.length = 0

      globals._dispatchKeyDown("ArrowDown")

      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args).toEqual([Context.GRID, 4])
    })

    test("Enter activates the focused element via click", () => {
      const clicked = mock(() => {})
      const mockElement = { click: clicked, dataset: {} }
      const { system, calls, globals } = setup({
        getCurrentFocusedItem: () => mockElement,
      })
      system.start({})
      calls.length = 0

      globals._dispatchKeyDown("Enter")
      expect(clicked).toHaveBeenCalled()
    })

    test("Escape in modal pushes close_detail event", () => {
      const hookEl = { pushEvent: mock(() => {}) }
      const { system, globals } = setup({
        getPresentation: () => "modal",
      })
      system.start(hookEl)

      globals._dispatchKeyDown("Escape")
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })
  })

  describe("text input mode", () => {
    test("Enter on text input activates edit mode", () => {
      const { system, globals } = setup()
      system.start({})

      const input = { tagName: "INPUT", value: "", closest: () => null }
      const event = globals._dispatchKeyDown("Enter", { target: input })

      expect(event.preventDefault).toHaveBeenCalled()
      expect(system._inputEditing).toBe(true)
    })

    test("Escape on text input with value clears it", () => {
      const dispatchEvent = mock(() => {})
      const input = { tagName: "INPUT", value: "hello", closest: () => null, dispatchEvent }

      const { system, globals } = setup()
      system.start({})

      globals._dispatchKeyDown("Escape", { target: input })

      expect(input.value).toBe("")
      expect(dispatchEvent).toHaveBeenCalled()
    })
  })

  describe("context memory", () => {
    test("saves grid entity ID when navigating away", () => {
      const focusedCard = { dataset: { entityId: "abc-123" } }
      const { system, globals } = setup({
        getCurrentFocusedItem: () => focusedCard,
        getFocusedIndex: () => 0,
        getItemCount: () => 8,
        getGridColumnCount: () => 4,
      })
      system.start({})

      // Navigate up to hit the wall → triggers save
      globals._dispatchKeyDown("ArrowUp")

      expect(system._lastGridEntityId).toBe("abc-123")
    })
  })

  describe("sidebar persistence", () => {
    test("destroy persists sidebar context to sessionStorage", () => {
      const { system, globals } = setup()
      system.start({})
      system.focusMachine.forceContext(Context.SIDEBAR)
      system.destroy()

      expect(globals._storage["inputSystem:resumeSidebar"]).toBe("true")
    })

    test("start resumes sidebar context from sessionStorage", () => {
      const { system, calls, globals } = setup({
        getActiveSidebarIndex: () => 1,
      })
      globals.sessionStorage.setItem("inputSystem:resumeSidebar", "true")

      system.start({})

      expect(system.focusMachine.context).toBe(Context.SIDEBAR)
      expect(globals.sessionStorage.getItem("inputSystem:resumeSidebar")).toBe(null)

      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.some(c => c.args[0] === Context.SIDEBAR && c.args[1] === 1)).toBe(true)
    })

    test("destroy does not persist when not in sidebar", () => {
      const { system, globals } = setup()
      system.start({})
      system.destroy()
      expect(globals._storage["inputSystem:resumeSidebar"]).toBeUndefined()
    })
  })

  describe("modal/drawer lifecycle", () => {
    test("modal appearing switches to modal context", () => {
      const { system, reader } = setup()
      system.start({})

      // Simulate modal appearing
      reader.getPresentation = () => "modal"
      system.onViewChanged()

      expect(system.focusMachine.context).toBe(Context.MODAL)
    })

    test("drawer appearing switches to drawer context", () => {
      const { system, reader } = setup()
      system.start({})

      reader.getPresentation = () => "drawer"
      reader.isDrawerOpen = () => true
      system.onViewChanged()

      expect(system.focusMachine.context).toBe(Context.DRAWER)
    })

    test("modal closing restores to grid and triggers origin focus restore", () => {
      const { system, reader, calls, globals } = setup()
      system.start({})

      // Simulate modal open
      reader.getPresentation = () => "modal"
      system.onViewChanged()
      expect(system.focusMachine.context).toBe(Context.MODAL)

      // Set an origin entity
      system._originEntityId = "origin-123"

      // Simulate modal close
      reader.getPresentation = () => null
      system.onViewChanged()

      expect(system.focusMachine.context).toBe(Context.GRID)
      // Origin focus restore is queued via rAF
      expect(globals._rafCallbacks.length).toBeGreaterThan(0)
    })
  })

  describe("data-captures-keys bypass", () => {
    test("prevents default when target has data-captures-keys ancestor", () => {
      const { system, calls, globals } = setup()
      system.start({})
      calls.length = 0

      const capturer = { closest: (sel) => sel === "[data-captures-keys]" ? capturer : null, tagName: "DIV" }
      const event = globals._dispatchKeyDown("ArrowDown", { target: capturer })

      expect(event.preventDefault).toHaveBeenCalled()
      // No navigation calls should have been made
      const navCalls = calls.filter(c => c.method === "focusByIndex")
      expect(navCalls.length).toBe(0)
    })
  })

  describe("zone cycling", () => {
    test("bracket keys cycle zone tabs", () => {
      const { system, calls, globals } = setup({
        getZoneTabCount: () => 3,
        getActiveZoneTabIndex: () => 0,
      })
      system.start({})
      calls.length = 0

      globals._dispatchKeyDown("]")

      const clickCalls = calls.filter(c => c.method === "clickZoneTab")
      expect(clickCalls.length).toBe(1)
      expect(clickCalls[0].args).toEqual([1])
    })
  })

  describe("page behavior integration", () => {
    test("detects and attaches page behavior from reader", () => {
      const { system, reader } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})

      expect(system._behavior).not.toBe(null)
      expect(system._behaviorName).toBe("library")
    })

    test("no behavior when reader returns null", () => {
      const { system } = setup({
        getPageBehavior: () => null,
      })
      system.start({})

      expect(system._behavior).toBe(null)
    })

    test("escape delegates to page behavior first", () => {
      let escapeCalled = false
      const { system, reader, globals } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})

      // Inject a mock behavior that consumes escape
      system._behavior = {
        onEscape: () => { escapeCalled = true; return true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      const event = globals._dispatchKeyDown("Escape")
      expect(escapeCalled).toBe(true)
      expect(event.preventDefault).toHaveBeenCalled()
    })

    test("escape falls through when behavior does not consume", () => {
      const hookEl = { pushEvent: mock(() => {}) }
      const { system, reader, globals } = setup({
        getPageBehavior: () => "library",
        getPresentation: () => "modal",
      })
      system.start(hookEl)

      // Inject a mock behavior that does NOT consume escape
      system._behavior = {
        onEscape: () => false,
        onSyncState: () => ({ clearGridMemory: false }),
      }

      globals._dispatchKeyDown("Escape")
      // Should fall through to normal handling (dismiss modal)
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })

    test("syncState delegates to behavior for grid memory clear", () => {
      const { system, reader, globals } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})

      system._behavior = {
        onSyncState: () => ({ clearGridMemory: true }),
      }
      system._lastGridEntityId = "should-clear"
      system._contextMemory[Context.GRID] = 5

      system.onViewChanged()

      expect(system._lastGridEntityId).toBe(null)
      expect(system._contextMemory[Context.GRID]).toBeUndefined()
    })

    test("behavior detached on destroy", () => {
      let detached = false
      const { system } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})
      system._behavior = {
        onDetach: () => { detached = true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      system.destroy()
      expect(detached).toBe(true)
    })
  })

  describe("exit sidebar uses forceContext", () => {
    test("exit sidebar restores to pre-sidebar context", () => {
      const { system, reader, calls } = setup({
        getItemCount: (ctx) => ctx === Context.TOOLBAR ? 5 : 8,
        getSidebarCollapsed: () => true,
        getActiveToolbarTabIndex: () => 2,
      })
      system.start({})

      // Set up: currently in sidebar, came from toolbar
      system.focusMachine.forceContext(Context.SIDEBAR)
      system._preSidebarContext = Context.TOOLBAR
      calls.length = 0

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
      const sidebarCalls = calls.filter(c => c.method === "setSidebarState")
      expect(sidebarCalls[0].args).toEqual([true]) // collapsed
    })

    test("exit sidebar stays in sidebar when no content", () => {
      const { system } = setup({
        getItemCount: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext(Context.SIDEBAR)

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe(Context.SIDEBAR)
    })

    test("exit sidebar goes to toolbar when grid is empty", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
        getSidebarCollapsed: () => false,
        getActiveToolbarTabIndex: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext(Context.SIDEBAR)
      system._preSidebarContext = null
      calls.length = 0

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
    })
  })

  describe("empty context safety", () => {
    test("start with empty grid falls back to toolbar in library zone", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
      })
      system.start({})

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
    })

    test("start with empty grid falls back to zone_tabs in watching zone", () => {
      const { system } = setup({
        getZone: () => "watching",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
      })
      system.start({})

      expect(system.focusMachine.context).toBe(Context.ZONE_TABS)
    })

    test("down from toolbar blocked when grid is empty", () => {
      const { system, calls, globals } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
        getFocusedIndex: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext(Context.TOOLBAR)
      calls.length = 0

      globals._dispatchKeyDown("ArrowDown")

      // Should stay in toolbar — no focus calls to grid
      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
      const gridFocusCalls = calls.filter(c =>
        (c.method === "focusFirst" && c.args[0] === Context.GRID) ||
        (c.method === "focusByIndex" && c.args[0] === Context.GRID)
      )
      expect(gridFocusCalls.length).toBe(0)
    })

    test("down from zone_tabs blocked when grid is empty in watching zone", () => {
      const { system, calls, globals } = setup({
        getZone: () => "watching",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
        getFocusedIndex: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext(Context.ZONE_TABS)
      calls.length = 0

      globals._dispatchKeyDown("ArrowDown")

      expect(system.focusMachine.context).toBe(Context.ZONE_TABS)
    })

    test("onViewChanged with newly empty grid falls back", () => {
      const itemCounts = { grid: 8, toolbar: 3, zone_tabs: 2, sidebar: 4 }
      const { system, reader } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => itemCounts[ctx] ?? 0,
      })
      system.start({})
      expect(system.focusMachine.context).toBe(Context.GRID)

      // Simulate grid becoming empty (e.g., filter applied)
      itemCounts.grid = 0
      system.onViewChanged()

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
    })
  })

  describe("left wall enters sidebar from zone tabs/toolbar", () => {
    test("left at index 0 in zone tabs enters sidebar", () => {
      const { system, reader, calls, globals } = setup({
        getFocusedIndex: () => 0,
        getItemCount: () => 3,
        getActiveSidebarIndex: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext(Context.ZONE_TABS)
      calls.length = 0

      // Trigger left navigation from zone tabs
      system._handleAction(Action.NAVIGATE_LEFT)

      expect(system.focusMachine.context).toBe(Context.SIDEBAR)
      expect(system._preSidebarContext).toBe(Context.ZONE_TABS)
    })
  })
})
