// The three form fields for a croppr box (profiles phase 5b): integers,
// and one side — the smaller, so rounding never pushes the box past the
// picture's edge. Anything without a positive size is empty, which the
// server reads as the centre square. Its own module so the hook's test
// never imports croppr, whose module body polyfills `window` globals
// bun's one-process run cannot host.
export function cropFields(box) {
  if (!box || !(box.width > 0) || !(box.height > 0)) {
    return { crop_x: "", crop_y: "", crop_side: "" }
  }
  const side = Math.round(Math.min(box.width, box.height))
  return {
    crop_x: String(Math.round(box.x)),
    crop_y: String(Math.round(box.y)),
    crop_side: String(side),
  }
}
