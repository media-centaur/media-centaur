import { describe, expect, test } from "bun:test"

import { createSocialBehavior } from "../social_behavior.js"
import { inputConfig } from "../config.js"
import { buildNavGraph } from "../core/index.js"

describe("social behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createSocialBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — watchlist cards should not click on focus", () => {
    const behavior = createSocialBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("the person cards are the one body zone under the zone tabs; the title rows belong to Incoming", () => {
    expect(inputConfig.layouts.social).toEqual({
      zone_tabs: { down: ["people"] },
      people: { up: ["zone_tabs"] },
      sidebar: { right: ["people", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.social).toEqual(["people", "zone_tabs", "sidebar"])

    // A stray title_rows zone in the DOM is ignored: nothing routes to it.
    const graph = buildNavGraph("social", { zone_tabs: 2, title_rows: 6, people: 3, sidebar: 4 }, inputConfig)
    expect(graph.zone_tabs.down).toBe("people")
    expect(graph.sidebar.right).toBe("people")
  })

  test("a title opened on Social navigates as the one detail overlay: the action row over an open menu over the tracking card (UIDR-043)", () => {
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
