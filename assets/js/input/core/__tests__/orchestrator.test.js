import { describe, expect, test, beforeEach, mock } from "bun:test"
import { Orchestrator } from "../orchestrator"
import { KeyboardSource } from "../keyboard"
import { Context } from "../focus_context"
import { Action } from "../actions"

// Test config — provides all config the orchestrator needs
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
  home: {
    hero:      { down: ["continue", "recently", "coming_up"], left: ["sidebar"] },
    continue:  { up: ["hero"], down: ["recently", "coming_up"], left: ["sidebar"] },
    recently:  { up: ["continue", "hero"], down: ["coming_up"], left: ["sidebar"] },
    coming_up: { up: ["recently", "continue", "hero"], left: ["sidebar"] },
    sidebar:   { right: ["hero", "continue", "recently", "coming_up"] },
  },
}

const TEST_CONFIG = {
  contextSelectors: {
    grid: "[data-nav-zone='grid'] [data-nav-item]",
    toolbar: "[data-nav-zone='toolbar'] [data-nav-item]",
    zone_tabs: "[data-nav-zone='zone-tabs'] [data-nav-item]",
    sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
    sections: "[data-nav-zone='sections'] [data-nav-item]",
    upcoming: "[data-nav-zone='upcoming'] > [data-nav-item]",
    hero: "[data-nav-zone='hero'] [data-nav-item]",
    continue: "[data-nav-zone='continue'] [data-nav-item]",
    recently: "[data-nav-zone='recently'] [data-nav-item]",
    coming_up: "[data-nav-zone='coming_up'] [data-nav-item]",
    drawer: "[data-detail-mode='drawer'] [data-nav-item]",
    modal: "[data-detail-mode='modal'] [data-nav-item]",
  },
  instanceTypes: {
    sidebar: "menu", sections: "menu", upcoming: "menu",
    hero: "shelf", continue: "shelf", recently: "shelf", coming_up: "shelf",
  },
  primaryMenu: "sidebar",
  layouts: TEST_LAYOUTS,
  cursorStartPriority: {
    watching:  ["grid", "zone_tabs", "sidebar"],
    library:   ["grid", "toolbar", "zone_tabs", "sidebar"],
    upcoming:  ["upcoming", "grid", "zone_tabs", "sidebar"],
    settings:  ["sections", "grid", "sidebar"],
    home:      ["hero", "continue", "recently", "coming_up", "sidebar"],
  },
  alwaysPopulated: ["sidebar", "sections"],
  activeClassNames: ["sidebar-link-active", "tab-active", "zone-tab-active", "menu-item-active"],
}

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
    getActiveItemIndex: () => -1,
    getZoneTabCount: () => 2,
    getEntityIndex: () => -1,
    getPageBehavior: () => null,
    getCurrentFocusedSubItem: () => null,
    getItemAt: () => null,
    hasForeignFocus: () => false,
    // Default geometry: one horizontal row of evenly spaced tiles. Shelf
    // navigation is spatial, so every shelf test needs rects, and a row is the
    // shape every shelf but the Coming Up mosaic actually has.
    getItemRects(context) {
      return rowRects(this.getItemCount(context))
    },
    ...overrides,
  }
}

/** A horizontal row of `n` equally sized tiles — the default shelf shape. */
function rowRects(n) {
  return Array.from({ length: n }, (_, i) => ({ x: i * 100, y: 0, width: 90, height: 60 }))
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
      hidden: false,
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
        stopPropagation: mock(() => {}),
        ...opts,
      }
      for (const fn of (listeners.keydown || [])) {
        fn(event)
      }
      return event
    },
    _dispatchMouseMove(x, y) {
      const event = { clientX: x, clientY: y }
      for (const fn of (listeners.mousemove || [])) {
        fn(event)
      }
      return event
    },
    _dispatchVisibilityChange() {
      for (const fn of (listeners.visibilitychange || [])) {
        fn()
      }
    },
  }
}

/** Mock behavior factory for tests that need behavior detection */
function mockCreateBehavior(name) {
  if (name === "library") {
    return {
      onAttach() {},
      onDetach() {},
      onClear: () => {},
      onSyncState: () => ({ clearGridMemory: false }),
    }
  }
  if (name === "settings" || name === "status" || name === "review") {
    return { onAttach() {}, onDetach() {} }
  }
  // Home (and watch-history) behaviors deliberately omit onAttach/onDetach —
  // the mock must mirror that so start() exercises the optional-hook path.
  if (name === "home") {
    return { onZoneChanged() {} }
  }
  return null
}

/**
 * Default source factory: creates a KeyboardSource wired to the orchestrator.
 * This mirrors the real app wiring — keyboard source driven by globals.document.
 */
function defaultSources() {
  return [
    (callbacks, globals) => new KeyboardSource({ document: globals.document, ...callbacks }),
  ]
}

function setup(readerOverrides = {}, configOverrides = {}) {
  const reader = createMockReader(readerOverrides)
  const { writer, calls } = createMockWriter()
  const globals = createMockGlobals()
  const system = new Orchestrator({
    reader,
    writer,
    globals,
    sources: defaultSources(),
    ...TEST_CONFIG,
    createBehavior: mockCreateBehavior,
    ...configOverrides,
  })
  return { system, reader, writer, calls, globals }
}

