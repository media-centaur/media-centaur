import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"
import { createDiscoveryBehavior } from "../discovery_behavior"

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

describe("discovery behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine", () => {
    expect(createDiscoveryBehavior({ getOmniboxInput: () => null }).onEscape).toBeUndefined()
  })

  test("CLEAR wipes a non-empty omnibox and leaves an empty one alone", () => {
    const typed = fakeInput("sample")
    createDiscoveryBehavior({ getOmniboxInput: () => typed }).onClear()
    expect(typed.cleared).toBe(true)

    const empty = fakeInput("")
    createDiscoveryBehavior({ getOmniboxInput: () => empty }).onClear()
    expect(empty.cleared).toBe(false)

    expect(() => createDiscoveryBehavior({ getOmniboxInput: () => null }).onClear()).not.toThrow()
  })

  test("the page's zones: the omnibox a MENU over the hero and the shelves, SHELF each", () => {
    expect(inputConfig.instanceTypes.omnibox).toBe(Context.MENU)
    for (const zone of ["hero", "out_now", "new_releases", "friends", "watchlist"]) {
      expect(inputConfig.instanceTypes[zone]).toBe(Context.SHELF)
    }
    expect(inputConfig.layouts.discovery.omnibox.down[0]).toBe("hero")
    expect(inputConfig.cursorStartPriority.discovery[0]).toBe("hero")
  })
})
