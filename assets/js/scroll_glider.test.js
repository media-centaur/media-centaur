import { describe, expect, test } from "bun:test"
import { scrollGlider } from "./scroll_glider.js"

describe("scrollGlider", () => {
  test("is reachable as the page's debug handle, so a measurement can swap the animator", () => {
    expect(globalThis.__scrollGlider).toBe(scrollGlider)
    expect(typeof scrollGlider.glide).toBe("function")
  })
})
