import { describe, expect, test } from "bun:test"

import { createWatchlistBehavior } from "../watchlist_behavior.js"

describe("watchlist behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createWatchlistBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — watchlist cards should not click on focus", () => {
    const behavior = createWatchlistBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})
