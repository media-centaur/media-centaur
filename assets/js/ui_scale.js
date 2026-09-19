// --ui-scale is the root zoom factor (auto × preference), composed in CSS
// and registered as a <number>, so its computed value is a plain number
// string. Anything that measures the page in visual pixels — a bounding
// rect, a canvas backing store — multiplies or divides by it; this is the
// one parser for it.

/**
 * Parse the raw `--ui-scale` custom-property string from computed style.
 * @param {string|undefined} raw
 * @returns {number} the scale, or 1 for anything absent or malformed
 */
export function parseUiScale(raw) {
  const scale = Number.parseFloat(raw)
  return Number.isFinite(scale) && scale > 0 ? scale : 1
}
