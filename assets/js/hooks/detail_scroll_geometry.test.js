import { describe, expect, test } from "bun:test"
import { pinReserve, sheetMaxRise } from "./detail_scroll_geometry"

describe("pinReserve — how much of the scrollport the pinned block claims", () => {
  test("reserves the block plus the gap it pins at", () => {
    expect(pinReserve({ pinInset: 24, blockHeight: 380, portHeight: 880 })).toBe(404)
  })

  test("rounds to whole pixels", () => {
    expect(pinReserve({ pinInset: 24.4, blockHeight: 380.2, portHeight: 880 })).toBe(405)
  })

  // Reserving more than the port can spare pushes the target off the bottom,
  // which is worse than landing behind the block.
  test("yields nothing when the port cannot spare the room", () => {
    expect(pinReserve({ pinInset: 24, blockHeight: 380, portHeight: 420 })).toBeNull()
  })

  test("the target still needs room below the reserve, not merely a pixel", () => {
    // 404 reserved in a 480 port leaves 76 — less than a comfortable row.
    expect(pinReserve({ pinInset: 24, blockHeight: 380, portHeight: 480 })).toBeNull()
    expect(pinReserve({ pinInset: 24, blockHeight: 380, portHeight: 500 })).toBe(404)
  })
})

describe("sheetMaxRise — how far the sheet replica may rise behind the pinned block", () => {
  // The replica's gradient zero-point rests blockHeight − reach below the
  // block's top edge; the cap brings it exactly to the top and no further,
  // so the block keeps the partial ramp instead of the full plateau.
  test("caps the rise at the distance from the resting anchor to the block top", () => {
    expect(sheetMaxRise({ blockHeight: 420, reach: 128 })).toBe(292)
  })

  test("rounds to whole pixels", () => {
    expect(sheetMaxRise({ blockHeight: 420.6, reach: 128.2 })).toBe(292)
  })

  // A block shorter than the reach already rests with the zero-point above
  // its top edge — any rise would darken past the cap, so the replica parks.
  test("parks the replica when the block is shorter than the reach", () => {
    expect(sheetMaxRise({ blockHeight: 100, reach: 128 })).toBe(0)
  })
})
