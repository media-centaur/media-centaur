import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"
import { createDownloadsBehavior } from "../downloads_behavior"

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
    const behavior = createDownloadsBehavior(mockDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  test("the search box is a MENU like every other Downloads zone — the input and its clear", () => {
    expect(inputConfig.contextSelectors.omnibox).toBe("[data-nav-zone='omnibox'] [data-nav-item]")
    expect(inputConfig.instanceTypes.omnibox).toBe(Context.MENU)
  })

  test("onAttach and onDetach are no-ops (callable)", () => {
    const behavior = createDownloadsBehavior(mockDom())
    expect(() => behavior.onAttach()).not.toThrow()
    expect(() => behavior.onDetach()).not.toThrow()
  })

  describe("onClear", () => {
    test("clears the omnibox query when it has content", () => {
      const omnibox = fakeInput("sample show")
      const historySearch = fakeInput("old query")
      const behavior = createDownloadsBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(true)
      expect(historySearch.cleared).toBe(false)
    })

    test("falls through to the history search when the omnibox is empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("failed grabs")
      const behavior = createDownloadsBehavior(mockDom({ omnibox, historySearch }))

      behavior.onClear()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(true)
    })

    test("does nothing when both inputs are empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("")
      const behavior = createDownloadsBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(false)
    })

    test("tolerates absent inputs (zones not rendered)", () => {
      const behavior = createDownloadsBehavior(mockDom())
      expect(() => behavior.onClear()).not.toThrow()
    })
  })
})
