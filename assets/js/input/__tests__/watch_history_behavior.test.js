import { describe, expect, test } from "bun:test"

import { createWatchHistoryBehavior } from "../watch_history_behavior.js"

describe("watch_history behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — the event list should not click on focus", () => {
    const behavior = createWatchHistoryBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})
