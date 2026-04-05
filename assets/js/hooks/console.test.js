import { describe, expect, test, beforeEach, mock } from "bun:test"
import { Console } from "./console"

// ---------------------------------------------------------------------------
// Global environment setup
//
// Bun 1.3.11 has no built-in DOM environment, so we polyfill the minimal
// browser globals the hook uses. This follows the same plain-object mock
// pattern as the existing input system tests in this project.
// ---------------------------------------------------------------------------

// Make `window` available as globalThis.
if (typeof window === "undefined") {
  globalThis.window = globalThis
}

// Minimal MutationObserver stub.
// Instances register themselves in `stubObservers` so tests can fire the
// callback imperatively via `instance.fire()`.
const stubObservers = []

class StubMutationObserver {
  constructor(callback) {
    this._callback = callback
    this._observing = false
    stubObservers.push(this)
  }
  observe(_target, _options) {
    this._observing = true
  }
  disconnect() {
    this._observing = false
  }
  fire() {
    this._callback([])
  }
}
if (typeof MutationObserver === "undefined") {
  globalThis.MutationObserver = StubMutationObserver
}

// requestAnimationFrame shim — calls synchronously for test determinism.
if (typeof requestAnimationFrame === "undefined") {
  globalThis.requestAnimationFrame = (callback) => callback(0)
}

// Minimal document.activeElement — returns null by default.
if (typeof document === "undefined") {
  globalThis.document = { activeElement: null }
}

// ---------------------------------------------------------------------------
// Event-listener tracking
//
// We replace window.addEventListener/removeEventListener so tests can
// dispatch events imperatively.
// ---------------------------------------------------------------------------

const windowListeners = {}

window.addEventListener = (event, handler, _opts) => {
  if (!windowListeners[event]) windowListeners[event] = []
  windowListeners[event].push(handler)
}

window.removeEventListener = (event, handler) => {
  if (windowListeners[event]) {
    windowListeners[event] = windowListeners[event].filter((h) => h !== handler)
  }
}

function dispatchWindowEvent(eventName) {
  const handlers = windowListeners[eventName] || []
  handlers.forEach((handler) => handler({ type: eventName }))
}

// ---------------------------------------------------------------------------
// DOM mock constructors
// ---------------------------------------------------------------------------

function buildEntry(_id, message) {
  return {
    dataset: { message: message.toLowerCase() },
    style: {},
  }
}

function buildEntriesContainer(entries = []) {
  return {
    _entries: entries,
    scrollTop: 0,
    querySelectorAll(_selector) {
      return this._entries
    },
  }
}

function buildSearchInput(value = "") {
  const input = {
    value,
    _blurred: false,
    _focused: false,
    _listeners: {},
    blur() { this._blurred = true },
    focus() {
      this._focused = true
      document.activeElement = this
    },
    addEventListener(event, handler) {
      this._listeners[event] = handler
    },
    removeEventListener(event, handler) {
      if (this._listeners[event] === handler) {
        delete this._listeners[event]
      }
    },
    dispatchInput() {
      this._listeners["input"]?.()
    },
  }
  return input
}

function buildPanel() {
  return {
    _attrs: {},
    _children: [],
    setAttribute(name, value) { this._attrs[name] = value },
    removeAttribute(name) { delete this._attrs[name] },
    getAttribute(name) { return this._attrs[name] ?? null },
    hasAttribute(name) { return name in this._attrs },
    contains(node) {
      return this._children.includes(node)
    },
  }
}

function buildRoot(panel, searchInput, entriesContainer) {
  const root = {
    _attrs: { "data-state": "closed" },
    _eventListeners: {},
    panel,
    searchInput,
    entriesContainer,

    setAttribute(name, value) { this._attrs[name] = value },
    removeAttribute(name) { delete this._attrs[name] },
    getAttribute(name) { return this._attrs[name] ?? null },
    get dataset() {
      return { state: this._attrs["data-state"] }
    },

    querySelector(selector) {
      if (selector === ".console-panel") return panel
      if (selector === "[data-console-search]") return searchInput
      if (selector === "#console-entries") return entriesContainer
      return null
    },

    addEventListener(event, handler) {
      if (!this._eventListeners[event]) this._eventListeners[event] = []
      this._eventListeners[event].push(handler)
    },

    removeEventListener(event, handler) {
      if (this._eventListeners[event]) {
        this._eventListeners[event] = this._eventListeners[event].filter(
          (h) => h !== handler,
        )
      }
    },

    _dispatchKeyDown(key, opts = {}) {
      const event = {
        type: "keydown",
        key,
        preventDefault: mock(() => {}),
        stopPropagation: mock(() => {}),
        ...opts,
      }
      const handlers = this._eventListeners["keydown"] || []
      handlers.forEach((h) => h(event))
      return event
    },

    _dispatchClick(target) {
      const event = {
        type: "click",
        target,
        preventDefault: mock(() => {}),
      }
      const handlers = this._eventListeners["click"] || []
      handlers.forEach((h) => h(event))
      return event
    },
  }
  return root
}

