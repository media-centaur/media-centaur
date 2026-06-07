import { describe, expect, test } from "bun:test"
import { withWipNotice } from "../wip_notice"

/**
 * Mock notice DOM — records how many times the floating notice was flashed.
 */
function mockNoticeDom() {
  let flashes = 0
  return {
    flash() {
      flashes += 1
    },
    get flashes() {
      return flashes
    },
  }
}

describe("withWipNotice", () => {
  test("flashes the notice when an action fires", () => {
    const dom = mockNoticeDom()
    const behavior = withWipNotice({}, dom)

    behavior.onAction("navigate_down", "grid", null)

    expect(dom.flashes).toBe(1)
  })

  test("passes the action through so existing nav still runs", () => {
    const behavior = withWipNotice({}, mockNoticeDom())

    // false / undefined return = orchestrator processes the action normally.
    expect(behavior.onAction("navigate_down", "grid", null)).toBe(false)
  })

  test("flashes on every action, re-arming each time", () => {
    const dom = mockNoticeDom()
    const behavior = withWipNotice({}, dom)

    behavior.onAction("navigate_down", "grid", null)
    behavior.onAction("navigate_up", "grid", null)
    behavior.onAction("select", "grid", null)

    expect(dom.flashes).toBe(3)
  })

  test("preserves the wrapped behavior's other methods", () => {
    const behavior = withWipNotice({ onEscape: () => "sidebar" }, mockNoticeDom())

    expect(behavior.onEscape()).toBe("sidebar")
  })

  test("delegates to the wrapped behavior's onAction and returns its result", () => {
    const dom = mockNoticeDom()
    const calls = []
    const wrapped = {
      onAction(action, context, focused) {
        calls.push([action, context, focused])
        return { transitionTo: "grid" }
      },
    }
    const behavior = withWipNotice(wrapped, dom)

    const result = behavior.onAction("navigate_right", "sections", "el")

    expect(dom.flashes).toBe(1)
    expect(calls).toEqual([["navigate_right", "sections", "el"]])
    expect(result).toEqual({ transitionTo: "grid" })
  })
})
