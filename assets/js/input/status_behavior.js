/**
 * Status page behavior.
 *
 * No page-specific hooks — navigation (toolbar → tile grid → drill-in,
 * left-at-the-edge into the sidebar, and the issue-view modal) is handled
 * by the framework via the `status` zone layout in config.js.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createStatusBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
