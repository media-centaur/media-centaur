import { describe, expect, test, beforeEach, afterEach, mock } from "bun:test"
import { ConsolePage } from "./console_page"
import {
  installGlobal,
  installWindow,
  installMutationObserver,
  restoreGlobals,
} from "../test_support/dom_stubs"

// ---------------------------------------------------------------------------
// DOM mock constructors
//
// Bun ships no DOM, so the browser globals the hook uses are installed fresh
// before every test — see `test_support/dom_stubs.js` for why they must not be
// installed conditionally.
// ---------------------------------------------------------------------------

function buildEntry(message) {
  return {
    dataset: { message: message.toLowerCase() },
    style: {},
  }
}

function buildEntriesContainer(entries = []) {
  return {
    _entries: entries,
    querySelectorAll(_selector) {
      return this._entries
    },
  }
}

function buildSearchInput(value = "") {
  return {
    value,
    _listeners: {},
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
}

function buildRoot(searchInput, entriesContainer) {
  return {
    querySelector(selector) {
      if (selector === "[data-console-search]") return searchInput
      if (selector === "#console-entries") return entriesContainer
      return null
    },
  }
}

// `handleEvent` is the LiveView hook API for `push_event` payloads; the stub
// records the callbacks so a test can fire one the way the server would.
function instantiateHook(root) {
  const hook = Object.create(ConsolePage)
  hook.el = root
  hook._serverEvents = {}
  hook.handleEvent = mock((name, callback) => {
    hook._serverEvents[name] = callback
  })
  hook.mounted()
  return hook
}

beforeEach(() => {
  installWindow()
  installMutationObserver()
})

afterEach(restoreGlobals)

describe("ConsolePage — client-side search", () => {
  test("hides entries that do not match the search query", () => {
    const entryA = buildEntry("Pipeline started successfully")
    const entryB = buildEntry("TMDB request failed")
    const entryC = buildEntry("Watcher detected new file")
    const searchInput = buildSearchInput("")
    const root = buildRoot(searchInput, buildEntriesContainer([entryA, entryB, entryC]))

    instantiateHook(root)

    searchInput.value = "tmdb"
    searchInput.dispatchInput()

    expect(entryA.style.display).toBe("none")
    expect(entryB.style.display).toBe("")
    expect(entryC.style.display).toBe("none")
  })

  test("search is case-insensitive", () => {
    const entryA = buildEntry("Pipeline Started")
    const searchInput = buildSearchInput("")
    const root = buildRoot(searchInput, buildEntriesContainer([entryA]))

    instantiateHook(root)

    searchInput.value = "PIPELINE"
    searchInput.dispatchInput()

    expect(entryA.style.display).toBe("")
  })

  test("empty query shows all entries", () => {
    const entryA = buildEntry("first message")
    const entryB = buildEntry("second message")
    const searchInput = buildSearchInput("")
    const root = buildRoot(searchInput, buildEntriesContainer([entryA, entryB]))

    instantiateHook(root)

    searchInput.value = "first"
    searchInput.dispatchInput()
    expect(entryB.style.display).toBe("none")

    searchInput.value = ""
    searchInput.dispatchInput()
    expect(entryA.style.display).toBe("")
    expect(entryB.style.display).toBe("")
  })

  test("a persisted query is applied to the first paint", () => {
    const entryA = buildEntry("pipeline started")
    const entryB = buildEntry("tmdb request failed")
    const searchInput = buildSearchInput("tmdb")
    const root = buildRoot(searchInput, buildEntriesContainer([entryA, entryB]))

    instantiateHook(root)

    expect(entryA.style.display).toBe("none")
    expect(entryB.style.display).toBe("")
  })

  test("entries streamed in after mount honour the active query", () => {
    const entryA = buildEntry("pipeline started")
    const container = buildEntriesContainer([entryA])
    const searchInput = buildSearchInput("")
    const observers = installMutationObserver()
    const root = buildRoot(searchInput, container)

    instantiateHook(root)

    searchInput.value = "tmdb"
    searchInput.dispatchInput()

    // A new row arrives from the stream; the observer re-applies the query.
    const entryB = buildEntry("tmdb request failed")
    container._entries.push(entryB)
    observers[0].fire()

    expect(entryA.style.display).toBe("none")
    expect(entryB.style.display).toBe("")
  })
})

describe("ConsolePage — server-pushed actions", () => {
  test("console:copy writes the payload to the clipboard", async () => {
    const written = []
    installGlobal("navigator", {
      clipboard: {
        writeText: (text) => {
          written.push(text)
          return Promise.resolve()
        },
      },
    })

    const hook = instantiateHook(buildRoot(buildSearchInput(""), buildEntriesContainer()))
    hook._serverEvents["console:copy"]({ content: "a log line" })

    expect(written).toEqual(["a log line"])
  })

  test("console:download clicks an anchor carrying the server's filename", () => {
    const anchor = { click: mock(() => {}) }
    const appended = []

    installGlobal(
      "Blob",
      class StubBlob {
        constructor(parts) {
          this.parts = parts
        }
      }
    )
    installGlobal("URL", {
      createObjectURL: () => "blob:stub",
      revokeObjectURL: mock(() => {}),
    })
    installGlobal("document", {
      createElement: () => anchor,
      body: {
        appendChild: (node) => appended.push(node),
        removeChild: mock(() => {}),
      },
    })

    const hook = instantiateHook(buildRoot(buildSearchInput(""), buildEntriesContainer()))
    hook._serverEvents["console:download"]({
      filename: "media-centaur-log.log",
      content: "a log line",
    })

    expect(anchor.download).toBe("media-centaur-log.log")
    expect(anchor.href).toBe("blob:stub")
    expect(anchor.click.mock.calls.length).toBe(1)
    expect(appended).toEqual([anchor])
  })
})

describe("ConsolePage — destroyed()", () => {
  test("releases the input listener and the mutation observer", () => {
    const searchInput = buildSearchInput("")
    const observers = installMutationObserver()
    const hook = instantiateHook(buildRoot(searchInput, buildEntriesContainer()))

    expect(searchInput._listeners["input"]).toBeDefined()
    expect(observers[0].observing).toBe(true)

    hook.destroyed()

    expect(searchInput._listeners["input"]).toBeUndefined()
    expect(observers[0].observing).toBe(false)
  })
})
