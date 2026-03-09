/**
 * Navigation graph — directional edges between focus contexts.
 *
 * Pure function module (no DOM access). Builds an adjacency map from static
 * layout definitions and live item counts. Empty contexts are skipped via
 * explicit fallback lists. Used for all arrow-key cross-context transitions.
 */

/**
 * Static spatial layouts per zone.
 *
 * Each edge is an ordered array of candidate targets. The graph builder
 * picks the first populated candidate — no implicit directional chaining.
 * This makes fallback behavior explicit and testable.
 *
 * Drawer candidates are automatically filtered when the drawer is closed.
 */
const LAYOUTS = {
  watching: {
    zone_tabs: { down: ["grid"],             left: ["sidebar"] },
    grid:      { up: ["zone_tabs"],          left: ["sidebar"], right: ["drawer"] },
    sidebar:   { right: ["grid", "zone_tabs"] },
    drawer:    { left: ["grid"] },
  },
  library: {
    zone_tabs: { down: ["toolbar", "grid"],  left: ["sidebar"] },
    toolbar:   { up: ["zone_tabs"],          down: ["grid"],   left: ["sidebar"] },
    grid:      { up: ["toolbar", "zone_tabs"], left: ["sidebar"], right: ["drawer"] },
    sidebar:   { right: ["grid", "toolbar", "zone_tabs"] },
    drawer:    { left: ["grid", "toolbar"] },
  },
}

/**
 * Ordered list of contexts to try when placing the cursor on page entry
 * or zone change. First populated context wins. Sidebar is always last
 * (guaranteed populated — static navigation links).
 */
const CURSOR_START_PRIORITY = {
  watching: ["grid", "zone_tabs", "sidebar"],
  library:  ["grid", "toolbar", "zone_tabs", "sidebar"],
}

/**
 * Build a navigation graph: `{ context: { direction: targetContext } }`.
 *
 * For each edge in the static layout, walks the candidate array and picks
 * the first populated context. Drawer candidates are excluded when the
 * drawer is closed. Sidebar is always considered populated.
 *
 * @param {string} zone - "watching" or "library"
 * @param {Object} counts - Map of context name to item count
 * @param {Object} [options]
 * @param {boolean} [options.drawerOpen=false]
 * @returns {Object} Adjacency map
 */
export function buildNavGraph(zone, counts, options = {}) {
  const layout = LAYOUTS[zone]
  if (!layout) return {}

  const drawerOpen = options.drawerOpen ?? false
  const graph = {}

  for (const [context, edges] of Object.entries(layout)) {
    // Skip drawer context entirely when closed
    if (context === "drawer" && !drawerOpen) continue

    graph[context] = {}

    for (const [direction, candidates] of Object.entries(edges)) {
      const target = resolveFirst(candidates, counts, drawerOpen)
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
function resolveFirst(candidates, counts, drawerOpen) {
  for (const candidate of candidates) {
    if (candidate === "drawer" && !drawerOpen) continue
    if (isPopulated(candidate, counts)) return candidate
  }
  return null
}

/**
 * Check if a context is populated. Sidebar is always considered populated
 * (static navigation links that are always present).
 */
function isPopulated(context, counts) {
  if (context === "sidebar") return true
  return (counts[context] ?? 0) > 0
}

/**
 * Walk the cursor start priority list for a zone, returning the first
 * populated context. Used on page entry and zone changes.
 *
 * @param {string} zone - "watching" or "library"
 * @param {Object} counts - Map of context name to item count
 * @returns {string|null} First populated context, or null if none
 */
export function resolveCursorStart(zone, counts) {
  const priority = CURSOR_START_PRIORITY[zone]
  if (!priority) return null

  for (const context of priority) {
    if (isPopulated(context, counts)) return context
  }

  return null
}
