/**
 * Download page behavior.
 *
 * No page-specific hooks yet — navigation (including left-at-the-edge
 * into the sidebar) is handled by the framework via the `download` zone
 * layout; the WIP-notice decorator adds the "nav coming soon" hint.
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createDownloadBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
