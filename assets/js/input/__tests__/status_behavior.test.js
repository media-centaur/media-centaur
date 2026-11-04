import { describe, expect, test } from "bun:test"
import { inputConfig } from "../config"
import { Context, buildNavGraph, resolveCursorStart } from "../core/index"
import { createStatusBehavior } from "../status_behavior"

describe("createStatusBehavior", () => {
  test("returns an object with lifecycle methods", () => {
    const behavior = createStatusBehavior()
    expect(typeof behavior.onAttach).toBe("function")
    expect(typeof behavior.onDetach).toBe("function")
  })

  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createStatusBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})

describe("status layout", () => {
  const counts = { toolbar: 1, subsystems: 9, "drill-in": 4, sidebar: 4 }

  test("the subsystem tiles are walked by geometry, between the toolbar and the drill-in", () => {
    const graph = buildNavGraph("status", counts, inputConfig)
    expect(inputConfig.instanceTypes.subsystems).toBe(Context.SHELF)
    expect(graph.toolbar.down).toBe("subsystems")
    expect(graph.subsystems.up).toBe("toolbar")
    expect(graph.subsystems.down).toBe("drill-in")
    expect(graph["drill-in"].up).toBe("subsystems")
  })

  test("the cursor starts on the tiles, entering at the selected one (?subsystem=X)", () => {
    expect(resolveCursorStart("status", counts, inputConfig)).toBe("subsystems")
    expect(inputConfig.entryDefaults.subsystems).toBe("[data-selected]")
  })
})
