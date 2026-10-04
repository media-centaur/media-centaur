import { describe, expect, test } from "bun:test"
// The helper, not the hook: the hook imports croppr, which touches `window` at load.
import { cropFields } from "./image_crop_fields"

// croppr hands a box in the picture's pixels as floats; the form carries
// four integers, kept on the picture so a rounding drift never pushes the
// box past its edge (the server would read that as no crop at all).
describe("cropFields", () => {
  const picture = { width: 400, height: 200 }

  test("rounds the box to integers", () => {
    expect(cropFields({ x: 12.4, y: 7.6, width: 199.6, height: 93.2 }, picture)).toEqual({
      crop_x: "12",
      crop_y: "8",
      crop_width: "200",
      crop_height: "93",
    })
  })

  test("a box rounded past the picture's edge is pulled back onto it", () => {
    expect(cropFields({ x: 200.4, y: 106.6, width: 199.9, height: 93.6 }, picture)).toEqual({
      crop_x: "200",
      crop_y: "107",
      crop_width: "200",
      crop_height: "93",
    })
  })

  test("nothing sensible → empty fields, which the server reads as the centre", () => {
    const empty = { crop_x: "", crop_y: "", crop_width: "", crop_height: "" }
    expect(cropFields(null, picture)).toEqual(empty)
    expect(cropFields({ x: 1, y: 1, width: 0, height: 0 }, picture)).toEqual(empty)
  })
})
