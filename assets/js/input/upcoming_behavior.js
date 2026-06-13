/**
 * Upcoming page behavior.
 *
 * Navigation is fully config-driven (see `config.js` `upcoming` layout): the
 * editorial rail and stragglers list are MENU zones, the mini-month is a
 * TOOLBAR for month paging, and the detail / track modals are handled by the
 * framework's MODAL context. There is no page-specific input concern — event
 * cards open the detail panel on SELECT (no activate-on-focus, so scrolling the
 * rail never opens a modal), and there is no clearable filter.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createUpcomingBehavior() {
  return {}
}
