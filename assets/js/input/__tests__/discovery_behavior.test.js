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

  test("the person cards are the one body zone under the zone tabs; the title rows TREE belongs to Incoming", () => {
    expect(inputConfig.contextSelectors.title_rows).toBe("[data-nav-zone='title_rows'] [data-nav-item]")
    expect(inputConfig.instanceTypes.title_rows).toBe(Context.TREE)
    expect(inputConfig.layouts.discovery).toEqual({
      zone_tabs: { down: ["people"] },
      people: { up: ["zone_tabs"] },
      sidebar: { right: ["people", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.discovery).toEqual(["people", "zone_tabs", "sidebar"])
  })

  test("a title opened on Discovery navigates as the one detail overlay: the action row over an open menu over the tracking card (UIDR-043)", () => {
    expect(inputConfig.overlays.title_detail).toBeUndefined()
    expect(inputConfig.contextSelectors.title_detail_body).toBeUndefined()
    expect(inputConfig.overlays.detail.entry.slice(0, 2)).toEqual(["detail_actions", "detail_menu"])
    expect(inputConfig.overlays.detail.layout.detail_menu).toEqual({
      up: ["detail_actions"],
      down: ["detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
      back: ["detail_actions"],
    })
    expect(inputConfig.overlays.detail.layout.detail_tracking.back).toEqual(["detail_actions"])
  })
})
