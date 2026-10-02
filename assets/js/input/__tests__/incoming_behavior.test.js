import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"
import { createIncomingBehavior } from "../incoming_behavior"

function fakeInput(initialValue) {
  return {
    value: initialValue,
    cleared: false,
    clear() {
      this.value = ""
      this.cleared = true
    },
  }
}

function mockDom({ omnibox = null, historySearch = null } = {}) {
  return {
    getOmniboxInput: () => omnibox,
    getHistorySearch: () => historySearch,
  }
}

describe("download behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createIncomingBehavior(mockDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  test("the Watchlist rows are a MENU like every other Incoming zone — one nav item per row", () => {
    expect(inputConfig.contextSelectors.title_rows).toBe("[data-nav-zone='title_rows'] [data-nav-item]")
    expect(inputConfig.instanceTypes.title_rows).toBe(Context.MENU)
  })

  test("onAttach and onDetach are no-ops (callable)", () => {
    const behavior = createIncomingBehavior(mockDom())
    expect(() => behavior.onAttach()).not.toThrow()
    expect(() => behavior.onDetach()).not.toThrow()
  })

  describe("onClear", () => {
    test("clears the omnibox query when it has content", () => {
      const omnibox = fakeInput("sample show")
      const historySearch = fakeInput("old query")
      const behavior = createIncomingBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(true)
      expect(historySearch.cleared).toBe(false)
    })

    test("falls through to the history search when the omnibox is empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("failed grabs")
      const behavior = createIncomingBehavior(mockDom({ omnibox, historySearch }))

      behavior.onClear()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(true)
    })

    test("does nothing when both inputs are empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("")
      const behavior = createIncomingBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(false)
    })

    test("tolerates absent inputs (zones not rendered)", () => {
      const behavior = createIncomingBehavior(mockDom())
      expect(() => behavior.onClear()).not.toThrow()
    })
  })
})
