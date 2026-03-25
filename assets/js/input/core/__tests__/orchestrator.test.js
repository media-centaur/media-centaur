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
  settings: {
    sections:  { right: ["grid"],            left: ["sidebar"] },
    grid:      { left: ["sections"] },
    sidebar:   { right: ["sections", "grid"] },
  },
}

const TEST_CONFIG = {
  contextSelectors: {
    grid: "[data-nav-zone='grid'] [data-nav-item]",
    toolbar: "[data-nav-zone='toolbar'] [data-nav-item]",
    zone_tabs: "[data-nav-zone='zone-tabs'] [data-nav-item]",
    sidebar: "[data-nav-zone='sidebar'] [data-nav-item]",
    sections: "[data-nav-zone='sections'] [data-nav-item]",
    drawer: "[data-detail-mode='drawer'] [data-nav-item]",
    modal: "[data-detail-mode='modal'] [data-nav-item]",
  },
  instanceTypes: { sidebar: "menu", sections: "menu" },
  primaryMenu: "sidebar",
  layouts: TEST_LAYOUTS,
  cursorStartPriority: {
    watching:  ["grid", "zone_tabs", "sidebar"],
    library:   ["grid", "toolbar", "zone_tabs", "sidebar"],
    settings:  ["sections", "grid", "sidebar"],
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
    getSidebarCollapsed: () => false,
    getPageBehavior: () => null,
    getCurrentFocusedSubItem: () => null,
    getItemAt: () => null,
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
  }
}

