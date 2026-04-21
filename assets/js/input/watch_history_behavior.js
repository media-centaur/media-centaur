/**
 * Watch history page behavior.
 *
 * Layout: toolbar (filter pills + search + optional date badge) → grid
 * (event list). BACK from either zone returns to the sidebar.
 *
 * The heatmap SVG rects remain mouse-only by design — keyboard users
 * filter by clicking the pill row instead. The per-event delete button
 * is revealed on focus via CSS so a user tabbing through the list can
 * still reach it.
 */
export function createWatchHistoryBehavior() {
  return {
    onEscape() {
      return "sidebar"
    },
  }
}
