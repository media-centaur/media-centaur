import { describe, expect, test } from "bun:test"
import { createDownloadBehavior } from "../download_behavior"

describe("download behavior", () => {
  test("onEscape returns sidebar", () => {
    const behavior = createDownloadBehavior()
    expect(behavior.onEscape()).toBe("sidebar")
  })

  test("onAttach and onDetach are no-ops (callable)", () => {
    const behavior = createDownloadBehavior()
    expect(() => behavior.onAttach()).not.toThrow()
    expect(() => behavior.onDetach()).not.toThrow()
  })
})
