import { describe, expect, test } from "bun:test"
import { cropFields } from "./avatar_crop"

// croppr hands a box in the picture's pixels as floats; the form carries
// three integers, and a square is one side: the smaller of the two, so a
// rounding drift never pushes the box off the picture's edge.
describe("cropFields", () => {
  test("rounds the box to integers and takes the smaller side", () => {
    expect(cropFields({ x: 12.4, y: 7.6, width: 199.6, height: 200.2 })).toEqual({
      crop_x: "12",
      crop_y: "8",
      crop_side: "200",
    })
  })

  test("a box at the origin", () => {
    expect(cropFields({ x: 0, y: 0, width: 300, height: 300 })).toEqual({
      crop_x: "0",
      crop_y: "0",
      crop_side: "300",
    })
  })

  test("nothing sensible → empty fields, which the server reads as the centre", () => {
    expect(cropFields(null)).toEqual({ crop_x: "", crop_y: "", crop_side: "" })
    expect(cropFields({ x: 1, y: 1, width: 0, height: 0 })).toEqual({ crop_x: "", crop_y: "", crop_side: "" })
  })
})
