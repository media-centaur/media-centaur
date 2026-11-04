/**
 * Apps launcher page behavior.
 *
 * Layout: a toolbar (Manage / Add app) above a banner-card grid, one item
 * per card in either mode. The add/edit modal is the `apps_modal` overlay
 * in config.js: its controls as a tree around the Steam picker, a region of
 * its own walked by geometry. No page-specific actions —
 * the framework defaults cover it, and cards must only launch on an
 * explicit SELECT (never on focus).
 */
export function createAppsBehavior() {
  return {}
}
