/**
 * Home page behavior.
 *
 * The home page (`/`) is a vertical stack of horizontal media shelves
 * (hero, Continue Watching, Recently Added, Coming Up) — each a SHELF
 * context. All cross-shelf and within-shelf navigation is handled by the
 * framework via the `home` zone layout (left at a shelf's left edge
 * reaches the sidebar); the page-specific concern is:
 *
 * - Reaching the hero shelf (the topmost) pins the page to the very top.
 *   The hero is ≤65vh and anchored at the page top, so scrolling back up to
 *   its Play / More info buttons should reveal the whole hero rather than
 *   leave it half-clipped — `scrollIntoView('nearest')` only guarantees the
 *   focused button is visible, not the title/backdrop above it.
 *
 * Shelves deliberately do NOT auto-activate on focus: moving across cards
 * must not open the detail modal — activation only happens on explicit
 * SELECT (so `activateOnFocus` is omitted).
 *
 * External dependencies are injected via the `dom` parameter, following the
 * same DI pattern as the orchestrator itself.
 */

/**
 * @typedef {Object} HomeDom
 * @property {function(): void} scrollToTop
 */

/** Default DOM implementation for production use. */
const REAL_DOM = {
  scrollToTop() {
    // Smooth, to match the reveal scroll the orchestrator issues a moment
    // later when it focuses the hero's Play button — an instant jump followed
    // by a glide reads as two separate movements.
    window.scrollTo({ top: 0, behavior: "smooth" })
  },
}

/**
 * Create a home page behavior instance.
 * @param {HomeDom} dom - DOM interface for scroll operations
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createHomeBehavior(dom) {
  return {
    onZoneChanged(context) {
      if (context === "hero") {
        dom.scrollToTop()
      }
    },
  }
}

/** Re-export the real DOM for the registry to pass through in production. */
export { REAL_DOM as homeDom }
