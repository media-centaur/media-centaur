import { describe, expect, test } from "bun:test"

import { createWatchHistoryBehavior } from "../watch_history_behavior.js"

describe("watch_history behavior", () => {
  test("onEscape returns 'sidebar' so BACK navigates toward the primary menu", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.onEscape()).toBe("sidebar")
  })

  test("activateOnFocus is empty — the event list should not click on focus", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})
