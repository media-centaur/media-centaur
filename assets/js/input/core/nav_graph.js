/**
 * Navigation graph — directional edges between focus contexts.
 *
 * Pure function module (no DOM access). Builds an adjacency map from
 * layout definitions and live item counts. Empty contexts are skipped via
 * explicit fallback lists. Used for all arrow-key cross-context transitions.
 *
 * Parameterized: layouts, cursorStartPriority, and alwaysPopulated are
 * passed via config rather than hardcoded as module-level constants.
 */

/**
 * Build a navigation graph: `{ context: { direction: targetContext } }`.
 *
 * For each edge in the layout, walks the candidate array and picks
 * the first populated context.
 *
 * @param {string} zone - The page's layout key (`data-nav-default-zone`)
 * @param {Object} counts - Map of context name to item count
 * @param {Object} [config={}]
 * @param {Object} [config.layouts] - Spatial layouts per zone
 * @param {string[]} [config.alwaysPopulated] - Contexts that skip item count check
 * @param {Object} [config.overlayLayout] - Edges contributed by an open overlay,
 *   merged over the page's. An overlay's regions relate to each other the same
 *   way whatever page it was opened from, so its topology is not per-zone.
 * @returns {Object} Adjacency map
 */
export function buildNavGraph(zone, counts, config = {}) {
  const layouts = config.layouts ?? {}
  const alwaysPopulated = config.alwaysPopulated ?? []

  const layout = { ...layouts[zone], ...config.overlayLayout }
  if (Object.keys(layout).length === 0) return {}

  const graph = {}

  for (const [context, edges] of Object.entries(layout)) {
    // A node exists only for a context on the page: BACK reads the primary
    // menu's node as "this page has a main menu", and a page that renders
    // none (the profile door) must not be entered into it.
    if (!isPopulated(context, counts, alwaysPopulated)) continue

    graph[context] = {}

    for (const [direction, candidates] of Object.entries(edges)) {
      const target = resolveFirst(candidates, counts, alwaysPopulated)
      if (target) {
        graph[context][direction] = target
      }
    }
  }

  return graph
}

/**
 * Walk a candidate list, returning the first populated context.
 */
function resolveFirst(candidates, counts, alwaysPopulated) {
  for (const candidate of candidates) {
    if (isPopulated(candidate, counts, alwaysPopulated)) return candidate
  }
  return null
}

/**
 * Check if a context is populated. Contexts in alwaysPopulated
 * are considered populated regardless of item count.
 */
function isPopulated(context, counts, alwaysPopulated) {
  if (alwaysPopulated.includes(context)) return true
  return (counts[context] ?? 0) > 0
}

/**
 * Walk the cursor start priority list for a zone, returning the first
 * populated context. Used on page entry and zone changes.
 *
 * @param {string} zone - The page's layout key (`data-nav-default-zone`)
 * @param {Object} counts - Map of context name to item count
 * @param {Object} [config={}]
 * @param {Object} [config.cursorStartPriority] - Priority list per zone
 * @param {string[]} [config.alwaysPopulated] - Contexts that skip item count check
 * @returns {string|null} First populated context, or null if none
 */
export function resolveCursorStart(zone, counts, config = {}) {
  const cursorStartPriority = config.cursorStartPriority ?? {}
  const alwaysPopulated = config.alwaysPopulated ?? []

  const priority = cursorStartPriority[zone]
  if (!priority) return null

  for (const context of priority) {
    if (isPopulated(context, counts, alwaysPopulated)) return context
  }

  return null
}
