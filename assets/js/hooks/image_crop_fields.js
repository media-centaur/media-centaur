// The four form fields for a croppr box: integers, kept on the picture so
// rounding never pushes the box past its edge. Anything without a
// positive size is empty, which the server reads as the centred
// rectangle. Its own module so the hook's test never imports croppr,
// whose module body polyfills `window` globals bun's one-process run
// cannot host.
export function cropFields(box, picture) {
  if (!box || !(box.width > 0) || !(box.height > 0)) {
    return { crop_x: "", crop_y: "", crop_width: "", crop_height: "" }
  }
  const x = Math.max(0, Math.round(box.x))
  const y = Math.max(0, Math.round(box.y))
  return {
    crop_x: String(x),
    crop_y: String(y),
    crop_width: String(Math.min(Math.round(box.width), picture.width - x)),
    crop_height: String(Math.min(Math.round(box.height), picture.height - y)),
  }
}
