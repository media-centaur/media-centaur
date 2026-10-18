import { describe, expect, test } from "bun:test"

import { createSocialBehavior } from "../social_behavior.js"
import { inputConfig } from "../config.js"
import { buildNavGraph } from "../core/index.js"

describe("social behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createSocialBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — person cards should not click on focus", () => {
    const behavior = createSocialBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("the body under the zone tabs is the Feed's rows or the person cards; the title rows belong to Incoming", () => {
    expect(inputConfig.layouts.social).toEqual({
      zone_tabs: { down: ["feed", "people"] },
      feed: { up: ["zone_tabs"] },
      people: { up: ["zone_tabs"] },
      sidebar: { right: ["feed", "people", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.social).toEqual(["feed", "people", "zone_tabs", "sidebar"])

    // A stray title_rows zone in the DOM is ignored: nothing routes to it.
    const friends = buildNavGraph("social", { zone_tabs: 2, title_rows: 6, people: 3, sidebar: 4 }, inputConfig)
    expect(friends.zone_tabs.down).toBe("people")
    expect(friends.sidebar.right).toBe("people")

    const feed = buildNavGraph("social", { zone_tabs: 2, feed: 20, sidebar: 4 }, inputConfig)
    expect(feed.zone_tabs.down).toBe("feed")
    expect(feed.feed.up).toBe("zone_tabs")
    expect(feed.sidebar.right).toBe("feed")
  })

  test("the Feed is a tree: rows walk up and down, a row's verbs are its sub-items", () => {
    expect(inputConfig.instanceTypes.feed).toBe("tree")
    expect(inputConfig.contextSelectors.feed).toBe("[data-nav-zone='feed'] [data-nav-item]")
  })

  test("a title opened on Social navigates as the one detail overlay: the action row over an open menu over the tracking card (UIDR-043)", () => {
    expect(inputConfig.overlays.title_detail).toBeUndefined()
    expect(inputConfig.contextSelectors.title_detail_body).toBeUndefined()
    // The finish prompt, when drawn, comes first (UIDR-052); otherwise the row, then an open menu.
    expect(inputConfig.overlays.detail.entry.slice(0, 3)).toEqual(["detail_finish", "detail_actions", "detail_menu"])
    expect(inputConfig.overlays.detail.layout.detail_menu).toEqual({
      up: ["detail_actions"],
      down: ["detail_rail", "manage_tools", "manage_list", "detail_list", "detail_cast", "detail_tracking"],
      back: ["detail_actions"],
    })
    expect(inputConfig.overlays.detail.layout.detail_tracking.back).toEqual(["detail_actions"])
  })
})
