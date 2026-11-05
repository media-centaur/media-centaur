import { describe, expect, test } from "bun:test"

import { createWatchHistoryBehavior } from "../watch_history_behavior.js"
import { inputConfig } from "../config.js"
import { buildNavGraph, Context } from "../core/index.js"

/** A fake page: the search box and the type filter's All option. */
function fakeDom({ search = "", allPressed = true } = {}) {
  const calls = []
  return {
    calls,
    getSearchInput: () => ({ value: search, clear: () => calls.push("search") }),
    resetType: () => { if (!allPressed) calls.push("type") },
  }
}

describe("watch_history behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createWatchHistoryBehavior(fakeDom())
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — the event list should not click on focus", () => {
    const behavior = createWatchHistoryBehavior(fakeDom())
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("CLEAR wipes the search and resets the type filter", () => {
    const dom = fakeDom({ search: "sample", allPressed: false })
    createWatchHistoryBehavior(dom).onClear()
    expect(dom.calls).toEqual(["search", "type"])
  })

  test("CLEAR with no filter set touches nothing", () => {
    const dom = fakeDom()
    createWatchHistoryBehavior(dom).onClear()
    expect(dom.calls).toEqual([])
  })
})

describe("watch history nav (real config)", () => {
  test("the rows are a tree under the toolbar", () => {
    expect(inputConfig.instanceTypes.history_rows).toBe(Context.TREE)
    const graph = buildNavGraph("watch_history", { toolbar: 6, history_rows: 50, sidebar: 7 }, inputConfig)
    expect(graph.toolbar.down).toBe("history_rows")
    expect(graph.history_rows.up).toBe("toolbar")
  })
})
