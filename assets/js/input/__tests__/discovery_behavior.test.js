import { describe, expect, test } from "bun:test"

import { createDiscoveryBehavior } from "../discovery_behavior.js"
import { inputConfig } from "../config.js"
import { Context } from "../core/index.js"

describe("discovery behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createDiscoveryBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — watchlist cards should not click on focus", () => {
    const behavior = createDiscoveryBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("the title rows are a TREE under the zone tabs — RIGHT steps onto a row's Ignore sub-item", () => {
    expect(inputConfig.contextSelectors.title_rows).toBe("[data-nav-zone='title_rows'] [data-nav-item]")
    expect(inputConfig.instanceTypes.title_rows).toBe(Context.TREE)
    expect(inputConfig.layouts.discovery).toEqual({
      zone_tabs: { down: ["title_rows", "people"] },
      title_rows: { up: ["zone_tabs"] },
      people: { up: ["zone_tabs"] },
      sidebar: { right: ["title_rows", "people", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.discovery).toEqual(["title_rows", "people", "zone_tabs", "sidebar"])
  })

  test("the title_detail overlay is the action strip over the scope menu over the tracking strip, DOWN/UP between them", () => {
    expect(inputConfig.overlays.title_detail).toEqual({
      entry: ["title_detail_body", "title_detail_menu", "title_detail_tracking"],
      layout: {
        title_detail_body: { down: ["title_detail_menu", "title_detail_tracking"] },
        title_detail_menu: { up: ["title_detail_body"], down: ["title_detail_tracking"] },
        title_detail_tracking: { up: ["title_detail_menu", "title_detail_body"] },
      },
    })
    expect(inputConfig.contextSelectors.title_detail_body).toBe("[data-nav-zone='title_detail_body'] [data-nav-item]")
    expect(inputConfig.contextSelectors.title_detail_menu).toBe("[data-nav-zone='title_detail_menu'] [data-nav-item]")
    expect(inputConfig.contextSelectors.title_detail_tracking).toBe("[data-nav-zone='title_detail_tracking'] [data-nav-item]")
  })
})
