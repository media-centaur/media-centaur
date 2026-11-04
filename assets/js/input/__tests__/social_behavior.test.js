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
    expect(inputConfig.cursorStartPriority.social.slice(0, 2)).toEqual(["feed", "people"])

    // A stray title_rows zone in the DOM is ignored: nothing routes to it.
    const friends = buildNavGraph("social", { zone_tabs: 2, title_rows: 6, people: 3, sidebar: 4 }, inputConfig)
    expect(friends.zone_tabs.down).toBe("people")
    expect(friends.sidebar.right).toBe("people")

    const feed = buildNavGraph("social", { zone_tabs: 2, feed: 20, sidebar: 4 }, inputConfig)
    expect(feed.zone_tabs.down).toBe("feed")
    expect(feed.feed.up).toBe("zone_tabs")
    expect(feed.sidebar.right).toBe("feed")

    // The person page: the card sits beside the rows — RIGHT reaches it
    // from the rows and LEFT returns — and DOWN past the last row enters it
    // too; UP from the card's top returns to the rows.
    const person = buildNavGraph("social", { zone_tabs: 2, person_rows: 5, person_view: 14, sidebar: 4 }, inputConfig)
    expect(person.zone_tabs.down).toBe("person_rows")
    expect(person.person_rows.right).toBe("person_view")
    expect(person.person_view.left).toBe("person_rows")
    expect(person.person_rows.down).toBe("person_view")
    expect(person.person_view.up).toBe("person_rows")
    expect(person.sidebar.right).toBe("person_rows")

    // The reader's own page has no card: DOWN at the last row is a wall.
    const own = buildNavGraph("social", { zone_tabs: 2, person_rows: 3, sidebar: 4 }, inputConfig)
    expect(own.person_rows.down).toBeUndefined()
    expect(own.person_rows.right).toBeUndefined()
  })

  test("the Feed's scope control sits RIGHT of the tab strip, over the Feed", () => {
    const feed = buildNavGraph("social", { zone_tabs: 2, toolbar: 3, feed: 20, sidebar: 4 }, inputConfig)
    expect(feed.zone_tabs.right).toBe("toolbar")
    expect(feed.toolbar.left).toBe("zone_tabs")
    expect(feed.toolbar.down).toBe("feed")
    expect(feed.feed.up).toBe("zone_tabs")
  })

  test("Friends: the cards over the hidden group, the add form and the Settings pointer", () => {
    expect(inputConfig.instanceTypes.hidden_people).toBe("tree")
    expect(inputConfig.instanceTypes.add_friend).toBe("toolbar")
    expect(inputConfig.instanceTypes.friends_pointer).toBe("toolbar")

    const friends = buildNavGraph(
      "social",
      { zone_tabs: 2, people: 3, hidden_people: 2, add_friend: 3, friends_pointer: 1, sidebar: 4 },
      inputConfig,
    )
    expect(friends.people.down).toBe("hidden_people")
    expect(friends.hidden_people.up).toBe("people")
    expect(friends.hidden_people.down).toBe("add_friend")
    expect(friends.add_friend.up).toBe("hidden_people")
    expect(friends.add_friend.down).toBe("friends_pointer")
    expect(friends.friends_pointer.up).toBe("add_friend")

    // Nobody hidden and no friends yet: the add form follows the empty
    // state's button (which carries the `people` zone) directly.
    const fresh = buildNavGraph("social", { zone_tabs: 2, people: 1, add_friend: 3, friends_pointer: 1, sidebar: 4 }, inputConfig)
    expect(fresh.people.down).toBe("add_friend")
    expect(fresh.add_friend.up).toBe("people")
  })

  test("the Undo toast after an Ignore is RIGHT of the rows while it shows", () => {
    expect(inputConfig.instanceTypes.undo_toast).toBe("toolbar")
    const feed = buildNavGraph("social", { zone_tabs: 2, feed: 20, undo_toast: 1, sidebar: 4 }, inputConfig)
    expect(feed.feed.right).toBe("undo_toast")
    expect(feed.undo_toast.left).toBe("feed")
    expect(feed.undo_toast.back).toBe("feed")

    // On a person page the toast comes before the card while it shows.
    const person = buildNavGraph("social", { zone_tabs: 2, person_rows: 5, person_view: 14, undo_toast: 1, sidebar: 4 }, inputConfig)
    expect(person.person_rows.right).toBe("undo_toast")

    const gone = buildNavGraph("social", { zone_tabs: 2, feed: 20, sidebar: 4 }, inputConfig)
    expect(gone.feed.right).toBeUndefined()
  })

  test("the person page's rows are a tree like the Feed's; its card is a tree of rows, the swatches one row", () => {
    expect(inputConfig.instanceTypes.person_rows).toBe("tree")
    expect(inputConfig.instanceTypes.person_view).toBe("tree")
    expect(inputConfig.contextSelectors.person_rows).toBe("[data-nav-zone='person_rows'] [data-nav-item]")
    expect(inputConfig.contextSelectors.person_view).toBe("[data-nav-zone='person_view'] [data-nav-item]")
  })

  test("the Review modal is three regions: the sentiments, the words, the footer; BACK cancels from any", () => {
    const review = inputConfig.overlays.review
    expect(review.entry[0]).toBe("review_choice")
    expect(inputConfig.instanceTypes.review_choice).toBe("toolbar")
    expect(inputConfig.instanceTypes.review_footer).toBe("toolbar")
    expect(review.layout.review_choice.down).toEqual(["review_text"])
    expect(review.layout.review_text).toEqual({ up: ["review_choice"], down: ["review_footer"] })
    expect(review.layout.review_footer.up).toEqual(["review_text"])
    for (const region of Object.values(review.layout)) expect(region.back).toBeUndefined()
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
