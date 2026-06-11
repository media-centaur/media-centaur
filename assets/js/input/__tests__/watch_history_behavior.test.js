import { describe, expect, test } from "bun:test"

import { createWatchHistoryBehavior } from "../watch_history_behavior.js"

describe("watch_history behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — the event list should not click on focus", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})