describe("Orchestrator", () => {
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
    test("Enter on text input activates edit mode in keyboard source", () => {
      const { system, globals } = setup()
      system.start({})

      const input = { tagName: "INPUT", value: "", closest: () => null }
      const event = globals._dispatchKeyDown("Enter", { target: input })

      expect(event.preventDefault).toHaveBeenCalled()
      // Edit state is now in the keyboard source
      expect(system._sources[0]._inputEditing).toBe(true)
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
      system.focusMachine.forceContext("sidebar")
      system.destroy()

      expect(globals._storage["inputSystem:resumeSidebar"]).toBe("true")
    })

    test("start resumes sidebar context from sessionStorage", () => {
      const { system, calls, globals } = setup({
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 1 : -1,
      })
      globals.sessionStorage.setItem("inputSystem:resumeSidebar", "true")

      system.start({})

      expect(system.focusMachine.context).toBe("sidebar")
      expect(globals.sessionStorage.getItem("inputSystem:resumeSidebar")).toBe(null)

      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.some(c => c.args[0] === "sidebar" && c.args[1] === 1)).toBe(true)
    })

    test("destroy does not persist when not in sidebar", () => {
      const { system, globals } = setup()
      system.start({})
      system.destroy()
      expect(globals._storage["inputSystem:resumeSidebar"]).toBeUndefined()
    })

    test("destroy persists input method to sessionStorage", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, globals } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})
      onInputCallback("gamepadbutton")
      system.destroy()

      expect(globals._storage["inputSystem:inputMethod"]).toBe("gamepad")
    })

    test("start restores input method from sessionStorage", () => {
      const { system, calls, globals } = setup()
      globals.sessionStorage.setItem("inputSystem:inputMethod", "gamepad")

      system.start({})

      expect(system.inputDetector.current).toBe("gamepad")
      expect(globals.sessionStorage.getItem("inputSystem:inputMethod")).toBe(null)

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.some(c => c.args[0] === "gamepad")).toBe(true)
    })

    test("start with sidebar resume writes correct nav context", () => {
      const { system, calls, globals } = setup({
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 1 : -1,
      })
      globals.sessionStorage.setItem("inputSystem:resumeSidebar", "true")
      system.start({})

      // The last setNavContext call should be "sidebar", not "grid"
      const navCalls = calls.filter(c => c.method === "setNavContext")
      expect(navCalls.length).toBeGreaterThan(0)
      expect(navCalls[navCalls.length - 1].args[0]).toBe("sidebar")
    })

    test("gamepad detection during start does not write stale nav context", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls, globals } = setup({
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 1 : -1,
      }, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      globals.sessionStorage.setItem("inputSystem:resumeSidebar", "true")
      system.start({})

      // Simulate gamepad input detected after start (should not write stale "grid")
      onInputCallback("gamepadbutton")

      const navCalls = calls.filter(c => c.method === "setNavContext")
      // No setNavContext("grid") should appear after the final "sidebar"
      const lastSidebarIdx = navCalls.findLastIndex(c => c.args[0] === "sidebar")
      const staleGridAfter = navCalls.slice(lastSidebarIdx + 1).some(c => c.args[0] === "grid")
      expect(staleGridAfter).toBe(false)
    })

    test("context change from action syncs nav context", () => {
      const { system, calls, globals } = setup()
      system.start({})

      // Clear calls from start
      calls.length = 0

      // Left at the grid's left wall (index 0, column 0) enters the sidebar.
      globals._dispatchKeyDown("ArrowLeft")

      const navCalls = calls.filter(c => c.method === "setNavContext")
      expect(navCalls.some(c => c.args[0] === "sidebar")).toBe(true)
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
    test("skips navigation when target has data-captures-keys ancestor", () => {
      const { system, calls, globals } = setup()
      system.start({})
      calls.length = 0

      const capturer = { closest: (sel) => sel === "[data-captures-keys]" ? capturer : null, tagName: "DIV" }
      const event = globals._dispatchKeyDown("ArrowDown", { target: capturer })

      // Does NOT preventDefault — allows normal browser behavior (typing, etc.)
      expect(event.preventDefault).not.toHaveBeenCalled()
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
      const { system } = setup({
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

    test("escape in a content context is a no-op — behaviors get no escape hook", () => {
      let escapeCalled = false
      const { system, calls, globals } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})

      // Even a behavior that still defines onEscape is ignored — left at
      // the left edge is the way to the sidebar, not Escape.
      system._behavior = {
        onEscape: () => { escapeCalled = true; return "sidebar" },
        onSyncState: () => ({ clearGridMemory: false }),
      }
      calls.length = 0

      globals._dispatchKeyDown("Escape")

      expect(escapeCalled).toBe(false)
      expect(system.focusMachine.context).toBe(Context.GRID)
      const navCalls = calls.filter(c => c.method === "setNavContext")
      expect(navCalls.some(c => c.args[0] === "sidebar")).toBe(false)
    })

    test("escape in modal still dismisses", () => {
      const hookEl = { pushEvent: mock(() => {}) }
      const { system, globals } = setup({
        getPageBehavior: () => "library",
        getPresentation: () => "modal",
      })
      system.start(hookEl)

      globals._dispatchKeyDown("Escape")
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })

    test("syncState delegates to behavior for grid memory clear", () => {
      const { system } = setup({
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
      const { system, calls } = setup({
        getItemCount: (ctx) => ctx === Context.TOOLBAR ? 5 : 8,        getActiveItemIndex: (ctx) => ctx === Context.TOOLBAR ? 2 : -1,
      })
      system.start({})

      // Set up: currently in sidebar, came from toolbar
      system.focusMachine.forceContext("sidebar")
      system._preSidebarContext = Context.TOOLBAR
      calls.length = 0

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
      // Rail width is the user's preference — nav never touches it
      const sidebarCalls = calls.filter(c => c.method === "setSidebarState")
      expect(sidebarCalls.length).toBe(0)
    })

    test("exit sidebar stays in sidebar when no content", () => {
      const { system } = setup({
        getItemCount: () => 0,
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe("sidebar")
    })

    test("exit sidebar goes to toolbar when grid is empty", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,        getActiveItemIndex: (ctx) => ctx === Context.TOOLBAR ? 0 : -1,
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")
      system._preSidebarContext = null
      calls.length = 0

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
    })
  })

  describe("empty context safety", () => {
    test("start with empty grid falls back to toolbar in library zone", () => {
      const { system } = setup({
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
      const itemCounts = { grid: 8, toolbar: 3, zone_tabs: 2, sidebar: 4, sections: 0, drawer: 0, modal: 0 }
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
      const { system, calls, globals } = setup({
        getFocusedIndex: () => 0,
        getItemCount: () => 3,
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 0 : -1,
      })
      system.start({})
      system.focusMachine.forceContext(Context.ZONE_TABS)
      calls.length = 0

      // Trigger left navigation from zone tabs
      system._handleAction(Action.NAVIGATE_LEFT)

      expect(system.focusMachine.context).toBe("sidebar")
      expect(system._preSidebarContext).toBe(Context.ZONE_TABS)
    })

    test("left at index 0 in a home shelf enters sidebar", () => {
      const { system } = setup({
        getZone: () => "home",
        getFocusedIndex: () => 0,
        getItemCount: (ctx) => ctx === "sidebar" ? 4 : 3,
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 0 : -1,
      })
      system.start({})
      system.focusMachine.forceContext("continue")

      system._handleAction(Action.NAVIGATE_LEFT)

      expect(system.focusMachine.context).toBe("sidebar")
      expect(system._preSidebarContext).toBe("continue")
    })
  })

  describe("upcoming mini-month (TOOLBAR companion to the rail)", () => {
    // The mini-month is a TOOLBAR instance to the RIGHT of the rail, so up/down
    // and left-wall must follow its OWN graph edges rather than the standard
    // top-left-toolbar assumptions (up→zone_tabs, down→grid, left→sidebar).
    const upcomingConfig = {
      instanceTypes: {
        ...TEST_CONFIG.instanceTypes,
        rail: "menu", stragglers: "menu", actions: "menu", "mini-month": "toolbar",
      },
      contextSelectors: {
        ...TEST_CONFIG.contextSelectors,
        rail: "[data-nav-zone='rail'] [data-nav-item]",
        stragglers: "[data-nav-zone='stragglers'] [data-nav-item]",
        actions: "[data-nav-zone='actions'] [data-nav-item]",
        "mini-month": "[data-nav-zone='mini-month'] [data-nav-item]",
      },
      layouts: {
        ...TEST_LAYOUTS,
        upcoming: {
          actions:      { down: ["rail", "stragglers"], left: ["sidebar"] },
          rail:         { up: ["actions"], down: ["stragglers"], right: ["mini-month"], left: ["sidebar"] },
          stragglers:   { up: ["rail", "actions"], right: ["mini-month"], left: ["sidebar"] },
          "mini-month": { up: ["actions"], down: ["stragglers"], left: ["rail", "stragglers", "sidebar"] },
          sidebar:      { right: ["rail", "stragglers", "mini-month", "actions"] },
        },
      },
      cursorStartPriority: {
        ...TEST_CONFIG.cursorStartPriority,
        upcoming: ["rail", "stragglers", "mini-month", "actions", "sidebar"],
      },
    }

    function inMiniMonth(readerOverrides = {}) {
      const { system, calls, globals } = setup({
        getZone: () => "upcoming",
        getFocusedIndex: () => 0,
        getItemCount: (ctx) => ctx === "sidebar" ? 4 : 2,
        getActiveItemIndex: () => -1,
        ...readerOverrides,
      }, upcomingConfig)
      system.start({})
      system.focusMachine.forceContext("mini-month")
      calls.length = 0
      return { system, calls, globals }
    }

    test("left at the first chevron returns to the rail, not the sidebar", () => {
      const { system } = inMiniMonth()
      system._handleAction(Action.NAVIGATE_LEFT)
      expect(system.focusMachine.context).toBe("rail")
    })

    test("up reaches the actions zone via the instance's own graph edge", () => {
      const { system } = inMiniMonth()
      system._handleAction(Action.NAVIGATE_UP)
      expect(system.focusMachine.context).toBe("actions")
    })

    test("down reaches the stragglers via the instance's own graph edge", () => {
      const { system } = inMiniMonth()
      system._handleAction(Action.NAVIGATE_DOWN)
      expect(system.focusMachine.context).toBe("stragglers")
    })

    test("left falls through to the sidebar when the rail and stragglers are empty", () => {
      const { system } = inMiniMonth({
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : ctx === "mini-month" ? 2 : 0),
      })
      system._handleAction(Action.NAVIGATE_LEFT)
      expect(system.focusMachine.context).toBe("sidebar")
    })
  })

  describe("home shelf navigation", () => {
    function homeShelves(focusedContext) {
      const { system, reader, calls, globals } = setup({
        getZone: () => "home",
        getFocusedIndex: () => 1,
        getItemCount: (ctx) => ctx === "sidebar" ? 4 : 5,
      })
      system.start({})
      system.focusMachine.forceContext(focusedContext)
      calls.length = 0
      return { system, reader, calls, globals }
    }

    test("down moves to the next shelf and focuses it", () => {
      const { system, calls } = homeShelves("continue")

      system._handleAction(Action.NAVIGATE_DOWN)

      expect(system.focusMachine.context).toBe("recently")
      const focusCalls = calls.filter(c =>
        (c.method === "focusFirst" || c.method === "focusByIndex") && c.args[0] === "recently"
      )
      expect(focusCalls.length).toBeGreaterThan(0)
    })

    test("right navigates within the shelf (no context change)", () => {
      const { system, calls } = homeShelves("continue")

      system._handleAction(Action.NAVIGATE_RIGHT)

      expect(system.focusMachine.context).toBe("continue")
      const focusCalls = calls.filter(c => c.method === "focusByIndex" && c.args[0] === "continue")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args[1]).toBe(2) // index 1 → 2
    })

    test("select in a shelf records origin context for modal restore", () => {
      const { system, reader } = homeShelves("continue")
      reader.getCurrentFocusedItem = () => ({
        dataset: { entityId: "abc-123" },
        hasAttribute: () => false,
        click() {},
      })

      system._handleAction(Action.SELECT)

      expect(system._originEntityId).toBe("abc-123")
      expect(system._originContext).toBe("continue")
    })
  })

  // The Coming Up marquee is a mosaic, not a row: one large tile on the left
  // and a stacked column of secondaries on the right. Adjacency is answered by
  // geometry; where the layout has no spatial answer the shelf falls back to
  // its sequence (right/down = next tile), which is what makes RIGHT from the
  // top secondary reach the one below it.
  const MOSAIC_RECTS = [
    { x: 0, y: 0, width: 1040, height: 360 },     // 0 — large tile, full height
    { x: 1056, y: 0, width: 610, height: 175 },   // 1 — top secondary
    { x: 1056, y: 185, width: 610, height: 175 }, // 2 — bottom secondary
  ]

  describe("Coming Up mosaic navigation", () => {
    function mosaic(focusedIndex) {
      const { system, reader, calls, globals } = setup({
        getZone: () => "home",
        getFocusedIndex: () => focusedIndex,
        getItemCount: (ctx) =>
          ctx === "coming_up" ? MOSAIC_RECTS.length : ctx === "sidebar" ? 4 : 5,
        getItemRects: (ctx) => (ctx === "coming_up" ? MOSAIC_RECTS : rowRects(5)),
      })
      system.start({})
      system.focusMachine.forceContext("coming_up")
      calls.length = 0
      return { system, reader, calls, globals }
    }

    /** The index the mosaic focused, or null if it focused nothing. */
    function focusedIndexAfter(calls) {
      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "coming_up"
      )
      return focusCalls.length > 0 ? focusCalls[focusCalls.length - 1].args[1] : null
    }

    test("right from the large tile goes to the TOP secondary, not the nearest by centre", () => {
      // The large tile spans the full height, so both secondaries are equally
      // "in line" with it — the bottom one is even marginally closer by centre
      // distance. Perfectly aligned candidates tie, and ties break by sequence.
      const { system, calls } = mosaic(0)

      system._handleAction(Action.NAVIGATE_RIGHT)

      expect(system.focusMachine.context).toBe("coming_up")
      expect(focusedIndexAfter(calls)).toBe(1)
    })

    test("left from the bottom secondary returns to the large tile", () => {
      const { system, calls } = mosaic(2)

      system._handleAction(Action.NAVIGATE_LEFT)

      expect(system.focusMachine.context).toBe("coming_up")
      expect(focusedIndexAfter(calls)).toBe(0)
    })

    test("up from the bottom secondary goes to the top secondary, not out of the shelf", () => {
      const { system, calls } = mosaic(2)

      system._handleAction(Action.NAVIGATE_UP)

      expect(system.focusMachine.context).toBe("coming_up")
      expect(focusedIndexAfter(calls)).toBe(1)
    })

    test("down from the top secondary goes to the bottom secondary", () => {
      const { system, calls } = mosaic(1)

      system._handleAction(Action.NAVIGATE_DOWN)

      expect(system.focusMachine.context).toBe("coming_up")
      expect(focusedIndexAfter(calls)).toBe(2)
    })

    test("right from the top secondary follows the sequence to the bottom secondary", () => {
      // Nothing is spatially to the right, and the shelf has no right edge in
      // the nav graph — so the sequence answers.
      const { system, calls } = mosaic(1)

      system._handleAction(Action.NAVIGATE_RIGHT)

      expect(system.focusMachine.context).toBe("coming_up")
      expect(focusedIndexAfter(calls)).toBe(2)
    })

    test("up from the large tile leaves the mosaic for the shelf above", () => {
      const { system } = mosaic(0)

      system._handleAction(Action.NAVIGATE_UP)

      expect(system.focusMachine.context).toBe("recently")
    })

    test("up from the top secondary leaves the mosaic for the shelf above", () => {
      const { system } = mosaic(1)

      system._handleAction(Action.NAVIGATE_UP)

      expect(system.focusMachine.context).toBe("recently")
    })

    test("left from the large tile enters the sidebar", () => {
      const { system } = mosaic(0)

      system._handleAction(Action.NAVIGATE_LEFT)

      expect(system.focusMachine.context).toBe("sidebar")
    })
  })

  describe("entering a shelf lands on the edge you crossed", () => {
    function crossInto(fromContext, comingUpMemory) {
      const { system, reader, calls, globals } = setup({
        getZone: () => "home",
        getFocusedIndex: () => 1,
        getItemCount: (ctx) =>
          ctx === "coming_up" ? MOSAIC_RECTS.length : ctx === "sidebar" ? 4 : 5,
        getItemRects: (ctx) => (ctx === "coming_up" ? MOSAIC_RECTS : rowRects(5)),
      })
      system.start({})
      system.focusMachine.forceContext(fromContext)
      if (comingUpMemory != null) system._contextMemory["coming_up"] = comingUpMemory
      calls.length = 0
      return { system, reader, calls, globals }
    }

    test("crossing down into the mosaic never lands on the bottom secondary", () => {
      // The bottom secondary does not touch the mosaic's top edge, so it is not
      // a candidate when you arrive from above — no matter what memory says.
      const { system, calls } = crossInto("recently", 2)

      system._handleAction(Action.NAVIGATE_DOWN)

      expect(system.focusMachine.context).toBe("coming_up")
      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "coming_up"
      )
      expect(focusCalls.length).toBeGreaterThan(0)
      expect(focusCalls[focusCalls.length - 1].args[1]).not.toBe(2)
    })

    test("crossing down into the mosaic keeps memory that IS on the top edge", () => {
      const { system, calls } = crossInto("recently", 1)

      system._handleAction(Action.NAVIGATE_DOWN)

      expect(system.focusMachine.context).toBe("coming_up")
      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "coming_up"
      )
      expect(focusCalls[focusCalls.length - 1].args[1]).toBe(1)
    })

    test("crossing down into a single-row shelf keeps memory (every tile is on the edge)", () => {
      const { system, calls } = crossInto("continue", null)
      system._contextMemory["recently"] = 3

      system._handleAction(Action.NAVIGATE_DOWN)

      expect(system.focusMachine.context).toBe("recently")
      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "recently"
      )
      expect(focusCalls[focusCalls.length - 1].args[1]).toBe(3)
    })
  })

  describe("hero entry anchor", () => {
    test("up from a shelf always lands on the hero's primary action", () => {
      // The hero's whole job is "press play". Nearest-neighbour would pick
      // More info when arriving from a right-ward card, and plain memory would
      // pick whichever CTA was last touched — both wrong.
      const { system, calls } = setup({
        getZone: () => "home",
        getFocusedIndex: () => 4,
        getItemCount: (ctx) => (ctx === "hero" ? 2 : ctx === "sidebar" ? 4 : 5),
      }, { entryAnchors: { hero: 0 } })
      system.start({})
      system.focusMachine.forceContext("continue")
      system._contextMemory["hero"] = 1
      calls.length = 0

      system._handleAction(Action.NAVIGATE_UP)

      expect(system.focusMachine.context).toBe("hero")
      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "hero"
      )
      expect(focusCalls.length).toBeGreaterThan(0)
      expect(focusCalls[focusCalls.length - 1].args[1]).toBe(0)
    })

    test("a post-patch reconcile does not drag focus back to the anchor", () => {
      // The anchor is an ENTRY rule. _reconcileFocus re-asserts focus after a
      // LiveView patch, which is not an entry — yanking More info back to Play
      // on every re-render would make the second CTA unusable.
      const { system, calls } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => (ctx === "hero" ? 2 : ctx === "sidebar" ? 4 : 5),
        getCurrentFocusedItem: () => null,
      }, { entryAnchors: { hero: 0 } })
      system.start({})
      system.focusMachine.forceContext("hero")
      system._contextMemory["hero"] = 1
      calls.length = 0

      system._reconcileFocus()

      const focusCalls = calls.filter(
        c => c.method === "focusByIndex" && c.args[0] === "hero"
      )
      expect(focusCalls.length).toBeGreaterThan(0)
      expect(focusCalls[focusCalls.length - 1].args[1]).toBe(1)
    })
  })

  describe("modal opened from a home shelf restores focus to that shelf", () => {
    test("closing modal restores origin context and focuses the originating card", () => {
      const { system, reader, calls, globals } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => ctx === "sidebar" ? 4 : 5,
      })
      system.start({})

      // Open a modal from the "recently" shelf
      system.focusMachine.forceContext("recently")
      system._originContext = "recently"
      system._originEntityId = "poster-9"
      reader.getPresentation = () => "modal"
      system.onViewChanged()
      expect(system.focusMachine.context).toBe(Context.MODAL)
      calls.length = 0

      // Close the modal
      reader.getPresentation = () => null
      system.onViewChanged()
      globals._flushRAF()

      expect(system.focusMachine.context).toBe("recently")
      const restoreCalls = calls.filter(c => c.method === "focusByEntityId" && c.args[0] === "recently")
      expect(restoreCalls.length).toBeGreaterThan(0)
      expect(restoreCalls[0].args[1]).toBe("poster-9")
    })
  })

  describe("home zone cursor start", () => {
    test("start does not throw when the page behavior has no onAttach hook", () => {
      // Regression: start() called this._behavior?.onAttach() (guarding only
      // the behavior, not the method). A behavior without onAttach (home,
      // watch-history) threw a TypeError that aborted start() before
      // _ensureCursorStart — leaving a grid-less page stuck in empty GRID.
      const { system } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 4,
        getPageBehavior: () => "home",
      })

      expect(() => system.start({})).not.toThrow()
      expect(system.focusMachine.context).toBe("hero")
    })

    test("start lands on hero when grid is empty (home has no grid)", () => {
      const { system } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 4,
      })
      system.start({})

      expect(system.focusMachine.context).toBe("hero")
    })

    test("start skips empty hero to the first populated shelf", () => {
      const { system } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => (ctx === "grid" || ctx === "hero") ? 0 : 4,
      })
      system.start({})

      expect(system.focusMachine.context).toBe("continue")
    })
  })

  describe("source lifecycle", () => {
    test("sources are started when orchestrator starts", () => {
      let started = false
      const mockSource = {
        start() { started = true },
        stop() {},
      }
      const { system } = setup({}, {
        sources: [() => mockSource],
      })
      system.start({})
      expect(started).toBe(true)
    })

    test("sources are stopped when orchestrator is destroyed", () => {
      let stopped = false
      const mockSource = {
        start() {},
        stop() { stopped = true },
      }
      const { system } = setup({}, {
        sources: [() => mockSource],
      })
      system.start({})
      system.destroy()
      expect(stopped).toBe(true)
    })

    test("multiple sources are all started and stopped", () => {
      const lifecycle = []
      const makeSource = (name) => ({
        start() { lifecycle.push(`${name}:start`) },
        stop() { lifecycle.push(`${name}:stop`) },
      })
      const { system } = setup({}, {
        sources: [
          () => makeSource("keyboard"),
          () => makeSource("gamepad"),
        ],
      })
      system.start({})
      system.destroy()
      expect(lifecycle).toEqual([
        "keyboard:start", "gamepad:start",
        "keyboard:stop", "gamepad:stop",
      ])
    })
  })

  describe("source-agnostic action routing", () => {
    test("actions from any source route through _handleAction", () => {
      let onActionCallback = null
      const mockSource = {
        start() {},
        stop() {},
      }
      const { system, calls } = setup({
        getFocusedIndex: () => 0,
        getItemCount: () => 8,
        getGridColumnCount: () => 4,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      calls.length = 0

      // Simulate an action from the source (like a gamepad would produce)
      onActionCallback(Action.NAVIGATE_DOWN)

      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args).toEqual([Context.GRID, 4])
    })

    test("input method updates from source callbacks", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})
      calls.length = 0

      onInputCallback("gamepadbutton")

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.length).toBe(1)
      expect(methodCalls[0].args).toEqual(["gamepad"])
    })
  })

  describe("BACK action semantics", () => {
    test("BACK in grid is a no-op — even a lingering behavior onEscape is ignored", () => {
      let escapeCalled = false
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getPageBehavior: () => "library",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      // Ensure we're in grid context (not sidebar)
      expect(system.focusMachine.context).toBe(Context.GRID)

      system._behavior = {
        onEscape: () => { escapeCalled = true; return "sidebar" },
        onSyncState: () => ({ clearGridMemory: false }),
      }
      calls.length = 0

      onActionCallback(Action.BACK)

      expect(escapeCalled).toBe(false)
      expect(system.focusMachine.context).toBe(Context.GRID)
      const navCalls = calls.filter(c => c.method === "setNavContext")
      expect(navCalls.some(c => c.args[0] === "sidebar")).toBe(false)
    })

    test("LEFT at the grid's left wall enters the sidebar without expanding it and records pre-sidebar context", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "library",
        getPageBehavior: () => "library",
        getItemCount: () => 8,
        getFocusedIndex: () => 0,
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 2 : -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)
      calls.length = 0

      onActionCallback(Action.NAVIGATE_LEFT)

      // Should enter sidebar
      expect(system.focusMachine.context).toBe("sidebar")
      // Rail stays at the user's chosen width — the collapsed rail labels
      // the focused icon via the SidebarTooltip hook instead
      const sidebarCalls = calls.filter(c => c.method === "setSidebarState")
      expect(sidebarCalls.length).toBe(0)
      // Should record pre-sidebar context for exit restoration
      expect(system._preSidebarContext).toBe(Context.GRID)
    })

    test("BACK in non-primary menu is a no-op — left is the way to the sidebar", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "settings",
        getPageBehavior: () => "settings",
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
        getActiveItemIndex: (ctx) => ctx === "sidebar" ? 0 : -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sections")
      calls.length = 0

      onActionCallback(Action.BACK)

      expect(system.focusMachine.context).toBe("sections")

      // Left is what walks toward the main nav
      onActionCallback(Action.NAVIGATE_LEFT)
      expect(system.focusMachine.context).toBe("sidebar")
    })

    test("BACK in sidebar exits", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPageBehavior: () => "library",
        getItemCount: () => 8,      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")

      onActionCallback(Action.BACK)

      // Should have exited the sidebar
      expect(system.focusMachine.context).not.toBe("sidebar")
    })

    test("BACK in modal dismisses", () => {
      let onActionCallback = null
      const hookEl = { pushEvent: mock(() => {}) }
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPageBehavior: () => "library",
        getPresentation: () => "modal",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start(hookEl)

      onActionCallback(Action.BACK)

      // Should dismiss the modal
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })

    test("BACK in modal uses custom dismiss event when getDismissEvent is set", () => {
      let onActionCallback = null
      const hookEl = { pushEvent: mock(() => {}) }
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPresentation: () => "modal",
        getDismissEvent: () => "cancel_stop_tracking",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start(hookEl)

      onActionCallback(Action.BACK)

      expect(hookEl.pushEvent).toHaveBeenCalledWith("cancel_stop_tracking", {})
    })

    test("BACK in drawer dismisses", () => {
      let onActionCallback = null
      const hookEl = { pushEvent: mock(() => {}) }
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPageBehavior: () => "library",
        getPresentation: () => "drawer",
        isDrawerOpen: () => true,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start(hookEl)

      onActionCallback(Action.BACK)

      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })
  })

  describe("CLEAR action delegates to behavior onClear", () => {
    test("CLEAR calls behavior onClear", () => {
      let clearCalled = false
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPageBehavior: () => "library",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})

      system._behavior = {
        onClear: () => { clearCalled = true },
      }

      onActionCallback(Action.CLEAR)
      expect(clearCalled).toBe(true)
    })

    test("CLEAR is a no-op when behavior has no onClear", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({}, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})

      // No behavior — CLEAR should not throw
      system._behavior = null
      onActionCallback(Action.CLEAR)
      // If we get here without error, the test passes
    })

    test("Backspace key fires CLEAR action", () => {
      let clearCalled = false
      const { system, globals } = setup({
        getPageBehavior: () => "library",
      })
      system.start({})

      system._behavior = {
        onClear: () => { clearCalled = true },
      }

      globals._dispatchKeyDown("Backspace")
      expect(clearCalled).toBe(true)
    })

    test("CLEAR transitions focus to the target context when onClear returns a string", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getPageBehavior: () => "library",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})

      // Move focus somewhere other than grid so we can see the transition.
      system.focusMachine.forceContext(Context.TOOLBAR)
      calls.length = 0

      system._behavior = {
        onClear: () => "grid",
      }

      onActionCallback(Action.CLEAR)

      expect(system.focusMachine.context).toBe(Context.GRID)
      const focusCalls = calls.filter((call) =>
        call.method === "focusFirst" || call.method === "focusByIndex"
      )
      expect(focusCalls.length).toBeGreaterThan(0)
    })

    test("CLEAR does not transition when onClear returns falsy", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getPageBehavior: () => "library",
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})

      system.focusMachine.forceContext(Context.TOOLBAR)

      system._behavior = {
        onClear: () => {},
      }

      onActionCallback(Action.CLEAR)

      expect(system.focusMachine.context).toBe(Context.TOOLBAR)
    })
  })

  describe("onAction behavior hook", () => {
    test("onAction returning true consumes the action", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getItemCount: () => 8,
        getCurrentFocusedItem: () => ({ dataset: { sectionType: "calendar" } }),
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system._behavior = {
        onAction: (action, context, focused) => {
          if (focused?.dataset?.sectionType === "calendar") return true
          return false
        },
      }
      calls.length = 0

      onActionCallback(Action.NAVIGATE_LEFT)

      // Action was consumed — no focus changes
      const focusCalls = calls.filter(c => c.method === "focusByIndex" || c.method === "focusFirst")
      expect(focusCalls.length).toBe(0)
    })

    test("onAction returning false lets framework handle it", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getItemCount: () => 8,
        getCurrentFocusedItem: () => ({ dataset: {} }),
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system._behavior = {
        onAction: () => false,
      }
      calls.length = 0

      onActionCallback(Action.NAVIGATE_DOWN)

      // Action was NOT consumed — framework handles it (grid navigate)
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
    })

    test("onAction returning transitionTo changes context and focuses it", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getItemCount: (ctx) => ctx === "upcoming" ? 5 : 8,
        getCurrentFocusedItem: () => ({ dataset: { sectionType: "tracking" } }),
        getFocusedIndex: () => 0,
        getActiveItemIndex: () => -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("upcoming")
      system._behavior = {
        onAction: (action) => {
          if (action === Action.SELECT) return { transitionTo: "GRID" }
          return false
        },
      }
      calls.length = 0

      onActionCallback(Action.SELECT)

      // Should transition to GRID context
      expect(system.focusMachine.context).toBe("GRID")
      // Should attempt to focus the grid
      const focusCalls = calls.filter(c => c.method === "focusFirst")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args).toEqual(["GRID"])
    })

    test("onAction is not called when behavior has no onAction", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getItemCount: () => 8,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system._behavior = {
        // no onAction defined
      }
      calls.length = 0

      onActionCallback(Action.NAVIGATE_DOWN)

      // Should fall through to normal handling
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
    })
  })

  describe("onZoneChanged behavior callback", () => {
    test("onZoneChanged fires when context changes", () => {
      const zoneChanges = []
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getItemCount: (ctx) => ctx === "upcoming" ? 5 : 8,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system._behavior = {
        onZoneChanged: (ctx) => zoneChanges.push(ctx),
        onAction: (action) => {
          if (action === Action.SELECT) return { transitionTo: "GRID" }
          return false
        },
      }

      system.focusMachine.forceContext("upcoming")
      onActionCallback(Action.SELECT)

      // Should have recorded the transitions
      expect(zoneChanges).toContain("upcoming")
      expect(zoneChanges).toContain("GRID")
    })
  })

  describe("MENU up/down wall uses nav graph", () => {
    test("UP at top of non-primary menu transitions to nav graph up neighbor", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "upcoming",
        getItemCount: (ctx) => ctx === "upcoming" ? 5 : 3,
        getFocusedIndex: (ctx) => ctx === "upcoming" ? 0 : -1,
        getActiveItemIndex: () => -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("upcoming")
      calls.length = 0

      onActionCallback(Action.NAVIGATE_UP)

      // Should transition to zone_tabs (upcoming.up in nav graph)
      expect(system.focusMachine.context).toBe("zone_tabs")
    })

    test("DOWN at bottom of non-primary menu is a wall when no down edge", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "upcoming",
        getItemCount: (ctx) => ctx === "upcoming" ? 5 : 3,
        getFocusedIndex: (ctx) => ctx === "upcoming" ? 4 : -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("upcoming")
      calls.length = 0

      onActionCallback(Action.NAVIGATE_DOWN)

      // No down edge for upcoming — should stay in upcoming
      expect(system.focusMachine.context).toBe("upcoming")
    })

    test("UP wall on primary menu (sidebar) does NOT transition via nav graph", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getItemCount: () => 4,
        getFocusedIndex: (ctx) => ctx === "sidebar" ? 0 : -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")
      calls.length = 0

      onActionCallback(Action.NAVIGATE_UP)

      // Primary menu has no up edge — should stay in sidebar
      expect(system.focusMachine.context).toBe("sidebar")
    })
  })

  describe("sub-focus fallback", () => {
    test("RIGHT in modal falls back to linear nav when no sub-item exists", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      // Mock items with no sub-items (querySelector returns null)
      const mockItem = { querySelector: () => null, dataset: {} }
      const { system, calls } = setup({
        getPresentation: () => "modal",
        getItemCount: () => 2,
        getFocusedIndex: () => 0,
        getCurrentFocusedItem: () => mockItem,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("modal")
      calls.length = 0

      onActionCallback(Action.NAVIGATE_RIGHT)

      // Should fall back to linear navigation — focus next item (index 1)
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args).toEqual(["modal", 1])
    })
  })

  describe("SELECT on menu activates and exits", () => {
    test("SELECT on primary menu exits sidebar without clicking (already activated on focus)", () => {
      const clicked = mock(() => {})
      const mockItem = { click: clicked, dataset: {}, hasAttribute: () => false }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 8,      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")
      calls.length = 0

      onActionCallback(Action.SELECT)

      // Primary menu items activate on focus — no redundant click
      expect(clicked).not.toHaveBeenCalled()
      // Should have exited the sidebar (same as pressing RIGHT)
      expect(system.focusMachine.context).not.toBe("sidebar")
    })

    test("SELECT on primary menu with data-nav-defer-activate activates instead of exiting", () => {
      const dispatchedEvents = []
      const mockItem = {
        click: mock(() => {}),
        dataset: { navAction: "phx:nav-action" },
        hasAttribute: (attr) => attr === "data-nav-defer-activate",
        dispatchEvent(event) { dispatchedEvents.push(event) },
      }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 8,      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")
      calls.length = 0

      onActionCallback(Action.SELECT)

      // Should activate (dispatch custom event), not exit sidebar
      expect(system.focusMachine.context).toBe("sidebar")
      expect(dispatchedEvents.length).toBe(1)
      expect(dispatchedEvents[0].type).toBe("phx:nav-action")
      expect(mockItem.click).not.toHaveBeenCalled()
    })

    test("SELECT on primary menu with data-nav-defer-activate clicks when no nav-action", () => {
      const clickMock = mock(() => {})
      const mockItem = {
        click: clickMock,
        dataset: {},
        hasAttribute: (attr) => attr === "data-nav-defer-activate",
        dispatchEvent() {},
      }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 8,      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sidebar")
      calls.length = 0

      onActionCallback(Action.SELECT)

      // Should click (no nav-action to dispatch) and stay in sidebar
      expect(system.focusMachine.context).toBe("sidebar")
      expect(clickMock).toHaveBeenCalled()
    })

    test("SELECT on non-primary menu with data-nav-defer-activate still exits", () => {
      const clickMock = mock(() => {})
      const mockItem = {
        click: clickMock,
        dataset: {},
        hasAttribute: (attr) => attr === "data-nav-defer-activate",
        dispatchEvent() {},
      }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "settings",
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sections")
      calls.length = 0

      onActionCallback(Action.SELECT)

      // Non-primary menus always exit — defer-activate is primary-menu-only
      expect(system.focusMachine.context).not.toBe("sections")
      expect(clickMock).toHaveBeenCalled()
    })

    test("SELECT on non-primary menu clicks item and moves to right neighbor", () => {
      const clicked = mock(() => {})
      const mockItem = { click: clicked, dataset: {}, hasAttribute: () => false }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "settings",
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      system.focusMachine.forceContext("sections")
      calls.length = 0

      onActionCallback(Action.SELECT)

      expect(clicked).toHaveBeenCalled()
      // Should move to the right neighbor (grid, per settings layout)
      expect(system.focusMachine.context).toBe(Context.GRID)
    })

    test("SELECT on grid still activates without exit behavior", () => {
      const clicked = mock(() => {})
      const mockItem = { click: clicked, dataset: {} }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system } = setup({
        getCurrentFocusedItem: () => mockItem,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      expect(system.focusMachine.context).toBe(Context.GRID)

      onActionCallback(Action.SELECT)

      expect(clicked).toHaveBeenCalled()
      // Should stay in grid — no menu exit behavior
      expect(system.focusMachine.context).toBe(Context.GRID)
    })
  })

  describe("expected presentation guards dismiss focus restoration", () => {
    test("_ensureCursorStart is a no-op when _expectedPresentation is set", () => {
      const { system } = setup({
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
        getZone: () => "library",
      })
      system.start({})
      // Would normally fall back to toolbar since grid is empty
      system.focusMachine.forceContext(Context.GRID)
      system._expectedPresentation = null

      system._ensureCursorStart()

      // Guard prevented the fallback — still in GRID
      expect(system.focusMachine.context).toBe(Context.GRID)
    })

    test("_syncState skips presentation re-entry when _expectedPresentation is set", () => {
      const { system, reader } = setup({
        getPresentation: () => "modal",
      })
      system.start({})
      // Modal detected on start — context is now MODAL
      expect(system.focusMachine.context).toBe(Context.MODAL)

      // Dismiss sets expected presentation and restores to GRID
      system.focusMachine.presentationChanged(null)
      system._expectedPresentation = null

      // DOM still shows modal (LiveView hasn't round-tripped)
      system.onViewChanged()

      // Should NOT re-enter MODAL — expected presentation guards it
      expect(system.focusMachine.context).toBe(Context.GRID)
    })

    test("_expectedPresentation clears when DOM confirms expected state", () => {
      const { system, reader } = setup({
        getPresentation: () => "modal",
      })
      system.start({})

      // Simulate dismiss
      system.focusMachine.presentationChanged(null)
      system._expectedPresentation = null

      // DOM now confirms no presentation
      reader.getPresentation = () => null
      system.onViewChanged()

      expect(system._expectedPresentation).toBe(undefined)
    })

    test("full dismiss → onViewChanged with empty grid stays in GRID context", () => {
      const hookEl = { pushEvent: mock(() => {}) }
      const itemCounts = { grid: 8, toolbar: 3, zone_tabs: 2, sidebar: 4, sections: 0, drawer: 0, modal: 3 }
      let presentation = null
      const { system, reader, globals } = setup({
        getZone: () => "watching",
        getPresentation: () => presentation,
        getItemCount: (ctx) => itemCounts[ctx] ?? 0,
      })
      system.start(hookEl)

      // Open modal
      presentation = "modal"
      system.onViewChanged()
      expect(system.focusMachine.context).toBe(Context.MODAL)

      // Dismiss via Escape
      globals._dispatchKeyDown("Escape")
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
      expect(system.focusMachine.context).toBe(Context.GRID)

      // LiveView round-trip: DOM still shows modal, grid transiently empty
      itemCounts.grid = 0
      system.onViewChanged()

      // Must stay in GRID — _expectedPresentation guards both _syncState and _ensureCursorStart
      expect(system.focusMachine.context).toBe(Context.GRID)

      // DOM catches up: modal gone, grid repopulated
      presentation = null
      itemCounts.grid = 8
      system.onViewChanged()

      // _expectedPresentation cleared, back to normal
      expect(system._expectedPresentation).toBe(undefined)
      expect(system.focusMachine.context).toBe(Context.GRID)
    })
  })

  describe("keyboard stopPropagation prevents dual Escape", () => {
    test("keyboard source calls stopPropagation on handled keys", () => {
      const { system, globals } = setup()
      system.start({})

      const stopPropagation = mock(() => {})
      const event = globals._dispatchKeyDown("Escape", { stopPropagation })

      expect(stopPropagation).toHaveBeenCalled()
    })

    test("keyboard source does not call stopPropagation for unhandled keys", () => {
      const { system, globals } = setup()
      system.start({})

      const stopPropagation = mock(() => {})
      // F5 is not mapped to any action
      globals._dispatchKeyDown("F5", { stopPropagation })

      expect(stopPropagation).not.toHaveBeenCalled()
    })
  })

  describe("mouse position tracking", () => {
    test("first mousemove only primes position, does not switch method", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls, globals } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})

      // Switch to gamepad
      onInputCallback("gamepadbutton")
      calls.length = 0

      // First mousemove — should only prime, not switch
      globals._dispatchMouseMove(100, 200)

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.length).toBe(0)
    })

    test("mousemove at same position does not switch to mouse", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls, globals } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})

      // Prime mouse position, then switch to gamepad
      globals._dispatchMouseMove(100, 200)
      onInputCallback("gamepadbutton")
      calls.length = 0

      // Mousemove at same position (layout shift) — should not switch
      globals._dispatchMouseMove(100, 200)

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.length).toBe(0)
    })

    test("mousemove at new position switches to mouse", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls, globals } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})

      // Switch to gamepad
      onInputCallback("gamepadbutton")
      calls.length = 0

      // Prime position, then move
      globals._dispatchMouseMove(100, 200)
      globals._dispatchMouseMove(105, 200)

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.length).toBe(1)
      expect(methodCalls[0].args).toEqual(["mouse"])
    })

    test("data-nav-defer-activate skips auto-click on navigate in primary menu", () => {
      const clickMock = mock(() => {})
      const items = [
        { dataset: {}, focus() {}, click: mock(() => {}), hasAttribute: () => false },
        { dataset: {}, focus() {}, click: clickMock, hasAttribute: (attr) => attr === "data-nav-defer-activate" },
      ]
      let focusIndex = 0
      const { system, calls, globals } = setup({
        getItemCount: (ctx) => ctx === "sidebar" ? 2 : 8,
        getFocusedIndex: (ctx) => ctx === "sidebar" ? focusIndex : 0,
        getCurrentFocusedItem: () => items[focusIndex],
        getActiveItemIndex: () => 0,
      })
      system.start({})
      calls.length = 0

      // Enter sidebar
      globals._dispatchKeyDown("Escape")
      globals._flushRAF()
      calls.length = 0

      // Navigate down to the defer-activate item
      focusIndex = 0
      globals._dispatchKeyDown("ArrowDown")
      focusIndex = 1
      globals._flushRAF()

      // The item should NOT have been clicked
      expect(clickMock).not.toHaveBeenCalled()
    })

    test("data-nav-action dispatches custom event on SELECT instead of click", () => {
      const clickMock = mock(() => {})
      const dispatchedEvents = []
      const focusedItem = {
        dataset: { navAction: "phx:nav-action" },
        click: clickMock,
        hasAttribute: () => false,
        dispatchEvent(event) { dispatchedEvents.push(event) },
      }
      const { system, calls, globals } = setup({
        getCurrentFocusedItem: () => focusedItem,
        getFocusedIndex: () => 0,
        getItemCount: () => 8,
      })
      system.start({})
      calls.length = 0

      // Press Enter (SELECT) — should dispatch custom event, not click
      globals._dispatchKeyDown("Enter")

      expect(clickMock).not.toHaveBeenCalled()
      expect(dispatchedEvents.length).toBe(1)
      expect(dispatchedEvents[0].type).toBe("phx:nav-action")
      expect(dispatchedEvents[0].bubbles).toBe(true)
    })

    test("SELECT without data-nav-action still calls click", () => {
      const clickMock = mock(() => {})
      const focusedItem = {
        dataset: {},
        click: clickMock,
        hasAttribute: () => false,
        dispatchEvent: mock(() => {}),
      }
      const { system, calls, globals } = setup({
        getCurrentFocusedItem: () => focusedItem,
        getFocusedIndex: () => 0,
        getItemCount: () => 8,
      })
      system.start({})
      calls.length = 0

      globals._dispatchKeyDown("Enter")

      expect(clickMock).toHaveBeenCalledTimes(1)
    })

    test("layout shift mousemove after LiveView patch is ignored", () => {
      let onInputCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls, globals } = setup({}, {
        sources: [
          (callbacks) => {
            onInputCallback = callbacks.onInputDetected
            return mockSource
          },
        ],
      })
      system.start({})

      // Switch to gamepad, prime mouse position
      onInputCallback("gamepadbutton")
      globals._dispatchMouseMove(100, 200)
      calls.length = 0

      // LiveView patch triggers view update + layout shift mousemove
      system.onViewChanged()
      globals._dispatchMouseMove(100, 200) // same position

      const methodCalls = calls.filter(c => c.method === "setInputMethod")
      expect(methodCalls.length).toBe(0)
    })
  })

  describe("Sub-focus", () => {
    test("RIGHT in modal with sub-item focuses the sub-item element", () => {
      const subItemFocus = mock(() => {})
      const subItem = {
        focus: subItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
      }
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? subItem : null
        },
      }

      const { system, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => parentRow,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      })
      system.start({})

      globals._dispatchKeyDown("ArrowRight")

      expect(subItemFocus).toHaveBeenCalled()
      expect(system._subFocusIndex).toBe(0)
    })

    test("RIGHT in modal without sub-item is noop and clears subFocus", () => {
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector() { return null },
      }

      const { system, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => parentRow,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      })
      system.start({})

      globals._dispatchKeyDown("ArrowRight")

      expect(system.focusMachine.subFocus).toBe(false)
      expect(system._subFocusIndex).toBeNull()
    })

    test("LEFT in sub-focus refocuses the parent row via writer", () => {
      const subItemFocus = mock(() => {})
      const subItem = {
        focus: subItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
      }
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? subItem : null
        },
      }

      const { system, calls, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => parentRow,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      })
      system.start({})

      // Enter sub-focus
      globals._dispatchKeyDown("ArrowRight")
      expect(system._subFocusIndex).toBe(0)
      calls.length = 0

      // Exit sub-focus
      globals._dispatchKeyDown("ArrowLeft")
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(1)
      expect(focusCalls[0].args).toEqual(["modal", 0])
      expect(system._subFocusIndex).toBeNull()
    })

    test("UP/DOWN in sub-focus navigates to adjacent row", () => {
      const subItemFocus = mock(() => {})
      const subItem = {
        focus: subItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
      }
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? subItem : null
        },
      }

      const { system, calls, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => parentRow,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      })
      system.start({})

      // Enter sub-focus
      globals._dispatchKeyDown("ArrowRight")
      calls.length = 0

      // DOWN exits sub-focus and navigates
      globals._dispatchKeyDown("ArrowDown")

      // Writer refocuses parent by index first, then navigates to next row
      expect(system._subFocusIndex).toBeNull()
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.length).toBe(2) // restore parent + navigate
      expect(focusCalls[0].args).toEqual(["modal", 0]) // restore parent
      expect(focusCalls[1].args[1]).toBe(1) // next index
    })

    test("SELECT in sub-focus clicks the sub-item", () => {
      const subItemClick = mock(() => {})
      const subItemFocus = mock(() => {})
      const subItem = {
        click: subItemClick,
        focus: subItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
        dataset: {},
      }
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? subItem : null
        },
      }

      // After entering sub-focus, getCurrentFocusedItem returns null
      // (sub-item has no data-nav-item), and getCurrentFocusedSubItem returns the sub-item
      let inSubFocus = false
      const { system, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => inSubFocus ? null : parentRow,
        getCurrentFocusedSubItem: () => inSubFocus ? subItem : null,
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
      })
      system.start({})

      // Enter sub-focus
      globals._dispatchKeyDown("ArrowRight")
      inSubFocus = true

      // SELECT activates the sub-item
      globals._dispatchKeyDown("Enter")
      expect(subItemClick).toHaveBeenCalled()
    })

    test("onViewChanged re-acquires sub-focus after morphdom patch", () => {
      const subItemFocus = mock(() => {})
      const subItem = {
        focus: subItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
      }
      const parentRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? subItem : null
        },
      }

      // After morphdom, getItemAt returns a fresh row with a fresh sub-item
      const freshSubItemFocus = mock(() => {})
      const freshSubItem = {
        focus: freshSubItemFocus,
        hasAttribute(attr) { return attr === "data-nav-sub-item" },
      }
      const freshRow = {
        hasAttribute(attr) { return attr === "data-nav-item" },
        dataset: {},
        querySelector(sel) {
          return sel === "[data-nav-sub-item]" ? freshSubItem : null
        },
      }

      const { system, globals } = setup({
        getPresentation: () => "modal",
        getCurrentFocusedItem: () => parentRow,
        getItemCount: () => 3,
        getFocusedIndex: () => 1,
        getItemAt: (context, index) => index === 1 ? freshRow : null,
      })
      system.start({})

      // Enter sub-focus on row at index 1
      globals._dispatchKeyDown("ArrowRight")
      expect(system._subFocusIndex).toBe(1)

      // Simulate LiveView patch
      system.onViewChanged()

      // Should have re-acquired: sub-item refocused from fresh DOM
      expect(system._subFocusIndex).toBe(1)
      expect(freshSubItemFocus).toHaveBeenCalled()
    })
  })

  describe("visibility change", () => {
    test("visibilitychange listener registered on start", () => {
      const reader = createMockReader()
      const { writer } = createMockWriter()
      const globals = createMockGlobals()

      const system = new Orchestrator({ ...TEST_CONFIG, reader, writer, globals })
      system.start({})

      expect(globals._listeners.visibilitychange?.length).toBe(1)
    })

    test("visibilitychange listener removed on destroy", () => {
      const reader = createMockReader()
      const { writer } = createMockWriter()
      const globals = createMockGlobals()

      const system = new Orchestrator({ ...TEST_CONFIG, reader, writer, globals })
      system.start({})
      system.destroy()

      expect(globals._listeners.visibilitychange?.length ?? 0).toBe(0)
    })

    test("sources are paused when document becomes hidden", () => {
      const reader = createMockReader()
      const { writer } = createMockWriter()
      const globals = createMockGlobals()

      const pauseCalls = []
      const mockSource = {
        start() {},
        stop() {},
        pause() { pauseCalls.push("paused") },
        resume() {},
      }

      const system = new Orchestrator({
        ...TEST_CONFIG,
        reader,
        writer,
        globals,
        sources: [() => mockSource],
      })
      system.start({})

      globals.document.hidden = true
      globals._dispatchVisibilityChange()

      expect(pauseCalls).toEqual(["paused"])
    })

    test("sources are resumed when document becomes visible", () => {
      const reader = createMockReader()
      const { writer } = createMockWriter()
      const globals = createMockGlobals()

      const resumeCalls = []
      const mockSource = {
        start() {},
        stop() {},
        pause() {},
        resume() { resumeCalls.push("resumed") },
      }

      const system = new Orchestrator({
        ...TEST_CONFIG,
        reader,
        writer,
        globals,
        sources: [() => mockSource],
      })
      system.start({})

      globals.document.hidden = false
      globals._dispatchVisibilityChange()

      expect(resumeCalls).toEqual(["resumed"])
    })

    test("sources without pause/resume are not affected", () => {
      const reader = createMockReader()
      const { writer } = createMockWriter()
      const globals = createMockGlobals()

      const minimalSource = {
        start() {},
        stop() {},
      }

      const system = new Orchestrator({
        ...TEST_CONFIG,
        reader,
        writer,
        globals,
        sources: [() => minimalSource],
      })
      system.start({})

      // Should not throw
      globals.document.hidden = true
      globals._dispatchVisibilityChange()
      globals.document.hidden = false
      globals._dispatchVisibilityChange()
    })

    test("keyboard actions suppressed while document is hidden", () => {
      const reader = createMockReader({ getItemCount: () => 8 })
      const { writer, calls } = createMockWriter()
      const globals = createMockGlobals()

      const system = new Orchestrator({
        ...TEST_CONFIG,
        reader,
        writer,
        globals,
        sources: [(callbacks, g) => new KeyboardSource({
          document: g.document,
          onAction: callbacks.onAction,
          onInputDetected: callbacks.onInputDetected,
        })],
      })
      system.start({})

      // Hide document — keyboard listener should be removed
      globals.document.hidden = true
      globals._dispatchVisibilityChange()

      // Key events should not produce actions
      const focusCallsBefore = calls.filter(c => c.method === "focusByIndex").length
      globals._dispatchKeyDown("ArrowDown")
      const focusCallsAfter = calls.filter(c => c.method === "focusByIndex").length
      expect(focusCallsAfter).toBe(focusCallsBefore)
    })
  })

  describe("grid focus survives dynamic library updates", () => {
    // Regression: a library mutation (e.g. a completed download) makes
    // LibraryLive call `stream(:grid, …, reset: true)`, which re-renders the
    // whole grid and drops focus to <body>. The orchestrator must re-grab the
    // focused card after the patch instead of leaving focus lost — otherwise
    // the next arrow press falls back to focusFirst (index 0) and a left press
    // from there exits to the sidebar.
    test("restores grid focus to the remembered card after a stream-reset patch", () => {
      const card = { dataset: { entityId: "entity-3" }, hasAttribute: () => false, click() {} }
      let focusLost = false
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 5),
        getGridColumnCount: () => 7,
        getCurrentFocusedItem: () => (focusLost ? null : card),
        getFocusedIndex: () => (focusLost ? -1 : 3),
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)

      // User is on a grid card; navigating records it as the grid focus memory.
      system._handleAction(Action.NAVIGATE_LEFT)

      // The stream reset re-rendered the grid: the focused card is gone and
      // focus has fallen to <body>.
      focusLost = true
      calls.length = 0
      system.onViewChanged()

      const restore = calls.filter(
        c => c.method === "focusByEntityId" && c.args[0] === Context.GRID,
      )
      expect(restore.length).toBe(1)
      expect(restore[0].args[1]).toBe("entity-3")
    })

    test("snapshots focus before the patch so the idle case restores the exact card", () => {
      const card = { dataset: { entityId: "entity-7" }, hasAttribute: () => false }
      let focusLost = false
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 9),
        getGridColumnCount: () => 7,
        getCurrentFocusedItem: () => (focusLost ? null : card),
        getFocusedIndex: () => (focusLost ? -1 : 6),
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)

      // User is idle on a card (no navigation since landing on it). The hook's
      // beforeUpdate fires right before morphdom patches the DOM.
      system.onBeforeViewChange()

      focusLost = true
      calls.length = 0
      system.onViewChanged()

      const restore = calls.filter(
        c => c.method === "focusByEntityId" && c.args[0] === Context.GRID,
      )
      expect(restore.length).toBe(1)
      expect(restore[0].args[1]).toBe("entity-7")
    })

    test("does not touch focus on a patch that preserves the focused card", () => {
      const card = { dataset: { entityId: "entity-2" }, hasAttribute: () => false, click() {} }
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 5),
        getGridColumnCount: () => 7,
        getCurrentFocusedItem: () => card,
        getFocusedIndex: () => 2,
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)
      system._handleAction(Action.NAVIGATE_LEFT)

      calls.length = 0
      system.onViewChanged()

      // Focus never left the card, so the orchestrator must not re-focus it.
      const refocus = calls.filter(
        c => c.method === "focusByEntityId" || c.method === "focusFirst" || c.method === "focusByIndex",
      )
      expect(refocus.length).toBe(0)
    })
  })

  describe("focus reconciliation generalizes across content/menu contexts", () => {
    // The grid was the reported case, but any content/menu context can lose its
    // focused element to a LiveView patch (a streamed home shelf reload, a
    // re-rendered toolbar). One reconciler covers them all, keyed on the
    // context's own identity (entity id for content, saved index for the rest).
    test("restores a home shelf's focus after a patch re-renders the row", () => {
      const card = { dataset: { entityId: "rec-2" }, hasAttribute: () => false }
      let focusLost = false
      const { system, calls } = setup({
        getZone: () => "home",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 6),
        getCurrentFocusedItem: () => (focusLost ? null : card),
        getFocusedIndex: () => (focusLost ? -1 : 2),
      })
      system.start({})
      system.focusMachine.forceContext("recently")

      // Snapshot focus, then a patch drops it.
      system.onBeforeViewChange()
      focusLost = true
      calls.length = 0
      system.onViewChanged()

      const restore = calls.filter(
        c => (c.method === "focusByIndex" || c.method === "focusFirst") && c.args[0] === "recently",
      )
      expect(restore.length).toBeGreaterThan(0)
    })

    test("restores toolbar focus after a patch drops it", () => {
      const item = { dataset: {}, hasAttribute: () => false }
      let focusLost = false
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 3),
        getCurrentFocusedItem: () => (focusLost ? null : item),
        getFocusedIndex: () => (focusLost ? -1 : 1),
      })
      system.start({})
      system.focusMachine.forceContext(Context.TOOLBAR)

      system.onBeforeViewChange()
      focusLost = true
      calls.length = 0
      system.onViewChanged()

      const restore = calls.filter(
        c => (c.method === "focusByIndex" || c.method === "focusFirst") && c.args[0] === Context.TOOLBAR,
      )
      expect(restore.length).toBeGreaterThan(0)
    })
  })

  describe("focus reconciler yields to focus it does not own", () => {
    // The reconciler re-asserts the focus the system OWNS after a patch. When
    // focus lives on an element outside every managed nav context — an
    // unmanaged overlay's input, button, or card (the Track-new-release modal
    // is a plain data-state overlay, invisible to the input system) — the
    // system does not own that focus and must cede: re-asserting nav focus
    // there yanks focus onto a page row mid-interaction, 1–2s after the user
    // clicked into the overlay. `hasForeignFocus()` is the signal. It is the
    // containment generalization of "is the user typing", so it protects the
    // overlay's non-editable controls too, not just its text field. See
    // ADR-053.
    test("reconciler does not restore content focus while foreign focus is active", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 5),
        getGridColumnCount: () => 7,
        // Focus is on an element outside all managed contexts, so the reader
        // reports no current nav item — same shape as focus-fell-to-body.
        getCurrentFocusedItem: () => null,
        hasForeignFocus: () => true,
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)

      calls.length = 0
      system.onViewChanged()

      const steal = calls.filter(
        c => c.method === "focusByEntityId" || c.method === "focusFirst" || c.method === "focusByIndex",
      )
      expect(steal.length).toBe(0)
    })

    test("cursor-start seeding does not steal foreign focus on an empty context", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        // Current context (grid) is empty, so cursor-start would normally seed
        // focus into the toolbar — but foreign focus is active, so it must not.
        getItemCount: (ctx) => (ctx === "grid" ? 0 : 3),
        getCurrentFocusedItem: () => null,
        hasForeignFocus: () => true,
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)

      calls.length = 0
      system.onViewChanged()

      const steal = calls.filter(
        c => c.method === "focusByEntityId" || c.method === "focusFirst" || c.method === "focusByIndex",
      )
      expect(steal.length).toBe(0)
    })

    test("still restores when focus genuinely dropped to body (not foreign)", () => {
      // The complement: getCurrentFocusedItem() is null because a patch dropped
      // focus to <body>, NOT because focus moved to a foreign element. The
      // system OWNS this — it must restore, exactly as before the guard existed.
      // This pins that the guard does not over-broaden into normal nav.
      const card = { dataset: { entityId: "entity-4" }, hasAttribute: () => false, click() {} }
      let focusLost = false
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => (ctx === "sidebar" ? 4 : 5),
        getGridColumnCount: () => 7,
        getCurrentFocusedItem: () => (focusLost ? null : card),
        getFocusedIndex: () => (focusLost ? -1 : 3),
        hasForeignFocus: () => false,
      })
      system.start({})
      system.focusMachine.forceContext(Context.GRID)
      system._handleAction(Action.NAVIGATE_LEFT)

      focusLost = true
      calls.length = 0
      system.onViewChanged()

      const restore = calls.filter(
        c => c.method === "focusByEntityId" && c.args[0] === Context.GRID,
      )
      expect(restore.length).toBe(1)
      expect(restore[0].args[1]).toBe("entity-4")
    })
  })
})
