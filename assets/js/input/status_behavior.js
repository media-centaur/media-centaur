/**
 * Status page behavior.
 *
 * No page-specific hooks — navigation (toolbar → subsystem tiles → drill-in,
 * the issue-view modal, the report wizard overlay) is handled by the
 * framework via the `status` zone layout in config.js.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createStatusBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
