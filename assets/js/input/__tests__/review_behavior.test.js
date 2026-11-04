import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Action, Context, buildNavGraph } from "../core/index"
import { createReviewBehavior } from "../review_behavior"

function fakeButton({ opensSearch }) {
  return {
    clicked: 0,
    blurred: false,
    click() {
      this.clicked += 1
    },
    blur() {
      this.blurred = true
    },
    hasAttribute(name) {
      return opensSearch && name === "data-review-open-search"
    },
  }
}

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

  test("SELECT on Search TMDB opens the panel and takes the cursor into it", () => {
    const behavior = createReviewBehavior()
    const button = fakeButton({ opensSearch: true })

    const result = behavior.onAction(Action.SELECT, "review-actions", button)

    expect(button.clicked).toBe(1)
    expect(button.blurred).toBe(true)
    expect(result).toEqual({ transitionTo: "review-search" })
  })

  test("any other SELECT passes through", () => {
    const behavior = createReviewBehavior()
    const button = fakeButton({ opensSearch: false })

    expect(behavior.onAction(Action.SELECT, "review-actions", button)).toBe(false)
    expect(button.clicked).toBe(0)
  })
})

describe("review layout", () => {
  test("the decision buttons are a toolbar between the detail and the search panel", () => {
    const counts = { zone_tabs: 2, "review-list": 3, "review-detail": 2, "review-actions": 4, "review-search": 5 }
    const graph = buildNavGraph("review", counts, inputConfig)

    expect(inputConfig.instanceTypes["review-actions"]).toBe(Context.TOOLBAR)
    expect(graph["review-detail"].down).toBe("review-actions")
    expect(graph["review-actions"].up).toBe("review-detail")
    expect(graph["review-actions"].down).toBe("review-search")
    expect(graph["review-actions"].left).toBe("review-list")
    expect(graph["review-search"].up).toBe("review-actions")
  })

  test("a single file with nothing above the row: the list's RIGHT lands on the row", () => {
    const counts = { zone_tabs: 2, "review-list": 3, "review-detail": 0, "review-actions": 4, "review-search": 0 }
    const graph = buildNavGraph("review", counts, inputConfig)

    expect(graph["review-list"].right).toBe("review-actions")
    expect(graph["review-actions"].up).toBe("zone_tabs")
  })

  test("BACK from the search panel returns to the row (the zone's dismiss event closes it)", () => {
    expect(inputConfig.layouts.review["review-search"].back).toEqual(["review-actions"])
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
