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

  test("the body under the zone tabs is the Feed's rows, the person cards, or the person page's rows over its card", () => {
    expect(inputConfig.layouts.social).toEqual({
      zone_tabs: { down: ["feed", "people", "person_rows", "person_view"] },
      feed: { up: ["zone_tabs"] },
      people: { up: ["zone_tabs"] },
      person_rows: { up: ["zone_tabs"], down: ["person_view"] },
      person_view: { up: ["person_rows", "zone_tabs"] },
      sidebar: { right: ["feed", "people", "person_rows", "person_view", "zone_tabs"] },
    })
    expect(inputConfig.cursorStartPriority.social).toEqual([
      "feed", "people", "person_rows", "person_view", "zone_tabs", "sidebar",
    ])

    // A stray title_rows zone in the DOM is ignored: nothing routes to it.
    const friends = buildNavGraph("social", { zone_tabs: 2, title_rows: 6, people: 3, sidebar: 4 }, inputConfig)
    expect(friends.zone_tabs.down).toBe("people")
    expect(friends.sidebar.right).toBe("people")

    const feed = buildNavGraph("social", { zone_tabs: 2, feed: 20, sidebar: 4 }, inputConfig)
    expect(feed.zone_tabs.down).toBe("feed")
    expect(feed.feed.up).toBe("zone_tabs")
    expect(feed.sidebar.right).toBe("feed")

    // The person page: DOWN past the last row enters the card; UP from the card's top returns to the rows.
    const person = buildNavGraph("social", { zone_tabs: 2, person_rows: 5, person_view: 14, sidebar: 4 }, inputConfig)
    expect(person.zone_tabs.down).toBe("person_rows")
    expect(person.person_rows.down).toBe("person_view")
    expect(person.person_view.up).toBe("person_rows")
    expect(person.sidebar.right).toBe("person_rows")

    // The reader's own page has no card: DOWN at the last row is a wall.
    const own = buildNavGraph("social", { zone_tabs: 2, person_rows: 3, sidebar: 4 }, inputConfig)
    expect(own.person_rows.down).toBeUndefined()
  })

  test("the person page's rows are a tree like the Feed's; its card walks like a Settings card", () => {
    expect(inputConfig.instanceTypes.person_rows).toBe("tree")
    expect(inputConfig.instanceTypes.person_view).toBe("grid")
    expect(inputConfig.contextSelectors.person_rows).toBe("[data-nav-zone='person_rows'] [data-nav-item]")
    expect(inputConfig.contextSelectors.person_view).toBe("[data-nav-zone='person_view'] [data-nav-item]")
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
