import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context, buildNavGraph } from "../core/index"
import { createReviewBehavior } from "../review_behavior"

describe("createReviewBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createReviewBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createReviewBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})

describe("review layout", () => {
  // The bulk list (campaign `review-bulk-match`): the toolbar over the rows,
  // the action bar under them while rows are ticked.
  const ticked = { zone_tabs: 2, "review-toolbar": 4, "review-rows": 9, "review-bar": 6, "review-results": 3 }

  test("the rows are a tree between the toolbar and the action bar", () => {
    const graph = buildNavGraph("review", ticked, inputConfig)

    expect(inputConfig.instanceTypes["review-rows"]).toBe(Context.TREE)
    expect(graph["review-toolbar"].down).toBe("review-rows")
    expect(graph["review-rows"].up).toBe("review-toolbar")
    expect(graph["review-rows"].down).toBe("review-bar")
  })

  test("RIGHT from any row reaches the results, so acting never means walking the list", () => {
    const graph = buildNavGraph("review", ticked, inputConfig)
    expect(graph["review-rows"].right).toBe("review-results")

    const noResults = buildNavGraph("review", { ...ticked, "review-results": 0 }, inputConfig)
    expect(noResults["review-rows"].right).toBe("review-bar")
  })

  test("BACK from the bar or its results returns to the rows they act on", () => {
    const graph = buildNavGraph("review", ticked, inputConfig)
    expect(graph["review-bar"].back).toBe("review-rows")
    expect(graph["review-results"].back).toBe("review-rows")
    expect(inputConfig.instanceTypes["review-results"]).toBe(Context.SHELF)
  })

  test("nothing ticked: the rows have no edge below and the page opens on them", () => {
    const graph = buildNavGraph("review", { ...ticked, "review-bar": 0, "review-results": 0 }, inputConfig)
    expect(graph["review-rows"].down).toBeUndefined()
    expect(inputConfig.cursorStartPriority.review[0]).toBe("review-rows")
  })
})

describe("episode-mapping layout", () => {
  test("Confirm matches and Dismiss all are a toolbar over the files", () => {
    const counts = {
      zone_tabs: 2,
      "episode-mapping-list": 2,
      "episode-mapping-actions": 2,
      "episode-mapping-detail": 6,
    }
    const graph = buildNavGraph("episode-mapping", counts, inputConfig)

    expect(inputConfig.instanceTypes["episode-mapping-actions"]).toBe(Context.TOOLBAR)
    expect(graph["episode-mapping-list"].right).toBe("episode-mapping-actions")
    expect(graph["episode-mapping-actions"].down).toBe("episode-mapping-detail")
    expect(graph["episode-mapping-actions"].left).toBe("episode-mapping-list")
    expect(graph["episode-mapping-detail"].up).toBe("episode-mapping-actions")
  })
})
