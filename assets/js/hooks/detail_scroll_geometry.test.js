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
  // block's top edge; the cap lets it climb to the top plus the overshoot,
  // so the block settles on a chosen slice of the ramp, never sliding on
  // to the full plateau.
  test("caps the rise at the block top plus the overshoot", () => {
    expect(sheetMaxRise({ blockHeight: 420, reach: 128, overshoot: 128 })).toBe(420)
  })

  test("zero overshoot stops the zero-point exactly at the block top", () => {
    expect(sheetMaxRise({ blockHeight: 420, reach: 128, overshoot: 0 })).toBe(292)
  })

  test("rounds to whole pixels", () => {
    expect(sheetMaxRise({ blockHeight: 420.6, reach: 128.2, overshoot: 0 })).toBe(292)
  })

  // A block shorter than reach − overshoot already rests with the
  // zero-point above its cap — any rise would darken past it, so the
  // replica parks.
  test("parks the replica when the resting anchor is already past the cap", () => {
    expect(sheetMaxRise({ blockHeight: 100, reach: 128, overshoot: 0 })).toBe(0)
  })
})
