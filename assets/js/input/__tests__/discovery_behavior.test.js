import { describe, expect, test } from "bun:test"

import { createDiscoveryBehavior } from "../discovery_behavior.js"
import { inputConfig } from "../config.js"

describe("discovery behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createDiscoveryBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — watchlist cards should not click on focus", () => {
    const behavior = createDiscoveryBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("the title_detail overlay is one toolbar region — the modal's action row", () => {
    expect(inputConfig.overlays.title_detail).toEqual({
      entry: ["title_detail_body"],
      layout: { title_detail_body: {} },
    })
    expect(inputConfig.contextSelectors.title_detail_body).toBe("[data-nav-zone='title_detail_body'] [data-nav-item]")
  })
})
