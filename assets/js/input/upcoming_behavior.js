/**
 * Upcoming page behavior.
 *
 * The upcoming page's in-page navigation is still being built (see
 * `wip_notice.js`). For now the behavior only wires BACK back to the
 * sidebar so a gamepad user is never trapped on the page; the WIP-notice
 * decorator surfaces the "nav coming soon" hint on every action.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createUpcomingBehavior() {
  return {
    onEscape() {
      return "sidebar"
    },
  }
}
