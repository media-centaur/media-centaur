/**
 * Status page behavior.
 *
 * No page-specific hooks — navigation (including left from sections
 * into the sidebar) is handled by the framework via the `status` zone
 * layout.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createStatusBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
