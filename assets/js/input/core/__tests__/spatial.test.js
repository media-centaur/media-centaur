import { describe, expect, test } from "bun:test"
import { findNearest, gridNavigate } from "../spatial"

// Helper: create a rect at grid position (col, row) with standard size
function makeRect(col, row, width = 100, height = 150, gap = 10) {
  return {
    x: col * (width + gap),
    y: row * (height + gap),
    width,
    height,
  }
}

describe("findNearest", () => {
  test("returns null for empty candidates", () => {
    expect(findNearest(makeRect(0, 0), "right", [])).toBe(null)
  })

  test("finds right neighbor in a row", () => {
    const from = makeRect(0, 0)
    const candidates = [makeRect(1, 0), makeRect(2, 0)]
    expect(findNearest(from, "right", candidates)).toBe(0)
  })

  test("finds left neighbor in a row", () => {
    const from = makeRect(2, 0)
    const candidates = [makeRect(0, 0), makeRect(1, 0)]
    expect(findNearest(from, "left", candidates)).toBe(1)
  })

  test("finds down neighbor in a column", () => {
    const from = makeRect(0, 0)
    const candidates = [makeRect(0, 1), makeRect(0, 2)]
    expect(findNearest(from, "down", candidates)).toBe(0)
  })

  test("finds up neighbor in a column", () => {
    const from = makeRect(0, 2)
    const candidates = [makeRect(0, 0), makeRect(0, 1)]
    expect(findNearest(from, "up", candidates)).toBe(1)
  })

  test("prefers aligned candidate over closer unaligned one", () => {
    // Origin at (0,0). Two candidates below:
    // - candidate 0: directly below but far (row 3)
    // - candidate 1: closer (row 1) but offset far right (col 3)
    const from = makeRect(0, 0)
    const candidates = [
      makeRect(0, 3), // aligned, far
      makeRect(3, 1), // close, misaligned
    ]
    expect(findNearest(from, "down", candidates)).toBe(0)
  })

  test("returns null when no candidates in direction", () => {
    const from = makeRect(0, 0)
    const candidates = [makeRect(1, 0)] // only to the right
    expect(findNearest(from, "left", candidates)).toBe(null)
    expect(findNearest(from, "up", candidates)).toBe(null)
  })

  test("navigates a 3x3 grid correctly", () => {
    // 3x3 grid
    const grid = []
    for (let row = 0; row < 3; row++) {
      for (let col = 0; col < 3; col++) {
        grid.push(makeRect(col, row))
      }
    }
    // index: 0  1  2
    //        3  4  5
    //        6  7  8

    // From center (4), right should be 5
    expect(findNearest(grid[4], "right", grid)).toBe(5)
    // From center (4), left should be 3
    expect(findNearest(grid[4], "left", grid)).toBe(3)
    // From center (4), up should be 1
    expect(findNearest(grid[4], "up", grid)).toBe(1)
    // From center (4), down should be 7
    expect(findNearest(grid[4], "down", grid)).toBe(7)
  })

  test("handles single candidate", () => {
    const from = makeRect(0, 0)
    const candidates = [makeRect(1, 0)]
    expect(findNearest(from, "right", candidates)).toBe(0)
    expect(findNearest(from, "left", candidates)).toBe(null)
  })
})

describe("gridNavigate", () => {
  // 4-column grid with 10 items (last row has 2)
  // 0  1  2  3
  // 4  5  6  7
  // 8  9

  test("moves right within row", () => {
    expect(gridNavigate(0, 4, 10, "right")).toBe(1)
    expect(gridNavigate(1, 4, 10, "right")).toBe(2)
    expect(gridNavigate(4, 4, 10, "right")).toBe(5)
  })

  test("stops at right edge of row", () => {
    expect(gridNavigate(3, 4, 10, "right")).toBe(null)
    expect(gridNavigate(7, 4, 10, "right")).toBe(null)
  })

  test("stops at right edge of short last row", () => {
    expect(gridNavigate(9, 4, 10, "right")).toBe(null)
  })

  test("moves left within row", () => {
    expect(gridNavigate(1, 4, 10, "left")).toBe(0)
    expect(gridNavigate(3, 4, 10, "left")).toBe(2)
    expect(gridNavigate(5, 4, 10, "left")).toBe(4)
  })

  test("stops at left edge", () => {
    expect(gridNavigate(0, 4, 10, "left")).toBe(null)
    expect(gridNavigate(4, 4, 10, "left")).toBe(null)
    expect(gridNavigate(8, 4, 10, "left")).toBe(null)
  })

  test("moves down between rows", () => {
    expect(gridNavigate(0, 4, 10, "down")).toBe(4)
    expect(gridNavigate(1, 4, 10, "down")).toBe(5)
    expect(gridNavigate(4, 4, 10, "down")).toBe(8)
    expect(gridNavigate(5, 4, 10, "down")).toBe(9)
  })

  test("stops at bottom when no item below", () => {
    expect(gridNavigate(8, 4, 10, "down")).toBe(null)
    expect(gridNavigate(9, 4, 10, "down")).toBe(null)
    // Column 2, row 1 → row 2 would be index 10, out of bounds
    expect(gridNavigate(6, 4, 10, "down")).toBe(null)
  })

  test("moves up between rows", () => {
    expect(gridNavigate(4, 4, 10, "up")).toBe(0)
    expect(gridNavigate(5, 4, 10, "up")).toBe(1)
    expect(gridNavigate(8, 4, 10, "up")).toBe(4)
  })

  test("stops at top edge", () => {
    expect(gridNavigate(0, 4, 10, "up")).toBe(null)
    expect(gridNavigate(3, 4, 10, "up")).toBe(null)
  })

  test("returns null for empty grid", () => {
    expect(gridNavigate(0, 4, 0, "right")).toBe(null)
  })

  test("single column grid", () => {
    // 1-column, 3 items
    expect(gridNavigate(0, 1, 3, "down")).toBe(1)
    expect(gridNavigate(1, 1, 3, "down")).toBe(2)
    expect(gridNavigate(2, 1, 3, "down")).toBe(null)
    expect(gridNavigate(0, 1, 3, "right")).toBe(null)
    expect(gridNavigate(0, 1, 3, "left")).toBe(null)
  })

  test("single item grid", () => {
    expect(gridNavigate(0, 1, 1, "up")).toBe(null)
    expect(gridNavigate(0, 1, 1, "down")).toBe(null)
    expect(gridNavigate(0, 1, 1, "left")).toBe(null)
    expect(gridNavigate(0, 1, 1, "right")).toBe(null)
  })
})