/** Mock behavior factory for tests that need behavior detection */
function mockCreateBehavior(name) {
  if (name === "library") {
    return {
      onAttach() {},
      onDetach() {},
      onEscape: () => "sidebar",
      onClear: () => {},
      onSyncState: () => ({ clearGridMemory: false }),
    }
  }
  if (name === "settings") {
    return { onAttach() {}, onDetach() {}, onEscape: () => "sections" }
  }
  if (name === "dashboard" || name === "review") {
    return { onAttach() {}, onDetach() {}, onEscape: () => "sidebar" }
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

      // Create a behavior that returns "sidebar" on escape
      system._behavior = { onEscape: () => "sidebar" }
      system._behaviorName = "test"

      globals._dispatchKeyDown("Escape")

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

    test("escape delegates to page behavior first", () => {
      let escapeCalled = false
      const { system, globals } = setup({
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
      const { system, globals } = setup({
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
        getItemCount: (ctx) => ctx === Context.TOOLBAR ? 5 : 8,
        getSidebarCollapsed: () => true,
        getActiveItemIndex: (ctx) => ctx === Context.TOOLBAR ? 2 : -1,
      })
      system.start({})

      // Set up: currently in sidebar, came from toolbar
      system.focusMachine.forceContext("sidebar")
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
      system.focusMachine.forceContext("sidebar")

      system._executeExitSidebar()

      expect(system.focusMachine.context).toBe("sidebar")
    })

    test("exit sidebar goes to toolbar when grid is empty", () => {
      const { system, calls } = setup({
        getZone: () => "library",
        getItemCount: (ctx) => ctx === "grid" ? 0 : 3,
        getSidebarCollapsed: () => false,
        getActiveItemIndex: (ctx) => ctx === Context.TOOLBAR ? 0 : -1,
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

  describe("BACK action triggers behavior onEscape", () => {
    test("BACK in grid triggers behavior onEscape", () => {
      let escapeCalled = false
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
      // Ensure we're in grid context (not sidebar)
      expect(system.focusMachine.context).toBe(Context.GRID)

      system._behavior = {
        onEscape: () => { escapeCalled = true; return true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      onActionCallback(Action.BACK)
      expect(escapeCalled).toBe(true)
    })

    test("BACK falls through to dismiss when behavior does not consume", () => {
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

      system._behavior = {
        onEscape: () => false,
        onSyncState: () => ({ clearGridMemory: false }),
      }

      onActionCallback(Action.BACK)
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })

    test("BACK navigates to context returned by onEscape string", () => {
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getZone: () => "settings",
        getPageBehavior: () => "settings",
        getItemCount: () => 3,
        getFocusedIndex: () => 0,
        getActiveItemIndex: (ctx) => ctx === "sections" ? 1 : -1,
      }, {
        sources: [
          (callbacks) => {
            onActionCallback = callbacks.onAction
            return mockSource
          },
        ],
      })
      system.start({})
      // Start in grid context
      system.focusMachine.forceContext(Context.GRID)
      calls.length = 0

      onActionCallback(Action.BACK)

      // Should navigate to "sections" (returned by settings onEscape)
      expect(system.focusMachine.context).toBe("sections")
      // Should restore focus in sections
      const focusCalls = calls.filter(c => c.method === "focusByIndex")
      expect(focusCalls.some(c => c.args[0] === "sections")).toBe(true)
    })

    test("BACK to sidebar via onEscape expands sidebar and records pre-sidebar context", () => {
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

      onActionCallback(Action.BACK)

      // Should enter sidebar
      expect(system.focusMachine.context).toBe("sidebar")
      // Should expand sidebar (setSidebarState(false))
      const sidebarCalls = calls.filter(c => c.method === "setSidebarState")
      expect(sidebarCalls.some(c => c.args[0] === false)).toBe(true)
      // Should record pre-sidebar context for exit restoration
      expect(system._preSidebarContext).toBe(Context.GRID)
    })

    test("BACK in non-primary menu bypasses onEscape and follows nav graph", () => {
      let escapeCalled = false
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

      system._behavior = {
        onEscape: () => { escapeCalled = true; return "sections" },
      }
      calls.length = 0

      onActionCallback(Action.BACK)

      // onEscape must NOT be called when in a menu context
      expect(escapeCalled).toBe(false)
      // Should follow nav graph left edge → sidebar
      expect(system.focusMachine.context).toBe("sidebar")
    })

    test("BACK in sidebar bypasses onEscape and exits", () => {
      let escapeCalled = false
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getPageBehavior: () => "library",
        getItemCount: () => 8,
        getSidebarCollapsed: () => true,
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

      system._behavior = {
        onEscape: () => { escapeCalled = true; return true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      onActionCallback(Action.BACK)

      // onEscape must NOT be called when in sidebar
      expect(escapeCalled).toBe(false)
      // Should have exited the sidebar
      expect(system.focusMachine.context).not.toBe("sidebar")
    })

    test("BACK in modal bypasses onEscape and dismisses", () => {
      let escapeCalled = false
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

      system._behavior = {
        onEscape: () => { escapeCalled = true; return true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      onActionCallback(Action.BACK)

      // onEscape must NOT be called when in modal
      expect(escapeCalled).toBe(false)
      // Should dismiss the modal
      expect(hookEl.pushEvent).toHaveBeenCalledWith("close_detail", {})
    })

    test("BACK in drawer bypasses onEscape and dismisses", () => {
      let escapeCalled = false
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

      system._behavior = {
        onEscape: () => { escapeCalled = true; return true },
        onSyncState: () => ({ clearGridMemory: false }),
      }

      onActionCallback(Action.BACK)

      expect(escapeCalled).toBe(false)
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
  })

  describe("SELECT on menu activates and exits", () => {
    test("SELECT on primary menu exits sidebar without clicking (already activated on focus)", () => {
      const clicked = mock(() => {})
      const mockItem = { click: clicked, dataset: {}, hasAttribute: () => false }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 8,
        getSidebarCollapsed: () => true,
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
        dataset: { navAction: "phx:cycle-theme" },
        hasAttribute: (attr) => attr === "data-nav-defer-activate",
        dispatchEvent(event) { dispatchedEvents.push(event) },
      }
      let onActionCallback = null
      const mockSource = { start() {}, stop() {} }
      const { system, calls } = setup({
        getCurrentFocusedItem: () => mockItem,
        getItemCount: () => 8,
        getSidebarCollapsed: () => true,
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

      onActionCallback(Action.SELECT)

      // Should activate (dispatch custom event), not exit sidebar
      expect(system.focusMachine.context).toBe("sidebar")
      expect(dispatchedEvents.length).toBe(1)
      expect(dispatchedEvents[0].type).toBe("phx:cycle-theme")
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
        getItemCount: () => 8,
        getSidebarCollapsed: () => true,
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
        dataset: { navAction: "phx:cycle-theme" },
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
      expect(dispatchedEvents[0].type).toBe("phx:cycle-theme")
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
})