function instantiateHook(root) {
  const hook = Object.create(Console)
  hook.el = root
  hook.handleEvent = mock(() => {})
  hook.pushEvent = mock(() => {})
  hook.mounted()
  return hook
}

// Simulate the server responding to a `toggle_console` event by flipping
// `data-state` on the root element. In production this is driven by
// `assign(:open, ...)` + template re-render; in tests we bypass the round
// trip and poke the DOM directly, then call `updated()` to give the hook
// a chance to react to the transition.
function simulateServerStateTransition(hook, root, newState) {
  root._attrs["data-state"] = newState
  hook.updated()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  // Clear window event listeners between tests.
  Object.keys(windowListeners).forEach((key) => delete windowListeners[key])
  // Reset document.activeElement.
  document.activeElement = null
  // Clear the stub observer registry.
  stubObservers.length = 0
})

describe("Console hook — _applyClientSearch", () => {
  test("hides entries that do not match the search query", () => {
    const entryA = buildEntry(1, "Pipeline started successfully")
    const entryB = buildEntry(2, "TMDB request failed")
    const entryC = buildEntry(3, "Watcher detected new file")
    const container = buildEntriesContainer([entryA, entryB, entryC])
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, container)

    instantiateHook(root)

    searchInput.value = "tmdb"
    searchInput.dispatchInput()

    expect(entryA.style.display).toBe("none")
    expect(entryB.style.display).toBe("")
    expect(entryC.style.display).toBe("none")
  })

  test("search is case-insensitive", () => {
    const entryA = buildEntry(1, "Pipeline Started")
    const container = buildEntriesContainer([entryA])
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, container)

    instantiateHook(root)

    searchInput.value = "PIPELINE"
    searchInput.dispatchInput()

    expect(entryA.style.display).toBe("")
  })

  test("empty query shows all entries", () => {
    const entryA = buildEntry(1, "first message")
    const entryB = buildEntry(2, "second message")
    const container = buildEntriesContainer([entryA, entryB])
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, container)

    instantiateHook(root)

    // Filter to something first.
    searchInput.value = "first"
    searchInput.dispatchInput()
    expect(entryB.style.display).toBe("none")

    // Clear the filter.
    searchInput.value = ""
    searchInput.dispatchInput()
    expect(entryA.style.display).toBe("")
    expect(entryB.style.display).toBe("")
  })
})

describe("Console hook — _pushToggle", () => {
  test("window backtick event pushes a toggle_console event to the server", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    dispatchWindowEvent("mc:console:toggle")

    expect(hook.pushEvent.mock.calls.length).toBe(1)
    expect(hook.pushEvent.mock.calls[0][0]).toBe("toggle_console")
  })

  test("updated() focuses the search input on closed→open transition", () => {
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")

    expect(searchInput._focused).toBe(true)
  })

  test("updated() blurs the search input on open→closed transition", () => {
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, buildEntriesContainer())
    const hook = instantiateHook(root)

    // Move to open first, then back to closed.
    simulateServerStateTransition(hook, root, "open")
    searchInput._blurred = false // reset after initial mount
    simulateServerStateTransition(hook, root, "closed")

    expect(searchInput._blurred).toBe(true)
  })

  test("updated() does nothing when state has not changed", () => {
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, buildEntriesContainer())
    const hook = instantiateHook(root)

    // Same state — should not touch focus.
    hook.updated()

    expect(searchInput._focused).toBe(false)
    expect(searchInput._blurred).toBe(false)
  })
})

describe("Console hook — _handleKeyDown", () => {
  test("Escape key pushes toggle_console when open", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    hook.pushEvent.mockClear?.()  // ignore any push from opening

    root._dispatchKeyDown("Escape")

    expect(hook.pushEvent.mock.calls.some((call) => call[0] === "toggle_console")).toBe(true)
  })

  test("backtick key pushes toggle_console when open", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    hook.pushEvent.mockClear?.()

    root._dispatchKeyDown("`")

    expect(hook.pushEvent.mock.calls.some((call) => call[0] === "toggle_console")).toBe(true)
  })

  test("Escape key calls preventDefault and stopPropagation when open", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    const event = root._dispatchKeyDown("Escape")

    expect(event.preventDefault.mock.calls.length).toBeGreaterThan(0)
    expect(event.stopPropagation.mock.calls.length).toBeGreaterThan(0)
  })

  test("slash key focuses the search input when open", () => {
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    // updated() may focus; reset so we can verify the / handler does it.
    searchInput._focused = false
    document.activeElement = {}

    root._dispatchKeyDown("/")
    expect(searchInput._focused).toBe(true)
  })

  test("keys are ignored when the console is closed", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    // Stay closed — no toggle, no keys handled.
    const event = root._dispatchKeyDown("Escape")

    expect(event.preventDefault.mock.calls.length).toBe(0)
    expect(hook.pushEvent.mock.calls.length).toBe(0)
  })
})

