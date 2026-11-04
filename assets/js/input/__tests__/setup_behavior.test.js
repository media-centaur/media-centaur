import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { buildNavGraph, resolveCursorStart } from "../core/index"
import { createSetupBehavior } from "../setup_behavior"

describe("setup behavior", () => {
  test("does not activate items on focus — Begin/Next require an explicit SELECT", () => {
    const behavior = createSetupBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("defines no onEscape — the wizard has no sidebar to exit to", () => {
    const behavior = createSetupBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})

describe("setup layout", () => {
  const counts = { toolbar: 1, grid: 5 }

  test("Skip the tour (toolbar) sits above the step card and is reached by UP from the card", () => {
    const graph = buildNavGraph("setup", counts, inputConfig)
    expect(graph.grid.up).toBe("toolbar")
    expect(graph.toolbar.down).toBe("grid")
  })

  test("the cursor starts in the step card, not on Skip the tour", () => {
    expect(resolveCursorStart("setup", counts, inputConfig)).toBe("grid")
  })

  test("the summary step has no Skip the tour: the card stands alone", () => {
    const graph = buildNavGraph("setup", { toolbar: 0, grid: 4 }, inputConfig)
    expect(graph.grid.up).toBeUndefined()
  })
})
