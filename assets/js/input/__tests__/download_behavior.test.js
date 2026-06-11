import { describe, expect, test } from "bun:test"
import { createDownloadBehavior } from "../download_behavior"

describe("download behavior", () => {
  test("defines no onEscape — BACK is a no-op in content; left at the left edge reaches the sidebar", () => {
    const behavior = createDownloadBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })

  test("onAttach and onDetach are no-ops (callable)", () => {
    const behavior = createDownloadBehavior()
    expect(() => behavior.onAttach()).not.toThrow()
    expect(() => behavior.onDetach()).not.toThrow()
  })
})
