/**
 * Spatial navigation — nearest-neighbor algorithm for arbitrary layouts.
 *
 * Operates on abstract {x, y, width, height} rects. No DOM dependency.
 */

/**
 * Find the nearest candidate in the given direction from the origin rect.
 *
 * Algorithm:
 * 1. Filter candidates to the correct directional half-plane from origin's edge
 * 2. Score by weighted combination: alignment (perpendicular) + distance (primary axis)
 * 3. Return index of lowest-scoring candidate, or null if none qualify
 *
 * @param {{x: number, y: number, width: number, height: number}} fromRect
 * @param {"up"|"down"|"left"|"right"} direction
 * @param {Array<{x: number, y: number, width: number, height: number}>} candidates
 * @returns {number|null} Index into candidates array, or null
 */
export function findNearest(fromRect, direction, candidates) {
  if (candidates.length === 0) return null

  const fromCenter = rectCenter(fromRect)
  let bestIndex = null
  let bestScore = Infinity

  for (let i = 0; i < candidates.length; i++) {
    const candidate = candidates[i]
    const candidateCenter = rectCenter(candidate)

    // Filter: candidate must be in the correct half-plane
    if (!isInDirection(fromRect, candidateCenter, direction)) continue

    // Score: primary axis distance + alignment penalty
    const score = computeScore(fromRect, candidate, direction)

    if (score < bestScore) {
      bestScore = score
      bestIndex = i
    }
  }

  return bestIndex
}

/**
 * Fast-path grid navigation using index arithmetic.
 * For uniform grids where all cells are the same size.
 *
 * @param {number} currentIndex - Current focused item index (0-based)
 * @param {number} columnCount - Number of columns in the grid
 * @param {number} totalCount - Total number of items
 * @param {"up"|"down"|"left"|"right"} direction
 * @returns {number|null} New index, or null if at wall
 */
export function gridNavigate(currentIndex, columnCount, totalCount, direction) {
  if (totalCount === 0) return null

  const row = Math.floor(currentIndex / columnCount)
  const col = currentIndex % columnCount
  const totalRows = Math.ceil(totalCount / columnCount)

  switch (direction) {
    case "up":
      return row > 0 ? currentIndex - columnCount : null

    case "down": {
      const nextIndex = currentIndex + columnCount
      return nextIndex < totalCount ? nextIndex : null
    }

    case "left":
      return col > 0 ? currentIndex - 1 : null

    case "right": {
      const nextIndex = currentIndex + 1
      // Don't wrap to next row
      return (nextIndex % columnCount !== 0 && nextIndex < totalCount) ? nextIndex : null
    }

    default:
      return null
  }
}

// --- Internal helpers ---

function rectCenter(rect) {
  return {
    x: rect.x + rect.width / 2,
    y: rect.y + rect.height / 2,
  }
}

/**
 * Check if a point is in the directional half-plane relative to origin rect.
 * Uses the rect's edge, not center, for the boundary.
 */
function isInDirection(fromRect, point, direction) {
  switch (direction) {
    case "up":    return point.y < fromRect.y
    case "down":  return point.y > fromRect.y + fromRect.height
    case "left":  return point.x < fromRect.x
    case "right": return point.x > fromRect.x + fromRect.width
    default:      return false
  }
}

/**
 * Score a candidate: lower is better.
 * Primary axis distance + weighted perpendicular alignment penalty.
 *
 * A candidate whose cross-axis span lies wholly inside the origin's is
 * *perfectly* aligned and pays no penalty at all — there is nothing to be more
 * in line with. This is what a tall tile facing a stack of short ones looks
 * like (the Coming Up marquee's large tile beside its column of secondaries):
 * every secondary is equally in line, so they tie on distance and the caller's
 * document order breaks the tie, which reads as "the next one". Scoring by
 * centre distance instead would silently pick the middle of the stack.
 */
function computeScore(fromRect, toRect, direction) {
  const fromCenter = rectCenter(fromRect)
  const toCenter = rectCenter(toRect)
  const dx = Math.abs(toCenter.x - fromCenter.x)
  const dy = Math.abs(toCenter.y - fromCenter.y)

  // Weight alignment more heavily to prefer elements that are "in line"
  const ALIGNMENT_WEIGHT = 2.0

  switch (direction) {
    case "up":
    case "down": {
      // Primary: vertical distance. Alignment: horizontal offset.
      const aligned = spansWithin(toRect.x, toRect.width, fromRect.x, fromRect.width)
      return dy + (aligned ? 0 : dx * ALIGNMENT_WEIGHT)
    }

    case "left":
    case "right": {
      // Primary: horizontal distance. Alignment: vertical offset.
      const aligned = spansWithin(toRect.y, toRect.height, fromRect.y, fromRect.height)
      return dx + (aligned ? 0 : dy * ALIGNMENT_WEIGHT)
    }

    default:
      return Infinity
  }
}

/** True when [start, start+size] lies wholly inside [outerStart, outerStart+outerSize]. */
function spansWithin(start, size, outerStart, outerSize) {
  return start >= outerStart && start + size <= outerStart + outerSize
}
