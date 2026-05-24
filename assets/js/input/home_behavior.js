/**
 * Home page behavior.
 *
 * The home page (`/`) is a vertical stack of horizontal media shelves
 * (hero, Continue Watching, Recently Added, Coming Up) — each a SHELF
 * context. All cross-shelf and within-shelf navigation is handled by the
 * framework via the `home` zone layout; the only page-specific concern is
 * BACK, which returns to the sidebar like every other content page.
 *
 * Shelves deliberately do NOT auto-activate on focus: moving across cards
 * must not open the detail modal — activation only happens on explicit
 * SELECT (so `activateOnFocus` is omitted).
 */
export function createHomeBehavior() {
  return {
    onEscape: () => "sidebar",
  }
}
