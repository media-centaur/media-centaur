import { describe, expect, test } from "bun:test"
import { captionFor } from "./plan_grid_caption"

const cell = caption => ({ dataset: { caption } })

// The pointer is the more deliberate signal: a hovered cell captions even
// while another cell holds the cursor. Without a pointer the cursor's cell
// captions; with neither the line is empty — the grid speaks for itself.
describe("captionFor", () => {
  test("hovered cell wins over the focused one", () => {
    expect(captionFor(cell("E03 — Show.S01E03.1080p"), cell("E01 — Show.S01E01.1080p"))).toBe(
      "E03 — Show.S01E03.1080p",
    )
  })

  test("focused cell captions when nothing is hovered", () => {
    expect(captionFor(null, cell("E01 — Show.S01E01.1080p"))).toBe("E01 — Show.S01E01.1080p")
  })

  test("nothing hovered or focused → empty", () => {
    expect(captionFor(null, null)).toBe("")
  })

  test("an element without a caption contributes nothing", () => {
    expect(captionFor({ dataset: {} }, cell("E02 — searching"))).toBe("E02 — searching")
  })
})
