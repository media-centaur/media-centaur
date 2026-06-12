import { describe, expect, test } from "bun:test"
import { createDownloadBehavior } from "../download_behavior"

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
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createDownloadBehavior(mockDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  test("onAttach and onDetach are no-ops (callable)", () => {
    const behavior = createDownloadBehavior(mockDom())
    expect(() => behavior.onAttach()).not.toThrow()
    expect(() => behavior.onDetach()).not.toThrow()
  })

  describe("onClear", () => {
    test("clears the omnibox query when it has content", () => {
      const omnibox = fakeInput("sample show")
      const historySearch = fakeInput("old query")
      const behavior = createDownloadBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(true)
      expect(historySearch.cleared).toBe(false)
    })

    test("falls through to the history search when the omnibox is empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("failed grabs")
      const behavior = createDownloadBehavior(mockDom({ omnibox, historySearch }))

      behavior.onClear()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(true)
    })

    test("does nothing when both inputs are empty", () => {
      const omnibox = fakeInput("")
      const historySearch = fakeInput("")
      const behavior = createDownloadBehavior(mockDom({ omnibox, historySearch }))

      expect(behavior.onClear()).toBeUndefined()
      expect(omnibox.cleared).toBe(false)
      expect(historySearch.cleared).toBe(false)
    })

    test("tolerates absent inputs (zones not rendered)", () => {
      const behavior = createDownloadBehavior(mockDom())
      expect(() => behavior.onClear()).not.toThrow()
    })
  })
})
