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
 * the first populated context. Drawer candidates are excluded when the
 * drawer is closed.
 *
 * @param {string} zone - "watching", "library", or "settings"
 * @param {Object} counts - Map of context name to item count
 * @param {Object} [config={}]
 * @param {Object} [config.layouts] - Spatial layouts per zone
 * @param {string[]} [config.alwaysPopulated] - Contexts that skip item count check
 * @param {boolean} [config.drawerOpen=false]
 * @returns {Object} Adjacency map
 */
export function buildNavGraph(zone, counts, config = {}) {
  const layouts = config.layouts ?? {}
  const alwaysPopulated = config.alwaysPopulated ?? []
  const drawerOpen = config.drawerOpen ?? false

  const layout = layouts[zone]
  if (!layout) return {}

  const graph = {}

  for (const [context, edges] of Object.entries(layout)) {
    // Skip drawer context entirely when closed
    if (context === "drawer" && !drawerOpen) continue

    graph[context] = {}

    for (const [direction, candidates] of Object.entries(edges)) {
      const target = resolveFirst(candidates, counts, drawerOpen, alwaysPopulated)
      if (target) {
        graph[context][direction] = target
      }
    }
  }

  return graph
}

/**
 * Walk a candidate list, returning the first populated context.
 * Drawer candidates are skipped when the drawer is closed.
 */
function resolveFirst(candidates, counts, drawerOpen, alwaysPopulated) {
  for (const candidate of candidates) {
    if (candidate === "drawer" && !drawerOpen) continue
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
 * @param {string} zone - "watching", "library", or "settings"
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
