/**
 * Geometry of the detail modal's scrollport.
 *
 * The orientation block (identity lockup + hairline + controls) is
 * `position: sticky` inside the scrollport, so it covers the top of the
 * scrolling region once pinned. Anything scrolled to the top edge therefore
 * lands *behind* it — which is what `scroll-padding-top` exists to prevent: it
 * insets the "optimal viewing region" every programmatic scroll aims into.
 *
 * The reserve has to be measured rather than declared, because the block's
 * height depends on the title (logo or text lockup, tagline, synopsis length,
 * facet strip). This module owns the arithmetic; the hook in `app.js` owns
 * reading the DOM and republishing after patches.
 */

/**
 * How much of the scrollport's top the pinned block claims, or `null` when the
 * port is too short to give it up.
 *
 * All three inputs must be **layout** pixels (`offsetHeight`, `clientHeight`,
 * computed `top`) and never `getBoundingClientRect`. The UI runs under a root
 * zoom, so rects come back in visual pixels and mixing the families silently
 * scales one side.
 *
 * @param {Object} m
 * @param {number} m.pinInset - the sticky `top` the block pins at
 * @param {number} m.blockHeight - the block's height, constant pinned or not
 * @param {number} m.portHeight - the scrollport's visible height
 * @param {number} [m.minRoom=96] - room a target still needs below the reserve
 * @returns {number|null}
 */
export function pinReserve({ pinInset, blockHeight, portHeight, minRoom = 96 }) {
  const reserved = pinInset + blockHeight
  // Reserving more than the port can spare would push the target off the
  // bottom — worse than landing behind the block, and the same trade rule 5 of
  // UIDR-018 makes for a shelf whose reserve outgrows its viewport: keeping the
  // item on screen beats framing it.
  if (reserved > portHeight - minRoom) return null
  return Math.round(reserved)
}

/**
 * How far the backing's sheet replica may rise behind the pinned block before
 * freezing, in layout pixels.
 *
 * The replica's gradient zero-point rests `blockHeight − reach` below the
 * block's top edge (backing box bottom − 2rem − reach; see
 * `.orientation-backing-sheet`). The cap lets it climb that far plus the
 * overshoot: at the freeze the block's top edge sits `overshoot` deep in the
 * gradient ramp, so the overshoot IS the darkness dial
 * (`--detail-sheet-overshoot` — each stop of the ramp it advances past adds
 * that stop's alpha behind the lockup). Deeper scrolling never advances it
 * further, so the block settles on that slice of the ramp, never the full
 * plateau.
 *
 * @param {Object} m
 * @param {number} m.blockHeight - the orientation block's height
 * @param {number} m.reach - --detail-sheet-reach, how far the sheet's box
 *   extends up behind the block at rest
 * @param {number} m.overshoot - --detail-sheet-overshoot, how far past the
 *   block's top edge the zero-point may climb
 * @returns {number}
 */
export function sheetMaxRise({ blockHeight, reach, overshoot }) {
  return Math.max(0, Math.round(blockHeight - reach + overshoot))
}
