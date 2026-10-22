import { describe, expect, test } from "bun:test"
import { Action } from "../core/index.js"
import { createPageBehavior } from "../page_behavior"

/**
 * The factory is the seam between the orchestrator and the viewing
 * decorator: every dep the orchestrator supplies for a viewing has to reach
 * `withViewing`. A dep dropped here is invisible to the decorator's own tests
 * (they build their deps by hand) and surfaces as a TypeError on the first
 * key that needs it — SELECT on the Sony, 2026-10-22.
 */
describe("createPageBehavior while a viewing is on", () => {
  function build(prompt) {
    const pushed = []
    const behavior = createPageBehavior(null, {
      viewing: true,
      pushEvent: (event, payload) => pushed.push([event, payload]),
      isMenuOpen: () => false,
      hasPrompt: () => prompt,
    })
    return { behavior, pushed }
  }

  test("SELECT acts on the prompt while one shows", () => {
    const { behavior, pushed } = build(true)
    expect(behavior.onAction(Action.SELECT, "modal", null)).toBe(true)
    expect(pushed).toEqual([["viewing_prompt", {}]])
  })

  test("SELECT toggles pause when no prompt shows", () => {
    const { behavior, pushed } = build(false)
    expect(behavior.onAction(Action.SELECT, "modal", null)).toBe(true)
    expect(pushed).toEqual([["viewing_command", { command: "toggle_pause" }]])
  })

  test("without a viewing a page with no behavior has none", () => {
    expect(createPageBehavior(null, { viewing: false })).toBe(null)
  })
})
