import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context } from "../core/index"
import { createPageBehavior } from "../page_behavior"
import { createWatchlistBehavior } from "../watchlist_behavior"

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

describe("watchlist behavior", () => {
  test("is registered under the page root's name", () => {
    expect(createPageBehavior("watchlist")).not.toBeNull()
  })

  test("defines no onEscape — BACK semantics live in the state machine", () => {
    expect(createWatchlistBehavior({ getSearchInput: () => null }).onEscape).toBeUndefined()
  })

  test("CLEAR wipes a non-empty search and leaves an empty or absent one alone", () => {
    const typed = fakeInput("sample")
    createWatchlistBehavior({ getSearchInput: () => typed }).onClear()
    expect(typed.cleared).toBe(true)

    const empty = fakeInput("")
    createWatchlistBehavior({ getSearchInput: () => empty }).onClear()
    expect(empty.cleared).toBe(false)

    expect(() => createWatchlistBehavior({ getSearchInput: () => null }).onClear()).not.toThrow()
  })

  test("the page's zones: the rows a TREE under the toolbar, the rung menu nested with a back edge", () => {
    expect(inputConfig.instanceTypes.watchlist_rows).toBe(Context.TREE)
    expect(inputConfig.instanceTypes.watchlist_rung_menu).toBe(Context.TREE)
    expect(inputConfig.layouts.watchlist.toolbar.down).toEqual(["watchlist_rows"])
    expect(inputConfig.layouts.watchlist.watchlist_rows.down).toEqual(["watchlist_rung_menu"])
    expect(inputConfig.layouts.watchlist.watchlist_rung_menu.back).toEqual(["watchlist_rows"])
    expect(inputConfig.cursorStartPriority.watchlist[0]).toBe("watchlist_rows")
  })
})
