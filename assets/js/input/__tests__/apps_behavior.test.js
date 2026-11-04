import { describe, expect, test } from "bun:test"

import { createAppsBehavior } from "../apps_behavior.js"
import { inputConfig } from "../config.js"
import { buildNavGraph, Context } from "../core/index.js"

describe("apps behavior", () => {
  test("defines no onEscape — BACK semantics live in the state machine (content BACK enters the sidebar)", () => {
    const behavior = createAppsBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("activateOnFocus is empty — app cards must never launch on focus", () => {
    const behavior = createAppsBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })
})

describe("apps modal nav (real config)", () => {
  test("the Steam picker is a geometry-resolved region under the modal's controls", () => {
    expect(inputConfig.instanceTypes.apps_steam).toBe(Context.SHELF)
    expect(inputConfig.instanceTypes.apps_controls).toBe(Context.TREE)
    expect(inputConfig.overlays.apps_modal.entry).toEqual(["apps_steam", "apps_controls"])
    const graph = buildNavGraph("apps", { apps_controls: 3, apps_steam: 12, grid: 4, toolbar: 2, sidebar: 7 }, {
      ...inputConfig,
      overlayLayout: inputConfig.overlays.apps_modal.layout,
    })
    expect(graph.apps_controls.down).toBe("apps_steam")
    expect(graph.apps_steam.up).toBe("apps_controls")
  })
})
