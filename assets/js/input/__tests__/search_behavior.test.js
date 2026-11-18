import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"
import { createSearchBehavior } from "../search_behavior"

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

describe("search behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine", () => {
    expect(createSearchBehavior({ getOmniboxInput: () => null }).onEscape).toBeUndefined()
  })

  test("CLEAR wipes a non-empty omnibox and leaves an empty one alone", () => {
    const typed = fakeInput("sample")
    createSearchBehavior({ getOmniboxInput: () => typed }).onClear()
    expect(typed.cleared).toBe(true)

    const empty = fakeInput("")
    createSearchBehavior({ getOmniboxInput: () => empty }).onClear()
    expect(empty.cleared).toBe(false)

    expect(() => createSearchBehavior({ getOmniboxInput: () => null }).onClear()).not.toThrow()
  })

  test("the page's zones: the omnibox a MENU over the hero and the shelves, SHELF each", () => {
    expect(inputConfig.instanceTypes.omnibox).toBe(Context.MENU)
    for (const zone of ["hero", "out_now", "new_releases", "friends", "watchlist"]) {
      expect(inputConfig.instanceTypes[zone]).toBe(Context.SHELF)
    }
    expect(inputConfig.layouts.search.omnibox.down[0]).toBe("hero")
    expect(inputConfig.cursorStartPriority.search[0]).toBe("hero")
  })
})