describe("Console hook — _handleBackdropClick", () => {
  test("pushes toggle_console when clicking outside the panel while open", () => {
    const panel = buildPanel()
    const outsideNode = {}  // not in panel._children — contains() returns false
    const root = buildRoot(panel, buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    hook.pushEvent.mockClear?.()

    root._dispatchClick(outsideNode)

    expect(hook.pushEvent.mock.calls.some((call) => call[0] === "toggle_console")).toBe(true)
  })

  test("does not push when clicking inside the panel", () => {
    const panel = buildPanel()
    const insideNode = {}
    panel._children.push(insideNode)  // contains() returns true
    const root = buildRoot(panel, buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    simulateServerStateTransition(hook, root, "open")
    hook.pushEvent.mockClear?.()

    root._dispatchClick(insideNode)

    expect(hook.pushEvent.mock.calls.length).toBe(0)
  })

  test("click does nothing when console is closed", () => {
    const panel = buildPanel()
    const outsideNode = {}
    const root = buildRoot(panel, buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    // Stay closed — no push.
    root._dispatchClick(outsideNode)
    expect(hook.pushEvent.mock.calls.length).toBe(0)
  })
})

describe("Console hook — _maintainTopScroll", () => {
  test("snaps scrollTop to 0 when already at the top", () => {
    const container = buildEntriesContainer([])
    container.scrollTop = 0
    const root = buildRoot(buildPanel(), buildSearchInput(""), container)
    instantiateHook(root)

    // Simulate LiveView inserting a new entry at the top.
    stubObservers[0].fire()

    expect(container.scrollTop).toBe(0)
  })

  test("snaps scrollTop to 0 when within the 10 px threshold", () => {
    const container = buildEntriesContainer([])
    container.scrollTop = 8
    const root = buildRoot(buildPanel(), buildSearchInput(""), container)
    instantiateHook(root)

    stubObservers[0].fire()

    expect(container.scrollTop).toBe(0)
  })

  test("does not change scrollTop when user has scrolled down past threshold", () => {
    const container = buildEntriesContainer([])
    container.scrollTop = 200
    const root = buildRoot(buildPanel(), buildSearchInput(""), container)
    instantiateHook(root)

    stubObservers[0].fire()

    // scrollTop unchanged — user is reading older entries.
    expect(container.scrollTop).toBe(200)
  })
})

describe("Console hook — destroyed()", () => {
  test("removes all event listeners", () => {
    const searchInput = buildSearchInput("")
    const root = buildRoot(buildPanel(), searchInput, buildEntriesContainer())
    const hook = instantiateHook(root)

    // Verify listeners are registered
    expect(windowListeners["mc:console:toggle"]?.length).toBe(1)
    expect(root._eventListeners["keydown"]?.length).toBe(1)
    expect(root._eventListeners["click"]?.length).toBe(1)
    expect(searchInput._listeners["input"]).toBeDefined()

    hook.destroyed()

    // All listeners removed
    expect(windowListeners["mc:console:toggle"]?.length ?? 0).toBe(0)
    expect(root._eventListeners["keydown"]?.length ?? 0).toBe(0)
    expect(root._eventListeners["click"]?.length ?? 0).toBe(0)
    expect(searchInput._listeners["input"]).toBeUndefined()
  })

  test("toggle events are ignored after destroyed", () => {
    const root = buildRoot(buildPanel(), buildSearchInput(""), buildEntriesContainer())
    const hook = instantiateHook(root)

    // Before destroy: a window event should push toggle_console to the server.
    dispatchWindowEvent("mc:console:toggle")
    const pushesBeforeDestroy = hook.pushEvent.mock.calls.length
    expect(pushesBeforeDestroy).toBe(1)

    hook.destroyed()

    // After destroy: the listener is gone, so the same window event should
    // NOT produce another pushEvent call.
    dispatchWindowEvent("mc:console:toggle")
    expect(hook.pushEvent.mock.calls.length).toBe(pushesBeforeDestroy)
  })
})
