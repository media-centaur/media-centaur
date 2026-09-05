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

  test("the title_detail overlay is the action strip over the scope menu, DOWN/UP between them", () => {
    expect(inputConfig.overlays.title_detail).toEqual({
      entry: ["title_detail_body", "title_detail_menu"],
      layout: {
        title_detail_body: { down: ["title_detail_menu"] },
        title_detail_menu: { up: ["title_detail_body"] },
      },
    })
    expect(inputConfig.contextSelectors.title_detail_body).toBe("[data-nav-zone='title_detail_body'] [data-nav-item]")
    expect(inputConfig.contextSelectors.title_detail_menu).toBe("[data-nav-zone='title_detail_menu'] [data-nav-item]")
  })
})
