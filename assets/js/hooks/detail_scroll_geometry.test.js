import { describe, expect, test } from "bun:test"
import { pinReserve } from "./detail_scroll_geometry"

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
